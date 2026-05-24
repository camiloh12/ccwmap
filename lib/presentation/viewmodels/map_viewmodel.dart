import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/services/blocklist_service.dart';
import '../../data/services/network_monitor.dart';
import '../../data/sync/bbox_request_debouncer.dart';
import '../../data/sync/viewport_pins_manager.dart';
import '../../domain/models/map_item.dart';
import '../../domain/models/pin.dart';
import '../../domain/repositories/pin_repository.dart';
import '../../domain/validators/location_validator.dart';

/// ViewModel for the MapScreen
/// Manages pin data and exposes it to the UI
class MapViewModel extends ChangeNotifier {
  final PinRepository _repository;
  final NetworkMonitor _networkMonitor;
  final BlocklistService _blocklist;
  final ViewportPinsManager? _viewportPinsManager;
  // Wired in Task 12; consumed by Task 17 — used by the pathological-cache
  // safety check in [initialize] to scope "non-mine" rows.
  final String? Function()? _userIdProvider;

  /// Hard cap per spec §6 — twice the soft cache limit (default 20000).
  /// If the on-disk cache exceeds this on startup, we drop the non-mine rows
  /// and let the next `onCameraIdle` rebuild via bbox.
  static const int _pathologicalCacheCap = 40000;
  late final BboxRequestDebouncer? _bboxDebouncer;
  StreamSubscription<List<Pin>>? _pinsSubscription;
  StreamSubscription<bool>? _networkSubscription;

  // Fallback notifier used when no [ViewportPinsManager] was supplied (e.g.
  // in legacy widget tests). Cached so the getter doesn't leak a fresh
  // ValueNotifier per access.
  ValueNotifier<List<MapItemCluster>>? _emptyClustersFallback;

  // Pending viewport saved while the debounce timer is counting down.
  double? _pendingSwLat;
  double? _pendingSwLng;
  double? _pendingNeLat;
  double? _pendingNeLng;
  int? _pendingZoom;

  List<Pin> _pinsAll = [];
  List<Pin> _pins = [];
  bool _isLoading = false;
  String? _error;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  bool _wasOffline = false;

  MapViewModel(
    this._repository,
    this._networkMonitor,
    this._blocklist, {
    ViewportPinsManager? viewportPinsManager,
    String? Function()? userIdProvider,
    Duration bboxDebounce = const Duration(milliseconds: 500),
  }) : _viewportPinsManager = viewportPinsManager,
       _userIdProvider = userIdProvider {
    _bboxDebouncer = viewportPinsManager == null
        ? null
        : BboxRequestDebouncer(
            interval: bboxDebounce,
            onFire: _runPendingBboxFetch,
          );
    // Re-apply the filter whenever the blocklist changes so the map
    // updates immediately when the user blocks/unblocks someone.
    _blocklist.addListener(_applyBlocklistFilter);
  }

  /// Exposed for the map screen's cluster layer. Falls back to a cached
  /// empty notifier when no viewport manager was wired up.
  ValueListenable<List<MapItemCluster>> get viewportClusters {
    final vpm = _viewportPinsManager;
    if (vpm != null) return vpm.clusters;
    return _emptyClustersFallback ??= ValueNotifier<List<MapItemCluster>>(
      const [],
    );
  }

  /// Map screen calls this from `onCameraIdle`. Stores the viewport and
  /// kicks the debouncer; actual fetch fires after `bboxDebounce` elapses.
  void onCameraIdle({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
  }) {
    final debouncer = _bboxDebouncer;
    if (debouncer == null) return;
    _pendingSwLat = swLat;
    _pendingSwLng = swLng;
    _pendingNeLat = neLat;
    _pendingNeLng = neLng;
    _pendingZoom = zoom;
    debouncer.tick();
  }

  Future<void> _runPendingBboxFetch() async {
    final vpm = _viewportPinsManager;
    if (vpm == null) return;
    final swLat = _pendingSwLat;
    final swLng = _pendingSwLng;
    final neLat = _pendingNeLat;
    final neLng = _pendingNeLng;
    final zoom = _pendingZoom;
    if (swLat == null ||
        swLng == null ||
        neLat == null ||
        neLng == null ||
        zoom == null) {
      return;
    }
    try {
      await vpm.fetch(
        swLat: swLat,
        swLng: swLng,
        neLat: neLat,
        neLng: neLng,
        zoom: zoom,
      );
    } catch (_) {
      // Non-fatal; viewportClusters stays as-is.
    }
  }

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
      // Pathological-cache safety (spec §6): if the on-disk cache somehow
      // exceeded its soft limit (e.g. crashed mid-eviction in a prior run,
      // schema migration didn't run), drop the non-mine rows and let the
      // next onCameraIdle rebuild via bbox. Runs before the pins stream is
      // subscribed so the first emission reflects the post-reset state, and
      // before any debounced bbox fetch could fire.
      final vpm = _viewportPinsManager;
      if (vpm != null) {
        final myId = _resolveMyUserId();
        if (myId != null) {
          final all = await _repository.getPins();
          final nonMineCount = all
              .where((p) => p.metadata.createdBy != myId)
              .length;
          if (nonMineCount > _pathologicalCacheCap) {
            await vpm.reset();
          }
        }
      }

      // Start watching pins
      _pinsSubscription = _repository.watchPins().listen(
        (pins) {
          _pinsAll = pins;
          _applyBlocklistFilter();
        },
        onError: (error) {
          _setError(error.toString());
        },
      );

      // Listen to network connectivity changes
      _wasOffline = !_networkMonitor.isOnline;
      _networkSubscription = _networkMonitor.isOnlineStream.listen((isOnline) {
        // Trigger sync when coming back online
        if (isOnline && _wasOffline) {
          syncWithRemote();
        }

        _wasOffline = !isOnline;
      });

      // Trigger initial sync with remote to download existing pins (if online)
      if (_networkMonitor.isOnline) {
        syncWithRemote();
      } else {}

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

  String? _resolveMyUserId() => _userIdProvider?.call();

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

  void _applyBlocklistFilter() {
    _pins = _pinsAll
        .where((p) => !_blocklist.isBlocked(p.metadata.createdBy))
        .toList(growable: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _bboxDebouncer?.dispose();
    _emptyClustersFallback?.dispose();
    _blocklist.removeListener(_applyBlocklistFilter);
    _pinsSubscription?.cancel();
    _networkSubscription?.cancel();
    super.dispose();
  }
}
