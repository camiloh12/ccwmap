import 'package:ccwmap/data/database/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase schemaVersion 3', () {
    test('reports schemaVersion == 3', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, 3);
    });

    test('pins table has provenance columns with safe defaults', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // Insert a minimal pin without touching any provenance column.
      await db.into(db.pins).insert(PinsCompanion.insert(
            id: 'pin-1',
            name: 'Test',
            latitude: 30.0,
            longitude: -95.0,
            status: 0,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            lastModified: DateTime.now().millisecondsSinceEpoch,
          ));

      final row = await (db.select(db.pins)
            ..where((t) => t.id.equals('pin-1')))
          .getSingle();

      expect(row.source, 'user');
      expect(row.sourceExternalId, isNull);
      expect(row.sourceDatasetVersion, isNull);
      expect(row.importedAt, isNull);
      expect(row.userModified, isFalse);
      expect(row.confidence, isNull);
      expect(row.legalCitation, isNull);
      expect(row.legalCitationVerifiedDate, isNull);
      expect(row.sourceOrphanedAt, isNull);
    });
  });
}
