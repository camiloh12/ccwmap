import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../domain/models/poi.dart';

/// Client for fetching POI data from OpenStreetMap via Overpass API
class OverpassApiClient {
  static const String _baseUrl = 'https://overpass-api.de/api/interpreter';
  static const Duration _timeout = Duration(seconds: 25);

  final http.Client _httpClient;

  OverpassApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Fetches POIs within the given geographic bounds
  ///
  /// Returns a list of POIs or throws an exception on error.
  /// Rate limit: 2 requests/second (enforced by Overpass API)
  Future<List<Poi>> fetchPOIs(OverpassBounds bounds) async {
    final query = _buildOverpassQuery(bounds);

    try {
      final response = await _httpClient
          .post(
            Uri.parse(_baseUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'data': query},
          )
          .timeout(_timeout);

      if (response.statusCode == 429) {
        throw OverpassRateLimitException(
            'Rate limit exceeded. Please wait before making more requests.');
      }

      if (response.statusCode != 200) {
        throw OverpassApiException(
            'Failed to fetch POIs: ${response.statusCode} ${response.reasonPhrase}');
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final elements = jsonData['elements'] as List<dynamic>?;

      if (elements == null) {
        throw OverpassApiException('Invalid response: missing elements array');
      }

      return elements
          .map((e) => e as Map<String, dynamic>)
          .where((e) => _isValidPoi(e))
          .map((e) => Poi.fromOverpassJson(e))
          .toList();
    } on TimeoutException {
      throw OverpassApiException('Request timed out after ${_timeout.inSeconds} seconds');
    } on http.ClientException catch (e) {
      throw OverpassApiException('Network error: ${e.message}');
    } on FormatException catch (e) {
      throw OverpassApiException('Failed to parse response: ${e.message}');
    }
  }

  /// Builds the Overpass QL query for the given bounds
  String _buildOverpassQuery(OverpassBounds bounds) {
    final south = bounds.south;
    final west = bounds.west;
    final north = bounds.north;
    final east = bounds.east;

    return '''
[out:json][timeout:25];
(
  node["amenity"]($south,$west,$north,$east);
  node["tourism"]($south,$west,$north,$east);
  node["leisure"]($south,$west,$north,$east);
  way["amenity"]($south,$west,$north,$east);
  way["tourism"]($south,$west,$north,$east);
);
out center;
''';
  }

  /// Validates that a POI element has the required data
  bool _isValidPoi(Map<String, dynamic> element) {
    // Must have either direct coordinates or center coordinates
    final hasDirectCoords = element['lat'] != null && element['lon'] != null;
    final hasCenterCoords = element['center'] != null &&
        element['center']['lat'] != null &&
        element['center']['lon'] != null;

    if (!hasDirectCoords && !hasCenterCoords) {
      return false;
    }

    // Must have tags
    if (element['tags'] == null) {
      return false;
    }

    return true;
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Represents geographic bounds for a map viewport
class OverpassBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const OverpassBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  @override
  String toString() {
    return 'OverpassBounds{south: $south, west: $west, north: $north, east: $east}';
  }

  /// Rounds coordinates to specified decimal places for cache key generation
  OverpassBounds rounded([int decimals = 2]) {
    final factor = pow(10, decimals).toDouble();
    return OverpassBounds(
      south: (south * factor).round() / factor,
      west: (west * factor).round() / factor,
      north: (north * factor).round() / factor,
      east: (east * factor).round() / factor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverpassBounds &&
          runtimeType == other.runtimeType &&
          south == other.south &&
          west == other.west &&
          north == other.north &&
          east == other.east;

  @override
  int get hashCode => Object.hash(south, west, north, east);
}

/// Exception thrown when Overpass API encounters an error
class OverpassApiException implements Exception {
  final String message;

  OverpassApiException(this.message);

  @override
  String toString() => 'OverpassApiException: $message';
}

/// Exception thrown when rate limit is exceeded
class OverpassRateLimitException extends OverpassApiException {
  OverpassRateLimitException(super.message);
}
