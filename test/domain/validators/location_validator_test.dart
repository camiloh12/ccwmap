import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/validators/location_validator.dart';

void main() {
  group('LocationValidator', () {
    group('isWithinUSBounds', () {
      test('returns true for location in center of US', () {
        // Kansas City, MO (center of continental US)
        expect(LocationValidator.isWithinUSBounds(39.0997, -94.5786), isTrue);
      });

      test('returns true for location in California', () {
        // Los Angeles
        expect(LocationValidator.isWithinUSBounds(34.0522, -118.2437), isTrue);
      });

      test('returns true for location in New York', () {
        // New York City
        expect(LocationValidator.isWithinUSBounds(40.7128, -74.0060), isTrue);
      });

      test('returns true for location in Texas', () {
        // Dallas
        expect(LocationValidator.isWithinUSBounds(32.7767, -96.7970), isTrue);
      });

      test('returns true for location in Florida', () {
        // Miami
        expect(LocationValidator.isWithinUSBounds(25.7617, -80.1918), isTrue);
      });

      test('returns true for exact minimum latitude', () {
        expect(LocationValidator.isWithinUSBounds(24.396308, -95.0), isTrue);
      });

      test('returns true for exact maximum latitude', () {
        expect(LocationValidator.isWithinUSBounds(49.384358, -95.0), isTrue);
      });

      test('returns true for exact minimum longitude', () {
        expect(LocationValidator.isWithinUSBounds(35.0, -125.0), isTrue);
      });

      test('returns true for exact maximum longitude', () {
        expect(LocationValidator.isWithinUSBounds(35.0, -66.93457), isTrue);
      });

      test('returns false for location too far south', () {
        // Below southern boundary
        expect(LocationValidator.isWithinUSBounds(20.0, -95.0), isFalse);
      });

      test('returns false for location too far north', () {
        // Above northern boundary (Alaska)
        expect(LocationValidator.isWithinUSBounds(64.8378, -147.7164), isFalse);
      });

      test('returns false for location too far west', () {
        // West of western boundary
        expect(LocationValidator.isWithinUSBounds(35.0, -130.0), isFalse);
      });

      test('returns false for location too far east', () {
        // East of eastern boundary
        expect(LocationValidator.isWithinUSBounds(35.0, -60.0), isFalse);
      });

      test('returns false for Hawaii', () {
        // Honolulu
        expect(LocationValidator.isWithinUSBounds(21.3099, -157.8581), isFalse);
      });

      test('returns false for Alaska', () {
        // Anchorage
        expect(LocationValidator.isWithinUSBounds(61.2181, -149.9003), isFalse);
      });

      test('returns false for location in Europe', () {
        // Paris, France
        expect(LocationValidator.isWithinUSBounds(48.8566, 2.3522), isFalse);
      });

      test('returns false for location in Asia', () {
        // Tokyo, Japan
        expect(LocationValidator.isWithinUSBounds(35.6762, 139.6503), isFalse);
      });

      test('returns false for location in South America', () {
        // São Paulo, Brazil
        expect(LocationValidator.isWithinUSBounds(-23.5505, -46.6333), isFalse);
      });

      test('returns false for location just outside minimum latitude', () {
        expect(LocationValidator.isWithinUSBounds(24.396307, -95.0), isFalse);
      });

      test('returns false for location just outside maximum latitude', () {
        expect(LocationValidator.isWithinUSBounds(49.384359, -95.0), isFalse);
      });

      test('returns false for location just outside minimum longitude', () {
        expect(LocationValidator.isWithinUSBounds(35.0, -125.000001), isFalse);
      });

      test('returns false for location just outside maximum longitude', () {
        expect(LocationValidator.isWithinUSBounds(35.0, -66.93456), isFalse);
      });
    });
  });
}
