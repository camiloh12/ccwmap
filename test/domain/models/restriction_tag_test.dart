import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';

void main() {
  group('RestrictionTag', () {
    test('displayName returns correct values', () {
      expect(RestrictionTag.FEDERAL_PROPERTY.displayName, 'Federal Property');
      expect(RestrictionTag.AIRPORT_SECURE.displayName, 'Airport Secure Area');
      expect(RestrictionTag.STATE_LOCAL_GOVT.displayName, 'State/Local Government');
      expect(RestrictionTag.SCHOOL_K12.displayName, 'School (K-12)');
      expect(RestrictionTag.COLLEGE_UNIVERSITY.displayName, 'College/University');
      expect(RestrictionTag.BAR_ALCOHOL.displayName, 'Bar/Alcohol Establishment');
      expect(RestrictionTag.HEALTHCARE.displayName, 'Healthcare Facility');
      expect(RestrictionTag.PLACE_OF_WORSHIP.displayName, 'Place of Worship');
      expect(RestrictionTag.SPORTS_ENTERTAINMENT.displayName, 'Sports/Entertainment Venue');
      expect(RestrictionTag.PRIVATE_PROPERTY.displayName, 'Private Property');
    });

    test('fromString converts correctly', () {
      expect(
        RestrictionTag.fromString('FEDERAL_PROPERTY'),
        RestrictionTag.FEDERAL_PROPERTY,
      );
      expect(
        RestrictionTag.fromString('AIRPORT_SECURE'),
        RestrictionTag.AIRPORT_SECURE,
      );
      expect(
        RestrictionTag.fromString('PRIVATE_PROPERTY'),
        RestrictionTag.PRIVATE_PROPERTY,
      );
    });

    test('fromString returns null for invalid value', () {
      expect(RestrictionTag.fromString('INVALID_TAG'), isNull);
    });

    test('fromString returns null for null value', () {
      expect(RestrictionTag.fromString(null), isNull);
    });

    test('all enum values have displayNames', () {
      for (final tag in RestrictionTag.values) {
        expect(tag.displayName, isNotEmpty);
      }
    });
  });
}
