import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Sample pins across the United States for testing and demonstration
class SampleData {
  static List<Pin> getSamplePins() {
    final now = DateTime.now();

    return [
      // 1. Starbucks in Seattle (ALLOWED - Green)
      Pin(
        id: _uuid.v4(),
        name: 'Starbucks Coffee - Seattle',
        location: Location.fromLatLng(47.6062, -122.3321),
        status: PinStatus.ALLOWED,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          votes: 15,
        ),
      ),

      // 2. City Hall in New York (NO_GUN - Red)
      Pin(
        id: _uuid.v4(),
        name: 'New York City Hall',
        location: Location.fromLatLng(40.7128, -74.0060),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.STATE_LOCAL_GOVT,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: 'Security checkpoint at entrance',
          votes: 42,
        ),
      ),

      // 3. Restaurant in Chicago (UNCERTAIN - Yellow)
      Pin(
        id: _uuid.v4(),
        name: 'The Purple Pig Restaurant',
        location: Location.fromLatLng(41.8781, -87.6298),
        status: PinStatus.UNCERTAIN,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: 'No clear signage visible',
          votes: 8,
        ),
      ),

      // 4. Elementary School in Los Angeles (NO_GUN - Red)
      Pin(
        id: _uuid.v4(),
        name: 'Washington Elementary School',
        location: Location.fromLatLng(34.0522, -118.2437),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.SCHOOL_K12,
        hasSecurityScreening: false,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: 'School zone - guns prohibited by law',
          votes: 67,
        ),
      ),

      // 5. Gas Station in Dallas (ALLOWED - Green)
      Pin(
        id: _uuid.v4(),
        name: 'Shell Gas Station',
        location: Location.fromLatLng(32.7767, -96.7970),
        status: PinStatus.ALLOWED,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          votes: 5,
        ),
      ),

      // 6. Airport in Denver (NO_GUN - Red)
      Pin(
        id: _uuid.v4(),
        name: 'Denver International Airport - Secure Area',
        location: Location.fromLatLng(39.8561, -104.6737),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.AIRPORT_SECURE,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: 'Past TSA checkpoint',
          votes: 103,
        ),
      ),

      // 7. Bar in Austin (NO_GUN - Red)
      Pin(
        id: _uuid.v4(),
        name: 'Sixth Street Bar & Grill',
        location: Location.fromLatLng(30.2672, -97.7431),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.BAR_ALCOHOL,
        hasSecurityScreening: false,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: '51% alcohol sales - prohibited under Texas law',
          votes: 23,
        ),
      ),

      // 8. Park in San Francisco (ALLOWED - Green)
      Pin(
        id: _uuid.v4(),
        name: 'Golden Gate Park',
        location: Location.fromLatLng(37.7694, -122.4862),
        status: PinStatus.ALLOWED,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          votes: 31,
        ),
      ),

      // 9. Hospital in Boston (NO_GUN - Red)
      Pin(
        id: _uuid.v4(),
        name: 'Massachusetts General Hospital',
        location: Location.fromLatLng(42.3601, -71.0589),
        status: PinStatus.NO_GUN,
        restrictionTag: RestrictionTag.HEALTHCARE,
        hasSecurityScreening: true,
        hasPostedSignage: true,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: 'Hospital policy prohibits weapons',
          votes: 54,
        ),
      ),

      // 10. Shopping Mall in Miami (UNCERTAIN - Yellow)
      Pin(
        id: _uuid.v4(),
        name: 'Aventura Mall',
        location: Location.fromLatLng(25.9572, -80.1428),
        status: PinStatus.UNCERTAIN,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'sample-user',
          createdAt: now,
          lastModified: now,
          notes: 'Private property - policy unclear',
          votes: 12,
        ),
      ),
    ];
  }
}
