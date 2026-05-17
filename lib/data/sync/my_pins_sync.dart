import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/data/mappers/supabase_pin_mapper.dart';
import 'package:ccwmap/data/mappers/sync_operation_mapper.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:ccwmap/domain/models/sync_operation.dart';
import 'package:ccwmap/domain/repositories/pin_repository.dart';

/// Bidirectional sync for `created_by = auth.uid()` pins only.
///
/// Replaces the legacy SyncManager in two ways:
/// 1. Download is a delta query (`last_modified > watermark`) instead of a
///    full fetch.
/// 2. Tombstones for *my* pins are mirrored from server-side `pin_deletions`
///    so cross-device deletes apply locally.
///
/// Anonymous callers (`userIdProvider() == null`) are an unconditional
/// no-op — they have no own pins to sync.
class MyPinsSync {
  static const int _maxRetries = 3;

  final String? Function() userIdProvider;
  final SyncQueueDao syncQueueDao;
  final PinDao pinDao;
  final PinTombstoneDao tombstoneDao;
  final ServerPinDeletionDao serverDeletionDao;
  final RemoteDataSourceInterface remote;
  final NetworkMonitor networkMonitor;
  final LastSyncedAtStore watermarks;

  MyPinsSync({
    required this.userIdProvider,
    required this.syncQueueDao,
    required this.pinDao,
    required this.tombstoneDao,
    required this.serverDeletionDao,
    required this.remote,
    required this.networkMonitor,
    required this.watermarks,
  });

  Future<SyncResult> sync() async {
    final userId = userIdProvider();
    if (userId == null) {
      return const SyncResult(uploaded: 0, downloaded: 0, errors: 0);
    }
    if (!networkMonitor.isOnline) {
      return const SyncResult(
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
      await _optimizeQueue();
      final upload = await _processQueue();
      uploaded = upload.uploaded;
      errors += upload.errors;
      errorMessage ??= upload.errorMessage;

      final download = await _downloadMyPins(userId, upload.deletedPinIds);
      downloaded = download.downloaded;
      errors += download.errors;
      errorMessage ??= download.errorMessage;

      final tomb = await _downloadMyTombstones(userId);
      errors += tomb.errors;
      errorMessage ??= tomb.errorMessage;
    } catch (e) {
      errors++;
      errorMessage ??= e.toString();
    }

    return SyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      errors: errors,
      errorMessage: errorMessage,
    );
  }

  // --- Upload path: identical semantics to the deleted legacy sync path. --

  Future<void> _optimizeQueue() async {
    final all = await syncQueueDao.getPendingOperationsSorted();
    if (all.isEmpty) return;

    final byPin = <String, List<SyncQueueEntity>>{};
    for (final op in all) {
      byPin.putIfAbsent(op.pinId, () => []).add(op);
    }

    for (final ops in byPin.values) {
      if (ops.length <= 1) continue;
      final del = ops.lastWhere(
        (o) => o.operationType == 'DELETE',
        orElse: () => ops.first,
      );
      if (del.operationType == 'DELETE') {
        for (final o in ops) {
          if (o.id != del.id) await syncQueueDao.dequeue(o.id);
        }
      } else {
        final updates = ops.where((o) => o.operationType == 'UPDATE').toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        for (int i = 0; i < updates.length - 1; i++) {
          await syncQueueDao.dequeue(updates[i].id);
        }
      }
    }
  }

  Future<_ProcessQueueResult> _processQueue() async {
    final ops = await syncQueueDao.getPendingOperationsSorted();
    if (ops.isEmpty) {
      return _ProcessQueueResult(uploaded: 0, errors: 0, deletedPinIds: {});
    }

    int uploaded = 0;
    int errors = 0;
    String? errorMessage;
    final deletedIds = <String>{};

    for (final entity in ops) {
      final op = SyncOperationMapper.fromEntity(entity);

      if (op.hasExceededMaxRetries(maxRetries: _maxRetries)) {
        await syncQueueDao.dequeue(op.id);
        errors++;
        errorMessage ??= 'Some operations exceeded max retries';
        continue;
      }
      if (!op.canRetry()) continue;

      try {
        await _processOperation(op);
        uploaded++;
        if (op.operationType == SyncOperationType.delete) {
          deletedIds.add(op.pinId);
        }
        await syncQueueDao.dequeue(op.id);
      } catch (e) {
        errors++;
        errorMessage ??= e.toString();
        await syncQueueDao.incrementRetryCount(op.id, e.toString());
      }
    }

    return _ProcessQueueResult(
      uploaded: uploaded,
      errors: errors,
      errorMessage: errorMessage,
      deletedPinIds: deletedIds,
    );
  }

