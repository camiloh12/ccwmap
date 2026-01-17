import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/services/network_monitor.dart';
import '../../domain/models/pin.dart';
import '../../domain/repositories/pin_repository.dart';
import '../../domain/validators/location_validator.dart';

/// ViewModel for the MapScreen
/// Manages pin data and exposes it to the UI
class MapViewModel extends ChangeNotifier {
  final PinRepository _repository;
  final NetworkMonitor _networkMonitor;
  StreamSubscription<List<Pin>>? _pinsSubscription;
  StreamSubscription<bool>? _networkSubscription;

  List<Pin> _pins = [];
  bool _isLoading = false;
  String? _error;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  bool _wasOffline = false;

  MapViewModel(this._repository, this._networkMonitor);

  // Getters
  List<Pin> get pins => _pins;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Stream<List<Pin>> get pinsStream => _repository.watchPins();
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Initialize the ViewModel and load data
  Future<void> initialize() async {
    _setLoading(true);
    try {
      // Start watching pins
      _pinsSubscription = _repository.watchPins().listen(
        (pins) {
          _pins = pins;
          notifyListeners();
        },
        onError: (error) {
          _setError(error.toString());
        },
      );

      // Listen to network connectivity changes
      _wasOffline = !_networkMonitor.isOnline;
      _networkSubscription = _networkMonitor.isOnlineStream.listen(
        (isOnline) {

          // Trigger sync when coming back online
          if (isOnline && _wasOffline) {
            syncWithRemote();
          }

          _wasOffline = !isOnline;
        },
      );

      // Trigger initial sync with remote to download existing pins (if online)
      if (_networkMonitor.isOnline) {
        syncWithRemote();
      } else {
      }

      _setLoading(false);
    } catch (e) {
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

      // Trigger immediate sync to upload the new pin
      syncWithRemote();
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

      // Trigger immediate sync to upload the changes
      syncWithRemote();
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

      // Trigger immediate sync to propagate the deletion
      syncWithRemote();
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
      return;
    }

    try {
      _isSyncing = true;
      notifyListeners();

      final result = await _repository.syncWithRemote();

      _lastSyncTime = DateTime.now();

      if (!result.isSuccess) {
        // Don't set error state - sync errors are non-blocking
      }
    } catch (e) {
      // Don't set error state - sync failures are non-blocking
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pinsSubscription?.cancel();
    _networkSubscription?.cancel();
    super.dispose();
  }
}
