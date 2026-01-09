import '../models/supabase_pin_dto.dart';

/// Interface for remote pin data operations
///
/// This abstraction allows for easy testing with fake implementations.
abstract class RemoteDataSourceInterface {
  /// Fetch all pins from remote
  Future<List<SupabasePinDto>> getAllPins();

  /// Insert a new pin to remote
  Future<void> insertPin(SupabasePinDto pin);

  /// Update an existing pin on remote
  Future<void> updatePin(SupabasePinDto pin);

  /// Delete a pin from remote
  Future<void> deletePin(String pinId);

  /// Get a single pin by ID from remote
  Future<SupabasePinDto?> getPinById(String pinId);
}
