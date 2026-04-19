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
  @override
  Future<List<SupabasePinDto>> getAllPins() async {
    try {

      final response = await _supabase
          .from('pins')
          .select()
          .order('created_at', ascending: false);

      final List<SupabasePinDto> pins = (response as List)
          .map((json) => SupabasePinDto.fromJson(json as Map<String, dynamic>))
          .toList();

      return pins;
    } catch (e) {
      rethrow;
    }
  }

  /// Insert a new pin to Supabase
  ///
  /// Throws exception if pin already exists or on API error.
  @override
  Future<void> insertPin(SupabasePinDto pin) async {
    try {

      await _supabase
          .from('pins')
          .insert(pin.toJson());

    } catch (e) {
      rethrow;
    }
  }

  /// Update an existing pin in Supabase
  ///
  /// Throws exception if pin doesn't exist or on API error.
  @override
  Future<void> updatePin(SupabasePinDto pin) async {
    try {

      await _supabase
          .from('pins')
          .update(pin.toJson())
          .eq('id', pin.id);

    } catch (e) {
      rethrow;
    }
  }

  /// Delete a pin from Supabase.
  ///
  /// Postgrest's `delete()` does not throw when a row survives the DELETE
  /// (e.g. RLS filtered it, network glitch, or another client recreated it
  /// mid-flight) — it just returns 0 rows affected. To detect that, we do a
  /// follow-up `select('id')` and throw if the row survived. Under the
  /// current "any authenticated user can delete any pin" policy this check
  /// should only trip on genuine errors, but it's cheap defense-in-depth.
  ///
  /// Idempotent: if the row was already gone before the call, the follow-up
  /// check returns null and the method succeeds.
  @override
  Future<void> deletePin(String pinId) async {
    try {
      await _supabase.from('pins').delete().eq('id', pinId);

      final survivor = await _supabase
          .from('pins')
          .select('id')
          .eq('id', pinId)
          .maybeSingle();

      if (survivor != null) {
        throw Exception(
          'Remote delete did not remove pin $pinId — row still exists after '
          'DELETE. Check network connectivity and Supabase RLS policy.',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get a single pin by ID from Supabase
  ///
  /// Returns null if pin doesn't exist.
  /// Throws exception on API error.
  @override
  Future<SupabasePinDto?> getPinById(String pinId) async {
    try {

      final response = await _supabase
          .from('pins')
          .select()
          .eq('id', pinId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      final pin = SupabasePinDto.fromJson(response);
      return pin;
    } catch (e) {
      rethrow;
    }
  }
}
