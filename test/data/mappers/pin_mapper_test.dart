import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';

void main() {
  group('PinMapper', () {
    final now = DateTime.now();
    final metadata = PinMetadata(
      createdBy: 'user-123',
      createdAt: now,
      lastModified: now,
      photoUri: 'https://example.com/photo.jpg',
      notes: 'Test notes',
      votes: 5,
    );

    test('toEntity converts Pin to PinEntity correctly', () {
      final pin = Pin(
        id: 'pin-1',
        name: 'Test Location',
        location: Location.fromLatLng(39.8283, -98.5795),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.SCHOOL_K12,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: metadata,
      );

      final entity = PinMapper.toEntity(pin);

      expect(entity.id, 'pin-1');
      expect(entity.name, 'Test Location');
      expect(entity.latitude, 39.8283);
      expect(entity.longitude, -98.5795);
      expect(entity.status, 2); // NO_GUN color code
      expect(entity.restrictionTag, 'SCHOOL_K12');
      expect(entity.hasSecurityScreening, isTrue);
      expect(entity.hasPostedSignage, isTrue);
      expect(entity.createdBy, 'user-123');
      expect(entity.createdAt, now.millisecondsSinceEpoch);
      expect(entity.lastModified, now.millisecondsSinceEpoch);
      expect(entity.photoUri, 'https://example.com/photo.jpg');
      expect(entity.notes, 'Test notes');
      expect(entity.votes, 5);
    });

    test('fromEntity converts PinEntity to Pin correctly', () {
      final entity = PinEntity(
        id: 'pin-1',
        name: 'Test Location',
        latitude: 39.8283,
        longitude: -98.5795,
        status: 1, // UNCERTAIN
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-456',
        createdAt: now.millisecondsSinceEpoch,
        lastModified: now.millisecondsSinceEpoch,
        photoUri: null,
        notes: null,
        votes: 0,
      );

      final pin = PinMapper.fromEntity(entity);

      expect(pin.id, 'pin-1');
      expect(pin.name, 'Test Location');
      expect(pin.location.latitude, 39.8283);
      expect(pin.location.longitude, -98.5795);
      expect(pin.status, PinStatus.UNCERTAIN);
      expect(pin.restrictionTag, isNull);
      expect(pin.hasSecurityScreening, isFalse);
      expect(pin.hasPostedSignage, isFalse);
      expect(pin.metadata.createdBy, 'user-456');
      expect(pin.metadata.createdAt, DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch));
      expect(pin.metadata.photoUri, isNull);
      expect(pin.metadata.notes, isNull);
      expect(pin.metadata.votes, 0);
    });

    test('round-trip conversion preserves all data', () {
      final originalPin = Pin(
        id: 'pin-123',
        name: 'Round Trip Test',
        location: Location.fromLatLng(40.7128, -74.0060),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.FEDERAL_PROPERTY,
        hasSecurityScreening: true,
        hasPostedSignage: false,
        metadata: metadata,
      );

      // Convert to entity and back
      final entity = PinMapper.toEntity(originalPin);
      final convertedPin = PinMapper.fromEntity(entity);

      expect(convertedPin.id, originalPin.id);
      expect(convertedPin.name, originalPin.name);
      expect(convertedPin.location, originalPin.location);
      expect(convertedPin.status, originalPin.status);
      expect(convertedPin.restrictionTag, originalPin.restrictionTag);
      expect(convertedPin.hasSecurityScreening, originalPin.hasSecurityScreening);
      expect(convertedPin.hasPostedSignage, originalPin.hasPostedSignage);
      expect(convertedPin.metadata.createdBy, originalPin.metadata.createdBy);
      expect(convertedPin.metadata.votes, originalPin.metadata.votes);
    });

    test('handles null optional fields correctly', () {
      final pin = Pin(
        id: 'pin-null-test',
        name: 'Null Test',
        location: Location.fromLatLng(0, 0),
        status: PinStatus.ALLOWED,
        metadata: PinMetadata(
          createdBy: null,
          createdAt: now,
          lastModified: now,
          photoUri: null,
          notes: null,
          votes: 0,
        ),
      );

      final entity = PinMapper.toEntity(pin);
      final convertedPin = PinMapper.fromEntity(entity);

      expect(convertedPin.restrictionTag, isNull);
      expect(convertedPin.metadata.createdBy, isNull);
      expect(convertedPin.metadata.photoUri, isNull);
      expect(convertedPin.metadata.notes, isNull);
    });

    test('converts all PinStatus values correctly', () {
      final statuses = [
        PinStatus.ALLOWED,
        PinStatus.UNCERTAIN,
        PinStatus.NO_GUN,
      ];

      for (final status in statuses) {
        final pin = Pin(
          id: 'pin-status-test',
          name: 'Status Test',
          location: Location.fromLatLng(0, 0),
          status: status,
          restrictionTag: status == PinStatus.NO_GUN
              ? RestrictionTag.PRIVATE_PROPERTY
              : null,
          metadata: PinMetadata(
            createdAt: now,
            lastModified: now,
          ),
        );

        final entity = PinMapper.toEntity(pin);
        final convertedPin = PinMapper.fromEntity(entity);

        expect(convertedPin.status, status);
      }
    });

    test('converts all RestrictionTag values correctly', () {
      final tags = RestrictionTag.values;

      for (final tag in tags) {
        final pin = Pin(
          id: 'pin-tag-test',
          name: 'Tag Test',
          location: Location.fromLatLng(0, 0),
          status: PinStatus.NO_GUN,
          restrictionTag: tag,
          metadata: PinMetadata(
            createdAt: now,
            lastModified: now,
          ),
        );

        final entity = PinMapper.toEntity(pin);
        final convertedPin = PinMapper.fromEntity(entity);

        expect(convertedPin.restrictionTag, tag);
      }
    });

    test('preserves timestamp precision', () {
      final preciseTime = DateTime(2024, 1, 15, 10, 30, 45, 123);
      final pin = Pin(
        id: 'pin-time-test',
        name: 'Time Test',
        location: Location.fromLatLng(0, 0),
        status: PinStatus.ALLOWED,
        metadata: PinMetadata(
          createdAt: preciseTime,
          lastModified: preciseTime,
        ),
      );

      final entity = PinMapper.toEntity(pin);
      final convertedPin = PinMapper.fromEntity(entity);

      expect(
        convertedPin.metadata.createdAt.millisecondsSinceEpoch,
        preciseTime.millisecondsSinceEpoch,
      );
      expect(
        convertedPin.metadata.lastModified.millisecondsSinceEpoch,
        preciseTime.millisecondsSinceEpoch,
      );
    });
  });
}
