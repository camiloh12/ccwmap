import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ccwmap/data/services/location_service.dart';

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

  // Initial camera position - center of US
  static const double _initialLatitude = 39.8283;
  static const double _initialLongitude = -98.5795;
  static const double _initialZoom = 4.0;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
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
  }

  /// Enable the location indicator on the map
  void _enableLocationComponent() {
    if (_mapController != null && _currentLocation != null) {
      // Note: myLocationEnabled is set to true in MapLibreMap widget
      debugPrint('Location component enabled');
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

  void _onExitTapped() {
    debugPrint('Exit button tapped');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Sign out functionality will be added in Iteration 5'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // MapLibre map widget
          MapLibreMap(
            styleString: 'https://demotiles.maplibre.org/style.json',
            initialCameraPosition: const CameraPosition(
              target: LatLng(_initialLatitude, _initialLongitude),
              zoom: _initialZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoadedCallback,
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
    _mapController?.dispose();
    super.dispose();
  }
}
