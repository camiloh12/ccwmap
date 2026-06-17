import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/presentation/map/map_render_helpers.dart';

void main() {
  group('buildClusterHeatmapGeoJson', () {
    test('empty cluster list produces an empty FeatureCollection', () {
      final geo = buildClusterHeatmapGeoJson(const []);
      expect(geo['type'], 'FeatureCollection');
      expect(geo['features'], isEmpty);
    });

    test('maps each cluster to a weighted point in [lng, lat] order', () {
      final clusters = [
        const MapItemCluster(
          centroidLat: 29.76,
          centroidLng: -95.37,
          count: 1200,
          dominantStatus: PinStatus.NO_GUN,
          dominantRestrictionTag: null,
        ),
      ];
      final geo = buildClusterHeatmapGeoJson(clusters);
      final features = geo['features'] as List;
      expect(features.length, 1);
      final f = features.first as Map<String, dynamic>;
      expect(f['type'], 'Feature');
      expect(f['geometry']['type'], 'Point');
      // GeoJSON is [lng, lat] — guard against accidental swaps.
      expect(f['geometry']['coordinates'], [-95.37, 29.76]);
      expect(f['properties']['count'], 1200);
    });

    test('maps multiple clusters preserving order and per-cluster count', () {
      final clusters = [
        const MapItemCluster(
          centroidLat: 29.76,
          centroidLng: -95.37,
          count: 1200,
          dominantStatus: PinStatus.NO_GUN,
          dominantRestrictionTag: null,
        ),
        const MapItemCluster(
          centroidLat: 25.77,
          centroidLng: -80.19,
          count: 42,
          dominantStatus: PinStatus.ALLOWED,
          dominantRestrictionTag: null,
        ),
      ];
      final features = buildClusterHeatmapGeoJson(clusters)['features'] as List;
      expect(features.length, 2);
      expect(features[0]['geometry']['coordinates'], [-95.37, 29.76]);
      expect(features[0]['properties']['count'], 1200);
      expect(features[1]['geometry']['coordinates'], [-80.19, 25.77]);
      expect(features[1]['properties']['count'], 42);
    });
  });

  group('resolveWaterLayerId', () {
    test('returns the exact case-insensitive "water" id when present', () {
      final id = resolveWaterLayerId([
        'Background',
        'Farmland',
        'Water',
        'Water intermittent',
        'Road',
      ]);
      expect(id, 'Water');
    });

    test('exact "water" wins over an earlier contains-water id', () {
      // Pass 1 (exact) must beat pass 2 (contains) regardless of order.
      expect(resolveWaterLayerId(['water-shadow', 'Water', 'road']), 'Water');
    });

    test('falls back to the first id containing "water"', () {
      expect(
        resolveWaterLayerId(['bg', 'water-shadow', 'road']),
        'water-shadow',
      );
    });

    test('falls back to an "ocean" id when no "water" id exists', () {
      expect(resolveWaterLayerId(['bg', 'ocean fill', 'road']), 'ocean fill');
    });

    test('returns null when nothing matches', () {
      expect(resolveWaterLayerId(['bg', 'road', 'labels']), isNull);
    });
  });
}
