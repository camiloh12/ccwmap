import 'dart:async';
import 'dart:math' show Point;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/data/services/location_service.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/poi.dart';
import 'package:ccwmap/domain/repositories/poi_repository.dart';
import 'package:ccwmap/data/repositories/poi_repository_impl.dart';
import 'package:ccwmap/data/datasources/overpass_api_client.dart';
import 'package:ccwmap/data/datasources/poi_cache.dart';
import 'package:uuid/uuid.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _mapController;
  final LocationService _locationService = LocationService();
  Position? _currentLocation;
  bool _isLoadingLocation = false;

  // ViewModel and pins
  MapViewModel? _viewModel;
  List<Pin> _pins = [];
  bool _isDialogOpen = false;
  DateTime? _lastDialogCloseTime;

  // Track added symbols for removal
  final List<Symbol> _addedSymbols = [];

  // POI Integration
  late final PoiRepository _poiRepository;
  List<Poi> _pois = [];
  Timer? _cameraDebounceTimer;
  bool _isLoadingPois = false;
  static const Duration _cameraDebounceDelay = Duration(milliseconds: 500);
  static const double _minZoomForPois = 12.0; // Only fetch POIs at zoom level 12+

  // Initial camera position - center of US
  static const double _initialLatitude = 39.8283;
  static const double _initialLongitude = -98.5795;
  static const double _initialZoom = 4.0;

  @override
  void initState() {
    super.initState();

    // Initialize POI repository
    _poiRepository = PoiRepositoryImpl(
      apiClient: OverpassApiClient(),
      cache: PoiCache(),
    );

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
        debugPrint('Location obtained: ${position.latitude}, ${position.longitude}');
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

    // Enable location component if we have a location
    if (_currentLocation != null) {
      _enableLocationComponent();
    }
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
  void _onFeatureTapped(Point<double> point, LatLng coordinates, String id, String layerId, dynamic annotation) {
    debugPrint('=== FEATURE TAPPED ===');
    debugPrint('Feature ID: $id');
    debugPrint('Layer ID: $layerId');
    debugPrint('Point: ${point.x}, ${point.y}');
    debugPrint('Coordinates: ${coordinates.latitude}, ${coordinates.longitude}');

    // Only handle taps on our pins layer
    if (layerId != 'pins-layer') {
      debugPrint('Not our layer, ignoring');
      return;
    }

    // Prevent opening multiple dialogs
    if (_isDialogOpen) {
      debugPrint('Dialog already open, ignoring feature tap');
      return;
    }

    // Find the pin by ID
    Pin? pin;
    try {
      pin = _pins.firstWhere((p) => p.id == id);
    } catch (e) {
      debugPrint('Pin not found by ID, using geographic fallback');
      // Fallback: find nearest pin by coordinates
      for (final p in _pins) {
        final distance = _calculateGeographicDistance(
          coordinates.latitude,
          coordinates.longitude,
          p.location.latitude,
          p.location.longitude,
        );
        if (distance < 100) { // Within 100 meters
          pin = p;
          break;
        }
      }
    }

    if (pin != null) {
      debugPrint('Found pin: ${pin.name}');
      _showPinDialog(
        isEditMode: true,
        poiName: pin.name,
        initialStatus: pin.status,
        initialRestrictionTag: pin.restrictionTag,
        initialHasSecurityScreening: pin.hasSecurityScreening,
        initialHasPostedSignage: pin.hasPostedSignage,
        pinId: pin.id,
      );
    } else {
      debugPrint('Could not find matching pin');
    }
  }

  void _onStyleLoadedCallback() {
    debugPrint('Map style loaded');

    // Enable location component after style loads
    if (_currentLocation != null) {
      _enableLocationComponent();
    }

    // Add pins layer to map
    _updatePinsLayer();
  }

  /// Update pins on the map using circle layers
  /// Note: Circles will block clicks on web, but we use geographic distance
  /// detection to find clicked pins, so this works fine
  Future<void> _updatePinsLayer() async {
    if (_mapController == null) {
      debugPrint('MapScreen: Cannot update pins - map controller is null');
      return;
    }

    try {
      debugPrint('MapScreen: Updating pins layer with ${_pins.length} pins');

      // Build GeoJSON from pins
      final geojson = _buildPinsGeoJson();

      // Remove existing source/layer if present
      try {
        await _mapController!.removeLayer('pins-layer');
        await _mapController!.removeSource('pins-source');
      } catch (e) {
        // Layer/source doesn't exist yet, that's ok
      }

      // Add GeoJSON source
      await _mapController!.addGeoJsonSource('pins-source', geojson);

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

      debugPrint('MapScreen: Pins layer updated successfully');
    } catch (e) {
      debugPrint('MapScreen: Error updating pins layer: $e');
    }
  }

  /// Get hex color string for pin status
  String _getColorForStatus(PinStatus status) {
    switch (status) {
      case PinStatus.ALLOWED:
        return '#4CAF50'; // Green
      case PinStatus.UNCERTAIN:
        return '#FFC107'; // Yellow
      case PinStatus.NO_GUN:
        return '#F44336'; // Red
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

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  /// Called when camera movement starts - debounce POI fetching
  void _onCameraMove(CameraPosition? position) {
    // Cancel existing timer
    _cameraDebounceTimer?.cancel();
  }

  /// Called when camera movement ends - fetch POIs after debounce delay
  void _onCameraIdle() {
    // Cancel existing timer
    _cameraDebounceTimer?.cancel();

    // Start new timer for debounced POI fetching
    _cameraDebounceTimer = Timer(_cameraDebounceDelay, () {
      _fetchPOIsForViewport();
    });
  }

  /// Fetch POIs for the current viewport
  Future<void> _fetchPOIsForViewport() async {
    if (_mapController == null || _isLoadingPois) {
      return;
    }

    // Check zoom level - only fetch at reasonable zoom levels
    final cameraPosition = _mapController!.cameraPosition;
    final zoomLevel = cameraPosition?.zoom ?? 0.0;

    if (zoomLevel < _minZoomForPois) {
      debugPrint('Zoom level $zoomLevel too low for POI fetching (min: $_minZoomForPois)');
      // Clear POIs at low zoom levels
      if (_pois.isNotEmpty) {
        setState(() {
          _pois = [];
        });
        _updatePoisLayer();
      }
      return;
    }

    try {
      setState(() {
        _isLoadingPois = true;
      });

      // Get visible bounds
      final bounds = await _mapController!.getVisibleRegion();
      final overpassBounds = OverpassBounds(
        south: math.min(bounds.southwest.latitude, bounds.northeast.latitude),
        west: math.min(bounds.southwest.longitude, bounds.northeast.longitude),
        north: math.max(bounds.southwest.latitude, bounds.northeast.latitude),
        east: math.max(bounds.southwest.longitude, bounds.northeast.longitude),
      );

      debugPrint('Fetching POIs for bounds: $overpassBounds');

      // Fetch POIs from repository (with caching)
      final pois = await _poiRepository.getPOIs(overpassBounds);

      if (mounted) {
        setState(() {
          _pois = pois;
          _isLoadingPois = false;
        });

        // Update POI layer on map
        _updatePoisLayer();

        debugPrint('Loaded ${pois.length} POIs for current viewport');
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching POIs: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isLoadingPois = false;
        });
      }
    }
  }

  /// Update POI labels on the map using symbol layer
  Future<void> _updatePoisLayer() async {
    if (_mapController == null) {
      debugPrint('MapScreen: Cannot update POIs - map controller is null');
      return;
    }

    try {
      debugPrint('MapScreen: Updating POIs layer with ${_pois.length} POIs');

      // Build GeoJSON from POIs
      final geojson = _buildPoisGeoJson();

      // Remove existing source/layer if present
      try {
        await _mapController!.removeLayer('pois-layer');
        await _mapController!.removeSource('pois-source');
      } catch (e) {
        // Layer/source doesn't exist yet, that's ok
      }

      // Only add layer if we have POIs
      if (_pois.isNotEmpty) {
        // Add GeoJSON source
        await _mapController!.addGeoJsonSource('pois-source', geojson);

        // Add symbol layer for POI labels
        await _mapController!.addSymbolLayer(
          'pois-source',
          'pois-layer',
          SymbolLayerProperties(
            textField: [
              'get',
              'name'
            ],
            textSize: 12.0,
            textColor: '#333333',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 2.0,
            textOffset: [
              Expressions.literal,
              [0, 1.5]
            ],
            textAnchor: 'top',
            textAllowOverlap: false, // Prevent label clutter
            textIgnorePlacement: false,
          ),
        );

        debugPrint('MapScreen: POIs layer updated successfully');
      } else {
        debugPrint('MapScreen: No POIs to display');
      }
    } catch (e) {
      debugPrint('MapScreen: Error updating POIs layer: $e');
    }
  }

  /// Build GeoJSON FeatureCollection from POIs
  Map<String, dynamic> _buildPoisGeoJson() {
    final features = _pois.map((poi) {
      return {
        'type': 'Feature',
        'id': poi.id,
        'geometry': {
          'type': 'Point',
          'coordinates': [poi.longitude, poi.latitude],
        },
        'properties': {
          'id': poi.id,
          'name': poi.name,
          'type': poi.type,
        },
      };
    }).toList();

    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  /// Enable the location indicator on the map
  void _enableLocationComponent() {
    if (_mapController != null && _currentLocation != null) {
      // Note: myLocationEnabled is set to true in MapLibreMap widget
      debugPrint('Location component enabled');
    }
  }

  /// Handle map click - detect if user tapped on a pin
  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    debugPrint('=== MAP CLICK DEBUG ===');
    debugPrint('Click at: ${coordinates.latitude}, ${coordinates.longitude}');
    debugPrint('Screen point: ${point.x}, ${point.y}');

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
        debugPrint('Cooldown period active (${timeSinceClose.inMilliseconds}ms), ignoring map click');
        return;
      }
    }

    try {
      debugPrint('Querying features at point...');
      debugPrint('Number of pins in _pins list: ${_pins.length}');
      debugPrint('Number of POIs in _pois list: ${_pois.length}');
      debugPrint('Click coordinates: ${coordinates.latitude}, ${coordinates.longitude}');

      // PRIORITY 1: Check if user tapped on a POI label
      // POI tap should create a new pin with POI name pre-filled
      try {
        final poiFeatures = await _mapController!.queryRenderedFeatures(
          point,
          ['pois-layer'],
          null,
        );

        if (poiFeatures.isNotEmpty) {
          final poiFeature = poiFeatures.first;
          debugPrint('POI tapped: ${poiFeature}');

          // Extract POI properties
          final poiId = poiFeature['id']?.toString();
          final poiName = poiFeature['properties']?['name']?.toString() ?? 'Unknown POI';

          debugPrint('Opening create dialog for POI: $poiName');

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

          // Show create dialog with POI name
          if (mounted) {
            _showPinDialog(
              isEditMode: false,
              poiName: poiName,
              initialStatus: null,
              initialRestrictionTag: null,
              initialHasSecurityScreening: false,
              initialHasPostedSignage: false,
              coordinates: coordinates,
            );
          }
          return;
        }
      } catch (e) {
        debugPrint('Error querying POI features: $e');
        // Continue to pin detection
      }

      // Get current zoom level to calculate appropriate threshold
      final cameraPosition = _mapController!.cameraPosition;
      final zoomLevel = cameraPosition?.zoom ?? 10.0;

      // Calculate threshold based on zoom level
      // At zoom 15 (city level): ~30 meters
      // At zoom 10 (state level): ~600 meters
      // At zoom 18 (street level): ~30 meters (capped minimum)
      // Formula: threshold decreases as zoom increases, with 30m minimum
      final clickThresholdMeters = math.max(30.0, 10000.0 / math.pow(2, zoomLevel));

      debugPrint('Zoom level: ${zoomLevel.toStringAsFixed(1)}, Threshold: ${clickThresholdMeters.toStringAsFixed(0)}m');

      // PRIORITY 2: Find pin by checking geographic distance from click point
      Pin? clickedPin;
      double minDistance = double.infinity;

      for (final pin in _pins) {
        // Calculate geographic distance in meters
        final distanceMeters = _calculateGeographicDistance(
          coordinates.latitude,
          coordinates.longitude,
          pin.location.latitude,
          pin.location.longitude,
        );

        debugPrint('Pin ${pin.name}: ${distanceMeters.toStringAsFixed(0)}m away');

        if (distanceMeters < clickThresholdMeters && distanceMeters < minDistance) {
          minDistance = distanceMeters;
          clickedPin = pin;
        }
      }

      if (clickedPin != null) {
        debugPrint('Found clicked pin: ${clickedPin.name} (${minDistance.toStringAsFixed(0)}m away)');
        debugPrint('Opening edit dialog for manually detected pin: ${clickedPin.name}');
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
          final hasSecurityScreening = properties['hasSecurityScreening'] as bool? ?? false;
          final hasPostedSignage = properties['hasPostedSignage'] as bool? ?? false;

          // Parse status and restriction tag
          final status = statusCode != null
              ? PinStatus.fromColorCode(statusCode)
              : PinStatus.ALLOWED;
          final restrictionTag = restrictionTagStr != null
              ? RestrictionTag.fromString(restrictionTagStr)
              : null;

          debugPrint('Opening edit dialog for pin: $pinName (ID: $pinId)');

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
        // User clicked on empty map area - show create dialog
        debugPrint('No features found, showing create dialog');
        if (mounted) {
          debugPrint('Opening create dialog at: ${coordinates.latitude}, ${coordinates.longitude}');

          _showPinDialog(
            isEditMode: false,
            poiName: 'Location at ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}',
            initialStatus: null,
            initialRestrictionTag: null,
            initialHasSecurityScreening: false,
            initialHasPostedSignage: false,
            coordinates: coordinates,
          );
        }
      }
    } catch (e) {
      debugPrint('Error handling map click: $e');
    }
  }

  Future<void> _showPinDialog({
    required bool isEditMode,
    required String poiName,
    required PinStatus? initialStatus,
    required RestrictionTag? initialRestrictionTag,
    required bool initialHasSecurityScreening,
    required bool initialHasPostedSignage,
    String? pinId,  // For edit mode
    LatLng? coordinates,  // For create mode
  }) async {
    // Set flag to prevent multiple dialogs
    _isDialogOpen = true;

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
        onConfirm: (result) async {
          debugPrint('Pin dialog confirmed:');
          debugPrint('  Status: ${result.status.displayName}');
          debugPrint('  Restriction: ${result.restrictionTag?.displayName ?? 'None'}');
          debugPrint('  Security Screening: ${result.hasSecurityScreening}');
          debugPrint('  Posted Signage: ${result.hasPostedSignage}');

          Navigator.of(dialogContext, rootNavigator: true).pop();

          try {
            if (isEditMode && pinId != null) {
              // Edit existing pin
              final existingPin = await _viewModel?.getPinById(pinId);
              if (existingPin != null) {
                final updatedPin = existingPin.copyWith(
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
              final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
              final currentUser = authViewModel.currentUser;

              final newPin = Pin(
                id: const Uuid().v4(),
                name: poiName,
                location: Location.fromLatLng(
                  coordinates.latitude,
                  coordinates.longitude,
                ),
                status: result.status,
                restrictionTag: result.restrictionTag,
                hasSecurityScreening: result.hasSecurityScreening,
                hasPostedSignage: result.hasPostedSignage,
                metadata: PinMetadata(
                  createdBy: currentUser?.id ?? 'anonymous',
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${e.toString()}'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        onDelete: isEditMode && pinId != null ? () async {
          debugPrint('Pin delete requested for ID: $pinId');

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
                  onPressed: () => Navigator.of(confirmContext).pop(false),
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
            Navigator.of(dialogContext, rootNavigator: true).pop();

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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error deleting pin: ${e.toString()}'),
                    duration: const Duration(seconds: 3),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
        } : null,
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

  /// Calculate geographic distance between two points using Haversine formula
  /// Returns distance in meters
  double _calculateGeographicDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0; // Earth's radius in meters

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  /// Check if coordinates are within continental US bounds
  bool _isWithinUSBounds(double latitude, double longitude) {
    const double minLat = 24.396308;  // Southern border
    const double maxLat = 49.384358;  // Northern border
    const double minLng = -125.0;     // Western border
    const double maxLng = -66.93457;  // Eastern border

    return latitude >= minLat &&
           latitude <= maxLat &&
           longitude >= minLng &&
           longitude <= maxLng;
  }

  /// Get status name from color code
  String _getStatusName(int? statusCode) {
    if (statusCode == null) return 'Unknown';
    switch (statusCode) {
      case 0:
        return 'ALLOWED (Green)';
      case 1:
        return 'UNCERTAIN (Yellow)';
      case 2:
        return 'NO_GUN (Red)';
      default:
        return 'Unknown';
    }
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

  Future<void> _onExitTapped() async {
    debugPrint('Exit button tapped');

    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true && mounted) {
      final authViewModel = context.read<AuthViewModel>();
      await authViewModel.signOut();
      // AuthGate will automatically navigate to LoginScreen
    }
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
    return Scaffold(
      body: Stack(
        children: [
          // MapLibre map widget
          MapLibreMap(
            styleString: _getMapStyleUrl(),
            initialCameraPosition: const CameraPosition(
              target: LatLng(_initialLatitude, _initialLongitude),
              zoom: _initialZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoadedCallback,
            onMapClick: _onMapClick,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true, // Show location dot
            myLocationTrackingMode: MyLocationTrackingMode.none, // But no auto-tracking
            compassEnabled: false,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),

          // Title bar overlay (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: const Text(
                'CCW Map',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),

          // Exit/sign out icon (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: Material(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              elevation: 2,
              child: InkWell(
                onTap: _onExitTapped,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.exit_to_app,
                    color: Colors.black87,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // Re-center FAB (bottom-right, positioned above MapLibre controls)
          Positioned(
            bottom: 96, // Moved up to avoid MapLibre's location button
            right: 16,
            child: FloatingActionButton(
              onPressed: _onRecenterTapped,
              backgroundColor: const Color(0xFFE8DEF8), // Light purple/lavender
              elevation: 4,
              child: const Icon(
                Icons.my_location,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onPinsChanged);
    _mapController?.onFeatureTapped.remove(_onFeatureTapped);
    _mapController?.dispose();
    _cameraDebounceTimer?.cancel();
    super.dispose();
  }
}
