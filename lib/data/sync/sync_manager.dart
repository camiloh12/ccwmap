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
      print('[SyncManager] Offline, skipping sync');
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
      print('[SyncManager] Starting sync...');

      // Step 1: Optimize queue (remove redundant operations)
      await _optimizeQueue();

      // Step 2: Process queue (upload pending operations)
      final uploadResult = await _processQueue();
      uploaded = uploadResult.uploaded;
      errors = uploadResult.errors;
      errorMessage = uploadResult.errorMessage;

      // Step 3: Download and merge remote changes
      final downloadResult = await _downloadRemoteChanges();
      downloaded = downloadResult.downloaded;
      errors += downloadResult.errors;
      errorMessage ??= downloadResult.errorMessage;

      print('[SyncManager] Sync complete: uploaded=$uploaded, downloaded=$downloaded, errors=$errors');

      return SyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        errors: errors,
        errorMessage: errorMessage,
      );
    } catch (e) {
      print('[SyncManager] Sync failed: $e');
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

    print('[SyncManager] Optimizing queue (${allOperations.length} operations)');

    // Group operations by pinId
    final Map<String, List<SyncQueueEntity>> operationsByPin = {};
    for (final op in allOperations) {
      operationsByPin.putIfAbsent(op.pinId, () => []).add(op);
    }

    // Process each pin's operations
    for (final entry in operationsByPin.entries) {
      final pinId = entry.key;
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
            print('[SyncManager] Removing redundant ${op.operationType} for pin $pinId (DELETE exists)');
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
            print('[SyncManager] Removing redundant UPDATE for pin $pinId (newer UPDATE exists)');
            await _syncQueueDao.dequeue(updates[i].id);
          }
        }
      }
    }
  }

  /// Process the sync queue and upload operations to remote
  Future<SyncResult> _processQueue() async {
    final operations = await _syncQueueDao.getPendingOperationsSorted();
    if (operations.isEmpty) {
      print('[SyncManager] Queue is empty');
      return SyncResult(uploaded: 0, downloaded: 0, errors: 0);
    }

    print('[SyncManager] Processing ${operations.length} queued operations');

    int uploaded = 0;
    int errors = 0;
    String? errorMessage;

    for (final entity in operations) {
      final operation = SyncOperationMapper.fromEntity(entity);

      // Check if operation has exceeded max retries
      if (operation.hasExceededMaxRetries(maxRetries: _maxRetries)) {
        print('[SyncManager] Operation ${operation.id} exceeded max retries, removing from queue');
        await _syncQueueDao.dequeue(operation.id);
        errors++;
        errorMessage ??= 'Some operations exceeded max retries';
        continue;
      }

      // Check if enough time has passed for retry
      if (!operation.canRetry()) {
        print('[SyncManager] Operation ${operation.id} not ready for retry yet');
        continue;
      }

      // Process the operation
      try {
        await _processOperation(operation);
        uploaded++;
        // Remove from queue on success
        await _syncQueueDao.dequeue(operation.id);
        print('[SyncManager] Successfully synced ${operation.operationType} for pin ${operation.pinId}');
      } catch (e) {
        print('[SyncManager] Error syncing ${operation.operationType} for pin ${operation.pinId}: $e');
        errors++;
        errorMessage ??= e.toString();
        // Increment retry count
        await _syncQueueDao.incrementRetryCount(operation.id, e.toString());
      }
    }

    return SyncResult(
      uploaded: uploaded,
      downloaded: 0,
      errors: errors,
      errorMessage: errorMessage,
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
      print('[SyncManager] Pin $pinId not found locally, skipping CREATE');
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
        print('[SyncManager] Pin $pinId already exists remotely (idempotent)');
        return; // Treat as success
      }
      rethrow;
    }
  }

  /// Process UPDATE operation: upload pin changes to remote
  Future<void> _processUpdateOperation(String pinId) async {
    // Get pin from local database
    final pinEntity = await _pinDao.getPinById(pinId);
    if (pinEntity == null) {
      print('[SyncManager] Pin $pinId not found locally, skipping UPDATE');
      return; // Pin was deleted locally, operation is now obsolete
    }

    final pin = PinMapper.fromEntity(pinEntity);
    final dto = SupabasePinMapper.toDto(pin);

    try {
      await _remoteDataSource.updatePin(dto);
    } catch (e) {
      // Check if pin doesn't exist remotely (treat as success - it was deleted remotely)
      if (e.toString().contains('not found') || e.toString().contains('no rows')) {
        print('[SyncManager] Pin $pinId not found remotely, skipping UPDATE');
        return; // Treat as success
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
        print('[SyncManager] Pin $pinId not found remotely (idempotent)');
        return; // Treat as success
      }
      rethrow;
    }
  }

  /// Download remote changes and merge with local database
  Future<SyncResult> _downloadRemoteChanges() async {
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;

    try {
      final remotePins = await _remoteDataSource.getAllPins();
      print('[SyncManager] Downloaded ${remotePins.length} pins from remote');

      for (final remoteDto in remotePins) {
        try {
          final remotePinDomain = SupabasePinMapper.fromDto(remoteDto);
          final wasMerged = await _mergeRemotePin(remotePinDomain);
          if (wasMerged) {
            downloaded++;
          }
        } catch (e) {
          print('[SyncManager] Error merging remote pin ${remoteDto.id}: $e');
          errors++;
          errorMessage ??= e.toString();
        }
      }

      return SyncResult(
        uploaded: 0,
        downloaded: downloaded,
        errors: errors,
        errorMessage: errorMessage,
      );
    } catch (e) {
      print('[SyncManager] Error downloading remote changes: $e');
      return SyncResult(
        uploaded: 0,
        downloaded: downloaded,
        errors: errors + 1,
        errorMessage: e.toString(),
      );
    }
  }

  /// Merge a remote pin with local database using conflict resolution
  ///
  /// Returns true if the pin was inserted or updated locally.
  /// Returns false if the local version was kept (newer or same).
  Future<bool> _mergeRemotePin(pin) async {
    final localEntity = await _pinDao.getPinById(pin.id);

    // If pin doesn't exist locally, insert it
    if (localEntity == null) {
      print('[SyncManager] Inserting new remote pin: ${pin.id}');
      await _pinDao.insertPin(PinMapper.toEntity(pin));
      return true;
    }

    // Pin exists locally - compare timestamps for conflict resolution
    final localPin = PinMapper.fromEntity(localEntity);

    // If remote is newer, update local
    if (pin.metadata.lastModified.isAfter(localPin.metadata.lastModified)) {
      print('[SyncManager] Remote pin is newer, updating local: ${pin.id}');
      await _pinDao.updatePin(PinMapper.toEntity(pin));
      return true;
    }

    // Local is newer or same, keep local
    print('[SyncManager] Local pin is newer or same, keeping local: ${localPin.id}');
    return false;
  }
}
