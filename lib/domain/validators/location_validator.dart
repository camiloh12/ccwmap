/// Validator for geographic locations
class LocationValidator {
  // Continental US boundaries (excludes Alaska, Hawaii, territories)
  static const double minLatitude = 24.396308;
  static const double maxLatitude = 49.384358;
  static const double minLongitude = -125.0;
  static const double maxLongitude = -66.93457;

  /// Check if coordinates are within continental US bounds
  ///
  /// Returns true if the location is within the continental United States,
  /// false otherwise. This excludes Alaska, Hawaii, and US territories.
  ///
  /// Boundaries:
  /// - Latitude: 24.396308 to 49.384358
  /// - Longitude: -125.0 to -66.93457
  static bool isWithinUSBounds(double latitude, double longitude) {
    return latitude >= minLatitude &&
           latitude <= maxLatitude &&
           longitude >= minLongitude &&
           longitude <= maxLongitude;
  }
}
