import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    // Create in-memory database for testing
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('PinDao', () {
    test('insert and retrieve pin', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pin = PinEntity(
        id: 'pin-1',
        name: 'Test Pin',
        latitude: 39.8283,
        longitude: -98.5795,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-1',
        createdAt: now,
        lastModified: now,
        photoUri: null,
        notes: null,
        votes: 0,
      );

      await database.pinDao.insertPin(pin);
      final retrieved = await database.pinDao.getPinById('pin-1');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'pin-1');
      expect(retrieved.name, 'Test Pin');
      expect(retrieved.latitude, 39.8283);
      expect(retrieved.longitude, -98.5795);
    });

    test('update pin', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pin = PinEntity(
        id: 'pin-2',
        name: 'Original Name',
        latitude: 40.0,
        longitude: -100.0,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-1',
        createdAt: now,
        lastModified: now,
        photoUri: null,
        notes: null,
        votes: 0,
      );

      await database.pinDao.insertPin(pin);

      final updated = pin.copyWith(
        name: 'Updated Name',
        status: 1,
        lastModified: now + 1000,
      );
      await database.pinDao.updatePin(updated);

      final retrieved = await database.pinDao.getPinById('pin-2');
      expect(retrieved!.name, 'Updated Name');
      expect(retrieved.status, 1);
    });

    test('delete pin', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pin = PinEntity(
        id: 'pin-3',
        name: 'To Delete',
        latitude: 40.0,
        longitude: -100.0,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-1',
        createdAt: now,
        lastModified: now,
        photoUri: null,
        notes: null,
        votes: 0,
      );

      await database.pinDao.insertPin(pin);
      await database.pinDao.deletePin('pin-3');

      final retrieved = await database.pinDao.getPinById('pin-3');
      expect(retrieved, isNull);
    });

    test('get all pins', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert multiple pins
      for (int i = 0; i < 5; i++) {
        final pin = PinEntity(
          id: 'pin-$i',
          name: 'Pin $i',
          latitude: 40.0 + i,
          longitude: -100.0 + i,
          status: 0,
          restrictionTag: null,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          createdBy: 'user-1',
          createdAt: now,
          lastModified: now,
          photoUri: null,
          notes: null,
          votes: 0,
        );
        await database.pinDao.insertPin(pin);
      }

      final allPins = await database.pinDao.getAllPins();
      expect(allPins.length, 5);
    });

    test('watch pins stream emits updates', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Start watching and collect emissions
      final stream = database.pinDao.watchAllPins();
      final emissions = <List<PinEntity>>[];

      // Listen to stream
      final subscription = stream.listen(emissions.add);

      // Wait for initial emission (should be empty)
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emissions, isNotEmpty);
      expect(emissions.first, isEmpty);

      // Insert a pin
      final pin = PinEntity(
        id: 'pin-stream',
        name: 'Stream Test',
        latitude: 40.0,
        longitude: -100.0,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-1',
        createdAt: now,
        lastModified: now,
        photoUri: null,
        notes: null,
        votes: 0,
      );
      await database.pinDao.insertPin(pin);

      // Wait for stream to emit the update
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify the stream emitted the new pin
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.length, 1);
      expect(emissions.last.first.id, 'pin-stream');

      await subscription.cancel();
    });

    test('insert or replace updates existing pin', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pin = PinEntity(
        id: 'pin-replace',
        name: 'Original',
        latitude: 40.0,
        longitude: -100.0,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-1',
        createdAt: now,
        lastModified: now,
        photoUri: null,
        notes: null,
        votes: 0,
      );

      await database.pinDao.insertPin(pin);

      // Insert again with same ID but different name
      final updated = pin.copyWith(name: 'Replaced');
      await database.pinDao.insertPin(updated);

      final all = await database.pinDao.getAllPins();
      expect(all.length, 1);
      expect(all.first.name, 'Replaced');
    });
  });

  group('SyncQueueDao', () {
    test('enqueue and retrieve operations', () async {
      final operation = SyncQueueEntity(
        id: 'op-1',
        pinId: 'pin-1',
        operationType: 'CREATE',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        retryCount: 0,
        lastError: null,
      );

      await database.syncQueueDao.enqueue(operation);
      final pending = await database.syncQueueDao.getPendingOperations();

      expect(pending.length, 1);
      expect(pending.first.id, 'op-1');
      expect(pending.first.operationType, 'CREATE');
    });

    test('dequeue removes operation', () async {
      final operation = SyncQueueEntity(
        id: 'op-2',
        pinId: 'pin-2',
        operationType: 'UPDATE',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        retryCount: 0,
        lastError: null,
      );

      await database.syncQueueDao.enqueue(operation);
      await database.syncQueueDao.dequeue('op-2');

      final pending = await database.syncQueueDao.getPendingOperations();
      expect(pending, isEmpty);
    });

    test('increment retry count updates operation', () async {
      final operation = SyncQueueEntity(
        id: 'op-3',
        pinId: 'pin-3',
        operationType: 'DELETE',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        retryCount: 0,
        lastError: null,
      );

      await database.syncQueueDao.enqueue(operation);
      await database.syncQueueDao.incrementRetryCount('op-3', 'Network error');

      final pending = await database.syncQueueDao.getPendingOperations();
      expect(pending.first.retryCount, 1);
      expect(pending.first.lastError, 'Network error');
    });

    test('clear completed removes all operations', () async {
      for (int i = 0; i < 3; i++) {
        final operation = SyncQueueEntity(
          id: 'op-$i',
          pinId: 'pin-$i',
          operationType: 'CREATE',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          retryCount: 0,
          lastError: null,
        );
        await database.syncQueueDao.enqueue(operation);
      }

      await database.syncQueueDao.clearCompleted();
      final pending = await database.syncQueueDao.getPendingOperations();
      expect(pending, isEmpty);
    });

    test('multiple operations maintain order', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < 5; i++) {
        final operation = SyncQueueEntity(
          id: 'op-$i',
          pinId: 'pin-$i',
          operationType: 'CREATE',
          timestamp: now + i,
          retryCount: 0,
          lastError: null,
        );
        await database.syncQueueDao.enqueue(operation);
      }

      final pending = await database.syncQueueDao.getPendingOperations();
      expect(pending.length, 5);
    });
  });
}
