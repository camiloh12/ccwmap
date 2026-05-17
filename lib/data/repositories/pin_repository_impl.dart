import 'package:uuid/uuid.dart';

import '../../domain/models/pin.dart';
import '../../domain/models/sync_operation.dart';
import '../../domain/repositories/pin_repository.dart';
import '../database/database.dart';
import '../mappers/pin_mapper.dart';
import '../mappers/sync_operation_mapper.dart';
import '../sync/my_pins_sync.dart';

/// Implementation of PinRepository with offline-first sync queue
class PinRepositoryImpl implements PinRepository {
  final PinDao _pinDao;
  final SyncQueueDao _syncQueueDao;
  final PinTombstoneDao _tombstoneDao;
  final MyPinsSync? _myPinsSync;
  final Uuid _uuid = const Uuid();

  PinRepositoryImpl(
    this._pinDao,
    this._syncQueueDao,
    this._tombstoneDao, {
    MyPinsSync? myPinsSync,
  }) : _myPinsSync = myPinsSync;

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

    // Record a persistent tombstone so the download phase of any future sync
    // cycle knows not to re-insert this pin from remote — even if the remote
    // delete is silently blocked by RLS or the DELETE operation is dequeued
    // before the download runs.
    await _tombstoneDao.insertTombstone(id, DateTime.now());

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
    final s = _myPinsSync;
    if (s != null) return s.sync();
    return const SyncResult(
      uploaded: 0,
      downloaded: 0,
      errors: 0,
      errorMessage: 'MyPinsSync not initialized',
    );
  }
}
