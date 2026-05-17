import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapItem', () {
    test('MapItemPin wraps a Pin', () {
      final pin = Pin(
        id: 'p1',
        name: 'x',
        location: Location.fromLatLng(30, -95),
        status: PinStatus.ALLOWED,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'me',
          createdAt: DateTime.utc(2026, 1, 1),
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      );
      final item = MapItemPin(pin);
      expect(item.pin, same(pin));
    });

    test('MapItemCluster carries centroid + count + dominant tags', () {
      const cluster = MapItemCluster(
        centroidLat: 30.5,
        centroidLng: -95.25,
        count: 42,
        dominantStatus: PinStatus.NO_GUN,
        dominantRestrictionTag: RestrictionTag.SCHOOL_K12,
      );
      expect(cluster.count, 42);
      expect(cluster.dominantStatus, PinStatus.NO_GUN);
      expect(cluster.dominantRestrictionTag, RestrictionTag.SCHOOL_K12);
    });

    test('sealed MapItem supports exhaustive pattern matching', () {
      final pin = Pin(
        id: 'p1',
        name: 'x',
        location: Location.fromLatLng(30, -95),
        status: PinStatus.ALLOWED,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'me',
          createdAt: DateTime.utc(2026, 1, 1),
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      );
      final List<MapItem> items = [
        MapItemPin(pin),
        const MapItemCluster(
          centroidLat: 30.5,
          centroidLng: -95.25,
          count: 7,
          dominantStatus: PinStatus.UNCERTAIN,
          dominantRestrictionTag: null,
        ),
      ];

      final descriptions = items.map((item) {
        return switch (item) {
          MapItemPin(:final pin) => 'pin:${pin.id}',
          MapItemCluster(:final count) => 'cluster:$count',
        };
      }).toList();

      expect(descriptions, ['pin:p1', 'cluster:7']);
    });
  });
}
