import '../../domain/models/map_item.dart';
import '../models/server_pin_deletion_dto.dart';
import '../models/supabase_pin_dto.dart';

/// Interface for remote pin data operations.
///
/// Phase 1 splits the legacy `getAllPins` into three targeted reads:
/// - [getMyPinsModifiedSince] feeds [MyPinsSync] (auth-uid-filtered delta).
/// - [getMyPinDeletionsSince] mirrors the server tombstones for my pins.
/// - [getPinsInView] feeds [ViewportPinsManager] (bbox-on-demand reads).
abstract class RemoteDataSourceInterface {
  /// Fetch my pins last modified strictly after [since]. Pass an epoch like
  /// `DateTime.utc(1970)` for a first-ever sync.
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  });

  /// Fetch tombstones for my pins deleted strictly after [since].
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  });

  /// Fetch pins (or server-side clusters) inside the bbox. Excludes pins
  /// created by the caller (enforced server-side via `auth.uid()` in the
  /// `get_pins_in_view` Postgres function — see migration 008 §7).
  ///
  /// The [currentUserId] parameter is NOT forwarded to the RPC. It is here
  /// so callers can make local decisions (skip the call when unauthenticated,
  /// adjust caching strategy, etc.). Pass `null` when unauthenticated.
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  });

  Future<void> insertPin(SupabasePinDto pin);
  Future<void> updatePin(SupabasePinDto pin);
  Future<void> deletePin(String pinId);
  Future<SupabasePinDto?> getPinById(String pinId);
}
