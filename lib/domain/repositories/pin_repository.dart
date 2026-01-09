import '../models/pin.dart';

/// Repository interface for managing pins
/// Provides abstraction over data sources (local database, remote API)
abstract class PinRepository {
  /// Watch all pins with real-time updates
  /// Returns a stream that emits whenever pins change in the database
  Stream<List<Pin>> watchPins();

  /// Get all pins as a one-time fetch
  Future<List<Pin>> getPins();

  /// Get a specific pin by its ID
  /// Returns null if pin doesn't exist
  Future<Pin?> getPinById(String id);

  /// Add a new pin to the repository
  Future<void> addPin(Pin pin);

  /// Update an existing pin
  Future<void> updatePin(Pin pin);

  /// Delete a pin by its ID
  Future<void> deletePin(String id);

  /// Synchronize pins with remote server
  /// Downloads remote changes and uploads local changes
  /// Returns SyncResult with upload/download counts and errors
  Future<SyncResult> syncWithRemote();
}

/// Result of a sync operation
class SyncResult {
  final int uploaded;
  final int downloaded;
  final int errors;
  final String? errorMessage;

  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.errors,
    this.errorMessage,
  });

  bool get isSuccess => errors == 0;

  @override
  String toString() {
    return 'SyncResult(uploaded: $uploaded, downloaded: $downloaded, errors: $errors)';
  }
}
