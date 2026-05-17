import 'package:ccwmap/data/database/database.dart';
// `hide isNull` is load-bearing — without it Drift's query helper
// `isNull` shadows the flutter_test matcher and `expect(x, isNull)` calls
// stop compiling. The analyzer can't see the directive as "using" the
// package, hence the ignore.
// ignore: unused_import
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase schemaVersion 4', () {
    test('reports schemaVersion == 4', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, 4);
    });

    test('pins table has nullable cachedAt column', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.pins)
          .insert(
            PinsCompanion.insert(
              id: 'pin-1',
              name: 'Test',
              latitude: 30.0,
              longitude: -95.0,
              status: 0,
              createdAt: 1,
              lastModified: 1,
            ),
          );

      final row = await (db.select(
        db.pins,
      )..where((t) => t.id.equals('pin-1'))).getSingle();
      expect(row.cachedAt, isNull);
    });

    test('fetched_bboxes table exists and accepts inserts', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.fetchedBboxes)
          .insert(
            FetchedBboxesCompanion.insert(
              swLat: 30.0,
              swLng: -95.5,
              neLat: 30.5,
              neLng: -95.0,
              zoom: 12,
              fetchedAt: 1,
              pinCount: 42,
            ),
          );

      final rows = await db.select(db.fetchedBboxes).get();
      expect(rows, hasLength(1));
      expect(rows.first.pinCount, 42);
    });

    test('server_pin_deletions table exists and accepts inserts', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.serverPinDeletions)
          .insert(
            ServerPinDeletionsCompanion.insert(pinId: 'pin-1', deletedAt: 1),
          );

      final rows = await db.select(db.serverPinDeletions).get();
      expect(rows.single.pinId, 'pin-1');
    });
  });
}
