import '../../domain/models/map_item.dart';

// Source/layer ids for the low-zoom density heatmap and land mask.
const String kHeatmapSourceId = 'clusters-heatmap-source';
const String kHeatmapLayerId = 'clusters-heatmap-layer';
const String kLandMaskSourceId = 'land-mask-source';
const String kLandMaskLayerId = 'land-mask-layer';

// Asset path for the bundled non-US land polygon (Task 1).
const String kLandMaskAsset = 'assets/geo/world_minus_us.geojson';

// streets-v4 basemap background/land color — keep the mask seamless.
const String kLandMaskColor = 'hsl(54, 100%, 97%)';

/// Builds a GeoJSON FeatureCollection of weighted points for the density
/// heatmap, one point per server cluster. `count` becomes the heatmap weight.
/// Coordinates are emitted [lng, lat] per the GeoJSON spec.
Map<String, dynamic> buildClusterHeatmapGeoJson(List<MapItemCluster> clusters) {
  return {
    'type': 'FeatureCollection',
    'features': clusters
        .map(
          (c) => {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [c.centroidLng, c.centroidLat],
            },
            'properties': {'count': c.count},
          },
        )
        .toList(),
  };
}

/// Picks the basemap's water fill layer id from a list of style layer ids,
/// so the heatmap can be inserted beneath it (ocean clip). Prefers an exact
/// case-insensitive `water`, then any id containing `water`, then `ocean`.
/// Returns null if no candidate exists (e.g. the demotiles fallback style).
String? resolveWaterLayerId(List<String> layerIds) {
  for (final id in layerIds) {
    if (id.toLowerCase() == 'water') return id;
  }
  for (final id in layerIds) {
    if (id.toLowerCase().contains('water')) return id;
  }
  for (final id in layerIds) {
    if (id.toLowerCase().contains('ocean')) return id;
  }
  return null;
}
