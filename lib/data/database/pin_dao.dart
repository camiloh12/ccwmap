part of 'database.dart';

@DriftAccessor(tables: [Pins])
class PinDao extends DatabaseAccessor<AppDatabase> with _$PinDaoMixin {
  PinDao(super.db);

  Future<void> insertPin(PinEntity pin) async {
    await into(pins).insert(pin, mode: InsertMode.insertOrReplace);
  }

  Future<void> updatePin(PinEntity pin) async {
    await update(pins).replace(pin);
  }

  Future<void> deletePin(String id) async {
    await (delete(pins)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<PinEntity?> getPinById(String id) async {
    return (select(pins)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Stream<List<PinEntity>> watchAllPins() {
    return select(pins).watch();
  }

  Future<List<PinEntity>> getAllPins() {
    return select(pins).get();
  }

  /// Batch insert and update pins in a single transaction
  ///
  /// This triggers only one stream emission instead of one per operation,
  /// significantly reducing UI rebuilds during sync.
  Future<void> batchUpsertPins(
    List<PinEntity> toInsert,
    List<PinEntity> toUpdate,
  ) async {
    await batch((b) {
      // Batch inserts using insertOrReplace for conflict handling
      for (final pin in toInsert) {
        b.insert(pins, pin, mode: InsertMode.insertOrReplace);
      }
      // Batch updates
      for (final pin in toUpdate) {
        b.replace(pins, pin);
      }
    });
  }
}
