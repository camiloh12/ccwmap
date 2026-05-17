import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:ccwmap/data/sync/my_pins_sync.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-test fake — no mockito to keep dependencies light. Records calls
/// so individual tests can assert on them.
class _FakeRemote implements RemoteDataSourceInterface {
  List<SupabasePinDto> pinsToReturn = [];
  List<ServerPinDeletionDto> deletionsToReturn = [];
  final List<SupabasePinDto> inserts = [];
  final List<SupabasePinDto> updates = [];
  final List<String> deletes = [];

  // Per-method error injection — when non-null, the next call to that
  // method throws instead of recording. Reset to null after each test
  // by the per-test setUp (a fresh _FakeRemote is already created).
  Object? insertError;
  Object? updateError;
  Object? deleteError;

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async => pinsToReturn;

  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async => deletionsToReturn;

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat, required double swLng,
    required double neLat, required double neLng,
    required int zoom, required String? currentUserId,
  }) async => [];

  @override
  Future<void> insertPin(SupabasePinDto pin) async {
    if (insertError != null) throw insertError!;
    inserts.add(pin);
  }

  @override
  Future<void> updatePin(SupabasePinDto pin) async {
    if (updateError != null) throw updateError!;
    updates.add(pin);
  }

  @override
  Future<void> deletePin(String id) async {
    if (deleteError != null) throw deleteError!;
    deletes.add(id);
  }

  @override
  Future<SupabasePinDto?> getPinById(String id) async => null;
}

class _AlwaysOnline implements NetworkMonitor {
  @override bool get isOnline => true;
  @override Stream<bool> get isOnlineStream => const Stream.empty();
  @override Future<void> initialize() async {}
  @override void dispose() {}
}