  Future<void> _processOperation(SyncOperation op) async {
    switch (op.operationType) {
      case SyncOperationType.create:
        final entity = await pinDao.getPinById(op.pinId);
        if (entity == null) return;
        try {
          await remote.insertPin(
            SupabasePinMapper.toDto(PinMapper.fromEntity(entity)),
          );
        } catch (e) {
          final m = e.toString();
          if (m.contains('duplicate') ||
              m.contains('already exists') ||
              m.contains('unique'))
            return;
          rethrow;
        }
        break;
      case SyncOperationType.update:
        final entity = await pinDao.getPinById(op.pinId);
        if (entity == null) return;
        try {
          await remote.updatePin(
            SupabasePinMapper.toDto(PinMapper.fromEntity(entity)),
          );
        } catch (e) {
          final m = e.toString();
          if (m.contains('not found') || m.contains('no rows')) return;
          rethrow;
        }
        break;
      case SyncOperationType.delete:
        try {
          await remote.deletePin(op.pinId);
        } catch (e) {
          final m = e.toString();
          if (m.contains('not found') || m.contains('no rows')) return;
          rethrow;
        }
        break;
    }
  }

  // --- Download path: delta + tombstone mirroring. ---

  Future<SyncResult> _downloadMyPins(
    String userId,
    Set<String> justDeletedIds,
  ) async {
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;
    final fetchStartedAt = DateTime.now().toUtc();

    try {
      final since = await watermarks.readPinsWatermark(userId);
      final remotePins = await remote.getMyPinsModifiedSince(
        userId: userId,
        since: since,
      );

      final pending = (await syncQueueDao.getPendingOperationsSorted())
          .where((o) => o.operationType == 'DELETE')
          .map((o) => o.pinId)
          .toSet();
      final localTombstones = await tombstoneDao.getAllTombstonedPinIds();
      final suppress = {...pending, ...justDeletedIds, ...localTombstones};

      final toInsert = <PinEntity>[];
      final toUpdate = <PinEntity>[];
      DateTime maxLastModified = since;

      for (final dto in remotePins) {
        try {
          if (suppress.contains(dto.id)) continue;
          final remotePin = SupabasePinMapper.fromDto(dto);
          final entity = PinMapper.toEntity(remotePin);
          final local = await pinDao.getPinById(remotePin.id);
          if (local == null) {
            toInsert.add(entity);
            downloaded++;
          } else {
            final localDomain = PinMapper.fromEntity(local);
            if (remotePin.metadata.lastModified.isAfter(
              localDomain.metadata.lastModified,
            )) {
              toUpdate.add(entity);
              downloaded++;
            }
          }
          if (remotePin.metadata.lastModified.isAfter(maxLastModified)) {
            maxLastModified = remotePin.metadata.lastModified;
          }
        } catch (e) {
          errors++;
          errorMessage ??= e.toString();
        }
      }

      if (toInsert.isNotEmpty || toUpdate.isNotEmpty) {
        await pinDao.batchUpsertPins(toInsert, toUpdate);
      }

      // Advance the watermark to the newest row we saw (or fetchStartedAt
      // if no rows came back — keeps subsequent queries cheap).
      final advanceTo = maxLastModified == since
          ? fetchStartedAt
          : maxLastModified;
      await watermarks.writePinsWatermark(userId, advanceTo);
    } catch (e) {
      errors++;
      errorMessage ??= e.toString();
    }

    return SyncResult(
      uploaded: 0,
      downloaded: downloaded,
      errors: errors,
      errorMessage: errorMessage,
    );
  }

  Future<SyncResult> _downloadMyTombstones(String userId) async {
    int errors = 0;
    String? errorMessage;
    final fetchStartedAt = DateTime.now().toUtc();

    try {
      final since = await watermarks.readDeletionsWatermark(userId);
      final tombstones = await remote.getMyPinDeletionsSince(
        userId: userId,
        since: since,
      );

      DateTime maxDeletedAt = since;
      for (final t in tombstones) {
        try {
          await serverDeletionDao.upsert(
            pinId: t.pinId,
            deletedAt: t.deletedAt,
          );
          await pinDao.deletePin(t.pinId);
          if (t.deletedAt.isAfter(maxDeletedAt)) maxDeletedAt = t.deletedAt;
        } catch (e) {
          errors++;
          errorMessage ??= e.toString();
        }
      }

      final advanceTo = maxDeletedAt == since ? fetchStartedAt : maxDeletedAt;
      await watermarks.writeDeletionsWatermark(userId, advanceTo);
    } catch (e) {
      errors++;
      errorMessage ??= e.toString();
    }

    return SyncResult(
      uploaded: 0,
      downloaded: 0,
      errors: errors,
      errorMessage: errorMessage,
    );
  }
}

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
