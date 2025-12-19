import 'package:drift/drift.dart';
import 'database.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase> with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<void> enqueue(SyncQueueEntity operation) async {
    await into(syncQueue).insert(operation, mode: InsertMode.insertOrReplace);
  }

  Future<void> dequeue(String id) async {
    await (delete(syncQueue)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<List<SyncQueueEntity>> getPendingOperations() {
    return select(syncQueue).get();
  }

  Future<void> incrementRetryCount(String id, String error) async {
    final operation = await (select(syncQueue)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (operation != null) {
      await update(syncQueue).replace(
        operation.copyWith(
          retryCount: operation.retryCount + 1,
          lastError: Value(error),
        ),
      );
    }
  }

  Future<void> clearCompleted() async {
    await delete(syncQueue).go();
  }
}
