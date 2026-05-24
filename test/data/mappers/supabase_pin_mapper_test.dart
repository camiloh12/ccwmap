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

  group('SupabasePinDto provenance round-trip', () {
    test('fromJson reads source/confidence/legal_citation', () {
      final dto = SupabasePinDto.fromJson({
        'id': 'pin-1',
        'name': 'Federal Courthouse',
        'latitude': 30.0,
        'longitude': -95.0,
        'status': 2,
        'restriction_tag': 'FEDERAL_PROPERTY',
        'has_security_screening': true,
        'has_posted_signage': true,
        'created_by': '81775f8b-1a6a-47d6-b793-e9ab7e38634e',
        'created_at': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
        'photo_uri': null,
        'notes': null,
        'votes': 0,
        'source': 'hifld_courts',
        'source_external_id': 'HIFLD-COURT-12345',
        'confidence': 'high',
        'legal_citation': '18 USC 930(a)',
        'legal_citation_verified_date': '2026-01-15',
      });

      expect(dto.source, 'hifld_courts');
      expect(dto.sourceExternalId, 'HIFLD-COURT-12345');
      expect(dto.confidence, 'high');
      expect(dto.legalCitation, '18 USC 930(a)');
      expect(dto.legalCitationVerifiedDate, '2026-01-15');
    });

    test('fromJson defaults source to "user" when absent', () {
      final dto = SupabasePinDto.fromJson({
        'id': 'pin-1',
        'name': 'My pin',
        'latitude': 30.0,
        'longitude': -95.0,
        'status': 0,
        'restriction_tag': null,
        'has_security_screening': false,
        'has_posted_signage': false,
        'created_by': null,
        'created_at': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
        'photo_uri': null,
        'notes': null,
        'votes': 0,
        // no source key at all — server omitted it
      });

      expect(dto.source, 'user');
      expect(dto.sourceExternalId, isNull);
      expect(dto.confidence, isNull);
    });

    test('toJsonForUpdate omits provenance fields '
        '(authenticated users have no GRANT on them)', () {
      final dto = SupabasePinDto(
        id: 'pin-1',
        name: 'x',
        latitude: 30,
        longitude: -95,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: null,
        createdAt: '2026-01-01T00:00:00Z',
        lastModified: '2026-01-01T00:00:00Z',
        photoUri: null,
        notes: null,
        votes: 0,
        source: 'osm',
        sourceExternalId: 'OSM-NODE-42',
        confidence: 'medium',
        legalCitation: 'TX Penal Code §46.035(b)(1)',
        legalCitationVerifiedDate: '2026-01-15',
      );

      final json = dto.toJsonForUpdate();
      expect(json.containsKey('source'), isFalse);
      expect(json.containsKey('source_external_id'), isFalse);
      expect(json.containsKey('confidence'), isFalse);
      expect(json.containsKey('legal_citation'), isFalse);
      expect(json.containsKey('legal_citation_verified_date'), isFalse);

      // Pin the exact set of updatable columns to migration 008 §8's
      // column-level GRANT. Any drift fails loudly.
      expect(json.keys.toSet(), {
        'name',
        'latitude',
        'longitude',
        'status',
        'restriction_tag',
        'has_security_screening',
        'has_posted_signage',
        'notes',
        'photo_uri',
        'votes',
      });
    });
  });
}
