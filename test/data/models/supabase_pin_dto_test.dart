import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';

void main() {
  group('SupabasePinDto', () {
    late SupabasePinDto dto;

    setUp(() {
      dto = const SupabasePinDto(
        id: 'pin-1',
        name: 'Test',
        latitude: 30.0,
        longitude: -95.0,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: 'user-123',
        createdAt: '2026-05-16T00:00:00Z',
        lastModified: '2026-05-16T00:00:00Z',
        photoUri: null,
        notes: null,
        votes: 0,
      );
    });

    group('toJson', () {
      test('includes all 19 columns (full DTO for INSERT)', () {
        final json = dto.toJson();

        expect(json.keys.toSet(), {
          'id',
          'name',
          'latitude',
          'longitude',
          'status',
          'restriction_tag',
          'has_security_screening',
          'has_posted_signage',
          'created_by',
          'created_at',
          'last_modified',
          'photo_uri',
          'notes',
          'votes',
          'source',
          'source_external_id',
          'confidence',
          'legal_citation',
          'legal_citation_verified_date',
        });
      });

      test('maps field values correctly', () {
        final json = dto.toJson();

        expect(json['id'], 'pin-1');
        expect(json['name'], 'Test');
        expect(json['latitude'], 30.0);
        expect(json['longitude'], -95.0);
        expect(json['status'], 0);
        expect(json['restriction_tag'], isNull);
        expect(json['has_security_screening'], false);
        expect(json['has_posted_signage'], false);
        expect(json['created_by'], 'user-123');
        expect(json['created_at'], '2026-05-16T00:00:00Z');
        expect(json['last_modified'], '2026-05-16T00:00:00Z');
        expect(json['photo_uri'], isNull);
        expect(json['notes'], isNull);
        expect(json['votes'], 0);
      });
    });

    group('toJsonForUpdate', () {
      test(
        'excludes immutable and server-managed columns, matching migration 008 grants',
        () {
          final json = dto.toJsonForUpdate();

          // Must include all 10 columns granted UPDATE to authenticated in migration 008.
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

          // Must NOT include id, created_by, created_at, last_modified — those
          // fall outside the migration-008 GRANT and would trigger a Postgres
          // permission error.
          expect(json.containsKey('id'), isFalse);
          expect(json.containsKey('created_by'), isFalse);
          expect(json.containsKey('created_at'), isFalse);
          expect(json.containsKey('last_modified'), isFalse);
        },
      );

      test('maps mutable field values correctly', () {
        final dtoWithValues = const SupabasePinDto(
          id: 'pin-2',
          name: 'Gun Store',
          latitude: 35.5,
          longitude: -97.3,
          status: 2,
          restrictionTag: 'FEDERAL_PROPERTY',
          hasSecurityScreening: true,
          hasPostedSignage: true,
          createdBy: 'user-456',
          createdAt: '2026-01-01T00:00:00Z',
          lastModified: '2026-05-16T12:00:00Z',
          photoUri: 'https://example.com/photo.jpg',
          notes: 'Some notes',
          votes: 7,
        );

        final json = dtoWithValues.toJsonForUpdate();

        expect(json['name'], 'Gun Store');
        expect(json['latitude'], 35.5);
        expect(json['longitude'], -97.3);
        expect(json['status'], 2);
        expect(json['restriction_tag'], 'FEDERAL_PROPERTY');
        expect(json['has_security_screening'], true);
        expect(json['has_posted_signage'], true);
        expect(json['photo_uri'], 'https://example.com/photo.jpg');
        expect(json['notes'], 'Some notes');
        expect(json['votes'], 7);
      });
    });
  });
}
