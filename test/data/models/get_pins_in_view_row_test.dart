import 'package:ccwmap/data/models/get_pins_in_view_row.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GetPinsInViewRow.parse', () {
    test('parses a pin row into MapItemPin with provenance', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'pin',
        'pin_id': 'pin-1',
        'latitude': 30.0,
        'longitude': -95.0,
        'name': 'Federal Courthouse',
        'status': 2,
        'restriction_tag': 'FEDERAL_PROPERTY',
        'has_security_screening': true,
        'has_posted_signage': true,
        'created_by': '81775f8b-1a6a-47d6-b793-e9ab7e38634e',
        'created_at': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
        'source': 'hifld_courts',
        'source_external_id': 'HIFLD-COURT-12345',
        'confidence': 'high',
        'legal_citation': '18 USC 930(a)',
        'legal_citation_verified_date': '2026-01-15',
        'cluster_count': null,
        'dominant_status': null,
        'dominant_restriction_tag': null,
      });

      expect(item, isA<MapItemPin>());
      final mip = item as MapItemPin;
      expect(mip.pin.id, 'pin-1');
      expect(mip.pin.status, PinStatus.NO_GUN);
      expect(mip.pin.restrictionTag, RestrictionTag.FEDERAL_PROPERTY);
    });

    test('parses a cluster row into MapItemCluster', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'cluster',
        'pin_id': null,
        'latitude': 30.5,
        'longitude': -95.25,
        'name': null,
        'status': null,
        'restriction_tag': null,
        'has_security_screening': null,
        'has_posted_signage': null,
        'created_by': null,
        'created_at': null,
        'last_modified': null,
        'source': null,
        'source_external_id': null,
        'confidence': null,
        'legal_citation': null,
        'legal_citation_verified_date': null,
        'cluster_count': 42,
        'dominant_status': 2,
        'dominant_restriction_tag': 'SCHOOL_K12',
      });

      expect(item, isA<MapItemCluster>());
      final c = item as MapItemCluster;
      expect(c.centroidLat, 30.5);
      expect(c.centroidLng, -95.25);
      expect(c.count, 42);
      expect(c.dominantStatus, PinStatus.NO_GUN);
      expect(c.dominantRestrictionTag, RestrictionTag.SCHOOL_K12);
    });

    test('cluster row with null dominant_restriction_tag yields null', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'cluster',
        'pin_id': null,
        'latitude': 30.5,
        'longitude': -95.25,
        'name': null,
        'status': null,
        'restriction_tag': null,
        'has_security_screening': null,
        'has_posted_signage': null,
        'created_by': null,
        'created_at': null,
        'last_modified': null,
        'source': null,
        'source_external_id': null,
        'confidence': null,
        'legal_citation': null,
        'legal_citation_verified_date': null,
        'cluster_count': 3,
        'dominant_status': 0,
        'dominant_restriction_tag': null,
      });

      final c = item as MapItemCluster;
      expect(c.dominantRestrictionTag, isNull);
    });

    test('throws on unknown kind', () {
      expect(
        () => GetPinsInViewRow.parse({'kind': 'meteor'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses provenance columns for a system pin row', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'pin',
        'pin_id': 'p1',
        'name': 'Federal Courthouse',
        'latitude': 30.0,
        'longitude': -97.0,
        'status': 2,
        'restriction_tag': 'STATE_LOCAL_GOVT',
        'has_security_screening': true,
        'has_posted_signage': false,
        'created_by': '81775f8b-1a6a-47d6-b793-e9ab7e38634e',
        'created_at': '2026-05-31T00:00:00Z',
        'last_modified': '2026-05-31T00:00:00Z',
        'source': 'hifld_courts',
        'source_external_id': 'GLOBALID-123',
        'confidence': 'high',
        'legal_citation': 'TX Penal Code 46.03(a)(3)',
        'legal_citation_verified_date': '2026-05-31',
      });
      expect(item, isA<MapItemPin>());
      final pin = (item as MapItemPin).pin;
      expect(pin.metadata.source, 'hifld_courts');
      expect(pin.metadata.confidence, 'high');
      expect(pin.metadata.legalCitation, 'TX Penal Code 46.03(a)(3)');
      expect(pin.metadata.sourceExternalId, 'GLOBALID-123');
      expect(pin.metadata.legalCitationVerifiedDate, '2026-05-31');
    });
  });
}
