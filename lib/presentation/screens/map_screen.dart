import 'dart:async';
import 'dart:math' show Point;
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/core/build_flags.dart';
import 'package:ccwmap/core/system_constants.dart';
import 'package:ccwmap/data/datasources/maptiler_geocoding_client.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'package:ccwmap/data/services/location_service.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';
import 'package:ccwmap/presentation/widgets/report_pin_dialog.dart';
import 'package:ccwmap/presentation/widgets/sign_in_prompt_sheet.dart';
import 'package:ccwmap/presentation/widgets/compass_button.dart';
import 'package:ccwmap/presentation/utils/error_messages.dart';
import 'package:ccwmap/presentation/screens/settings_screen.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:uuid/uuid.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// Returns true when [pinCreatorId] belongs to a different real user
/// (not null, not the viewer, not a pre-populated system pin). Used to
/// gate the Report/Block buttons on the pin edit dialog.
@visibleForTesting
bool isOtherUserPin({
  required String? pinCreatorId,
  required String? currentUserId,
}) {
  if (pinCreatorId == null) return false;
  if (pinCreatorId == currentUserId) return false;
  if (pinCreatorId == kSystemUserId) return false;
  return true;
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _mapController;
  final LocationService _locationService = LocationService();
  Position? _currentLocation;
  bool _isLoadingLocation = false;
  bool _locationComponentEnabled = false;
  bool _styleLoaded = false;

  // ViewModel and pins
  MapViewModel? _viewModel;
  List<Pin> _pins = [];
  bool _isDialogOpen = false;
  DateTime? _lastDialogCloseTime;
  bool _isUpdatingLayers = false;
  bool _pendingLayerUpdate = false;
  bool _isUpdatingClusters = false;
  bool _pendingClusterUpdate = false;

  // Debug state (toggled by long-pressing the title bar — lets user verify
  // iOS POI tap detection on-device without a Mac)
  bool _debugMode = false;
  String? _debugLastTap;
  String? _debugLastDetection;
  String? _debugLocationPipeline;
  int _locationComponentCallCount = 0;

  // Initial camera position - center of US
  static const double _initialLatitude = 39.8283;
  static const double _initialLongitude = -98.5795;
  static const double _initialZoom = 4.0;

  // Pin tap/near-miss thresholds in screen pixels. Pixel-based thresholds are
  // zoom-agnostic and avoid relying on cameraPosition.zoom, which can be stale
  // on iOS and lead to the nearest-pin fallback picking a pin hundreds of
  // meters away.
  //
  // Circle radius is 12 px; 30 px gives a small forgiveness zone around the
  // visible pin without catching unrelated taps in empty space.
  static const double _pinHitPixelThreshold = 30.0;
  static const double _nearPinPixelThreshold = 30.0;

  @override
  void initState() {
    super.initState();

    _requestLocationPermission();

    // Initialize ViewModel after the first frame to avoid notifying during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeViewModel();
    });
  }

  /// Initialize ViewModel and listen to pin updates
  Future<void> _initializeViewModel() async {
    _viewModel = Provider.of<MapViewModel>(context, listen: false);

    // Listen to pin changes
    _viewModel!.addListener(_onPinsChanged);

    // Listen to viewport cluster changes (low-zoom server aggregates).
    _viewModel!.viewportClusters.addListener(_onClustersChanged);

    // Initialize ViewModel (loads sample data if needed)
    await _viewModel!.initialize();
  }

  /// Called when pins change in ViewModel
  void _onPinsChanged() {
    if (!mounted) return;

    setState(() {
      _pins = _viewModel!.pins;
    });

    // Update pins layer if map is ready
    if (_mapController != null) {
      _updatePinsLayer();
    }
  }

  /// Called when the server-side cluster aggregates change. Reads the
  /// latest value off the notifier (not a closure-captured snapshot) so a
  /// rapid succession of fires always renders the freshest list.
  void _onClustersChanged() {
    if (!mounted) return;
    final clusters = _viewModel?.viewportClusters.value ?? const [];
    _updateClustersLayer(clusters);
  }

  /// Request location permission and get current location
  Future<void> _requestLocationPermission() async {
    try {
      setState(() => _isLoadingLocation = true);

      // Check if location services are enabled
      final serviceEnabled = await _locationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationServiceDisabledDialog();
        }
        return;
      }

      // Get current location
      final position = await _locationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentLocation = position;
          _isLoadingLocation = false;
        });
        debugPrint(
          'Location obtained: ${position.latitude}, ${position.longitude}',
        );

        // Try to enable — no-ops until map controller + style are ready.
        _tryEnableLocationComponent(from: 'loc-arrived');
      }
    } catch (e) {
      debugPrint('Error requesting location: $e');
      if (mounted) {
        setState(() => _isLoadingLocation = false);
        if (e.toString().contains('denied')) {
          _showPermissionDeniedDialog();
        }
      }
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    debugPrint('Map created successfully');

    // CRITICAL FOR WEB: Listen for direct taps on features (circles)
    // onMapClick doesn't fire when clicking directly on circles/symbols on web
    // onFeatureTapped is the only way to detect direct clicks on features
    controller.onFeatureTapped.add(_onFeatureTapped);

    // Actual location-component enable waits for style load — camera
    // operations before the style is ready can silently no-op on iOS.
    _tryEnableLocationComponent(from: 'map-created');
  }

  /// Called when a feature (circle) is directly tapped
  ///
  /// This is the PRIMARY method for detecting pin clicks on web.
  /// On web, clicking directly on a circle layer does NOT trigger onMapClick,
  /// but it DOES trigger onFeatureTapped. This gives us proper UX where users
  /// can click directly on pins.
  ///
  /// Parameters:
  /// - point: Screen coordinates of the tap
  /// - coordinates: Geographic lat/lng of the tap
  /// - id: Feature ID (should match pin.id from our GeoJSON)
  /// - layerId: Layer ID (should be 'pins-layer')
  /// - annotation: Additional annotation data (unused)
  void _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    dynamic annotation,
  ) async {
    // Cluster taps zoom in on the centroid; the resulting onCameraIdle
    // re-fetches the viewport so the user sees finer detail (either a
    // sub-cluster or individual pins).
    if (layerId == 'clusters-circle-layer' ||
        layerId == 'clusters-count-layer') {
      await _onClusterTapped(coordinates);
      return;
    }

    // Only handle taps on our pins layer
    if (layerId != 'pins-layer') {
      return;
    }

    // Prevent opening multiple dialogs
    if (_isDialogOpen) {
      debugPrint('Dialog already open, ignoring feature tap');
      return;
    }

    // Capture auth state before any awaits to satisfy use_build_context_synchronously.
    final auth = Provider.of<AuthViewModel>(context, listen: false);

    // Find the pin by ID. On web, maplibre-gl-js doesn't always surface the
    // GeoJSON feature id to onFeatureTapped (without an explicit promoteId),
    // so fall back to nearest-pin-by-pixel-distance if the id lookup misses.
    Pin? pin;
    try {
      pin = _pins.firstWhere((p) => p.id == id);
    } catch (_) {
      pin = null;
    }

    if (pin == null) {
      double minDist = double.infinity;
      for (final p in _pins) {
        final d = await _pixelDistanceToPin(p, point);
        if (d == null) continue;
        if (d < _pinHitPixelThreshold && d < minDist) {
          minDist = d;
          pin = p;
        }
      }
      if (pin == null) {
        debugPrint('No pin matched feature tap (id=$id, no nearby pin)');
        _setDebugDetection('feature-tap: id miss, no nearby pin');
        return;
      }
    }

    // Verify the tap actually landed near this pin on-screen. iOS's native
    // hit test can report a pin hit for taps that are visually far from the
    // circle — without this guard, tapping empty space near the map can open
    // the edit dialog for a distant pin.
    final pixelDist = await _pixelDistanceToPin(pin, point);
    if (pixelDist != null && pixelDist > _pinHitPixelThreshold) {
      debugPrint(
        'Feature tap rejected: ${pin.name} is ${pixelDist.toStringAsFixed(0)}px from tap',
      );
      _setDebugDetection(
        'feature-tap rejected: ${pin.name} ${pixelDist.toStringAsFixed(0)}px > $_pinHitPixelThreshold',
      );
      return;
    }

    debugPrint('Found pin: ${pin.name}');
    _setDebugDetection(
      'feature-tap: ${pin.name}${pixelDist != null ? " (${pixelDist.toStringAsFixed(0)}px)" : ""}',
    );

    if (!auth.isAuthenticated) {
      _showReadOnlyPinDialog(pin);
      return;
    }

    _showPinDialog(
      isEditMode: true,
      poiName: pin.name,
      initialStatus: pin.status,
      initialRestrictionTag: pin.restrictionTag,
      initialHasSecurityScreening: pin.hasSecurityScreening,
      initialHasPostedSignage: pin.hasPostedSignage,
      pinId: pin.id,
    );
  }

  /// Zoom in on a cluster's centroid. The resulting [animateCamera] completion
  /// triggers [_onCameraIdle], which the viewmodel debounces and dispatches as
  /// a fresh bbox fetch — surfacing either a finer cluster or individual pins.
  Future<void> _onClusterTapped(LatLng centroid) async {
    final controller = _mapController;
    if (controller == null) return;
    final currentZoom = controller.cameraPosition?.zoom ?? _initialZoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(centroid, (currentZoom + 2).clamp(4.0, 18.0)),
    );
  }

  void _onStyleLoadedCallback() {
    _styleLoaded = true;

    // Now that the style is loaded, camera animations will stick on iOS.
    _tryEnableLocationComponent(from: 'style-loaded');

    // Add pins layer to map
    _updatePinsLayer();

    // Initial bbox fetch for the starting viewport.
    _onCameraIdle();
  }

  /// Update pins on the map using circle layers
  /// Note: Circles will block clicks on web, but we use geographic distance
  /// detection to find clicked pins, so this works fine
  Future<void> _updatePinsLayer() async {
    if (_mapController == null) return;

    // Prevent concurrent layer updates - queue if busy
    if (_isUpdatingLayers) {
      _pendingLayerUpdate = true;
      return;
    }

    _isUpdatingLayers = true;
    _pendingLayerUpdate = false;
    try {
      // Build GeoJSON from pins
      final geojson = _buildPinsGeoJson();

      // Remove existing source/layers if present (in correct order)
      // Must remove layers before source, and in reverse order of creation
      try {
        await _mapController!.removeLayer('pins-labels-layer');
      } catch (e) {
        // Layer doesn't exist yet, that's ok
      }

      try {
        await _mapController!.removeLayer('pins-layer');
      } catch (e) {
        // Layer doesn't exist yet, that's ok
      }

      try {
        await _mapController!.removeSource('pins-source');
      } catch (e) {
        // Source doesn't exist yet, that's ok
      }

      // Add GeoJSON source. promoteId ensures maplibre-gl-js (web) surfaces
      // our UUID to onFeatureTapped; without it web falls back to auto-
      // generated numeric ids and the feature-id lookup in _onFeatureTapped
      // misses (the pixel-distance fallback there covers this case too, but
      // promoteId makes the ID path work correctly on all platforms).
      await _mapController!.addGeoJsonSource(
        'pins-source',
        geojson,
        promoteId: 'id',
      );

      // Add circle layer - even though it blocks clicks, our geographic distance
      // detection will find the closest pin
      await _mapController!.addCircleLayer(
        'pins-source',
        'pins-layer',
        CircleLayerProperties(
          circleRadius: 12.0,
          circleColor: [
            'match',
            ['get', 'status'],
            0, '#4CAF50', // ALLOWED - Green
            1, '#FFC107', // UNCERTAIN - Yellow
            2, '#F44336', // NO_GUN - Red
            '#999999', // Default gray
          ],
          circleStrokeWidth: 2.0,
          circleStrokeColor: '#FFFFFF',
          circleOpacity: 0.8,
        ),
      );

      // Add symbol layer for pin name labels
      // enableInteraction: false so taps fall through to pins-layer circles
      await _mapController!.addSymbolLayer(
        'pins-source',
        'pins-labels-layer',
        SymbolLayerProperties(
          textField: ['get', 'name'],
          textSize: 13.0,
          textColor: '#000000',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.5,
          textHaloBlur: 1.0,
          textOffset: [
            Expressions.literal,
            [0, 1.5], // Offset below the pin circle
          ],
          textAnchor: 'top',
          textMaxWidth: 10.0, // Wrap text at 10em
          textAllowOverlap: false,
          textIgnorePlacement: false,
        ),
        enableInteraction: false,
      );
    } catch (e) {
      debugPrint('MapScreen: Error updating pins layer: $e');
    } finally {
      _isUpdatingLayers = false;
      // Process any pending update that was queued while we were busy
      if (_pendingLayerUpdate) {
        _pendingLayerUpdate = false;
        _updatePinsLayer();
      }
    }
  }

  /// Render server-aggregated cluster circles at low zoom levels.
  ///
  /// Mirrors `_updatePinsLayer`'s pattern: tear down existing layers/source
  /// in reverse order, then add a GeoJSON source, a count-sized circle
  /// layer, and a count-text symbol layer on top. The symbol layer has
  /// `enableInteraction: false` so taps fall through to the circle (Task 15
  /// wires cluster tap routing).
  ///
  /// Reentrancy: if a fire arrives mid-await, set the pending flag and
  /// re-trigger from `finally` with the freshest value from the notifier
  /// (the captured `clusters` arg could be stale by then).
  Future<void> _updateClustersLayer(List<MapItemCluster> clusters) async {
    if (_mapController == null) return;
    if (_isUpdatingClusters) {
      _pendingClusterUpdate = true;
      return;
    }
    _isUpdatingClusters = true;
    _pendingClusterUpdate = false;

    try {
      final features = clusters
          .map(
            (c) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [c.centroidLng, c.centroidLat],
              },
              'properties': {
                'count': c.count,
                'status': c.dominantStatus.colorCode,
              },
            },
          )
          .toList();

      final geojson = {'type': 'FeatureCollection', 'features': features};

      // Tear down in reverse order of creation (layers before source).
      try {
        await _mapController!.removeLayer('clusters-count-layer');
      } catch (_) {
        // Layer doesn't exist yet, that's ok
      }
      try {
        await _mapController!.removeLayer('clusters-circle-layer');
      } catch (_) {
        // Layer doesn't exist yet, that's ok
      }
      try {
        await _mapController!.removeSource('clusters-source');
      } catch (_) {
        // Source doesn't exist yet, that's ok
      }

      await _mapController!.addGeoJsonSource('clusters-source', geojson);

      // Cluster circle: radius scales with count, color matches dominant
      // status (same palette as individual pins).
      await _mapController!.addCircleLayer(
        'clusters-source',
        'clusters-circle-layer',
        CircleLayerProperties(
          circleRadius: [
            'interpolate',
            ['linear'],
            ['get', 'count'],
            1, 14,
            10, 20,
            100, 30,
            1000, 40,
          ],
          circleColor: [
            'match',
            ['get', 'status'],
            0, '#4CAF50', // ALLOWED - Green
            1, '#FFC107', // UNCERTAIN - Yellow
            2, '#F44336', // NO_GUN - Red
            '#999999', // Default gray
          ],
          circleStrokeWidth: 2.0,
          circleStrokeColor: '#FFFFFF',
          circleOpacity: 0.85,
        ),
      );

      // Count label on top. enableInteraction: false so the underlying
      // circle still receives taps (Task 15 routes them).
      await _mapController!.addSymbolLayer(
        'clusters-source',
        'clusters-count-layer',
        SymbolLayerProperties(
          textField: ['get', 'count'],
          textSize: 14.0,
          textColor: '#FFFFFF',
          textHaloColor: '#000000',
          textHaloWidth: 1.0,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        enableInteraction: false,
      );
    } catch (e) {
      debugPrint('MapScreen: Error updating clusters layer: $e');
    } finally {
      _isUpdatingClusters = false;
      if (_pendingClusterUpdate) {
        _pendingClusterUpdate = false;
        // Re-pull from viewModel — captured cluster list could be stale.
        _updateClustersLayer(
          _viewModel?.viewportClusters.value ?? const [],
        );
      }
    }
  }

  /// Build GeoJSON FeatureCollection from pins
  Map<String, dynamic> _buildPinsGeoJson() {
    final features = _pins.map((pin) {
      return {
        'type': 'Feature',
        'id': pin.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [pin.location.longitude, pin.location.latitude],
        },
        'properties': {
          'id': pin.id,
          'name': pin.name,
          'status': pin.status.colorCode,
          'restrictionTag': pin.restrictionTag?.name,
          'hasSecurityScreening': pin.hasSecurityScreening,
          'hasPostedSignage': pin.hasPostedSignage,
          'createdBy': pin.metadata.createdBy,
          'votes': pin.metadata.votes,
        },
      };
    }).toList();

    return {'type': 'FeatureCollection', 'features': features};
  }

  /// Enable the location indicator on the map and pan to the user's location.
  ///
  /// Preconditions: map controller present, style loaded, location obtained,
  /// not already enabled. Called from three places (map created, style loaded,
  /// location arrived) — whichever one completes the trio triggers the work.
  ///
  /// iOS belt-and-suspenders: after the initial animateCamera we schedule a
  /// delayed moveCamera. Theory is that onStyleLoadedCallback can fire while
  /// MapLibre iOS is still applying initialCameraPosition, and our
  /// animateCamera gets clobbered mid-flight. The follow-up moveCamera is a
  /// no-op if the first call stuck, and corrects the camera if it didn't.
  ///
  /// Every call records its guard state into _debugLocationPipeline so the
  /// on-device debug overlay (bug icon, top-right) shows exactly which guard
  /// is failing on iOS TestFlight without needing a Mac.
  Future<void> _tryEnableLocationComponent({String from = 'unknown'}) async {
    _locationComponentCallCount++;
    _setLocationPipelineDebug(
      '#$_locationComponentCallCount $from '
      'ctrl=${_mapController != null ? "Y" : "N"} '
      'style=${_styleLoaded ? "Y" : "N"} '
      'loc=${_currentLocation != null ? "Y" : "N"} '
      'done=${_locationComponentEnabled ? "Y" : "N"}',
    );

    if (_mapController == null) return;
    if (!_styleLoaded) return;
    if (_currentLocation == null) return;
    if (_locationComponentEnabled) return;

    _locationComponentEnabled = true;

    final target = LatLng(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
    );

    try {
      debugPrint(
        'Enabling location component at: ${target.latitude}, ${target.longitude}',
      );

      if (kIsWeb) {
        // Web: myLocationEnabled doesn't render a puck reliably, so draw our
        // own circle layer.
        await _addUserLocationMarker();
      }

      _setLocationPipelineDebug(
        'animating ${target.latitude.toStringAsFixed(3)},${target.longitude.toStringAsFixed(3)}',
      );

      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 16.0),
        duration: const Duration(milliseconds: 1500),
      );

      _setLocationPipelineDebug('animate done');
      debugPrint('Location component enabled successfully');
    } catch (e) {
      // On failure, allow a retry — e.g. if the controller was torn down
      // between the guard and the call.
      _locationComponentEnabled = false;
      _setLocationPipelineDebug('animate err');
      debugPrint('Error enabling location component: $e');
      return;
    }

    // iOS retry: if the animate was clobbered by MapLibre iOS's own
    // initial-camera pass, re-apply with an instant moveCamera. No-op if
    // the animate already landed at target.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || _mapController == null) return;
      try {
        _setLocationPipelineDebug('ios retry');
        await _mapController!.moveCamera(
          CameraUpdate.newLatLngZoom(target, 16.0),
        );
        _setLocationPipelineDebug('ios retry done');
      } catch (e) {
        _setLocationPipelineDebug('ios retry err');
        debugPrint('iOS retry moveCamera failed: $e');
      }
    }
  }

  /// Record the latest location-pipeline state for the on-device debug
  /// overlay. Always updates the underlying field; setState only runs when
  /// debug mode is active, so subsequently toggling debug on reveals the
  /// most recent state regardless of when it was recorded.
  void _setLocationPipelineDebug(String info) {
    debugPrint('LocationPipeline: $info');
    _debugLocationPipeline = info;
    if (_debugMode && mounted) {
      setState(() {});
    }
  }

  /// Add a custom blue circle marker for user location (web platform workaround)
  Future<void> _addUserLocationMarker() async {
    if (_mapController == null || _currentLocation == null) return;

    try {
      // Create GeoJSON for user location
      final userLocationGeoJson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [
                _currentLocation!.longitude,
                _currentLocation!.latitude,
              ],
            },
            'properties': {'type': 'user-location'},
          },
        ],
      };

      // Remove existing user location layer/source if present
      try {
        await _mapController!.removeLayer('user-location-accuracy-layer');
      } catch (e) {
        // Layer doesn't exist, that's ok
      }
      try {
        await _mapController!.removeLayer('user-location-layer');
      } catch (e) {
        // Layer doesn't exist, that's ok
      }
      try {
        await _mapController!.removeSource('user-location-source');
      } catch (e) {
        // Source doesn't exist, that's ok
      }

      // Add source for user location
      await _mapController!.addGeoJsonSource(
        'user-location-source',
        userLocationGeoJson,
      );

      // Add outer circle for accuracy/glow effect
      await _mapController!.addCircleLayer(
        'user-location-source',
        'user-location-accuracy-layer',
        CircleLayerProperties(
          circleRadius: 20.0,
          circleColor: '#4285F4', // Google blue
          circleOpacity: 0.2,
          circleBlur: 0.5,
        ),
      );

      // Add inner blue dot for precise location
      await _mapController!.addCircleLayer(
        'user-location-source',
        'user-location-layer',
        CircleLayerProperties(
          circleRadius: 8.0,
          circleColor: '#4285F4', // Google blue
          circleStrokeWidth: 3.0,
          circleStrokeColor: '#FFFFFF',
          circleOpacity: 1.0,
        ),
      );

      debugPrint('User location marker added successfully');
    } catch (e) {
      debugPrint('Error adding user location marker: $e');
    }
  }

  /// Called by MapLibre after the camera settles from pan/zoom/rotate.
  /// Computes the visible bounding box + integer zoom and forwards to the
  /// view model, which debounces and dispatches to ViewportPinsManager.
  Future<void> _onCameraIdle() async {
    final controller = _mapController;
    final viewModel = _viewModel;
    if (controller == null || viewModel == null) return;

    try {
      final bounds = await controller.getVisibleRegion();
      final z = controller.cameraPosition?.zoom ?? _initialZoom;
      viewModel.onCameraIdle(
        swLat: bounds.southwest.latitude,
        swLng: bounds.southwest.longitude,
        neLat: bounds.northeast.latitude,
        neLng: bounds.northeast.longitude,
        zoom: z.round(),
      );
    } catch (e) {
      debugPrint('MapScreen: getVisibleRegion failed: $e');
    }
  }

  /// Handle map click - detect if user tapped on a pin
  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    debugPrint('=== MAP CLICK DEBUG ===');
    debugPrint('Click at: ${coordinates.latitude}, ${coordinates.longitude}');
    debugPrint('Screen point: ${point.x}, ${point.y}');

    if (_debugMode && mounted) {
      setState(() {
        _debugLastTap =
            'px=(${point.x.toStringAsFixed(0)},${point.y.toStringAsFixed(0)}) '
            'geo=(${coordinates.latitude.toStringAsFixed(5)},${coordinates.longitude.toStringAsFixed(5)})';
        _debugLastDetection = '…';
      });
    }

    if (_mapController == null) {
      debugPrint('Map controller is null, returning');
      return;
    }

    // Prevent opening multiple dialogs
    if (_isDialogOpen) {
      debugPrint('Dialog already open, ignoring map click');
      return;
    }

    // Add cooldown period after dialog close to prevent click propagation
    if (_lastDialogCloseTime != null) {
      final timeSinceClose = DateTime.now().difference(_lastDialogCloseTime!);
      if (timeSinceClose.inMilliseconds < 300) {
        debugPrint(
          'Cooldown period active (${timeSinceClose.inMilliseconds}ms), ignoring map click',
        );
        return;
      }
    }

    try {
      // PRIORITY 1: Check if user tapped on a POI label (from base map)
      final poiResult = await _detectPoiAtPoint(point, coordinates);

      // Re-check after async gap — onFeatureTapped may have opened a dialog
      if (_isDialogOpen) return;

      if (poiResult != null) {
        debugPrint(
          'POI detected: ${poiResult['name']} at ${poiResult['lat']}, ${poiResult['lng']}',
        );

        final poiLat = poiResult['lat'] as double;
        final poiLng = poiResult['lng'] as double;
        final poiName = poiResult['name'] as String;

        // Validate coordinates are within US bounds
        if (!_isWithinUSBounds(poiLat, poiLng)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot create pins outside the continental US'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        // Show create dialog with POI name (or prompt guests to sign in)
        if (mounted) {
          final auth = Provider.of<AuthViewModel>(context, listen: false);
          if (!auth.isAuthenticated) {
            _promptSignIn(
              title: 'Sign in to add pins',
              body:
                  'Create an account or sign in to contribute to the community map.',
            );
            return;
          }
          _showPinDialog(
            isEditMode: false,
            poiName: poiName,
            initialStatus: null,
            initialRestrictionTag: null,
            initialHasSecurityScreening: false,
            initialHasPostedSignage: false,
            coordinates: LatLng(poiLat, poiLng),
          );
        }
        return;
      }

      // PRIORITY 3: Find an existing pin very close to the tap (in screen
      // pixels). Only triggers when the tap narrowly misses a visible pin
      // circle. Pixel distance is used rather than meters because
      // cameraPosition.zoom can be stale on iOS, which previously caused taps
      // in empty space to match pins hundreds of meters away.
      Pin? clickedPin;
      double minPixelDistance = double.infinity;

      for (final pin in _pins) {
        final pixelDist = await _pixelDistanceToPin(pin, point);
        if (pixelDist == null) continue;

        debugPrint('Pin ${pin.name}: ${pixelDist.toStringAsFixed(0)}px away');

        if (pixelDist < _nearPinPixelThreshold &&
            pixelDist < minPixelDistance) {
          minPixelDistance = pixelDist;
          clickedPin = pin;
        }
      }

      if (_isDialogOpen) return;

      if (clickedPin != null) {
        debugPrint(
          'Found clicked pin: ${clickedPin.name} (${minPixelDistance.toStringAsFixed(0)}px away)',
        );
        _setDebugDetection(
          'near-pin: ${clickedPin.name} (${minPixelDistance.toStringAsFixed(0)}px)',
        );
        final Pin pin = clickedPin;
        final properties = {
          'id': pin.id,
          'name': pin.name,
          'status': pin.status.colorCode,
          'restrictionTag': pin.restrictionTag?.name,
          'hasSecurityScreening': pin.hasSecurityScreening,
          'hasPostedSignage': pin.hasPostedSignage,
        };

        if (mounted) {
          final pinId = properties['id'] as String?;
          final pinName = properties['name'] as String? ?? 'Unknown Location';
          final statusCode = properties['status'] as int?;
          final restrictionTagStr = properties['restrictionTag'] as String?;
          final hasSecurityScreening =
              properties['hasSecurityScreening'] as bool? ?? false;
          final hasPostedSignage =
              properties['hasPostedSignage'] as bool? ?? false;

          // Parse status and restriction tag
          final status = statusCode != null
              ? PinStatus.fromColorCode(statusCode)
              : PinStatus.ALLOWED;
          final restrictionTag = restrictionTagStr != null
              ? RestrictionTag.fromString(restrictionTagStr)
              : null;

          debugPrint('Opening edit dialog for pin: $pinName (ID: $pinId)');

          final auth = Provider.of<AuthViewModel>(context, listen: false);
          if (!auth.isAuthenticated) {
            // Pass the already-fetched pin straight to the read-only dialog.
            _showReadOnlyPinDialog(clickedPin);
            return;
          }
          _showPinDialog(
            isEditMode: true,
            poiName: pinName,
            initialStatus: status,
            initialRestrictionTag: restrictionTag,
            initialHasSecurityScreening: hasSecurityScreening,
            initialHasPostedSignage: hasPostedSignage,
            pinId: pinId,
          );
        }
      } else {
        // No pin or POI clicked - do nothing on single click
        // User must long-press to create a pin at empty location
        debugPrint(
          'No pin or POI found at click location. Use long-press to create pin here.',
        );
        _setDebugDetection('no POI, no nearby pin — tap ignored');
      }
    } catch (e) {
      debugPrint('Error handling map click: $e');
    }
  }

  /// Handle long-press on map - always creates a new pin with custom name
  Future<void> _onMapLongClick(Point<double> point, LatLng coordinates) async {
    debugPrint('=== MAP LONG-PRESS DEBUG ===');
    debugPrint(
      'Long-press at: ${coordinates.latitude}, ${coordinates.longitude}',
    );

    if (_mapController == null) {
      debugPrint('Map controller is null, returning');
      return;
    }

    // Prevent opening multiple dialogs
    if (_isDialogOpen) {
      debugPrint('Dialog already open, ignoring long-press');
      return;
    }

    // Add cooldown period after dialog close
    if (_lastDialogCloseTime != null) {
      final timeSinceClose = DateTime.now().difference(_lastDialogCloseTime!);
      if (timeSinceClose.inMilliseconds < 300) {
        debugPrint('Cooldown period active, ignoring long-press');
        return;
      }
    }

    try {
      // Validate coordinates are within US bounds
      if (!_isWithinUSBounds(coordinates.latitude, coordinates.longitude)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot create pins outside the continental US'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Always show create dialog with empty name for long-press
      // User explicitly wants to create a custom pin (not using POI)
      if (mounted) {
        debugPrint('Opening create dialog for long-press with empty name');
        final auth = Provider.of<AuthViewModel>(context, listen: false);
        if (!auth.isAuthenticated) {
          _promptSignIn(
            title: 'Sign in to add pins',
            body:
                'Create an account or sign in to contribute to the community map.',
          );
          return;
        }
        _showPinDialog(
          isEditMode: false,
          poiName: '', // Empty name - user will enter their own
          initialStatus: null,
          initialRestrictionTag: null,
          initialHasSecurityScreening: false,
          initialHasPostedSignage: false,
          coordinates: coordinates,
        );
      }
    } catch (e) {
      debugPrint('Error handling long-press: $e');
    }
  }

  /// Handle right-click on web - creates a new pin at the clicked location
  Future<void> _handleRightClick(Offset localPosition) async {
    debugPrint('=== RIGHT-CLICK DEBUG (Web) ===');
    debugPrint('Local position: ${localPosition.dx}, ${localPosition.dy}');

    if (_mapController == null) {
      debugPrint('Map controller is null, returning');
      return;
    }

    // Prevent opening multiple dialogs
    if (_isDialogOpen) {
      debugPrint('Dialog already open, ignoring right-click');
      return;
    }

    // Add cooldown period after dialog close
    if (_lastDialogCloseTime != null) {
      final timeSinceClose = DateTime.now().difference(_lastDialogCloseTime!);
      if (timeSinceClose.inMilliseconds < 300) {
        debugPrint('Cooldown period active, ignoring right-click');
        return;
      }
    }

    try {
      // Convert screen position to map coordinates
      final coordinates = await _mapController!.toLatLng(
        Point(localPosition.dx, localPosition.dy),
      );

      debugPrint(
        'Right-click at: ${coordinates.latitude}, ${coordinates.longitude}',
      );

      // Validate coordinates are within US bounds
      if (!_isWithinUSBounds(coordinates.latitude, coordinates.longitude)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot create pins outside the continental US'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Show create dialog with empty name
      if (mounted) {
        debugPrint('Opening create dialog for right-click');
        final auth = Provider.of<AuthViewModel>(context, listen: false);
        if (!auth.isAuthenticated) {
          _promptSignIn(
            title: 'Sign in to add pins',
            body:
                'Create an account or sign in to contribute to the community map.',
          );
          return;
        }
        _showPinDialog(
          isEditMode: false,
          poiName: '', // Empty name - user will enter their own
          initialStatus: null,
          initialRestrictionTag: null,
          initialHasSecurityScreening: false,
          initialHasPostedSignage: false,
          coordinates: coordinates,
        );
      }
    } catch (e) {
      debugPrint('Error handling right-click: $e');
    }
  }

  Future<void> _showPinDialog({
    required bool isEditMode,
    required String poiName,
    required PinStatus? initialStatus,
    required RestrictionTag? initialRestrictionTag,
    required bool initialHasSecurityScreening,
    required bool initialHasPostedSignage,
    String? pinId, // For edit mode
    LatLng? coordinates, // For create mode
  }) async {
    // Set flag to prevent multiple dialogs
    _isDialogOpen = true;

    // Resolve the creator id up front — needed for Report/Block visibility.
    final auth = Provider.of<AuthViewModel>(context, listen: false);
    final currentUserId = auth.currentUser?.id;
    String? pinCreatorId;
    if (isEditMode && pinId != null) {
      final existing = await _viewModel?.getPinById(pinId);
      pinCreatorId = existing?.metadata.createdBy;
    }
    if (!mounted) return;
    final canModerate =
        isEditMode &&
        currentUserId != null &&
        isOtherUserPin(
          pinCreatorId: pinCreatorId,
          currentUserId: currentUserId,
        );

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PinDialog(
        isEditMode: isEditMode,
        poiName: poiName,
        initialStatus: initialStatus,
        initialRestrictionTag: initialRestrictionTag,
        initialHasSecurityScreening: initialHasSecurityScreening,
        initialHasPostedSignage: initialHasPostedSignage,
        onReport: canModerate && pinId != null
            ? () => _handleReportPin(dialogContext, pinId)
            : null,
        onBlock: canModerate && pinCreatorId != null
            ? () => _handleBlockUser(dialogContext, pinCreatorId!, pinId!)
            : null,
        onConfirm: (result) async {
          debugPrint('Pin dialog confirmed:');
          debugPrint('  Status: ${result.status.displayName}');
          debugPrint(
            '  Restriction: ${result.restrictionTag?.displayName ?? 'None'}',
          );
          debugPrint('  Security Screening: ${result.hasSecurityScreening}');
          debugPrint('  Posted Signage: ${result.hasPostedSignage}');

          Navigator.of(dialogContext, rootNavigator: true).pop();

          try {
            if (isEditMode && pinId != null) {
              // Edit existing pin
              final existingPin = await _viewModel?.getPinById(pinId);
              if (existingPin != null) {
                final updatedPin = existingPin.copyWith(
                  name: result.name,
                  status: result.status,
                  restrictionTag: result.restrictionTag,
                  hasSecurityScreening: result.hasSecurityScreening,
                  hasPostedSignage: result.hasPostedSignage,
                  metadata: existingPin.metadata.copyWith(
                    lastModified: DateTime.now(),
                  ),
                );
                await _viewModel?.updatePin(updatedPin);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pin updated successfully'),
                      duration: Duration(seconds: 2),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            } else if (!isEditMode && coordinates != null) {
              // Create new pin
              final authViewModel = Provider.of<AuthViewModel>(
                context,
                listen: false,
              );
              final currentUser = authViewModel.currentUser;

              final newPin = Pin(
                id: const Uuid().v4(),
                name: result.name,
                location: Location.fromLatLng(
                  coordinates.latitude,
                  coordinates.longitude,
                ),
                status: result.status,
                restrictionTag: result.restrictionTag,
                hasSecurityScreening: result.hasSecurityScreening,
                hasPostedSignage: result.hasPostedSignage,
                metadata: PinMetadata(
                  createdBy: currentUser!.id,
                  createdAt: DateTime.now(),
                  lastModified: DateTime.now(),
                ),
              );

              await _viewModel?.addPin(newPin);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pin created successfully'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error saving pin: $e');
            if (mounted) {
              final friendlyMessage = ErrorMessages.getUserFriendlyMessage(
                e.toString(),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(friendlyMessage),
                  duration: const Duration(seconds: 3),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        onDelete: isEditMode && pinId != null
            ? () async {
                debugPrint('Pin delete requested for ID: $pinId');

                // Capture navigator before async operation
                final navigator = Navigator.of(
                  dialogContext,
                  rootNavigator: true,
                );

                // Show confirmation dialog
                final confirmed = await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: const Text('Delete Pin?'),
                    content: const Text(
                      'Are you sure you want to delete this pin? This action cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(confirmContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(confirmContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  // User confirmed deletion
                  navigator.pop();

                  try {
                    await _viewModel?.deletePin(pinId);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pin deleted successfully'),
                          duration: Duration(seconds: 2),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error deleting pin: $e');
                    if (mounted) {
                      final friendlyMessage =
                          ErrorMessages.getUserFriendlyMessage(e.toString());
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(friendlyMessage),
                          duration: const Duration(seconds: 3),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              }
            : null,
        onCancel: () {
          debugPrint('Pin dialog cancelled');
          try {
            Navigator.of(dialogContext, rootNavigator: true).pop();
            debugPrint('Dialog closed successfully');
          } catch (e) {
            debugPrint('Error closing dialog: $e');
          }
        },
      ),
    );

    // Reset flag after dialog closes
    _isDialogOpen = false;
    _lastDialogCloseTime = DateTime.now();
    debugPrint('Dialog closed, cooldown period started');
  }

  Future<void> _handleReportPin(
    BuildContext dialogContext,
    String pinId,
  ) async {
    final moderation = Provider.of<ModerationRepository>(
      context,
      listen: false,
    );

    final navigator = Navigator.of(dialogContext, rootNavigator: true);
    // Close the PinDialog first so the report sub-dialog is the topmost modal.
    navigator.pop();

    await showDialog<void>(
      context: context,
      builder: (ctx) => ReportPinDialog(
        onSubmit: (reason, note) async {
          try {
            await moderation.submitPinReport(
              pinId: pinId,
              reason: reason,
              note: note,
            );
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Report submitted. Thanks for helping keep the map accurate.',
                  ),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Report failed: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _handleBlockUser(
    BuildContext dialogContext,
    String userId,
    String pinId,
  ) async {
    final blocklist = Provider.of<BlocklistService>(context, listen: false);
    final rootNavigator = Navigator.of(dialogContext, rootNavigator: true);

    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this user?'),
        content: const Text("You won't see any of their pins anymore."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    rootNavigator.pop();

    try {
      await blocklist.block(userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User blocked.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Block failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Shows a read-only [PinDialog] for guests tapping an existing pin.
  /// Tapping "Sign in to edit" closes the dialog and opens the prompt sheet.
  Future<void> _showReadOnlyPinDialog(Pin pin) async {
    _isDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PinDialog(
        isEditMode: true,
        isReadOnly: true,
        poiName: pin.name,
        initialStatus: pin.status,
        initialRestrictionTag: pin.restrictionTag,
        initialHasSecurityScreening: pin.hasSecurityScreening,
        initialHasPostedSignage: pin.hasPostedSignage,
        onConfirm: (_) {
          // Unreachable in read-only mode; provided to satisfy required param.
        },
        onCancel: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
        onSignInToEdit: () {
          Navigator.of(dialogContext, rootNavigator: true).pop();
          _promptSignIn(
            title: 'Sign in to edit',
            body:
                'Create an account or sign in to contribute to the community map.',
          );
        },
      ),
    );
    _isDialogOpen = false;
    _lastDialogCloseTime = DateTime.now();
  }

  /// Detect POI at or near click point
  /// Returns map with 'name', 'lat', 'lng' if POI found, null otherwise
  /// Checks MapLibre base map POIs (from the map tiles), with a MapTiler
  /// reverse geocoding fallback on iOS (where queryRenderedFeatures does not
  /// return base map symbol features).
  Future<Map<String, dynamic>?> _detectPoiAtPoint(
    Point<double> point,
    LatLng coordinates,
  ) async {
    if (_mapController == null) return null;

    // Layer IDs to query for POIs from the base map tiles. Deliberately
    // excludes place_label/place-label (country/state/city/town/village/
    // suburb/neighbourhood) — those areas are too large to pin meaningfully.
    const poiLayerIds = [
      'poi', // Common base map layer
      'poi_label', // MapTiler POI labels
      'poi-label', // Alternative naming
    ];

    // Screen pixel offsets to check (for catching offset labels)
    // Labels are often offset from their anchor point
    const offsets = [
      [0.0, 0.0], // Center
      [0.0, -20.0], // Above (labels often below point)
      [0.0, 20.0], // Below
      [-20.0, 0.0], // Left
      [20.0, 0.0], // Right
      [-15.0, -15.0], // Diagonal offsets
      [15.0, -15.0],
      [-15.0, 15.0],
      [15.0, 15.0],
    ];

    // Debug counters so we can see on-device whether queryRenderedFeatures
    // is returning anything at all on iOS.
    int totalFeatures = 0;
    int namedFeatures = 0;

    // Query rendered features at multiple points
    for (final offset in offsets) {
      final queryPoint = Point<double>(
        point.x + offset[0],
        point.y + offset[1],
      );

      try {
        // First try querying specific POI layers
        for (final layerId in poiLayerIds) {
          try {
            final features = await _mapController!.queryRenderedFeatures(
              queryPoint,
              [layerId],
              null,
            );

            totalFeatures += features.length;
            if (features.isNotEmpty) {
              final feature = features.first;
              final name = feature['properties']?['name']?.toString();

              if (name != null && name.isNotEmpty) {
                namedFeatures++;
                // Extract coordinates from feature geometry
                final geometry = feature['geometry'];
                double? lat, lng;

                if (geometry != null && geometry['coordinates'] != null) {
                  final coords = geometry['coordinates'];
                  if (coords is List && coords.length >= 2) {
                    lng = (coords[0] as num).toDouble();
                    lat = (coords[1] as num).toDouble();
                  }
                }

                // Fall back to click coordinates if geometry extraction fails
                lat ??= coordinates.latitude;
                lng ??= coordinates.longitude;

                debugPrint('Found POI in layer $layerId: $name');
                _setDebugDetection('QRF hit layer=$layerId name=$name');
                return {'name': name, 'lat': lat, 'lng': lng};
              }
            }
          } catch (e) {
            // Layer might not exist, continue to next
          }
        }

        // Also try querying ALL layers and filter for features with names
        try {
          final allFeatures = await _mapController!.queryRenderedFeatures(
            queryPoint,
            [], // Empty list = query all layers
            null,
          );

          totalFeatures += allFeatures.length;

          for (final feature in allFeatures) {
            final name = feature['properties']?['name']?.toString();
            final layerId = feature['layer']?['id']?.toString() ?? '';

            // Skip our own pins. The maplibre Flutter wrapper drops layer
            // info on Android and web (only iOS sometimes retains it), so
            // layerId is usually '' — the 'status' property is what reliably
            // identifies our pins (only our pins carry the numeric 0/1/2).
            if (layerId.contains('pins')) continue;
            if (feature['properties']?['status'] != null) continue;

            // Filter out place features (continents/countries/states/cities/
            // towns/villages/etc.) — too large to pin meaningfully. We can't
            // filter by source-layer because the Flutter wrapper drops it on
            // Android and web. Instead use the OpenMapTiles per-feature
            // properties observed in real tiles:
            //   - place_label  -> class ∈ {village, neighbourhood, suburb, ...}
            //   - state_label  -> admin_level set
            //   - country_label-> only iso_a2/name/rank, no class, no subclass
            //   - continent_label-> only name
            //   - poi_*        -> always has either a non-place class or a subclass
            const placeClasses = {
              'continent',
              'country',
              'state',
              'province',
              'region',
              'city',
              'town',
              'village',
              'hamlet',
              'suburb',
              'quarter',
              'neighbourhood',
              'isolated_dwelling',
              'island',
              'archipelago',
            };
            final props = feature['properties'] as Map?;
            final featureClass = props?['class']?.toString();
            final hasSubclass = props?['subclass'] != null;
            if (featureClass != null && placeClasses.contains(featureClass))
              continue;
            if (props?['admin_level'] != null) continue;
            // Catches countries (iso_a2 only) and continents (name only).
            if (featureClass == null && !hasSubclass) continue;

            if (name != null && name.isNotEmpty) {
              namedFeatures++;
              final geometry = feature['geometry'];
              double? lat, lng;

              if (geometry != null && geometry['coordinates'] != null) {
                final coords = geometry['coordinates'];
                if (coords is List && coords.length >= 2) {
                  lng = (coords[0] as num).toDouble();
                  lat = (coords[1] as num).toDouble();
                }
              }

              lat ??= coordinates.latitude;
              lng ??= coordinates.longitude;

              debugPrint('Found named feature in layer $layerId: $name');
              _setDebugDetection(
                'QRF hit layer=${layerId.isEmpty ? "?" : layerId} name=$name',
              );
              return {'name': name, 'lat': lat, 'lng': lng};
            }
          }
        } catch (e) {
          debugPrint('Error querying all layers: $e');
        }
      } catch (e) {
        debugPrint('Error querying at offset $offset: $e');
      }
    }

    // queryRenderedFeatures miss. On iOS, base map symbol layers are not
    // returned by queryRenderedFeatures — fall back to MapTiler's reverse
    // geocoding API to identify the POI label that was tapped.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final fallback = await _reverseGeocodePoiAtPoint(point, coordinates);
      if (fallback != null) return fallback;
    } else {
      _setDebugDetection(
        'QRF miss (features=$totalFeatures named=$namedFeatures)',
      );
    }

    return null;
  }

  /// iOS fallback: reverse geocode the tap coordinate and, if a POI lives
  /// within 60 screen pixels of the tap, return it as a POI hit.
  Future<Map<String, dynamic>?> _reverseGeocodePoiAtPoint(
    Point<double> point,
    LatLng coordinates,
  ) async {
    final apiKey = dotenv.env['MAPTILER_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      _setDebugDetection('geocode skip: no API key');
      return null;
    }

    final result = await MaptilerGeocodingClient.reverseGeocode(
      lat: coordinates.latitude,
      lng: coordinates.longitude,
      apiKey: apiKey,
    );

    if (result == null) {
      _setDebugDetection('geocode: no result');
      return null;
    }
    if (!result.isPoi) {
      _setDebugDetection(
        'geocode: not POI (types=${result.placeType.join(",")})',
      );
      return null;
    }

    // Verify the POI's anchor is visually close to where the user tapped.
    try {
      final poiScreen = await _mapController!.toScreenLocation(
        LatLng(result.lat, result.lng),
      );
      final dx = poiScreen.x - point.x;
      final dy = poiScreen.y - point.y;
      final pixelDist = math.sqrt(dx * dx + dy * dy);

      if (pixelDist > 60.0) {
        _setDebugDetection(
          'geocode: ${result.name} too far (${pixelDist.toStringAsFixed(0)}px)',
        );
        return null;
      }

      _setDebugDetection(
        'geocode hit: ${result.name} (${pixelDist.toStringAsFixed(0)}px)',
      );
      return {'name': result.name, 'lat': result.lat, 'lng': result.lng};
    } catch (e) {
      debugPrint('_reverseGeocodePoiAtPoint: toScreenLocation failed: $e');
      _setDebugDetection('geocode: screen projection failed');
      return null;
    }
  }

  /// Record the latest POI detection outcome for the on-device debug overlay.
  void _setDebugDetection(String info) {
    debugPrint('POI detect: $info');
    if (!_debugMode || !mounted) return;
    setState(() {
      _debugLastDetection = info;
    });
  }

  /// Return the screen pixel distance from [tapPoint] to [pin], or null if
  /// the projection fails.
  Future<double?> _pixelDistanceToPin(Pin pin, Point<double> tapPoint) async {
    if (_mapController == null) return null;
    try {
      final pinScreen = await _mapController!.toScreenLocation(
        LatLng(pin.location.latitude, pin.location.longitude),
      );
      final dx = pinScreen.x - tapPoint.x;
      final dy = pinScreen.y - tapPoint.y;
      return math.sqrt(dx * dx + dy * dy);
    } catch (e) {
      debugPrint('_pixelDistanceToPin: toScreenLocation failed: $e');
      return null;
    }
  }

  /// Check if coordinates are within continental US bounds
  bool _isWithinUSBounds(double latitude, double longitude) {
    const double minLat = 24.396308; // Southern border
    const double maxLat = 49.384358; // Northern border
    const double minLng = -125.0; // Western border
    const double maxLng = -66.93457; // Eastern border

    return latitude >= minLat &&
        latitude <= maxLat &&
        longitude >= minLng &&
        longitude <= maxLng;
  }

  /// Re-center map to user's current location
  Future<void> _onRecenterTapped() async {
    debugPrint('Re-center button tapped');

    if (_currentLocation == null) {
      // Try to get location if we don't have it
      if (!_isLoadingLocation) {
        await _requestLocationPermission();
      }

      if (_currentLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location not available'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    // Animate camera to current location
    if (_mapController != null && _currentLocation != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
          16.0, // Zoom level for street view
        ),
        duration: const Duration(milliseconds: 1000),
      );
      debugPrint('Map re-centered to user location');
    }
  }

  Future<void> _onCompassTapped() async {
    final controller = _mapController;
    final current = controller?.cameraPosition;
    if (controller == null || current == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current.target,
          zoom: current.zoom,
          bearing: 0.0,
          tilt: 0.0,
        ),
      ),
      duration: const Duration(milliseconds: 300),
    );
  }

  /// Shows the sign-in bottom sheet. Called from guest taps that would
  /// otherwise start a create/edit flow.
  void _promptSignIn({required String title, required String body}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SignInPromptSheet(title: title, body: body),
    );
  }

  Widget _buildTopBarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: Colors.black87,
              size: 24,
              semanticLabel: tooltip,
            ),
          ),
        ),
      ),
    );
  }

  /// Show dialog when location permission is denied
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'CCW Map needs access to your location to show your position on the map and help you create location-based pins.\n\n'
          'Please grant location permission in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _locationService.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show dialog when location services are disabled
  void _showLocationServiceDisabledDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Please enable location services on your device to use location features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _locationService.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Get the map style URL with API key
  String _getMapStyleUrl() {
    final apiKey = dotenv.env['MAPTILER_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('MapTiler API key not found, using demo tiles');
      return 'https://demotiles.maplibre.org/style.json';
    }
    return 'https://api.maptiler.com/maps/streets-v4/style.json?key=$apiKey';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MapViewModel>(
      builder: (context, viewModel, child) {
        return Scaffold(
          body: Stack(
            children: [
              // MapLibre map widget wrapped in Listener for right-click on web
              Listener(
                onPointerDown: (event) {
                  // Detect right-click (secondary button) on web for creating pins
                  if (kIsWeb && event.buttons == kSecondaryMouseButton) {
                    _handleRightClick(event.localPosition);
                  }
                },
                child: MapLibreMap(
                  styleString: _getMapStyleUrl(),
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(_initialLatitude, _initialLongitude),
                    zoom: _initialZoom,
                  ),
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoadedCallback,
                  onMapClick: _onMapClick,
                  onMapLongClick: _onMapLongClick,
                  onCameraIdle: _onCameraIdle,
                  myLocationEnabled:
                      !kIsWeb, // Disable on web (use custom marker instead)
                  myLocationTrackingMode: MyLocationTrackingMode.none,
                  compassEnabled: false,
                  // Required for cameraPosition to reflect user pan/zoom/rotate
                  // on Android/iOS. Without this, the native MapLibre SDKs do not
                  // emit camera-move events to Flutter and controller.cameraPosition
                  // stays frozen at initialCameraPosition. Web is unaffected.
                  trackCameraPosition: true,
                  rotateGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                ),
              ),

              // Title bar overlay (top-left)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Semantics(
                    label: 'CCW Map - Concealed Carry Weapon Map Application',
                    child: Text(
                      kShowDebugUI && _debugMode
                          ? 'CCW Map · DEBUG'
                          : 'CCW Map',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: kShowDebugUI && _debugMode
                            ? Colors.red
                            : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),

              // Debug toggle (top-right, left of exit button). Gated on
              // kShowDebugUI so it is tree-shaken out of production release
              // builds. See lib/core/build_flags.dart.
              if (kShowDebugUI)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 72,
                  child: Material(
                    color: _debugMode
                        ? Colors.red.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _debugMode = !_debugMode;
                          if (!_debugMode) {
                            _debugLastTap = null;
                            _debugLastDetection = null;
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _debugMode
                                  ? 'Debug mode ON — tap anywhere to see detection info'
                                  : 'Debug mode OFF',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Tooltip(
                        message: 'Toggle debug overlay',
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.bug_report_outlined,
                            color: _debugMode ? Colors.white : Colors.black87,
                            size: 24,
                            semanticLabel: 'Debug overlay toggle',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Top-right icon. Guests see sign-in; authenticated users see
              // a gear that opens SettingsScreen (Sign Out lives there).
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: Consumer<AuthViewModel>(
                  builder: (context, auth, _) {
                    if (auth.isAuthenticated) {
                      return _buildTopBarButton(
                        icon: Icons.settings,
                        tooltip: 'Settings',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      );
                    }
                    return _buildTopBarButton(
                      icon: Icons.login,
                      tooltip: 'Sign in',
                      onTap: () => _promptSignIn(
                        title: 'Sign in',
                        body:
                            'Sign in to add pins and contribute to the community map.',
                      ),
                    );
                  },
                ),
              ),

              // Re-center FAB (bottom-right, positioned above MapLibre controls)
              Positioned(
                bottom: 96, // Moved up to avoid MapLibre's location button
                right: 16,
                child: FloatingActionButton(
                  // Stacked with CompassButton (also a FAB); opt out of Hero
                  // to avoid "multiple heroes share the same tag" on route
                  // push/pop.
                  heroTag: null,
                  onPressed: _onRecenterTapped,
                  backgroundColor: const Color(
                    0xFFE8DEF8,
                  ), // Light purple/lavender
                  elevation: 4,
                  tooltip: 'Re-center map to your location',
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.black87,
                    semanticLabel: 'Re-center map',
                  ),
                ),
              ),

              // Compass reset FAB (stacked above re-center FAB).
              Positioned(
                bottom: 160,
                right: 16,
                child: CompassButton(
                  listenable: _mapController,
                  bearingGetter: () =>
                      _mapController?.cameraPosition?.bearing ?? 0.0,
                  onReset: _onCompassTapped,
                ),
              ),

              // Debug info panel. Gated on kShowDebugUI so it is tree-shaken
              // out of production release builds. See lib/core/build_flags.dart.
              if (kShowDebugUI && _debugMode)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _debugLastTap == null
                              ? 'Tap somewhere to test POI detection'
                              : 'tap: ${_debugLastTap!}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (_debugLastDetection != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'det: ${_debugLastDetection!}',
                            style: const TextStyle(
                              color: Colors.lightGreenAccent,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                        if (_debugLocationPipeline != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'loc: ${_debugLocationPipeline!}',
                            style: const TextStyle(
                              color: Colors.yellowAccent,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Sync indicator (top-center, below title bar)
              if (viewModel.isSyncing)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Syncing...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Initial loading overlay
              if (viewModel.isLoading)
                Container(
                  color: Colors.white.withValues(alpha: 0.9),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Loading map...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onPinsChanged);
    _viewModel?.viewportClusters.removeListener(_onClustersChanged);
    _mapController?.onFeatureTapped.remove(_onFeatureTapped);
    _mapController?.dispose();
    super.dispose();
  }
}
