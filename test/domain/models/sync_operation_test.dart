import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/sync_operation.dart';

void main() {
  group('SyncOperationType', () {
    test('toStorageString returns uppercase name', () {
      expect(SyncOperationType.create.toStorageString(), 'CREATE');
      expect(SyncOperationType.update.toStorageString(), 'UPDATE');
      expect(SyncOperationType.delete.toStorageString(), 'DELETE');
    });

    test('fromStorageString parses correctly (case-insensitive)', () {
      expect(SyncOperationType.fromStorageString('CREATE'),
          SyncOperationType.create);
      expect(SyncOperationType.fromStorageString('create'),
          SyncOperationType.create);
      expect(SyncOperationType.fromStorageString('UPDATE'),
          SyncOperationType.update);
      expect(SyncOperationType.fromStorageString('DELETE'),
          SyncOperationType.delete);
    });

    test('fromStorageString throws on invalid value', () {
      expect(
        () => SyncOperationType.fromStorageString('INVALID'),
        throwsArgumentError,
      );
    });
  });

  group('SyncOperation', () {
    final now = DateTime.now();
    final operation = SyncOperation(
      id: 'test-id',
      pinId: 'pin-123',
      operationType: SyncOperationType.create,
      timestamp: now,
      retryCount: 0,
    );

    test('creates instance with required fields', () {
      expect(operation.id, 'test-id');
      expect(operation.pinId, 'pin-123');
      expect(operation.operationType, SyncOperationType.create);
      expect(operation.timestamp, now);
      expect(operation.retryCount, 0);
      expect(operation.lastError, null);
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = operation.copyWith(
        retryCount: 1,
        lastError: 'Network error',
      );

      expect(updated.id, operation.id);
      expect(updated.pinId, operation.pinId);
      expect(updated.retryCount, 1);
      expect(updated.lastError, 'Network error');
    });

    test('hasExceededMaxRetries returns correct value', () {
      expect(operation.hasExceededMaxRetries(), false);
      expect(operation.copyWith(retryCount: 2).hasExceededMaxRetries(), false);
      expect(operation.copyWith(retryCount: 3).hasExceededMaxRetries(), true);
      expect(operation.copyWith(retryCount: 4).hasExceededMaxRetries(), true);
    });

    test('hasExceededMaxRetries respects custom maxRetries', () {
      final op = operation.copyWith(retryCount: 2);
      expect(op.hasExceededMaxRetries(maxRetries: 1), true);
      expect(op.hasExceededMaxRetries(maxRetries: 5), false);
    });

    test('getRetryDelay returns exponential backoff', () {
      expect(operation.getRetryDelay(), Duration.zero);
      expect(
        operation.copyWith(retryCount: 1).getRetryDelay(),
        const Duration(seconds: 2),
      );
      expect(
        operation.copyWith(retryCount: 2).getRetryDelay(),
        const Duration(seconds: 4),
      );
      expect(
        operation.copyWith(retryCount: 3).getRetryDelay(),
        const Duration(seconds: 8),
      );
      expect(
        operation.copyWith(retryCount: 10).getRetryDelay(),
        const Duration(seconds: 8),
      );
    });

    test('canRetry returns true for first attempt', () {
      expect(operation.canRetry(), true);
    });

    test('canRetry respects retry delay', () {
      // Operation from 10 seconds ago with retry count 1 (2s delay)
      final oldOperation = SyncOperation(
        id: 'test-id',
        pinId: 'pin-123',
        operationType: SyncOperationType.create,
        timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
        retryCount: 1,
      );

      expect(oldOperation.canRetry(), true);

      // Recent operation with retry count 1
      final recentOperation = operation.copyWith(retryCount: 1);
      expect(recentOperation.canRetry(), false);
    });

    test('equality works correctly', () {
      final op1 = SyncOperation(
        id: 'id1',
        pinId: 'pin1',
        operationType: SyncOperationType.create,
        timestamp: now,
      );

      final op2 = SyncOperation(
        id: 'id1',
        pinId: 'pin1',
        operationType: SyncOperationType.create,
        timestamp: now,
      );

      final op3 = op1.copyWith(retryCount: 1);

      expect(op1, op2);
      expect(op1, isNot(op3));
    });

    test('hashCode works correctly', () {
      final op1 = SyncOperation(
        id: 'id1',
        pinId: 'pin1',
        operationType: SyncOperationType.create,
        timestamp: now,
      );

      final op2 = SyncOperation(
        id: 'id1',
        pinId: 'pin1',
        operationType: SyncOperationType.create,
        timestamp: now,
      );

      expect(op1.hashCode, op2.hashCode);
    });

    test('toString includes key information', () {
      final str = operation.toString();
      expect(str, contains('test-id'));
      expect(str, contains('pin-123'));
      expect(str, contains('create'));
      expect(str, contains('retryCount: 0'));
    });
  });
}
