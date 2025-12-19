import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';

void main() {
  group('Pin', () {
    final now = DateTime.now();
    final metadata = PinMetadata(
      createdBy: 'user-123',
      createdAt: now,
      lastModified: now,
    );
    final location = Location.fromLatLng(39.8283, -98.5795);

    test('creates pin with ALLOWED status', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      expect(pin.id, 'pin-1');
      expect(pin.name, 'Test Location');
      expect(pin.status, PinStatus.ALLOWED);
      expect(pin.restrictionTag, isNull);
    });

    test('creates pin with UNCERTAIN status', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.UNCERTAIN,
        metadata: metadata,
      );

      expect(pin.status, PinStatus.UNCERTAIN);
      expect(pin.restrictionTag, isNull);
    });

    test('creates pin with NO_GUN status and restriction tag', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.SCHOOL_K12,
        metadata: metadata,
      );

      expect(pin.status, PinStatus.NO_GUN);
      expect(pin.restrictionTag, RestrictionTag.SCHOOL_K12);
    });

    test('throws when NO_GUN status has no restriction tag', () {
      expect(
        () => Pin(
          id: 'pin-1',
          name: 'Test Location',
          location: location,
          status: PinStatus.NO_GUN,
          metadata: metadata,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('withNextStatus cycles through statuses', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      final next1 = pin.withNextStatus();
      expect(next1.status, PinStatus.UNCERTAIN);

      final next2 = next1.withNextStatus();
      expect(next2.status, PinStatus.NO_GUN);
      expect(next2.restrictionTag, isNotNull); // Should auto-set a default

      final next3 = next2.withNextStatus();
      expect(next3.status, PinStatus.ALLOWED);
      expect(next3.restrictionTag, isNull);
    });

    test('withStatus changes status correctly', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      final updated = pin.withStatus(
        PinStatus.NO_GUN,
        newRestrictionTag: RestrictionTag.FEDERAL_PROPERTY,
      );

      expect(updated.status, PinStatus.NO_GUN);
      expect(updated.restrictionTag, RestrictionTag.FEDERAL_PROPERTY);
      expect(updated.id, pin.id); // ID unchanged
      expect(updated.name, pin.name); // Name unchanged
    });

    test('copyWith creates new instance with changes', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      final copy = pin.copyWith(name: 'New Name');

      expect(copy.name, 'New Name');
      expect(copy.id, pin.id);
      expect(copy.status, pin.status);
    });

    test('includes optional fields', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: metadata,
      );

      expect(pin.hasSecurityScreening, isTrue);
      expect(pin.hasPostedSignage, isTrue);
    });

    test('default values for optional fields', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      expect(pin.hasSecurityScreening, isFalse);
      expect(pin.hasPostedSignage, isFalse);
    });

    test('equality works correctly', () {
      final pin1 = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      final pin2 = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      final pin3 = Pin(
        id: 'pin-2',
        name: 'Different Location',
        location: location,
        status: PinStatus.UNCERTAIN,
        metadata: metadata,
      );

      expect(pin1, equals(pin2));
      expect(pin1, isNot(equals(pin3)));
    });

    test('toString includes key information', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: location,
        status: PinStatus.ALLOWED,
        metadata: metadata,
      );

      final str = pin.toString();
      expect(str, contains('pin-1'));
      expect(str, contains('Test Location'));
      expect(str, contains('Allowed'));
    });
  });
}
