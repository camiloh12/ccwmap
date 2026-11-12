import 'dart:async';

import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemote implements RemoteDataSourceInterface {
  List<MapItem> bboxResult = [];

  /// When set, the next getPinsInView call awaits this before returning.
  Completer<void>? gate;

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  }) async {
    final g = gate;
    if (g != null) {
      gate = null;
      final snapshot = bboxResult;
      await g.future;
      return snapshot;
    }
    return bboxResult;
  }

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async => [];
  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async => [];
  @override
  Future<void> insertPin(SupabasePinDto pin) async {}
  @override
  Future<void> updatePin(SupabasePinDto pin) async {}
  @override
  Future<void> deletePin(String id) async {}
  @override
  Future<SupabasePinDto?> getPinById(String id) async => null;
}

Pin _pin(
  String id, {
  String createdBy = 'other',
  double lat = 30,
  double lng = -95,
}) => Pin(
  id: id,
  name: id,
  location: Location.fromLatLng(lat, lng),
  status: PinStatus.ALLOWED,
  restrictionTag: null,
  hasSecurityScreening: false,
  hasPostedSignage: false,
  metadata: PinMetadata(
    createdBy: createdBy,
    createdAt: DateTime.utc(2026, 1, 1),
    lastModified: DateTime.utc(2026, 1, 1),
  ),
);