void main() {
  late AppDatabase db;
  late _FakeRemote remote;
  late _AlwaysOnline network;
  late LastSyncedAtStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemote();
    network = _AlwaysOnline();
    store = await LastSyncedAtStore.create();
  });

  tearDown(() async => db.close());

  MyPinsSync _build(String? userId) => MyPinsSync(
        userIdProvider: () => userId,
        syncQueueDao: db.syncQueueDao,
        pinDao: db.pinDao,
        tombstoneDao: db.pinTombstoneDao,
        serverDeletionDao: db.serverPinDeletionDao,
        remote: remote,
        networkMonitor: network,
        watermarks: store,
      );

  test('returns early no-op for anonymous user', () async {
    final sync = _build(null);
    final result = await sync.sync();
    expect(result.uploaded, 0);
    expect(result.downloaded, 0);
    expect(result.errorMessage, isNull);
  });

  test('downloads pins from the delta endpoint and writes them locally',
      () async {
    final sync = _build('me');
    final iso = DateTime.utc(2026, 5, 16).toIso8601String();
    remote.pinsToReturn = [
      SupabasePinDto(
        id: 'pin-1', name: 'mine', latitude: 30, longitude: -95,
        status: 0, restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: iso, lastModified: iso,
        photoUri: null, notes: null, votes: 0,
      ),
    ];

    final result = await sync.sync();

    expect(result.downloaded, 1);
    final row = await db.pinDao.getPinById('pin-1');
    expect(row, isNotNull);
    expect(row!.createdBy, 'me');
    // Watermark advanced to (or past) the row's lastModified.
    final w = await store.readPinsWatermark('me');
    expect(w.isAfter(DateTime.utc(2026, 5, 15)), isTrue);
  });

  test('applies server tombstones for my deleted pins', () async {
    final sync = _build('me');

    // Pre-seed a local row that will be deleted.
    await db.pinDao.insertPin(PinEntity(
      id: 'pin-doomed', name: 'x', latitude: 30, longitude: -95,
      status: 0, restrictionTag: null,
      hasSecurityScreening: false, hasPostedSignage: false,
      createdBy: 'me', createdAt: 1, lastModified: 1,
      photoUri: null, notes: null, votes: 0,
      source: 'user', userModified: true, cachedAt: null,
    ));

    remote.deletionsToReturn = [
      ServerPinDeletionDto(
        pinId: 'pin-doomed',
        deletedAt: DateTime.utc(2026, 5, 16),
      ),
    ];

    final result = await sync.sync();

    expect(result.downloaded, 0);
    expect(await db.pinDao.getPinById('pin-doomed'), isNull);
    expect(
      await db.serverPinDeletionDao.getPinIdsDeletedSince(DateTime.utc(1970)),
      contains('pin-doomed'),
    );
  });

  test('respects local tombstones — does not re-insert pin user deleted',
      () async {
    final sync = _build('me');
    await db.pinTombstoneDao
        .insertTombstone('pin-1', DateTime.utc(2026, 5, 16));

    final iso = DateTime.utc(2026, 5, 16).toIso8601String();
    remote.pinsToReturn = [
      SupabasePinDto(
        id: 'pin-1', name: 'ghost', latitude: 30, longitude: -95,
        status: 0, restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: iso, lastModified: iso,
        photoUri: null, notes: null, votes: 0,
      ),
    ];

    await sync.sync();

    expect(await db.pinDao.getPinById('pin-1'), isNull);
  });

  group('upload path', () {
    test('queue optimization: DELETE supersedes earlier CREATE and UPDATE on same pin', () async {
      final sync = _build('me');

      // Enqueue CREATE then UPDATE then DELETE for the same pin (all directly
      // via the DAO so we don't run the repository's own dedup pass).
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-1', pinId: 'pin-1', operationType: 'CREATE',
        timestamp: 1, retryCount: 0, lastError: null,
      ));
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-2', pinId: 'pin-1', operationType: 'UPDATE',
        timestamp: 2, retryCount: 0, lastError: null,
      ));
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-3', pinId: 'pin-1', operationType: 'DELETE',
        timestamp: 3, retryCount: 0, lastError: null,
      ));

      await sync.sync();

      // Only the DELETE survives the optimization pass and is uploaded.
      expect(remote.deletes, ['pin-1']);
      expect(remote.inserts, isEmpty);
      expect(remote.updates, isEmpty);

      // Queue is fully drained.
      final pending = await db.syncQueueDao.getPendingOperationsSorted();
      expect(pending, isEmpty);
    });

    test('queue optimization: keeps only latest UPDATE when no DELETE present', () async {
      final sync = _build('me');

      // Pre-seed a local row so the UPDATE can find something to upload.
      await db.pinDao.insertPin(PinEntity(
        id: 'pin-1', name: 'x', latitude: 30, longitude: -95, status: 0,
        restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: 1, lastModified: 1,
        photoUri: null, notes: null, votes: 0,
        source: 'user', userModified: true, cachedAt: null,
      ));

      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-1', pinId: 'pin-1', operationType: 'UPDATE',
        timestamp: 1, retryCount: 0, lastError: null,
      ));
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-2', pinId: 'pin-1', operationType: 'UPDATE',
        timestamp: 2, retryCount: 0, lastError: null,
      ));
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-3', pinId: 'pin-1', operationType: 'UPDATE',
        timestamp: 3, retryCount: 0, lastError: null,
      ));

      await sync.sync();

      // Only one UPDATE call (the survivor of optimization).
      expect(remote.updates, hasLength(1));
      expect(remote.deletes, isEmpty);
      expect(remote.inserts, isEmpty);
    });

    test('CREATE swallows "duplicate" exception as idempotent success', () async {
      remote.insertError = Exception('duplicate key value violates unique constraint');
      final sync = _build('me');

      await db.pinDao.insertPin(PinEntity(
        id: 'pin-1', name: 'x', latitude: 30, longitude: -95, status: 0,
        restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: 1, lastModified: 1,
        photoUri: null, notes: null, votes: 0,
        source: 'user', userModified: true, cachedAt: null,
      ));
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-1', pinId: 'pin-1', operationType: 'CREATE',
        timestamp: 1, retryCount: 0, lastError: null,
      ));

      final result = await sync.sync();

      // No error surfaced — the exception was swallowed and treated as success.
      expect(result.uploaded, 1);
      expect(result.errors, 0);
      // Queue drained.
      expect(await db.syncQueueDao.getPendingOperationsSorted(), isEmpty);
    });

    test('DELETE swallows "not found" exception as idempotent success', () async {
      remote.deleteError = Exception('not found');
      final sync = _build('me');

      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-1', pinId: 'pin-1', operationType: 'DELETE',
        timestamp: 1, retryCount: 0, lastError: null,
      ));

      final result = await sync.sync();

      expect(result.uploaded, 1);
      expect(result.errors, 0);
      expect(await db.syncQueueDao.getPendingOperationsSorted(), isEmpty);
    });

    test('transient failure on CREATE increments retry count, op stays queued', () async {
      remote.insertError = Exception('genuine network error not a known idempotent string');
      final sync = _build('me');

      await db.pinDao.insertPin(PinEntity(
        id: 'pin-1', name: 'x', latitude: 30, longitude: -95, status: 0,
        restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: 1, lastModified: 1,
        photoUri: null, notes: null, votes: 0,
        source: 'user', userModified: true, cachedAt: null,
      ));
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-1', pinId: 'pin-1', operationType: 'CREATE',
        timestamp: 1, retryCount: 0, lastError: null,
      ));

      final result = await sync.sync();

      expect(result.errors, 1);
      expect(result.uploaded, 0);

      final pending = await db.syncQueueDao.getPendingOperationsSorted();
      expect(pending, hasLength(1));
      expect(pending.single.retryCount, 1);
      expect(pending.single.lastError, contains('genuine network error'));
    });

    test('just-deleted pin id suppresses re-insert in the subsequent download phase',
        () async {
      // Server returns this pin in the delta, but we just successfully DELETE'd it.
      final iso = DateTime.utc(2026, 5, 16).toIso8601String();
      remote.pinsToReturn = [
        SupabasePinDto(
          id: 'pin-1', name: 'ghost', latitude: 30, longitude: -95,
          status: 0, restrictionTag: null,
          hasSecurityScreening: false, hasPostedSignage: false,
          createdBy: 'me', createdAt: iso, lastModified: iso,
          photoUri: null, notes: null, votes: 0,
        ),
      ];

      final sync = _build('me');
      await db.syncQueueDao.enqueue(SyncQueueEntity(
        id: 'op-1', pinId: 'pin-1', operationType: 'DELETE',
        timestamp: 1, retryCount: 0, lastError: null,
      ));

      await sync.sync();

      // Even though the server still returned pin-1, the download phase saw it
      // in justDeletedIds (passed from _processQueue) and skipped the upsert.
      expect(await db.pinDao.getPinById('pin-1'), isNull);
    });
  });
}
