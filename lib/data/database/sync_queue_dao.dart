part of 'database.dart';

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

  /// Get pending operations sorted by timestamp (FIFO)
  Future<List<SyncQueueEntity>> getPendingOperationsSorted() {
    return (select(syncQueue)..orderBy([(tbl) => OrderingTerm(expression: tbl.timestamp)])).get();
  }

  /// Get all operations for a specific pin
  Future<List<SyncQueueEntity>> getOperationsForPin(String pinId) {
    return (select(syncQueue)..where((tbl) => tbl.pinId.equals(pinId))).get();
  }

  /// Delete all operations for a specific pin (useful for queue optimization)
  Future<void> deleteOperationsForPin(String pinId) async {
    await (delete(syncQueue)..where((tbl) => tbl.pinId.equals(pinId))).go();
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

  /// Update the timestamp of an operation (used when re-queueing)
  Future<void> updateTimestamp(String id, int timestamp) async {
    final operation = await (select(syncQueue)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
    if (operation != null) {
      await update(syncQueue).replace(
        operation.copyWith(timestamp: timestamp),
      );
    }
  }
}
