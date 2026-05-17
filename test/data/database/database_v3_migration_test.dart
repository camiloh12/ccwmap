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
  group('AppDatabase schemaVersion 3', () {
    // The "reports schemaVersion == 3" tripwire was removed when the schema
    // moved to v4. The v4 migration test owns the current-version assertion;
    // this group is retained because the provenance columns added in v3 must
    // still be present (and behave correctly) on the current schema.

    test('pins table has provenance columns with safe defaults', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // Insert a minimal pin without touching any provenance column.
      await db
          .into(db.pins)
          .insert(
            PinsCompanion.insert(
              id: 'pin-1',
              name: 'Test',
              latitude: 30.0,
              longitude: -95.0,
              status: 0,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              lastModified: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      final row = await (db.select(
        db.pins,
      )..where((t) => t.id.equals('pin-1'))).getSingle();

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
