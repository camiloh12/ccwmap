import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service that monitors network connectivity state
class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Stream of network connectivity state (true = online, false = offline)
  Stream<bool> get isOnlineStream => _controller.stream.distinct();

  /// Current connectivity state (true = online, false = offline)
  bool get isOnline => _isOnline;

  /// Initialize the network monitor
  Future<void> initialize() async {
    // Check initial connectivity
    final results = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(results);
    _controller.add(_isOnline);

    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = _isConnected(results);

      // Only emit if the state changed
      if (wasOnline != _isOnline) {
        _controller.add(_isOnline);
      }
    });
  }

  /// Check if any connectivity result indicates a connection
  bool _isConnected(List<ConnectivityResult> results) {
    // If we have any connection type other than none, we're online
    return results.any((result) => result != ConnectivityResult.none);
  }

  /// Dispose the network monitor
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
