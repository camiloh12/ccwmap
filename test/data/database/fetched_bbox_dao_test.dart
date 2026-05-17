import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('FetchedBboxDao', () {
    test('recordFetch inserts a row', () async {
      await db.fetchedBboxDao.recordFetch(
        swLat: 30.0,
        swLng: -95.5,
        neLat: 30.5,
        neLng: -95.0,
        zoom: 12,
        fetchedAt: DateTime.utc(2026, 5, 16, 12),
        pinCount: 42,
      );

      final rows = await db.fetchedBboxDao.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.pinCount, 42);
    });

    test('pruneOlderThan removes rows older than threshold', () async {
      await db.fetchedBboxDao.recordFetch(
        swLat: 0, swLng: 0, neLat: 1, neLng: 1, zoom: 10,
        fetchedAt: DateTime.utc(2026, 1, 1), pinCount: 1,
      );
      await db.fetchedBboxDao.recordFetch(
        swLat: 0, swLng: 0, neLat: 1, neLng: 1, zoom: 10,
        fetchedAt: DateTime.utc(2026, 5, 1), pinCount: 1,
      );

      await db.fetchedBboxDao.pruneOlderThan(DateTime.utc(2026, 3, 1));

      final rows = await db.fetchedBboxDao.getAll();
      expect(rows, hasLength(1));
      expect(
        rows.single.fetchedAt,
        DateTime.utc(2026, 5, 1).millisecondsSinceEpoch,
      );
    });
  });
}
