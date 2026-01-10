import 'package:uuid/uuid.dart';

import '../../domain/models/pin.dart';
import '../../domain/models/sync_operation.dart';
import '../../domain/repositories/pin_repository.dart';
import '../database/database.dart';
import '../datasources/remote_data_source_interface.dart';
import '../mappers/pin_mapper.dart';
import '../mappers/sync_operation_mapper.dart';
import '../sync/sync_manager.dart';

/// Implementation of PinRepository with offline-first sync queue
class PinRepositoryImpl implements PinRepository {
  final PinDao _pinDao;
  final SyncQueueDao _syncQueueDao;
  final SyncManager? _syncManager;
  final Uuid _uuid = const Uuid();

  PinRepositoryImpl(
    this._pinDao,
    this._syncQueueDao, {
    SyncManager? syncManager,
  }) : _syncManager = syncManager;

  @override
  Stream<List<Pin>> watchPins() {
    return _pinDao.watchAllPins().map((entities) {
      return entities.map((entity) => PinMapper.fromEntity(entity)).toList();
    });
  }

  @override
  Future<List<Pin>> getPins() async {
    final entities = await _pinDao.getAllPins();
    return entities.map((entity) => PinMapper.fromEntity(entity)).toList();
  }

  @override
  Future<Pin?> getPinById(String id) async {
    final entity = await _pinDao.getPinById(id);
    if (entity == null) return null;
    return PinMapper.fromEntity(entity);
  }

  @override
  Future<void> addPin(Pin pin) async {
    // Write to local database immediately (offline-first)
    final entity = PinMapper.toEntity(pin);
    await _pinDao.insertPin(entity);

    // Queue CREATE operation for sync
    final syncOperation = SyncOperation(
      id: _uuid.v4(),
      pinId: pin.id,
      operationType: SyncOperationType.create,
      timestamp: DateTime.now(),
      retryCount: 0,
    );
    await _syncQueueDao.enqueue(SyncOperationMapper.toEntity(syncOperation));
  }

  @override
  Future<void> updatePin(Pin pin) async {
    // Write to local database immediately (offline-first)
    final entity = PinMapper.toEntity(pin);
    await _pinDao.updatePin(entity);

    // Delete any existing queued operations for this pin (optimization)
    await _syncQueueDao.deleteOperationsForPin(pin.id);

    // Queue UPDATE operation for sync
    final syncOperation = SyncOperation(
      id: _uuid.v4(),
      pinId: pin.id,
      operationType: SyncOperationType.update,
      timestamp: DateTime.now(),
      retryCount: 0,
    );
    await _syncQueueDao.enqueue(SyncOperationMapper.toEntity(syncOperation));
  }

  @override
  Future<void> deletePin(String id) async {
    // Delete from local database immediately (offline-first)
    await _pinDao.deletePin(id);

    // Delete any existing queued operations for this pin (optimization)
    await _syncQueueDao.deleteOperationsForPin(id);

    // Queue DELETE operation for sync
    final syncOperation = SyncOperation(
      id: _uuid.v4(),
      pinId: id,
      operationType: SyncOperationType.delete,
      timestamp: DateTime.now(),
      retryCount: 0,
    );
    await _syncQueueDao.enqueue(SyncOperationMapper.toEntity(syncOperation));
  }

  @override
  Future<SyncResult> syncWithRemote() async {
    // Delegate to SyncManager if available (Iteration 10+)
    if (_syncManager != null) {
      print('[PinRepository] Delegating sync to SyncManager');
      return await _syncManager!.sync();
    }

    // Fallback: No sync manager available
    print('[PinRepository] No SyncManager available, skipping sync');
    return SyncResult(
      uploaded: 0,
      downloaded: 0,
      errors: 0,
      errorMessage: 'SyncManager not initialized',
    );
  }
}
