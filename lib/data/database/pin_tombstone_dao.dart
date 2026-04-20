part of 'database.dart';

@DriftAccessor(tables: [PinTombstones])
class PinTombstoneDao extends DatabaseAccessor<AppDatabase>
    with _$PinTombstoneDaoMixin {
  PinTombstoneDao(super.db);

  Future<void> insertTombstone(String pinId, DateTime deletedAt) async {
    await into(pinTombstones).insert(
      PinTombstoneEntity(
        pinId: pinId,
        deletedAt: deletedAt.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> removeTombstone(String pinId) async {
    await (delete(pinTombstones)..where((tbl) => tbl.pinId.equals(pinId))).go();
  }

  Future<Set<String>> getAllTombstonedPinIds() async {
    final rows = await select(pinTombstones).get();
    return rows.map((r) => r.pinId).toSet();
  }

  Future<bool> isTombstoned(String pinId) async {
    final row = await (select(pinTombstones)
          ..where((tbl) => tbl.pinId.equals(pinId)))
        .getSingleOrNull();
    return row != null;
  }
}
