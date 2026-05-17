import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('ServerPinDeletionDao', () {
    test('upsert + getPinIdsDeletedSince', () async {
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-1',
        deletedAt: DateTime.utc(2026, 5, 15),
      );
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-2',
        deletedAt: DateTime.utc(2026, 5, 16),
      );

      final ids = await db.serverPinDeletionDao
          .getPinIdsDeletedSince(DateTime.utc(2026, 5, 15, 23));

      expect(ids, {'pin-2'});
    });

    test('upsert is idempotent — re-inserting the same pin_id replaces',
        () async {
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-1',
        deletedAt: DateTime.utc(2026, 5, 15),
      );
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-1',
        deletedAt: DateTime.utc(2026, 5, 16),
      );

      final all = await db.serverPinDeletionDao.getAll();
      expect(all, hasLength(1));
      expect(
        all.single.deletedAt,
        DateTime.utc(2026, 5, 16).millisecondsSinceEpoch,
      );
    });
  });
}
