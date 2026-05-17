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
  Future<void> insertPin(SupabasePinDto pin) async => inserts.add(pin);

  @override
  Future<void> updatePin(SupabasePinDto pin) async => updates.add(pin);

  @override
  Future<void> deletePin(String id) async => deletes.add(id);

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
}
