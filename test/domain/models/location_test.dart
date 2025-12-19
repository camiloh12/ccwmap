import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/location.dart';

void main() {
  group('Location', () {
    test('creates valid location with fromLatLng', () {
      final location = Location.fromLatLng(39.8283, -98.5795);
      expect(location.latitude, 39.8283);
      expect(location.longitude, -98.5795);
    });

    test('creates valid location with fromLngLat', () {
      final location = Location.fromLngLat(-98.5795, 39.8283);
      expect(location.latitude, 39.8283);
      expect(location.longitude, -98.5795);
    });

    test('throws on invalid latitude (too low)', () {
      expect(
        () => Location.fromLatLng(-91, 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on invalid latitude (too high)', () {
      expect(
        () => Location.fromLatLng(91, 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on invalid longitude (too low)', () {
      expect(
        () => Location.fromLatLng(0, -181),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on invalid longitude (too high)', () {
      expect(
        () => Location.fromLatLng(0, 181),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts boundary latitude values', () {
      expect(() => Location.fromLatLng(-90, 0), returnsNormally);
      expect(() => Location.fromLatLng(90, 0), returnsNormally);
    });

    test('accepts boundary longitude values', () {
      expect(() => Location.fromLatLng(0, -180), returnsNormally);
      expect(() => Location.fromLatLng(0, 180), returnsNormally);
    });

    test('equality works correctly', () {
      final loc1 = Location.fromLatLng(39.8283, -98.5795);
      final loc2 = Location.fromLatLng(39.8283, -98.5795);
      final loc3 = Location.fromLatLng(40.0, -98.0);

      expect(loc1, equals(loc2));
      expect(loc1, isNot(equals(loc3)));
    });

    test('hashCode works correctly', () {
      final loc1 = Location.fromLatLng(39.8283, -98.5795);
      final loc2 = Location.fromLatLng(39.8283, -98.5795);

      expect(loc1.hashCode, equals(loc2.hashCode));
    });

    test('toString returns formatted string', () {
      final location = Location.fromLatLng(39.8283, -98.5795);
      expect(location.toString(), contains('39.8283'));
      expect(location.toString(), contains('-98.5795'));
    });
  });
}
