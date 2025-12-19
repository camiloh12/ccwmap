import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Service for handling device location operations
class LocationService {
  /// Check current location permission status
  Future<LocationPermission> checkPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      debugPrint('Location permission status: $permission');
      return permission;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      rethrow;
    }
  }

  /// Request location permission from the user
  Future<LocationPermission> requestPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      debugPrint('Location permission requested, result: $permission');
      return permission;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      rethrow;
    }
  }

  /// Check if location services are enabled on the device
  Future<bool> isLocationServiceEnabled() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('Location services enabled: $enabled');
      return enabled;
    } catch (e) {
      debugPrint('Error checking location service status: $e');
      rethrow;
    }
  }

  /// Get the current device location
  ///
  /// Throws [LocationServiceDisabledException] if location services are disabled
  /// Throws [PermissionDeniedException] if permission is denied
  Future<Position> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      // Check permission
      LocationPermission permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }

      // Get location
      debugPrint('Fetching current location...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      );

      debugPrint('Current location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('Error getting current location: $e');
      rethrow;
    }
  }

  /// Get a stream of location updates
  ///
  /// Returns a stream that emits position updates as the device moves
  Stream<Position> getLocationStream() {
    try {
      debugPrint('Starting location stream...');
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
          timeLimit: Duration(minutes: 5), // Timeout after 5 minutes
        ),
      );
    } catch (e) {
      debugPrint('Error starting location stream: $e');
      rethrow;
    }
  }

  /// Open the device's location settings
  Future<bool> openLocationSettings() async {
    try {
      debugPrint('Opening location settings...');
      return await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('Error opening location settings: $e');
      return false;
    }
  }

  /// Open the app's settings page
  Future<bool> openAppSettings() async {
    try {
      debugPrint('Opening app settings...');
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('Error opening app settings: $e');
      return false;
    }
  }
}
