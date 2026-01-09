import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supabase_pin_dto.dart';
import 'remote_data_source_interface.dart';

/// Remote data source for Pin synchronization with Supabase
///
/// Handles all Supabase API calls for CRUD operations on pins table.
/// Throws exceptions on API errors - caller must handle.
class SupabaseRemoteDataSource implements RemoteDataSourceInterface {
  final SupabaseClient _supabase;

  SupabaseRemoteDataSource(this._supabase);

  /// Fetch all pins from Supabase
  ///
  /// Returns empty list if no pins exist.
  /// Throws exception on API error.
  Future<List<SupabasePinDto>> getAllPins() async {
    try {
      print('[RemoteDataSource] Fetching all pins from Supabase...');

      final response = await _supabase
          .from('pins')
          .select()
          .order('created_at', ascending: false);

      final List<SupabasePinDto> pins = (response as List)
          .map((json) => SupabasePinDto.fromJson(json as Map<String, dynamic>))
          .toList();

      print('[RemoteDataSource] Fetched ${pins.length} pins');
      return pins;
    } catch (e) {
      print('[RemoteDataSource] Error fetching pins: $e');
      rethrow;
    }
  }

  /// Insert a new pin to Supabase
  ///
  /// Throws exception if pin already exists or on API error.
  Future<void> insertPin(SupabasePinDto pin) async {
    try {
      print('[RemoteDataSource] Inserting pin: ${pin.id}');

      await _supabase
          .from('pins')
          .insert(pin.toJson());

      print('[RemoteDataSource] Pin inserted successfully');
    } catch (e) {
      print('[RemoteDataSource] Error inserting pin: $e');
      rethrow;
    }
  }

  /// Update an existing pin in Supabase
  ///
  /// Throws exception if pin doesn't exist or on API error.
  Future<void> updatePin(SupabasePinDto pin) async {
    try {
      print('[RemoteDataSource] Updating pin: ${pin.id}');

      await _supabase
          .from('pins')
          .update(pin.toJson())
          .eq('id', pin.id);

      print('[RemoteDataSource] Pin updated successfully');
    } catch (e) {
      print('[RemoteDataSource] Error updating pin: $e');
      rethrow;
    }
  }

  /// Delete a pin from Supabase
  ///
  /// Throws exception on API error.
  /// Idempotent - no error if pin doesn't exist.
  Future<void> deletePin(String pinId) async {
    try {
      print('[RemoteDataSource] Deleting pin: $pinId');

      await _supabase
          .from('pins')
          .delete()
          .eq('id', pinId);

      print('[RemoteDataSource] Pin deleted successfully');
    } catch (e) {
      print('[RemoteDataSource] Error deleting pin: $e');
      rethrow;
    }
  }

  /// Get a single pin by ID from Supabase
  ///
  /// Returns null if pin doesn't exist.
  /// Throws exception on API error.
  Future<SupabasePinDto?> getPinById(String pinId) async {
    try {
      print('[RemoteDataSource] Fetching pin by ID: $pinId');

      final response = await _supabase
          .from('pins')
          .select()
          .eq('id', pinId)
          .maybeSingle();

      if (response == null) {
        print('[RemoteDataSource] Pin not found: $pinId');
        return null;
      }

      final pin = SupabasePinDto.fromJson(response as Map<String, dynamic>);
      print('[RemoteDataSource] Pin fetched successfully');
      return pin;
    } catch (e) {
      print('[RemoteDataSource] Error fetching pin: $e');
      rethrow;
    }
  }
}
