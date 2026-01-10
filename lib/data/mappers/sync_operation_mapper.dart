import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/domain/models/sync_operation.dart';

/// Mapper for converting between SyncQueueEntity (database) and SyncOperation (domain)
class SyncOperationMapper {
  /// Convert domain model to database entity
  static SyncQueueEntity toEntity(SyncOperation operation) {
    return SyncQueueEntity(
      id: operation.id,
      pinId: operation.pinId,
      operationType: operation.operationType.toStorageString(),
      timestamp: operation.timestamp.millisecondsSinceEpoch,
      retryCount: operation.retryCount,
      lastError: operation.lastError,
    );
  }

  /// Convert database entity to domain model
  static SyncOperation fromEntity(SyncQueueEntity entity) {
    return SyncOperation(
      id: entity.id,
      pinId: entity.pinId,
      operationType: SyncOperationType.fromStorageString(entity.operationType),
      timestamp: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
      retryCount: entity.retryCount,
      lastError: entity.lastError,
    );
  }

  /// Convert list of entities to list of domain models
  static List<SyncOperation> fromEntityList(List<SyncQueueEntity> entities) {
    return entities.map(fromEntity).toList();
  }

  /// Convert list of domain models to list of entities
  static List<SyncQueueEntity> toEntityList(List<SyncOperation> operations) {
    return operations.map(toEntity).toList();
  }
}
