import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/mappers/supabase_pin_mapper.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';

void main() {
  group('SupabasePinMapper', () {
    test('toDto converts Pin to SupabasePinDto correctly', () {
      final createdAt = DateTime(2024, 1, 15, 10, 30);
      final lastModified = DateTime(2024, 1, 16, 14, 45);

      final pin = Pin(
        id: 'test-pin-id',
        name: 'Test Location',
        location: Location.fromLatLng(39.8283, -98.5795),
        status: PinStatus.ALLOWED,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'user-123',
          createdAt: createdAt,
          lastModified: lastModified,
          photoUri: 'https://example.com/photo.jpg',
          notes: 'Test notes',
          votes: 5,
        ),
      );

      final dto = SupabasePinMapper.toDto(pin);

      expect(dto.id, 'test-pin-id');
      expect(dto.name, 'Test Location');
      expect(dto.latitude, 39.8283);
      expect(dto.longitude, -98.5795);
      expect(dto.status, 0); // ALLOWED = 0
      expect(dto.restrictionTag, isNull);
      expect(dto.hasSecurityScreening, false);
      expect(dto.hasPostedSignage, true);
      expect(dto.createdBy, 'user-123');
      expect(dto.createdAt, createdAt.toIso8601String());
      expect(dto.lastModified, lastModified.toIso8601String());
      expect(dto.photoUri, 'https://example.com/photo.jpg');
      expect(dto.notes, 'Test notes');
      expect(dto.votes, 5);
    });

    test('toDto converts NO_GUN status with restriction tag', () {
      final pin = Pin(
        id: 'no-gun-pin',
        name: 'Federal Building',
        location: Location.fromLatLng(40.0, -100.0),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.FEDERAL_PROPERTY,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'user-456',
          createdAt: DateTime.now(),
          lastModified: DateTime.now(),
        ),
      );

      final dto = SupabasePinMapper.toDto(pin);

      expect(dto.status, 2); // NO_GUN = 2
      expect(dto.restrictionTag, 'FEDERAL_PROPERTY');
      expect(dto.hasSecurityScreening, true);
      expect(dto.hasPostedSignage, true);
    });

    test('fromDto converts SupabasePinDto to Pin correctly', () {
      final createdAt = DateTime(2024, 1, 15, 10, 30).toIso8601String();
      final lastModified = DateTime(2024, 1, 16, 14, 45).toIso8601String();

      final dto = SupabasePinDto(
        id: 'dto-pin-id',
        name: 'DTO Location',
        latitude: 35.0,
        longitude: -95.0,
        status: 1, // UNCERTAIN
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-789',
        createdAt: createdAt,
        lastModified: lastModified,
        photoUri: null,
        notes: null,
        votes: 0,
      );

      final pin = SupabasePinMapper.fromDto(dto);

      expect(pin.id, 'dto-pin-id');
      expect(pin.name, 'DTO Location');
      expect(pin.location.latitude, 35.0);
      expect(pin.location.longitude, -95.0);
      expect(pin.status, PinStatus.UNCERTAIN);
      expect(pin.restrictionTag, isNull);
      expect(pin.hasSecurityScreening, false);
      expect(pin.hasPostedSignage, false);
      expect(pin.metadata.createdBy, 'user-789');
      expect(pin.metadata.createdAt, DateTime.parse(createdAt));
      expect(pin.metadata.lastModified, DateTime.parse(lastModified));
      expect(pin.metadata.photoUri, isNull);
      expect(pin.metadata.notes, isNull);
      expect(pin.metadata.votes, 0);
    });

    test('round-trip conversion (Pin -> DTO -> Pin) preserves data', () {
      final original = Pin(
        id: 'round-trip-id',
        name: 'Round Trip Test',
        location: Location.fromLatLng(42.5, -87.3),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.SCHOOL_K12,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'test-user',
          createdAt: DateTime(2024, 1, 1),
          lastModified: DateTime(2024, 1, 2),
          photoUri: 'photo.jpg',
          notes: 'Test',
          votes: 10,
        ),
      );

      final dto = SupabasePinMapper.toDto(original);
      final restored = SupabasePinMapper.fromDto(dto);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.location.latitude, original.location.latitude);
      expect(restored.location.longitude, original.location.longitude);
      expect(restored.status, original.status);
      expect(restored.restrictionTag, original.restrictionTag);
      expect(restored.hasSecurityScreening, original.hasSecurityScreening);
      expect(restored.hasPostedSignage, original.hasPostedSignage);
      expect(restored.metadata.createdBy, original.metadata.createdBy);
      expect(restored.metadata.photoUri, original.metadata.photoUri);
      expect(restored.metadata.notes, original.metadata.notes);
      expect(restored.metadata.votes, original.metadata.votes);
    });

    test('fromDtoList converts list correctly', () {
      final dtos = [
        SupabasePinDto(
          id: 'pin-1',
          name: 'Pin 1',
          latitude: 40.0,
          longitude: -100.0,
          status: 0,
          restrictionTag: null,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          createdBy: 'user-1',
          createdAt: DateTime.now().toIso8601String(),
          lastModified: DateTime.now().toIso8601String(),
          votes: 0,
        ),
        SupabasePinDto(
          id: 'pin-2',
          name: 'Pin 2',
          latitude: 41.0,
          longitude: -101.0,
          status: 1,
          restrictionTag: null,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          createdBy: 'user-2',
          createdAt: DateTime.now().toIso8601String(),
          lastModified: DateTime.now().toIso8601String(),
          votes: 0,
        ),
      ];

      final pins = SupabasePinMapper.fromDtoList(dtos);

      expect(pins.length, 2);
      expect(pins[0].id, 'pin-1');
      expect(pins[1].id, 'pin-2');
    });

    test('toDtoList converts list correctly', () {
      final now = DateTime.now();
      final pins = [
        Pin(
          id: 'pin-1',
          name: 'Pin 1',
          location: Location.fromLatLng(40.0, -100.0),
          status: PinStatus.ALLOWED,
          restrictionTag: null,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          metadata: PinMetadata(
            createdBy: 'user-1',
            createdAt: now,
            lastModified: now,
          ),
        ),
        Pin(
          id: 'pin-2',
          name: 'Pin 2',
          location: Location.fromLatLng(41.0, -101.0),
          status: PinStatus.UNCERTAIN,
          restrictionTag: null,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          metadata: PinMetadata(
            createdBy: 'user-2',
            createdAt: now,
            lastModified: now,
          ),
        ),
      ];

      final dtos = SupabasePinMapper.toDtoList(pins);

      expect(dtos.length, 2);
      expect(dtos[0].id, 'pin-1');
      expect(dtos[1].id, 'pin-2');
    });

    test('handles all restriction tag types', () {
      final restrictionTags = [
        RestrictionTag.FEDERAL_PROPERTY,
        RestrictionTag.AIRPORT_SECURE,
        RestrictionTag.STATE_LOCAL_GOVT,
        RestrictionTag.SCHOOL_K12,
        RestrictionTag.COLLEGE_UNIVERSITY,
        RestrictionTag.BAR_ALCOHOL,
        RestrictionTag.HEALTHCARE,
        RestrictionTag.PLACE_OF_WORSHIP,
        RestrictionTag.SPORTS_ENTERTAINMENT,
        RestrictionTag.PRIVATE_PROPERTY,
      ];

      for (final tag in restrictionTags) {
        final pin = Pin(
          id: 'test-id',
          name: 'Test',
          location: Location.fromLatLng(40.0, -100.0),
          status: PinStatus.NO_GUN,
          restrictionTag: tag,
          hasSecurityScreening: false,
          hasPostedSignage: false,
          metadata: PinMetadata(
            createdBy: 'user',
            createdAt: DateTime.now(),
            lastModified: DateTime.now(),
          ),
        );

        final dto = SupabasePinMapper.toDto(pin);
        final restored = SupabasePinMapper.fromDto(dto);

        expect(restored.restrictionTag, tag);
      }
    });
  });
}
