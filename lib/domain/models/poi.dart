/// Represents a Point of Interest from OpenStreetMap
class Poi {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String type;
  final Map<String, String>? tags;

  const Poi({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.tags,
  });

  /// Creates a Poi from Overpass API JSON response
  factory Poi.fromOverpassJson(Map<String, dynamic> json) {
    // Extract coordinates - handle both nodes and ways
    final double lat;
    final double lon;

    if (json['lat'] != null && json['lon'] != null) {
      // Node with direct coordinates
      lat = (json['lat'] as num).toDouble();
      lon = (json['lon'] as num).toDouble();
    } else if (json['center'] != null) {
      // Way with center coordinates
      lat = (json['center']['lat'] as num).toDouble();
      lon = (json['center']['lon'] as num).toDouble();
    } else {
      throw ArgumentError('POI must have coordinates');
    }

    // Extract tags
    final tags = json['tags'] as Map<String, dynamic>?;
    final tagMap = tags?.map((key, value) => MapEntry(key, value.toString()));

    // Determine type (amenity, tourism, leisure, etc.)
    String? type;
    if (tags != null) {
      type = tags['amenity'] as String? ??
          tags['tourism'] as String? ??
          tags['leisure'] as String? ??
          tags['shop'] as String? ??
          tags['building'] as String?;
    }
    final poiType = type ?? 'unknown';

    // Determine name - fallback to type or "Unknown"
    String? name;
    if (tags != null) {
      name = tags['name'] as String?;
    }
    final poiName = name ?? _formatTypeName(poiType);

    return Poi(
      id: json['id'].toString(),
      name: poiName,
      latitude: lat,
      longitude: lon,
      type: poiType,
      tags: tagMap,
    );
  }

  /// Formats type name for display when no name is available
  static String _formatTypeName(String type) {
    if (type == 'unknown') return 'Unknown';

    // Convert snake_case or kebab-case to Title Case
    return type
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Poi && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Poi{id: $id, name: $name, type: $type, lat: $latitude, lng: $longitude}';
  }
}
