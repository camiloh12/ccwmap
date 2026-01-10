import 'dart:async';
import 'package:ccwmap/data/services/network_monitor.dart';

/// Fake NetworkMonitor for testing
class FakeNetworkMonitor extends NetworkMonitor {
  bool _isOnline = true;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get isOnlineStream => _controller.stream;

  @override
  Future<void> initialize() async {
    // No-op for testing
  }

  /// Simulate going offline
  void goOffline() {
    _isOnline = false;
    _controller.add(false);
  }

  /// Simulate coming back online
  void goOnline() {
    _isOnline = true;
    _controller.add(true);
  }

  @override
  void dispose() {
    _controller.close();
  }
}
