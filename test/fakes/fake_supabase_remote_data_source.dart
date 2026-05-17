import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/domain/models/map_item.dart';

/// Fake implementation of remote data source for testing
///
/// Stores pins in memory and simulates API behavior.
class FakeSupabaseRemoteDataSource implements RemoteDataSourceInterface {
  final Map<String, SupabasePinDto> _pins = {};
  bool shouldThrowError = false;

  FakeSupabaseRemoteDataSource();

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    return _pins.values
        .where(
          (p) =>
              p.createdBy == userId &&
              DateTime.parse(p.lastModified).isAfter(since),
        )
        .toList()
      ..sort((a, b) => a.lastModified.compareTo(b.lastModified));
  }

  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    return const <ServerPinDeletionDto>[];
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
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    return const <MapItem>[];
  }

  @override
  Future<void> insertPin(SupabasePinDto pin) async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    if (_pins.containsKey(pin.id)) {
      throw Exception('Pin already exists');
    }
    _pins[pin.id] = pin;
  }

  @override
  Future<void> updatePin(SupabasePinDto pin) async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    if (!_pins.containsKey(pin.id)) {
      throw Exception('Pin not found');
    }
    _pins[pin.id] = pin;
  }

  @override
  Future<void> deletePin(String pinId) async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    _pins.remove(pinId);
  }

  @override
  Future<SupabasePinDto?> getPinById(String pinId) async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    return _pins[pinId];
  }

  // Helper methods for testing
  void addPinDirectly(SupabasePinDto pin) {
    _pins[pin.id] = pin;
  }

  void clear() {
    _pins.clear();
  }

  int get pinCount => _pins.length;
}
