class Location {
  final double latitude;
  final double longitude;

  Location._({
    required this.latitude,
    required this.longitude,
  }) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError('Latitude must be between -90 and 90, got: $latitude');
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError('Longitude must be between -180 and 180, got: $longitude');
    }
  }

  factory Location.fromLatLng(double latitude, double longitude) {
    return Location._(latitude: latitude, longitude: longitude);
  }

  factory Location.fromLngLat(double longitude, double latitude) {
    return Location._(latitude: latitude, longitude: longitude);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Location &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;

  @override
  String toString() => 'Location(lat: $latitude, lng: $longitude)';
}
