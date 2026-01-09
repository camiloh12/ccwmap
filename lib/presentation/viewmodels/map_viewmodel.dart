import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/pin.dart';
import '../../domain/repositories/pin_repository.dart';
import '../../domain/validators/location_validator.dart';

/// ViewModel for the MapScreen
/// Manages pin data and exposes it to the UI
class MapViewModel extends ChangeNotifier {
  final PinRepository _repository;
  StreamSubscription<List<Pin>>? _pinsSubscription;

  List<Pin> _pins = [];
  bool _isLoading = false;
  String? _error;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  MapViewModel(this._repository);

  // Getters
  List<Pin> get pins => _pins;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Stream<List<Pin>> get pinsStream => _repository.watchPins();
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;

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

      // Trigger initial sync with remote to download existing pins
      syncWithRemote();

      _setLoading(false);
      print('MapViewModel: Initialization complete. Total pins: ${_pins.length}');
    } catch (e) {
      print('MapViewModel: Initialization error - $e');
      _setError(e.toString());
      _setLoading(false);
    }
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

  /// Synchronize pins with remote Supabase
  ///
  /// Downloads remote changes and uploads local changes.
  /// Can be called manually or automatically on app launch.
  /// Runs in background without blocking UI.
  Future<void> syncWithRemote() async {
    if (_isSyncing) {
      print('MapViewModel: Sync already in progress, skipping');
      return;
    }

    try {
      _isSyncing = true;
      notifyListeners();

      print('MapViewModel: Starting sync with remote...');
      final result = await _repository.syncWithRemote();

      _lastSyncTime = DateTime.now();
      print('MapViewModel: Sync complete - $result');

      if (!result.isSuccess) {
        print('MapViewModel: Sync had errors: ${result.errorMessage}');
        // Don't set error state - sync errors are non-blocking
      }
    } catch (e) {
      print('MapViewModel: Sync failed with exception: $e');
      // Don't set error state - sync failures are non-blocking
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pinsSubscription?.cancel();
    super.dispose();
  }
}
