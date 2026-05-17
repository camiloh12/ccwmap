import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
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

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  }) async => bboxResult;

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

Pin _pin(String id, {String createdBy = 'other'}) => Pin(
  id: id,
  name: id,
  location: Location.fromLatLng(30, -95),
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
}
