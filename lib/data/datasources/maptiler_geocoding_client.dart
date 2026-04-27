import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Result from a MapTiler reverse geocoding lookup.
class GeocodingResult {
  final String name;
  final double lat;
  final double lng;
  final List<String> placeType;

  const GeocodingResult({
    required this.name,
    required this.lat,
    required this.lng,
    required this.placeType,
  });

  bool get isPoi => placeType.contains('poi');

  @override
  String toString() =>
      'GeocodingResult(name: $name, lat: $lat, lng: $lng, placeType: $placeType)';
}

/// Thin HTTP client for MapTiler's reverse geocoding endpoint.
///
/// Used as an iOS fallback when `queryRenderedFeatures` fails to return
/// base map POI labels. See docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md.
class MaptilerGeocodingClient {
  static const String _baseUrl = 'https://api.maptiler.com/geocoding';
  static const Duration _timeout = Duration(seconds: 5);

  /// Reverse-geocode a coordinate and return the closest POI, or null.
  ///
  /// Returns null on network error, timeout, missing API key, or when the
  /// result is not a POI (e.g. just an address or region).
  static Future<GeocodingResult?> reverseGeocode({
    required double lat,
    required double lng,
    required String apiKey,
  }) async {
    if (apiKey.isEmpty) return null;

    final uri = Uri.parse(
      '$_baseUrl/$lng,$lat.json?key=$apiKey&types=poi&limit=1',
    );

    try {
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          'MaptilerGeocodingClient: HTTP ${response.statusCode} for $lng,$lat',
        );
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final features = body['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      final feature = features.first as Map<String, dynamic>;
      final name = (feature['text'] ?? feature['place_name'])?.toString();
      if (name == null || name.isEmpty) return null;

      final placeType = (feature['place_type'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      final center = feature['center'] as List<dynamic>?;
      double poiLng = lng;
      double poiLat = lat;
      if (center != null && center.length >= 2) {
        poiLng = (center[0] as num).toDouble();
        poiLat = (center[1] as num).toDouble();
      }

      return GeocodingResult(
        name: name,
        lat: poiLat,
        lng: poiLng,
        placeType: placeType,
      );
    } on TimeoutException {
      debugPrint('MaptilerGeocodingClient: timeout for $lng,$lat');
      return null;
    } catch (e) {
      debugPrint('MaptilerGeocodingClient: error for $lng,$lat: $e');
      return null;
    }
  }
}
