import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/map_item.dart';
import '../models/get_pins_in_view_row.dart';
import '../models/server_pin_deletion_dto.dart';
import '../models/supabase_pin_dto.dart';
import 'remote_data_source_interface.dart';

/// Remote data source for Pin synchronization with Supabase
///
/// Handles all Supabase API calls for CRUD operations on pins table.
/// Throws exceptions on API errors - caller must handle.
class SupabaseRemoteDataSource implements RemoteDataSourceInterface {
  final SupabaseClient _supabase;

  SupabaseRemoteDataSource(this._supabase);

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async {
    final response = await _supabase
        .from('pins')
        .select()
        .eq('created_by', userId)
        .gt('last_modified', since.toIso8601String())
        .order('last_modified', ascending: true);

    return (response as List)
        .map((j) => SupabasePinDto.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async {
    // RLS already filters this to `original_created_by = auth.uid()`,
    // so the explicit .eq() is belt-and-suspenders. Cheap; keeps the
    // query intent legible at the call site.
    final response = await _supabase
        .from('pin_deletions')
        .select('pin_id, deleted_at, original_created_by')
        .eq('original_created_by', userId)
        .gt('deleted_at', since.toIso8601String())
        .order('deleted_at', ascending: true);

    return (response as List)
        .map((j) => ServerPinDeletionDto.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  }) async {
    final response = await _supabase.rpc(
      'get_pins_in_view',
      params: {
        'sw_lat': swLat,
        'sw_lng': swLng,
        'ne_lat': neLat,
        'ne_lng': neLng,
        'zoom': zoom,
      },
    );

    final rows = (response as List).cast<Map<String, dynamic>>();
    return rows.map(GetPinsInViewRow.parse).toList();
  }

  /// Insert a new pin to Supabase
  ///
  /// Throws exception if pin already exists or on API error.
  @override
  Future<void> insertPin(SupabasePinDto pin) async {
    try {
      await _supabase.from('pins').insert(pin.toJson());
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
          .update(pin.toJsonForUpdate())
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

  // --- SP-2: Agreements ---

  /// Returns true if [userId] has a row in user_agreements for [version].
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) async {
    final row = await _supabase
        .from('user_agreements')
        .select('id')
        .eq('user_id', userId)
        .eq('agreement_version', version)
        .maybeSingle();
    return row != null;
  }

  /// Records acceptance of [version] for [userId]. Relies on the
  /// UNIQUE (user_id, agreement_version) constraint to make repeated
  /// calls idempotent — a duplicate insert raises a unique-violation
  /// which we swallow.
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) async {
    try {
      await _supabase.from('user_agreements').insert({
        'user_id': userId,
        'agreement_version': version,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // unique_violation = already accepted
      rethrow;
    }
  }

  // --- SP-2: Moderation ---

  /// Returns the set of user IDs the current user has blocked.
  Future<Set<String>> fetchBlocklist() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return const <String>{};
    final rows = await _supabase
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', uid);
    return (rows as List)
        .map<String>((r) => (r as Map<String, dynamic>)['blocked_id'] as String)
        .toSet();
  }

  /// Inserts a block row. Idempotent — a duplicate insert (already blocked)
  /// raises unique-violation which we swallow.
  Future<void> blockUser(String blockedUserId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('blockUser requires authentication');
    }
    try {
      await _supabase.from('blocked_users').insert({
        'blocker_id': uid,
        'blocked_id': blockedUserId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return;
      rethrow;
    }
  }

  /// Removes a block. Idempotent — deleting a non-existent row is a no-op.
  Future<void> unblockUser(String blockedUserId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('unblockUser requires authentication');
    }
    await _supabase
        .from('blocked_users')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', blockedUserId);
  }

  /// Files a report. [note] is trimmed; empty notes become null.
  Future<void> submitPinReport({
    required String pinId,
    required String reason,
    String? note,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    final n = (note == null || note.trim().isEmpty) ? null : note.trim();
    await _supabase.from('pin_reports').insert({
      'pin_id': pinId,
      'reporter_id': uid,
      'reason': reason,
      'note': n,
    });
  }
}
