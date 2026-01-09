import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';

/// Fake implementation of remote data source for testing
///
/// Stores pins in memory and simulates API behavior.
class FakeSupabaseRemoteDataSource implements RemoteDataSourceInterface {
  final Map<String, SupabasePinDto> _pins = {};
  bool shouldThrowError = false;

  FakeSupabaseRemoteDataSource();

  @override
  Future<List<SupabasePinDto>> getAllPins() async {
    if (shouldThrowError) {
      throw Exception('Simulated network error');
    }
    return _pins.values.toList();
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
