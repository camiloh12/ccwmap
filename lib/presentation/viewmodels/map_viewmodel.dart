import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/pin.dart';
import '../../domain/repositories/pin_repository.dart';
import '../../domain/validators/location_validator.dart';
import '../../data/sample_data.dart';

/// ViewModel for the MapScreen
/// Manages pin data and exposes it to the UI
class MapViewModel extends ChangeNotifier {
  final PinRepository _repository;
  StreamSubscription<List<Pin>>? _pinsSubscription;

  List<Pin> _pins = [];
  bool _isLoading = false;
  String? _error;
  bool _hasLoadedSampleData = false;

  MapViewModel(this._repository);

  // Getters
  List<Pin> get pins => _pins;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Stream<List<Pin>> get pinsStream => _repository.watchPins();

  /// Initialize the ViewModel and load data
  Future<void> initialize() async {
    print('MapViewModel: Initializing...');
    _setLoading(true);
    try {
      // Start watching pins
      _pinsSubscription = _repository.watchPins().listen(
        (pins) {
          print('MapViewModel: Received ${pins.length} pins from stream');
          _pins = pins;
          notifyListeners();
        },
        onError: (error) {
          print('MapViewModel: Error in pins stream - $error');
          _setError(error.toString());
        },
      );

      // Load sample data on first launch
      await _loadSampleDataIfNeeded();

      _setLoading(false);
      print('MapViewModel: Initialization complete. Total pins: ${_pins.length}');
    } catch (e) {
      print('MapViewModel: Initialization error - $e');
      _setError(e.toString());
      _setLoading(false);
    }
  }

  /// Load sample pins if database is empty
  Future<void> _loadSampleDataIfNeeded() async {
    if (_hasLoadedSampleData) {
      print('MapViewModel: Sample data already loaded, skipping');
      return;
    }

    print('MapViewModel: Checking for existing pins...');
    final existingPins = await _repository.getPins();
    print('MapViewModel: Found ${existingPins.length} existing pins');

    if (existingPins.isEmpty) {
      print('MapViewModel: Loading sample data...');
      final samplePins = SampleData.getSamplePins();
      print('MapViewModel: Adding ${samplePins.length} sample pins');
      for (final pin in samplePins) {
        await _repository.addPin(pin);
      }
      print('MapViewModel: Sample data loaded successfully');
    }
    _hasLoadedSampleData = true;
  }

  /// Add a new pin
  /// Validates that the pin location is within US bounds before adding
  Future<void> addPin(Pin pin) async {
    try {
      // Validate location is within US bounds
      if (!LocationValidator.isWithinUSBounds(
        pin.location.latitude,
        pin.location.longitude,
      )) {
        throw Exception(
          'Pin location is outside continental US bounds. '
          'Please select a location within the United States.',
        );
      }

      await _repository.addPin(pin);
      _clearError();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    }
  }

  /// Update an existing pin
  Future<void> updatePin(Pin pin) async {
    try {
      await _repository.updatePin(pin);
      _clearError();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    }
  }

  /// Delete a pin
  Future<void> deletePin(String id) async {
    try {
      await _repository.deletePin(id);
      _clearError();
    } catch (e) {
      _setError(e.toString());
      rethrow;
    }
  }

  /// Get a pin by ID
  Future<Pin?> getPinById(String id) async {
    try {
      return await _repository.getPinById(id);
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pinsSubscription?.cancel();
    super.dispose();
  }
}
