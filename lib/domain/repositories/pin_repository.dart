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
}
