import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/data/mappers/supabase_pin_mapper.dart';
import 'package:ccwmap/data/mappers/sync_operation_mapper.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/domain/models/sync_operation.dart';
import 'package:ccwmap/domain/repositories/pin_repository.dart';

/// Manages synchronization between local database and remote server
///
/// Implements offline-first pattern with:
/// - Retry logic with exponential backoff
/// - Queue optimization (deduplication)
/// - Conflict resolution (last-write-wins)
class SyncManager {
  final SyncQueueDao _syncQueueDao;
  final PinDao _pinDao;
  final RemoteDataSourceInterface _remoteDataSource;
  final NetworkMonitor _networkMonitor;

  static const int _maxRetries = 3;

  SyncManager({
    required SyncQueueDao syncQueueDao,
    required PinDao pinDao,
    required RemoteDataSourceInterface remoteDataSource,
    required NetworkMonitor networkMonitor,
  })  : _syncQueueDao = syncQueueDao,
        _pinDao = pinDao,
        _remoteDataSource = remoteDataSource,
        _networkMonitor = networkMonitor;

  /// Perform a full sync: upload queued operations, then download remote changes
  Future<SyncResult> sync() async {
    // Check if we're online
    if (!_networkMonitor.isOnline) {
      return SyncResult(
        uploaded: 0,
        downloaded: 0,
        errors: 0,
        errorMessage: 'Device is offline',
      );
    }

    int uploaded = 0;
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;

    try {
      // Step 1: Optimize queue (remove redundant operations)
      await _optimizeQueue();

      // Step 2: Process queue (upload pending operations)
      // Returns deleted pin IDs so we don't re-download them
      final uploadResult = await _processQueue();
      uploaded = uploadResult.uploaded;
      errors = uploadResult.errors;
      errorMessage = uploadResult.errorMessage;

      // Step 3: Download and merge remote changes
      // Pass deleted pin IDs to avoid re-inserting them
      final downloadResult = await _downloadRemoteChanges(uploadResult.deletedPinIds);
      downloaded = downloadResult.downloaded;
      errors += downloadResult.errors;
      errorMessage ??= downloadResult.errorMessage;

      return SyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        errors: errors,
        errorMessage: errorMessage,
      );
    } catch (e) {
      return SyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        errors: errors + 1,
        errorMessage: e.toString(),
      );
    }
  }

  /// Optimize the queue by removing redundant operations
  ///
  /// Rules:
  /// - If DELETE exists for a pin, remove all earlier operations for that pin
  /// - If multiple UPDATEs exist for a pin, keep only the latest
  Future<void> _optimizeQueue() async {
    final allOperations = await _syncQueueDao.getPendingOperationsSorted();
    if (allOperations.isEmpty) return;

    // Group operations by pinId
    final Map<String, List<SyncQueueEntity>> operationsByPin = {};
    for (final op in allOperations) {
      operationsByPin.putIfAbsent(op.pinId, () => []).add(op);
    }

    // Process each pin's operations
    for (final entry in operationsByPin.entries) {
      final operations = entry.value;

      if (operations.length <= 1) continue; // Nothing to optimize

      // Check if there's a DELETE operation
      final deleteOp = operations.lastWhere(
        (op) => op.operationType == 'DELETE',
        orElse: () => operations.first, // Dummy, won't be used
      );

      if (deleteOp.operationType == 'DELETE') {
        // Remove all operations except the DELETE
        for (final op in operations) {
          if (op.id != deleteOp.id) {
            await _syncQueueDao.dequeue(op.id);
          }
        }
      } else {
        // No DELETE - keep only the latest UPDATE (if multiple exist)
        final updates = operations.where((op) => op.operationType == 'UPDATE').toList();
        if (updates.length > 1) {
          // Sort by timestamp, keep latest
          updates.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          for (int i = 0; i < updates.length - 1; i++) {
            await _syncQueueDao.dequeue(updates[i].id);
          }
        }
      }
    }
  }

  /// Process the sync queue and upload operations to remote
  ///
  /// Returns a result that includes IDs of successfully deleted pins,
  /// so they won't be re-downloaded during the download phase.
  Future<_ProcessQueueResult> _processQueue() async {
    final operations = await _syncQueueDao.getPendingOperationsSorted();
    if (operations.isEmpty) {
      return _ProcessQueueResult(uploaded: 0, errors: 0, deletedPinIds: {});
    }

    int uploaded = 0;
    int errors = 0;
    String? errorMessage;
    final Set<String> deletedPinIds = {};

    for (final entity in operations) {
      final operation = SyncOperationMapper.fromEntity(entity);

      // Check if operation has exceeded max retries
      if (operation.hasExceededMaxRetries(maxRetries: _maxRetries)) {
        await _syncQueueDao.dequeue(operation.id);
        errors++;
        errorMessage ??= 'Some operations exceeded max retries';
        continue;
      }

      // Check if enough time has passed for retry
      if (!operation.canRetry()) {
        continue;
      }

      // Process the operation
      try {
        await _processOperation(operation);
        uploaded++;
        // Track successfully deleted pins
        if (operation.operationType == SyncOperationType.delete) {
          deletedPinIds.add(operation.pinId);
        }
        // Remove from queue on success
        await _syncQueueDao.dequeue(operation.id);
      } catch (e) {
        errors++;
        errorMessage ??= e.toString();
        // Increment retry count
        await _syncQueueDao.incrementRetryCount(operation.id, e.toString());
      }
    }

    return _ProcessQueueResult(
      uploaded: uploaded,
      errors: errors,
      errorMessage: errorMessage,
      deletedPinIds: deletedPinIds,
    );
  }

  /// Process a single sync operation
  Future<void> _processOperation(SyncOperation operation) async {
    switch (operation.operationType) {
      case SyncOperationType.create:
        await _processCreateOperation(operation.pinId);
        break;
      case SyncOperationType.update:
        await _processUpdateOperation(operation.pinId);
        break;
      case SyncOperationType.delete:
        await _processDeleteOperation(operation.pinId);
        break;
    }
  }

  /// Process CREATE operation: upload pin to remote
  Future<void> _processCreateOperation(String pinId) async {
    // Get pin from local database
    final pinEntity = await _pinDao.getPinById(pinId);
    if (pinEntity == null) {
      return; // Pin was deleted locally, operation is now obsolete
    }

    final pin = PinMapper.fromEntity(pinEntity);
    final dto = SupabasePinMapper.toDto(pin);

    try {
      await _remoteDataSource.insertPin(dto);
    } catch (e) {
      // Check if pin already exists remotely (idempotent operation)
      if (e.toString().contains('duplicate') ||
          e.toString().contains('already exists') ||
          e.toString().contains('unique')) {
        return; // Treat as success (idempotent operation)
      }
      rethrow;
    }
  }

  /// Process UPDATE operation: upload pin changes to remote
  Future<void> _processUpdateOperation(String pinId) async {
    // Get pin from local database
    final pinEntity = await _pinDao.getPinById(pinId);
    if (pinEntity == null) {
      return; // Pin was deleted locally, operation is now obsolete
    }

    final pin = PinMapper.fromEntity(pinEntity);
    final dto = SupabasePinMapper.toDto(pin);

    try {
      await _remoteDataSource.updatePin(dto);
    } catch (e) {
      // Check if pin doesn't exist remotely (treat as success - it was deleted remotely)
      if (e.toString().contains('not found') || e.toString().contains('no rows')) {
        return; // Treat as success (pin deleted remotely)
      }
      rethrow;
    }
  }

  /// Process DELETE operation: delete pin from remote
  Future<void> _processDeleteOperation(String pinId) async {
    try {
      await _remoteDataSource.deletePin(pinId);
    } catch (e) {
      // Check if pin doesn't exist remotely (idempotent operation)
      if (e.toString().contains('not found') || e.toString().contains('no rows')) {
        return; // Treat as success (idempotent operation)
      }
      rethrow;
    }
  }

  /// Download remote changes and merge with local database
  ///
  /// Uses batched operations to minimize stream emissions and improve performance.
  /// [recentlyDeletedPinIds] contains IDs of pins that were just deleted in
  /// the upload phase - these should not be re-inserted.
  Future<SyncResult> _downloadRemoteChanges(Set<String> recentlyDeletedPinIds) async {
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;

    try {
      final remotePins = await _remoteDataSource.getAllPins();

      // Collect pins to insert/update in batch
      final List<PinEntity> pinsToInsert = [];
      final List<PinEntity> pinsToUpdate = [];

      // Get all pending delete operations to avoid re-inserting deleted pins
      final allPendingOps = await _syncQueueDao.getPendingOperationsSorted();
      final pendingDeletePinIds = allPendingOps
          .where((op) => op.operationType == 'DELETE')
          .map((op) => op.pinId)
          .toSet();

      // Combine pending deletes with recently deleted pins from this sync cycle
      final allDeletedPinIds = {...pendingDeletePinIds, ...recentlyDeletedPinIds};

      for (final remoteDto in remotePins) {
        try {
          final remotePinDomain = SupabasePinMapper.fromDto(remoteDto);

          // Skip pins that were deleted locally (pending or just processed)
          if (allDeletedPinIds.contains(remotePinDomain.id)) {
            continue;
          }

          final localEntity = await _pinDao.getPinById(remotePinDomain.id);
          final remoteEntity = PinMapper.toEntity(remotePinDomain);

          if (localEntity == null) {
            // Pin doesn't exist locally - insert it
            pinsToInsert.add(remoteEntity);
            downloaded++;
          } else {
            // Pin exists locally - compare timestamps
            final localPin = PinMapper.fromEntity(localEntity);
            if (remotePinDomain.metadata.lastModified.isAfter(localPin.metadata.lastModified)) {
              // Remote is newer - update local
              pinsToUpdate.add(remoteEntity);
              downloaded++;
            }
            // else: local is newer or same, keep local
          }
        } catch (e) {
          errors++;
          errorMessage ??= e.toString();
        }
      }

      // Batch execute all inserts and updates in a single transaction
      if (pinsToInsert.isNotEmpty || pinsToUpdate.isNotEmpty) {
        await _pinDao.batchUpsertPins(pinsToInsert, pinsToUpdate);
      }

      return SyncResult(
        uploaded: 0,
        downloaded: downloaded,
        errors: errors,
        errorMessage: errorMessage,
      );
    } catch (e) {
      return SyncResult(
        uploaded: 0,
        downloaded: downloaded,
        errors: errors + 1,
        errorMessage: e.toString(),
      );
    }
  }
}

/// Internal result class for _processQueue that includes deleted pin IDs
class _ProcessQueueResult {
  final int uploaded;
  final int errors;
  final String? errorMessage;
  final Set<String> deletedPinIds;

  _ProcessQueueResult({
    required this.uploaded,
    required this.errors,
    this.errorMessage,
    required this.deletedPinIds,
  });
}
