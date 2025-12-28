import 'dart:math' show Point;
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

  // Initial camera position - center of US
  static const double _initialLatitude = 39.8283;
  static const double _initialLongitude = -98.5795;
  static const double _initialZoom = 4.0;

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

    // Enable location component if we have a location
    if (_currentLocation != null) {
      _enableLocationComponent();
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

  /// Update pins layer on the map
  Future<void> _updatePinsLayer() async {
    if (_mapController == null) {
      debugPrint('MapScreen: Cannot update pins layer - map controller is null');
      return;
    }

    try {
      debugPrint('MapScreen: Updating pins layer with ${_pins.length} pins');

      // Build GeoJSON from pins
      final geojson = _buildPinsGeoJson();
      debugPrint('MapScreen: Built GeoJSON with ${geojson['features'].length} features');

      // Remove existing source/layer if present
      try {
        await _mapController!.removeLayer('pins-layer');
        await _mapController!.removeSource('pins-source');
        debugPrint('MapScreen: Removed existing pins layer/source');
      } catch (e) {
        // Layer/source doesn't exist yet, that's ok
        debugPrint('MapScreen: No existing pins layer to remove (expected on first load)');
      }

      // Add GeoJSON source
      await _mapController!.addGeoJsonSource('pins-source', geojson);
      debugPrint('MapScreen: Added GeoJSON source');

      // Add circle layer for pins
      await _mapController!.addCircleLayer(
        'pins-source',
        'pins-layer',
        const CircleLayerProperties(
          circleRadius: 8.0,
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
        ),
      );

      debugPrint('MapScreen: Pins layer updated successfully with ${_pins.length} pins');
    } catch (e) {
      debugPrint('MapScreen: Error updating pins layer: $e');
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

  /// Enable the location indicator on the map
  void _enableLocationComponent() {
    if (_mapController != null && _currentLocation != null) {
      // Note: myLocationEnabled is set to true in MapLibreMap widget
      debugPrint('Location component enabled');
    }
  }

  /// Handle map click - detect if user tapped on a pin
  Future<void> _onMapClick(Point<double> point, LatLng coordinates) async {
    if (_mapController == null) return;

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
      // Query features at clicked point
      final features = await _mapController!.queryRenderedFeatures(
        point,
        ['pins-layer'],
        null,
      );

      if (features.isNotEmpty) {
        // User clicked on a pin - show edit dialog
        final feature = features.first;
        final properties = feature['properties'] as Map<String, dynamic>?;

        if (properties != null && mounted) {
          final pinName = properties['name'] as String? ?? 'Unknown Location';
          final statusCode = properties['status'] as int?;
          final restrictionTagStr = properties['restriction_tag'] as String?;
          final hasSecurityScreening = properties['has_security_screening'] as bool? ?? false;
          final hasPostedSignage = properties['has_posted_signage'] as bool? ?? false;

          // Parse status and restriction tag
          final status = statusCode != null
              ? PinStatus.fromColorCode(statusCode)
              : PinStatus.ALLOWED;
          final restrictionTag = restrictionTagStr != null
              ? RestrictionTag.fromString(restrictionTagStr)
              : null;

          debugPrint('Opening edit dialog for pin: $pinName');

          _showPinDialog(
            isEditMode: true,
            poiName: pinName,
            initialStatus: status,
            initialRestrictionTag: restrictionTag,
            initialHasSecurityScreening: hasSecurityScreening,
            initialHasPostedSignage: hasPostedSignage,
          );
        }
      } else {
        // User clicked on empty map area - show create dialog
        if (mounted) {
          debugPrint('Opening create dialog at: ${coordinates.latitude}, ${coordinates.longitude}');

          _showPinDialog(
            isEditMode: false,
            poiName: 'Location at ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}',
            initialStatus: null,
            initialRestrictionTag: null,
            initialHasSecurityScreening: false,
            initialHasPostedSignage: false,
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
        onConfirm: (result) {
          debugPrint('Pin dialog confirmed:');
          debugPrint('  Status: ${result.status.displayName}');
          debugPrint('  Restriction: ${result.restrictionTag?.displayName ?? 'None'}');
          debugPrint('  Security Screening: ${result.hasSecurityScreening}');
          debugPrint('  Posted Signage: ${result.hasPostedSignage}');

          Navigator.of(dialogContext, rootNavigator: true).pop();

          // TODO: In Iteration 7, actually save the pin
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isEditMode
                      ? 'Pin updated (UI only - not saved yet)'
                      : 'Pin created (UI only - not saved yet)',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        onDelete: isEditMode ? () {
          debugPrint('Pin delete requested');
          Navigator.of(dialogContext, rootNavigator: true).pop();

          // TODO: In Iteration 7, actually delete the pin
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pin deleted (UI only - not saved yet)'),
                duration: Duration(seconds: 2),
              ),
            );
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
    _mapController?.dispose();
    super.dispose();
  }
}
