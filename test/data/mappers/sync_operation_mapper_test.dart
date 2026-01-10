import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/mappers/sync_operation_mapper.dart';
import 'package:ccwmap/domain/models/sync_operation.dart';
import 'package:drift/drift.dart' as drift;

void main() {
  group('SyncOperationMapper', () {
    final timestamp = DateTime(2025, 1, 9, 12, 0, 0);

    test('toEntity converts domain model to entity', () {
      final operation = SyncOperation(
        id: 'op-123',
        pinId: 'pin-456',
        operationType: SyncOperationType.create,
        timestamp: timestamp,
        retryCount: 0,
        lastError: null,
      );

      final entity = SyncOperationMapper.toEntity(operation);

      expect(entity.id, 'op-123');
      expect(entity.pinId, 'pin-456');
      expect(entity.operationType, 'CREATE');
      expect(entity.timestamp, timestamp.millisecondsSinceEpoch);
      expect(entity.retryCount, 0);
      expect(entity.lastError, null);
    });

    test('toEntity handles all operation types', () {
      final createOp = SyncOperation(
        id: '1',
        pinId: 'pin',
        operationType: SyncOperationType.create,
        timestamp: timestamp,
      );

      final updateOp = createOp.copyWith(
        id: '2',
        operationType: SyncOperationType.update,
      );

      final deleteOp = createOp.copyWith(
        id: '3',
        operationType: SyncOperationType.delete,
      );

      expect(SyncOperationMapper.toEntity(createOp).operationType, 'CREATE');
      expect(SyncOperationMapper.toEntity(updateOp).operationType, 'UPDATE');
      expect(SyncOperationMapper.toEntity(deleteOp).operationType, 'DELETE');
    });

    test('toEntity preserves retry count and error', () {
      final operation = SyncOperation(
        id: 'op-123',
        pinId: 'pin-456',
        operationType: SyncOperationType.update,
        timestamp: timestamp,
        retryCount: 2,
        lastError: 'Network timeout',
      );

      final entity = SyncOperationMapper.toEntity(operation);

      expect(entity.retryCount, 2);
      expect(entity.lastError, 'Network timeout');
    });

    test('fromEntity converts entity to domain model', () {
      final entity = SyncQueueEntity(
        id: 'op-789',
        pinId: 'pin-101',
        operationType: 'UPDATE',
        timestamp: timestamp.millisecondsSinceEpoch,
        retryCount: 1,
        lastError: 'Connection failed',
      );

      final operation = SyncOperationMapper.fromEntity(entity);

      expect(operation.id, 'op-789');
      expect(operation.pinId, 'pin-101');
      expect(operation.operationType, SyncOperationType.update);
      expect(operation.timestamp, timestamp);
      expect(operation.retryCount, 1);
      expect(operation.lastError, 'Connection failed');
    });

    test('fromEntity handles all operation types', () {
      final baseEntity = SyncQueueEntity(
        id: '1',
        pinId: 'pin',
        operationType: 'CREATE',
        timestamp: timestamp.millisecondsSinceEpoch,
        retryCount: 0,
      );

      expect(
        SyncOperationMapper.fromEntity(baseEntity).operationType,
        SyncOperationType.create,
      );

      expect(
        SyncOperationMapper.fromEntity(
          baseEntity.copyWith(operationType: 'UPDATE'),
        ).operationType,
        SyncOperationType.update,
      );

      expect(
        SyncOperationMapper.fromEntity(
          baseEntity.copyWith(operationType: 'DELETE'),
        ).operationType,
        SyncOperationType.delete,
      );
    });

    test('round-trip conversion preserves data', () {
      final original = SyncOperation(
        id: 'op-999',
        pinId: 'pin-888',
        operationType: SyncOperationType.delete,
        timestamp: timestamp,
        retryCount: 3,
        lastError: 'Max retries exceeded',
      );

      final entity = SyncOperationMapper.toEntity(original);
      final roundTrip = SyncOperationMapper.fromEntity(entity);

      expect(roundTrip, original);
    });

    test('fromEntityList converts list of entities', () {
      final entities = [
        SyncQueueEntity(
          id: '1',
          pinId: 'pin-1',
          operationType: 'CREATE',
          timestamp: timestamp.millisecondsSinceEpoch,
          retryCount: 0,
        ),
        SyncQueueEntity(
          id: '2',
          pinId: 'pin-2',
          operationType: 'UPDATE',
          timestamp: timestamp.millisecondsSinceEpoch,
          retryCount: 1,
        ),
      ];

      final operations = SyncOperationMapper.fromEntityList(entities);

      expect(operations.length, 2);
      expect(operations[0].id, '1');
      expect(operations[0].operationType, SyncOperationType.create);
      expect(operations[1].id, '2');
      expect(operations[1].operationType, SyncOperationType.update);
    });

    test('toEntityList converts list of operations', () {
      final operations = [
        SyncOperation(
          id: '1',
          pinId: 'pin-1',
          operationType: SyncOperationType.create,
          timestamp: timestamp,
        ),
        SyncOperation(
          id: '2',
          pinId: 'pin-2',
          operationType: SyncOperationType.delete,
          timestamp: timestamp,
        ),
      ];

      final entities = SyncOperationMapper.toEntityList(operations);

      expect(entities.length, 2);
      expect(entities[0].id, '1');
      expect(entities[0].operationType, 'CREATE');
      expect(entities[1].id, '2');
      expect(entities[1].operationType, 'DELETE');
    });
  });
}
