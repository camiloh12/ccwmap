part of 'database.dart';

@DriftAccessor(tables: [ServerPinDeletions])
class ServerPinDeletionDao extends DatabaseAccessor<AppDatabase>
    with _$ServerPinDeletionDaoMixin {
  ServerPinDeletionDao(super.db);

  Future<void> upsert({
    required String pinId,
    required DateTime deletedAt,
  }) async {
    await into(serverPinDeletions).insert(
      ServerPinDeletionEntity(
        pinId: pinId,
        deletedAt: deletedAt.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<Set<String>> getPinIdsDeletedSince(DateTime since) async {
    final rows = await (select(serverPinDeletions)
          ..where((t) =>
              t.deletedAt.isBiggerThanValue(since.millisecondsSinceEpoch)))
        .get();
    return rows.map((r) => r.pinId).toSet();
  }

  Future<List<ServerPinDeletionEntity>> getAll() =>
      select(serverPinDeletions).get();
}
