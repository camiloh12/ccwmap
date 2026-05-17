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

  /// Count pins not created by [myUserId] (anonymous-cached pins with
  /// `createdBy IS NULL` count too). Used by ViewportPinsManager to decide
  /// when to LRU-evict.
  Future<int> countNonMinePins(String myUserId) async {
    final query = selectOnly(pins)
      ..addColumns([pins.id.count()])
      ..where(pins.createdBy.equals(myUserId).not() | pins.createdBy.isNull());
    final row = await query.getSingle();
    return row.read(pins.id.count()) ?? 0;
  }

  /// Evict the oldest cached non-mine pins until row count <= [maxRows].
  /// Pins with `cachedAt IS NULL` are never evicted (they're not bbox-cache
  /// rows — either user-created or pre-Phase-1 legacy data).
  Future<void> evictOldestCachedNonMine({
    required String myUserId,
    required int maxRows,
  }) async {
    final excess = await countNonMinePins(myUserId) - maxRows;
    if (excess <= 0) return;

    final victims = await (select(pins)
          ..where((t) =>
              t.cachedAt.isNotNull() &
              (t.createdBy.equals(myUserId).not() | t.createdBy.isNull()))
          ..orderBy([(t) => OrderingTerm.asc(t.cachedAt)])
          ..limit(excess))
        .get();

    if (victims.isEmpty) return;

    await batch((b) {
      for (final v in victims) {
        b.deleteWhere(pins, (t) => t.id.equals(v.id));
      }
    });
  }

  /// Bulk upsert cached pins from a bbox fetch. Single transaction → single
  /// stream emission to the UI.
  Future<void> upsertCachedPins(List<PinEntity> entities) async {
    if (entities.isEmpty) return;
    await batch((b) {
      for (final e in entities) {
        b.insert(pins, e, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// Drop every cached non-mine pin. Used by the pathological-cache fallback
  /// on app start (spec §6: "if cached count > 2× soft limit, drop all
  /// created_by != me rows, rebuild via bbox").
  Future<void> deleteAllCachedNonMinePins(String myUserId) async {
    await (delete(pins)
          ..where((t) =>
              t.cachedAt.isNotNull() &
              (t.createdBy.equals(myUserId).not() | t.createdBy.isNull())))
        .go();
  }
}
