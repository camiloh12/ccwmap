import '../../domain/models/pin.dart';
import '../../domain/repositories/pin_repository.dart';
import '../database/database.dart';
import '../datasources/remote_data_source_interface.dart';
import '../mappers/pin_mapper.dart';
import '../mappers/supabase_pin_mapper.dart';

/// Implementation of PinRepository with Supabase sync
class PinRepositoryImpl implements PinRepository {
  final PinDao _pinDao;
  final RemoteDataSourceInterface _remoteDataSource;

  PinRepositoryImpl(this._pinDao, this._remoteDataSource);

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
    final entity = PinMapper.toEntity(pin);
    await _pinDao.insertPin(entity);
  }

  @override
  Future<void> updatePin(Pin pin) async {
    final entity = PinMapper.toEntity(pin);
    await _pinDao.updatePin(entity);
  }

  @override
  Future<void> deletePin(String id) async {
    await _pinDao.deletePin(id);
  }

  @override
  Future<SyncResult> syncWithRemote() async {
    int uploaded = 0;
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;

    try {
      print('[PinRepository] Starting sync...');

      // Step 1: Download remote pins
      final remotePins = await _remoteDataSource.getAllPins();
      print('[PinRepository] Downloaded ${remotePins.length} remote pins');

      // Step 2: Merge remote pins with local database
      for (final remoteDto in remotePins) {
        try {
          final remotePinDomain = SupabasePinMapper.fromDto(remoteDto);
          final wasMerged = await _mergeRemotePin(remotePinDomain);
          if (wasMerged) {
            downloaded++;
          }
        } catch (e) {
          print('[PinRepository] Error merging remote pin ${remoteDto.id}: $e');
          errors++;
        }
      }

      // Step 3: Upload local pins that don't exist remotely
      // For now, we'll do a simple check: upload all local pins
      // In Iteration 10, we'll use sync queue for smarter uploading
      final localPins = await getPins();
      print('[PinRepository] Uploading ${localPins.length} local pins');

      for (final localPin in localPins) {
        try {
          await _uploadPinIfNeeded(localPin);
          uploaded++;
        } catch (e) {
          print('[PinRepository] Error uploading pin ${localPin.id}: $e');
          errors++;
          errorMessage ??= e.toString();
        }
      }

      print('[PinRepository] Sync complete: uploaded=$uploaded, downloaded=$downloaded, errors=$errors');

      return SyncResult(
        uploaded: uploaded,
        downloaded: downloaded,
        errors: errors,
        errorMessage: errorMessage,
      );
    } catch (e) {
      print('[PinRepository] Sync failed: $e');
      return SyncResult(
        uploaded: uploaded,
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
  Future<bool> _mergeRemotePin(Pin remotePin) async {
    final localEntity = await _pinDao.getPinById(remotePin.id);

    // If pin doesn't exist locally, insert it
    if (localEntity == null) {
      print('[PinRepository] Inserting new remote pin: ${remotePin.id}');
      await _pinDao.insertPin(PinMapper.toEntity(remotePin));
      return true;
    }

    // Pin exists locally - compare timestamps for conflict resolution
    final localPin = PinMapper.fromEntity(localEntity);

    // If remote is newer, update local
    if (remotePin.metadata.lastModified
        .isAfter(localPin.metadata.lastModified)) {
      print('[PinRepository] Remote pin is newer, updating local: ${remotePin.id}');
      await _pinDao.updatePin(PinMapper.toEntity(remotePin));
      return true;
    }

    // Local is newer or same, keep local
    print('[PinRepository] Local pin is newer or same, keeping local: ${localPin.id}');
    return false;
  }

  /// Upload a pin to remote if it doesn't exist or if local is newer
  Future<void> _uploadPinIfNeeded(Pin localPin) async {
    try {
      // Check if pin exists remotely
      final remoteDto = await _remoteDataSource.getPinById(localPin.id);

      if (remoteDto == null) {
        // Pin doesn't exist remotely, insert it
        print('[PinRepository] Uploading new pin to remote: ${localPin.id}');
        await _remoteDataSource.insertPin(SupabasePinMapper.toDto(localPin));
      } else {
        // Pin exists remotely - compare timestamps
        final remotePin = SupabasePinMapper.fromDto(remoteDto);

        if (localPin.metadata.lastModified
            .isAfter(remotePin.metadata.lastModified)) {
          // Local is newer, update remote
          print('[PinRepository] Local pin is newer, updating remote: ${localPin.id}');
          await _remoteDataSource.updatePin(SupabasePinMapper.toDto(localPin));
        } else {
          // Remote is newer or same, skip upload
          print('[PinRepository] Remote pin is newer or same, skipping upload: ${localPin.id}');
        }
      }
    } catch (e) {
      // If pin already exists (duplicate key error), that's okay - treat as idempotent
      if (e.toString().contains('duplicate') ||
          e.toString().contains('already exists') ||
          e.toString().contains('unique')) {
        print('[PinRepository] Pin already exists on remote (idempotent): ${localPin.id}');
      } else {
        rethrow;
      }
    }
  }
}
