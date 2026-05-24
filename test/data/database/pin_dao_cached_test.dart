import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  PinEntity _pin({required String id, String? createdBy, int? cachedAt}) {
    return PinEntity(
      id: id,
      name: 'p',
      latitude: 30.0,
      longitude: -95.0,
      status: 0,
      restrictionTag: null,
      hasSecurityScreening: false,
      hasPostedSignage: false,
      createdBy: createdBy,
      createdAt: 1,
      lastModified: 1,
      photoUri: null,
      notes: null,
      votes: 0,
      source: 'user',
      userModified: false,
      cachedAt: cachedAt,
    );
  }

  group('PinDao cached-pin helpers', () {
    test('countNonMinePins excludes my pins', () async {
      await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
      await db.pinDao.insertPin(
        _pin(id: 'other-1', createdBy: 'other', cachedAt: 100),
      );
      await db.pinDao.insertPin(
        _pin(id: 'anon-cached', createdBy: null, cachedAt: 100),
      );

      final count = await db.pinDao.countNonMinePins('me');
      expect(count, 2); // other-1 and anon-cached
    });

    test(
      'evictOldestCachedNonMine keeps my pins and newer cached entries',
      () async {
        await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
        await db.pinDao.insertPin(
          _pin(id: 'old', createdBy: 'x', cachedAt: 100),
        );
        await db.pinDao.insertPin(
          _pin(id: 'mid', createdBy: 'x', cachedAt: 200),
        );
        await db.pinDao.insertPin(
          _pin(id: 'new', createdBy: 'x', cachedAt: 300),
        );

        // Cap at 2: should evict 'old' first.
        await db.pinDao.evictOldestCachedNonMine(myUserId: 'me', maxRows: 2);

        final remaining = await db.pinDao.getAllPins();
        final ids = remaining.map((p) => p.id).toSet();
        expect(ids, {'mine', 'mid', 'new'});
      },
    );

    test(
      'evictOldestCachedNonMine never touches pins with cachedAt = null',
      () async {
        await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
        // Pin created by another user but NOT via bbox cache (e.g. older
        // sync model leftover) — cachedAt is null. Eviction must skip it.
        await db.pinDao.insertPin(
          _pin(id: 'legacy-other', createdBy: 'x', cachedAt: null),
        );
        await db.pinDao.insertPin(
          _pin(id: 'cached-other', createdBy: 'x', cachedAt: 100),
        );

        await db.pinDao.evictOldestCachedNonMine(myUserId: 'me', maxRows: 1);

        final remaining = await db.pinDao.getAllPins();
        expect(remaining.map((p) => p.id).toSet(), {'mine', 'legacy-other'});
      },
    );

    test(
      'upsertCachedPins inserts new rows and updates existing ones',
      () async {
        await db.pinDao.insertPin(
          _pin(id: 'existing', createdBy: 'x', cachedAt: 100),
        );

        final updated = _pin(
          id: 'existing',
          createdBy: 'x',
          cachedAt: 200,
        ).copyWith(name: 'updated name');
        final inserted = _pin(id: 'new', createdBy: 'x', cachedAt: 200);

        await db.pinDao.upsertCachedPins([updated, inserted]);

        final all = await db.pinDao.getAllPins();
        expect(all.length, 2);
        expect(all.firstWhere((p) => p.id == 'existing').name, 'updated name');
        expect(all.firstWhere((p) => p.id == 'existing').cachedAt, 200);
      },
    );

    test(
      'deleteAllCachedNonMinePins removes only cached non-mine rows',
      () async {
        await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
        await db.pinDao.insertPin(
          _pin(id: 'legacy', createdBy: 'x', cachedAt: null),
        );
        await db.pinDao.insertPin(
          _pin(id: 'cached', createdBy: 'x', cachedAt: 100),
        );

        await db.pinDao.deleteAllCachedNonMinePins('me');

        final remaining = await db.pinDao.getAllPins();
        expect(remaining.map((p) => p.id).toSet(), {'mine', 'legacy'});
      },
    );
  });
}