void main() {
  late AppDatabase db;
  late _FakeRemote remote;
  late ViewportPinsManager vpm;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemote();
    vpm = ViewportPinsManager(
      remote: remote,
      pinDao: db.pinDao,
      tombstoneDao: db.pinTombstoneDao,
      fetchedBboxDao: db.fetchedBboxDao,
      userIdProvider: () => 'me',
      cacheRowLimit: 100,
    );
  });

  tearDown(() async => db.close());

  test('persists pins and exposes cluster items separately', () async {
    remote.bboxResult = [
      MapItemPin(_pin('pin-1')),
      const MapItemCluster(
        centroidLat: 31,
        centroidLng: -94,
        count: 7,
        dominantStatus: PinStatus.NO_GUN,
        dominantRestrictionTag: null,
      ),
    ];

    await vpm.fetch(swLat: 30, swLng: -96, neLat: 32, neLng: -94, zoom: 8);

    expect(await db.pinDao.getPinById('pin-1'), isNotNull);
    expect(vpm.clusters.value, hasLength(1));
    expect(vpm.clusters.value.single.count, 7);
  });

  test('filters out pins under local tombstones', () async {
    await db.pinTombstoneDao.insertTombstone(
      'pin-ghost',
      DateTime.utc(2026, 5, 16),
    );
    remote.bboxResult = [MapItemPin(_pin('pin-ghost'))];

    await vpm.fetch(swLat: 30, swLng: -96, neLat: 32, neLng: -94, zoom: 12);

    expect(await db.pinDao.getPinById('pin-ghost'), isNull);
  });

  test('LRU-evicts oldest cached non-mine pins past the cap', () async {
    // Seed 3 cached pins; cap is 2.
    final vpmSmall = ViewportPinsManager(
      remote: remote,
      pinDao: db.pinDao,
      tombstoneDao: db.pinTombstoneDao,
      fetchedBboxDao: db.fetchedBboxDao,
      userIdProvider: () => 'me',
      cacheRowLimit: 2,
    );
    await db.pinDao.upsertCachedPins([
      PinEntity(
        id: 'old',
        name: 'x',
        latitude: 30,
        longitude: -95,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'other',
        createdAt: 1,
        lastModified: 1,
        photoUri: null,
        notes: null,
        votes: 0,
        source: 'user',
        userModified: false,
        cachedAt: 100,
      ),
      PinEntity(
        id: 'mid',
        name: 'x',
        latitude: 30,
        longitude: -95,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'other',
        createdAt: 1,
        lastModified: 1,
        photoUri: null,
        notes: null,
        votes: 0,
        source: 'user',
        userModified: false,
        cachedAt: 200,
      ),
    ]);

    remote.bboxResult = [MapItemPin(_pin('new'))];

    await vpmSmall.fetch(
      swLat: 30,
      swLng: -96,
      neLat: 32,
      neLng: -94,
      zoom: 12,
    );

    final remaining = (await db.pinDao.getAllPins()).map((p) => p.id).toSet();
    expect(remaining, contains('new'));
    expect(remaining, isNot(contains('old')));
  });

  test('reset() drops every cached non-mine pin and clears clusters', () async {
    await db.pinDao.upsertCachedPins([
      PinEntity(
        id: 'cached',
        name: 'x',
        latitude: 30,
        longitude: -95,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'other',
        createdAt: 1,
        lastModified: 1,
        photoUri: null,
        notes: null,
        votes: 0,
        source: 'user',
        userModified: false,
        cachedAt: 100,
      ),
    ]);

    await vpm.reset();

    expect(await db.pinDao.getAllPins(), isEmpty);
    expect(vpm.clusters.value, isEmpty);
  });

  test(
    'resetForSignedOutUser() drops cached non-mine pins using the supplied id '
    'even when userIdProvider has already gone null',
    () async {
      // Build a manager whose userIdProvider returns null — simulating the
      // post-signout state where Supabase has already cleared the session.
      final signedOutVpm = ViewportPinsManager(
        remote: remote,
        pinDao: db.pinDao,
        tombstoneDao: db.pinTombstoneDao,
        fetchedBboxDao: db.fetchedBboxDao,
        userIdProvider: () => null,
        cacheRowLimit: 100,
      );

      // Seed a cached pin created by some "other" user (i.e. non-mine).
      await db.pinDao.upsertCachedPins([
        PinEntity(
          id: 'leftover',
          name: 'x',
          latitude: 30,
          longitude: -95,
          status: 0,
          restrictionTag: null,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          createdBy: 'other',
          createdAt: 1,
          lastModified: 1,
          photoUri: null,
          notes: null,
          votes: 0,
          source: 'user',
          userModified: false,
          cachedAt: 100,
        ),
      ]);
      // Sanity: reset() with a null userIdProvider must NOT delete the pin —
      // that's the gap this method exists to close.
      await signedOutVpm.reset();
      expect(await db.pinDao.getAllPins(), hasLength(1));

      await signedOutVpm.resetForSignedOutUser('former-user');

      expect(await db.pinDao.getAllPins(), isEmpty);
      expect(signedOutVpm.clusters.value, isEmpty);
    },
  );

  group('server-deleted pin cleanup', () {
    Future<void> seed(
      String id, {
      String createdBy = 'other',
      double lat = 30,
      double lng = -95,
    }) => db.pinDao.upsertCachedPins([
      PinMapper.toCachedEntity(
        _pin(id, createdBy: createdBy, lat: lat, lng: lng),
        cachedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);

    Future<void> fetchBox(int zoom) =>
        vpm.fetch(swLat: 29, swLng: -96, neLat: 31, neLng: -94, zoom: zoom);

    Future<Set<String>> ids() async =>
        (await db.pinDao.getAllPins()).map((p) => p.id).toSet();

    test(
      'drops cached pins the server no longer returns at pin zoom',
      () async {
        await seed('a');
        await seed('b');
        remote.bboxResult = [MapItemPin(_pin('a'))];
        await fetchBox(14);
        expect(await ids(), {'a'});
      },
    );

    test('keeps own pins', () async {
      await seed('mine', createdBy: 'me');
      await fetchBox(14);
      expect(await ids(), {'mine'});
    });

    test('keeps pins with a pending sync operation', () async {
      await seed('edited');
      await db.syncQueueDao.enqueue(
        SyncQueueEntity(
          id: 'q1',
          pinId: 'edited',
          operationType: 'UPDATE',
          timestamp: 1,
          retryCount: 0,
          lastError: null,
        ),
      );
      await fetchBox(14);
      expect(await ids(), {'edited'});
    });

    test('keeps pins outside the box', () async {
      await seed('far', lat: 40, lng: -80);
      await fetchBox(14);
      expect(await ids(), {'far'});
    });

    test('does nothing when the response has clusters', () async {
      await seed('a');
      remote.bboxResult = [
        const MapItemCluster(
          centroidLat: 30,
          centroidLng: -95,
          count: 5,
          dominantStatus: PinStatus.ALLOWED,
          dominantRestrictionTag: null,
        ),
      ];
      await fetchBox(14);
      expect(await ids(), {'a'});
    });

    test('does nothing below the cutover zoom', () async {
      await seed('a');
      await fetchBox(11);
      expect(await ids(), {'a'});
    });

    test('empty pin-zoom response clears cached ghosts in the box', () async {
      await seed('a');
      await seed('b');
      await fetchBox(12);
      expect(await ids(), isEmpty);
    });

    test('a superseded fetch deletes nothing', () async {
      await seed('a');
      final gate = Completer<void>();
      remote.gate = gate;
      remote.bboxResult = [];
      final first = fetchBox(14);
      remote.bboxResult = [MapItemPin(_pin('a'))];
      await fetchBox(14);
      gate.complete();
      await first;
      expect(await ids(), {'a'});
    });
  });
}
