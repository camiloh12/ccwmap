# Low-Zoom Heatmap Density View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ugly low-zoom cluster bubbles with a teal density heatmap clipped to US land, handing off to the existing status-colored pins as the user zooms in.

**Architecture:** Pure client rendering change — no schema/RPC migration. The existing `get_pins_in_view` RPC already returns cluster centroids+counts at low zoom and individual pins at high zoom (mutually exclusive per fetch). Cluster rows feed a MapLibre heatmap layer (weighted by `count`); individual pins feed the existing circle layers. The heatmap is inserted below the basemap's `Water` fill (ocean clip) and below a bundled "non-US land" mask fill (foreign-land clip). Mine/cached pins fade out at low zoom via a `circle-opacity` zoom ramp instead of always rendering.

**Tech Stack:** Flutter / Dart, `maplibre_gl` 0.24.1 (`addHeatmapLayer`, `addFillLayer`, `belowLayerId`, `getLayerIds`), MapTiler `streets-v4` vector basemap, Python+shapely (one-off asset generation).

**Spec:** `docs/superpowers/specs/2026-06-17-heatmap-density-lowzoom-design.md`

**Key facts verified against the live code/style (do not re-derive):**
- Basemap water fill layer id in `streets-v4` is **`'Water'`** (source-layer `water`); symbol/label layers start above it, so labels render over the glow.
- Basemap land/background color is **`hsl(54, 100%, 97%)`** — use it for the land mask so foreign land matches the basemap.
- `maplibre_gl` 0.24.1: `MapLibreMapController.addHeatmapLayer(sourceId, layerId, HeatmapLayerProperties(heatmapRadius/heatmapWeight/heatmapIntensity/heatmapColor/heatmapOpacity), {belowLayerId})`, `addFillLayer(..., {belowLayerId})`, `getLayerIds()` → `Future<List>` of layer-id strings.
- `MapItemCluster` (`lib/domain/models/map_item.dart`) fields: `centroidLat`, `centroidLng`, `count`, `dominantStatus`, `dominantRestrictionTag`.
- `ViewportPinsManager` sets `clusters.value = clustersOut` (empty when the RPC returns individual pins) — this is the mutual exclusivity the heatmap relies on; **do not change it.**
- Package name is `ccwmap`.

---

## File Structure

- **Create** `tool/generate_land_mask.py` — one-off generator for the foreign-land mask asset (Python+shapely+requests). Not part of the app build.
- **Create** `assets/geo/world_minus_us.geojson` — generated output, committed as a build asset.
- **Create** `lib/presentation/map/map_render_helpers.dart` — pure, testable helpers + id/color constants used by `map_screen.dart`.
- **Create** `test/presentation/map/map_render_helpers_test.dart` — unit tests for the helpers.
- **Modify** `pubspec.yaml` — declare the new asset.
- **Modify** `lib/presentation/screens/map_screen.dart` — render heatmap instead of cluster circles; add land mask + water-id resolution at style load; pin opacity zoom ramp; remove cluster tap routing and `_applyCachedPinsVisibility`.
- **Modify** `docs/dev/CLUSTER_RENDERING.md` — record the heatmap decision (supersedes Option B at low zoom).
- **Modify** `CLAUDE.md` — one-line status note.

---

## Task 1: Generate the foreign-land mask asset

**Files:**
- Create: `tool/generate_land_mask.py`
- Create: `assets/geo/world_minus_us.geojson` (generated)
- Modify: `pubspec.yaml` (assets list)

- [ ] **Step 1: Write the generator script**

Create `tool/generate_land_mask.py`:

```python
"""One-off: build assets/geo/world_minus_us.geojson — a single dissolved
polygon of all NON-US land within a North-America bounding box, used as a
fill mask so the low-zoom density heatmap doesn't bleed onto Canada/Mexico/
Cuba/etc. Natural Earth is public domain; no attribution required.

Run from the repo root (uses the importer's venv which already has shapely):
    cd importer && pip install requests shapely    # if not already present
    cd .. && python tool/generate_land_mask.py
"""
import json
import os
import requests
from shapely.geometry import shape, mapping, box
from shapely.ops import unary_union

# Natural Earth 1:50m Admin-0 countries (public domain).
URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_0_countries.geojson"
)
# Only foreign land reachable from the app's continental-US viewport matters.
NA_BBOX = box(-170.0, 5.0, -50.0, 75.0)
OUT_PATH = os.path.join("assets", "geo", "world_minus_us.geojson")
SIMPLIFY_TOLERANCE_DEG = 0.01  # ~1 km; small file, border fidelity near metros


def main() -> None:
    print(f"Downloading {URL} ...")
    data = requests.get(URL, timeout=180).json()

    geoms = []
    for feature in data["features"]:
        props = feature["properties"]
        name = props.get("SOVEREIGNT") or props.get("ADMIN") or ""
        if name == "United States of America":
            continue  # leave a US-shaped hole so the glow shows over the US
        geom = shape(feature["geometry"]).intersection(NA_BBOX)
        if not geom.is_empty:
            geoms.append(geom)

    merged = unary_union(geoms).simplify(
        SIMPLIFY_TOLERANCE_DEG, preserve_topology=True
    )

    out = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "note": "Non-US land mask. Natural Earth 1:50m (public domain).",
                },
                "geometry": mapping(merged),
            }
        ],
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    size_kb = os.path.getsize(OUT_PATH) / 1024
    print(f"Wrote {OUT_PATH} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the generator**

Run from the repo root (the importer venv already has `shapely`; install `requests` if missing):

```bash
python tool/generate_land_mask.py
```

Expected: prints `Wrote assets/geo/world_minus_us.geojson (NNN KB)` with a size roughly in the 50–400 KB range.

- [ ] **Step 3: Sanity-check the output**

Run:

```bash
python -c "import json; d=json.load(open('assets/geo/world_minus_us.geojson')); f=d['features'][0]; print('type', f['geometry']['type']); print('features', len(d['features']))"
```

Expected: `type MultiPolygon` (or `Polygon`) and `features 1`. If the file is empty or the download failed, fix before continuing.

- [ ] **Step 4: Declare the asset in pubspec.yaml**

In `pubspec.yaml`, under `flutter:` → `assets:`, change:

```yaml
  assets:
    - .env
```

to:

```yaml
  assets:
    - .env
    - assets/geo/world_minus_us.geojson
```

- [ ] **Step 5: Verify pub picks up the asset**

Run:

```bash
flutter pub get
```

Expected: completes with no error about a missing asset path.

- [ ] **Step 6: Commit**

```bash
git add tool/generate_land_mask.py assets/geo/world_minus_us.geojson pubspec.yaml
git commit -m "feat(map): add non-US land mask asset for heatmap clipping"
```

---

## Task 2: Pure render helpers (TDD)

**Files:**
- Create: `lib/presentation/map/map_render_helpers.dart`
- Test: `test/presentation/map/map_render_helpers_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/presentation/map/map_render_helpers_test.dart`:

```dart
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
          dominantStatus: PinStatus.noGun,
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
  });

  group('resolveWaterLayerId', () {
    test('returns the exact case-insensitive "water" id when present', () {
      final id = resolveWaterLayerId(
        ['Background', 'Farmland', 'Water', 'Water intermittent', 'Road'],
      );
      expect(id, 'Water');
    });

    test('falls back to the first id containing "water"', () {
      expect(resolveWaterLayerId(['bg', 'water-shadow', 'road']), 'water-shadow');
    });

    test('falls back to an "ocean" id when no "water" id exists', () {
      expect(resolveWaterLayerId(['bg', 'ocean fill', 'road']), 'ocean fill');
    });

    test('returns null when nothing matches', () {
      expect(resolveWaterLayerId(['bg', 'road', 'labels']), isNull);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/presentation/map/map_render_helpers_test.dart`
Expected: FAIL — `map_render_helpers.dart` does not exist / functions undefined.

- [ ] **Step 3: Write the helper**

Create `lib/presentation/map/map_render_helpers.dart`:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/presentation/map/map_render_helpers_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/map/map_render_helpers.dart test/presentation/map/map_render_helpers_test.dart
git commit -m "feat(map): add heatmap geojson + water-layer-resolve helpers"
```

---

## Task 3: Render the density heatmap instead of cluster circles

Replaces the cluster circle/count rendering in `map_screen.dart` with a heatmap layer fed by cluster centroids. Tap routing and land-mask insertion are handled in Tasks 4 and 6; this task focuses on the layer.

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Add the helper import**

Near the other relative imports at the top of `map_screen.dart`, add:

```dart
import '../map/map_render_helpers.dart';
```

- [ ] **Step 2: Rename the heatmap-related state fields**

Replace these field declarations (around lines 75–77):

```dart
  bool _clusterLayersCreated = false;
  bool _isUpdatingClusters = false;
  bool _pendingClusterUpdate = false;
```

with:

```dart
  bool _heatmapLayerCreated = false;
  bool _isUpdatingHeatmap = false;
  bool _pendingHeatmapUpdate = false;
  // Resolved from the live style at load (basemap water fill id) so the
  // heatmap + land mask can be inserted beneath it. Null on the demotiles
  // fallback style (no water layer to clip against).
  String? _waterLayerId;
  bool _landMaskCreated = false;
```

- [ ] **Step 3: Point the cluster listener at the renamed updater**

Replace the body of `_onClustersChanged` (around lines 145–149):

```dart
  void _onClustersChanged() {
    if (!mounted) return;
    final clusters = _viewModel?.viewportClusters.value ?? const [];
    _updateClustersLayer(clusters);
  }
```

with:

```dart
  void _onClustersChanged() {
    if (!mounted) return;
    final clusters = _viewModel?.viewportClusters.value ?? const [];
    _updateHeatmapLayer(clusters);
  }
```

- [ ] **Step 4: Replace `_updateClustersLayer` with `_updateHeatmapLayer`**

Replace the entire `_updateClustersLayer` method (from its doc comment at ~line 526 through its closing brace at ~line 670, i.e. the whole method including the `finally` block that re-triggers a pending update) with:

```dart
  /// Render the low-zoom density heatmap from server cluster aggregates.
  ///
  /// Each cluster centroid becomes a heatmap point weighted by its `count`.
  /// The layer is inserted beneath the land mask (and thus beneath the
  /// basemap water + labels) so the glow is clipped to US land. When the RPC
  /// returns individual pins instead of clusters, `clusters` is empty and the
  /// heatmap source is cleared — the density-driven glow→pins handoff.
  ///
  /// Reentrancy mirrors the old cluster updater: if a fire arrives mid-await,
  /// set the pending flag and re-trigger from `finally` with the freshest
  /// value off the notifier.
  Future<void> _updateHeatmapLayer(List<MapItemCluster> clusters) async {
    if (_mapController == null) return;
    if (_isUpdatingHeatmap) {
      _pendingHeatmapUpdate = true;
      return;
    }
    _isUpdatingHeatmap = true;
    _pendingHeatmapUpdate = false;

    try {
      final geojson = buildClusterHeatmapGeoJson(clusters);

      // Fast path: swap data in place (no blink) once the layer exists.
      if (_heatmapLayerCreated) {
        await _mapController!.setGeoJsonSource(kHeatmapSourceId, geojson);
        return;
      }

      // Tear down any prior heatmap layer/source (e.g. after a style reload),
      // plus the legacy cluster circle/count layers from the old design.
      for (final layerId in const [
        kHeatmapLayerId,
        'clusters-count-layer', // legacy
        'clusters-circle-layer', // legacy
      ]) {
        try {
          await _mapController!.removeLayer(layerId);
        } catch (_) {}
      }
      for (final sourceId in const [kHeatmapSourceId, 'clusters-source']) {
        try {
          await _mapController!.removeSource(sourceId);
        } catch (_) {}
      }

      await _mapController!.addGeoJsonSource(kHeatmapSourceId, geojson);

      // Insert beneath the land mask if present (which itself sits beneath the
      // basemap water fill), else directly beneath water, else on top (the
      // demotiles fallback has neither — acceptable for the dev-only style).
      final belowId = _landMaskCreated ? kLandMaskLayerId : _waterLayerId;

      await _mapController!.addHeatmapLayer(
        kHeatmapSourceId,
        kHeatmapLayerId,
        HeatmapLayerProperties(
          // Denser cells glow brighter. Tune stops against real data.
          heatmapWeight: [
            'interpolate',
            ['linear'],
            ['get', 'count'],
            1, 0.15,
            50, 0.4,
            500, 0.8,
            2000, 1.0,
          ],
          // Larger kernel at low zoom for a smooth regional glow.
          heatmapRadius: [
            'interpolate',
            ['linear'],
            ['zoom'],
            3, 26.0,
            6, 38.0,
            9, 52.0,
          ],
          heatmapIntensity: [
            'interpolate',
            ['linear'],
            ['zoom'],
            3, 0.6,
            9, 1.2,
          ],
          // Cool-teal ramp; density 0 fully transparent so the map shows
          // through. NOT zoom-ramped: visibility is data-driven (the source
          // is empty whenever the RPC returns individual pins).
          heatmapColor: [
            'interpolate',
            ['linear'],
            ['heatmap-density'],
            0.0, 'rgba(14,165,165,0)',
            0.2, 'rgba(153,246,228,0.45)',
            0.5, 'rgba(45,212,191,0.75)',
            0.8, 'rgba(14,165,165,0.90)',
            1.0, 'rgba(13,148,136,0.95)',
          ],
          heatmapOpacity: 0.9,
        ),
        belowLayerId: belowId,
      );

      _heatmapLayerCreated = true;
    } catch (e) {
      _heatmapLayerCreated = false;
      debugPrint('MapScreen: Error updating heatmap layer: $e');
    } finally {
      _isUpdatingHeatmap = false;
      if (_pendingHeatmapUpdate) {
        _pendingHeatmapUpdate = false;
        // Re-pull from viewModel — captured cluster list could be stale.
        _updateHeatmapLayer(_viewModel?.viewportClusters.value ?? const []);
      }
    }
  }
```

- [ ] **Step 5: Reset the renamed flag on style reload**

In `_onStyleLoadedCallback` (around lines 324–339), replace:

```dart
    _pinLayersCreated = false;
    _clusterLayersCreated = false;
```

with:

```dart
    _pinLayersCreated = false;
    _heatmapLayerCreated = false;
    _landMaskCreated = false;
    _waterLayerId = null;
```

(Task 4 repopulates `_waterLayerId` and the mask before the first fetch.)

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/presentation/screens/map_screen.dart lib/presentation/map/map_render_helpers.dart`
Expected: No errors. (Warnings about the now-unused `_onClusterTapped` are fine — removed in Task 6.)

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): render low-zoom density heatmap from cluster aggregates"
```

---

## Task 4: Resolve the water layer + add the land mask at style load

Inserts the bundled non-US land mask beneath `Water`, and resolves the water layer id, before the first viewport fetch — so the heatmap (Task 3) finds its `belowLayerId` anchors.

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Add the rootBundle import**

If not already imported, add at the top of `map_screen.dart`:

```dart
import 'package:flutter/services.dart' show rootBundle;
```

(`package:flutter/material.dart` does not export `rootBundle`; confirm this import is present.)

- [ ] **Step 2: Add a static-layers initializer**

Add this method to the `_MapScreenState` class (place it directly above `_updateHeatmapLayer`):

```dart
  /// One-time per style-load setup of the static map layers the heatmap
  /// depends on: resolve the basemap water fill id, then add the non-US land
  /// mask fill beneath it. Both are no-ops on the demotiles fallback style
  /// (no water layer) — the heatmap then renders unclipped, which is
  /// acceptable for that dev-only style.
  Future<void> _initStaticMapLayers() async {
    final controller = _mapController;
    if (controller == null) return;

    // Resolve the water layer id from the live style.
    try {
      final ids = (await controller.getLayerIds())
          .map((e) => e.toString())
          .toList();
      _waterLayerId = resolveWaterLayerId(ids);
    } catch (e) {
      debugPrint('MapScreen: getLayerIds failed: $e');
      _waterLayerId = null;
    }

    // Add the foreign-land mask beneath the water fill so it covers any glow
    // bleeding onto Canada/Mexico/Cuba while the basemap water covers ocean
    // bleed. Skipped if we couldn't resolve a water anchor.
    if (_waterLayerId != null) {
      try {
        final maskGeoJsonStr = await rootBundle.loadString(kLandMaskAsset);
        final maskGeoJson =
            jsonDecode(maskGeoJsonStr) as Map<String, dynamic>;
        try {
          await controller.removeLayer(kLandMaskLayerId);
        } catch (_) {}
        try {
          await controller.removeSource(kLandMaskSourceId);
        } catch (_) {}
        await controller.addGeoJsonSource(kLandMaskSourceId, maskGeoJson);
        await controller.addFillLayer(
          kLandMaskSourceId,
          kLandMaskLayerId,
          FillLayerProperties(
            fillColor: kLandMaskColor,
            // Zoom-gate the mask: opaque at low zoom (clip the glow), fully
            // transparent by metro zoom so border cities (El Paso/Juárez,
            // San Diego/Tijuana) show the real basemap for Mexico/Canada
            // where there's no glow to clip. Tracks the heatmap's active range.
            fillOpacity: const [
              'interpolate',
              ['linear'],
              ['zoom'],
              9, 1.0,
              11, 0.0,
            ],
          ),
          belowLayerId: _waterLayerId,
        );
        _landMaskCreated = true;
      } catch (e) {
        debugPrint('MapScreen: land mask add failed: $e');
        _landMaskCreated = false;
      }
    }
  }
```

- [ ] **Step 3: Confirm `jsonDecode` is available**

`jsonDecode` comes from `dart:convert`. Confirm `import 'dart:convert';` is present at the top of `map_screen.dart`; if not, add it.

- [ ] **Step 4: Sequence the initializer before the first fetch**

In `_onStyleLoadedCallback`, replace the tail of the method (the location-enable call, pins-layer call, and initial fetch) — currently:

```dart
    // Now that the style is loaded, camera animations will stick on iOS.
    _tryEnableLocationComponent(from: 'style-loaded');

    // Add pins layer to map
    _updatePinsLayer();

    // Initial bbox fetch for the starting viewport.
    _onCameraIdle();
```

with:

```dart
    // Now that the style is loaded, camera animations will stick on iOS.
    _tryEnableLocationComponent(from: 'style-loaded');

    // Resolve the water layer + add the land mask, THEN add pins and fetch —
    // so the heatmap (added when the first fetch returns) can anchor beneath
    // the mask/water.
    _initStaticMapLayers().then((_) {
      if (!mounted) return;
      _updatePinsLayer();
      _onCameraIdle();
    });
```

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/presentation/screens/map_screen.dart`
Expected: No errors.

- [ ] **Step 6: Manual smoke test (low zoom)**

Run on an Android emulator/device against staging data:

```bash
flutter run
```

Verify at country/regional zoom (zoom ~4–8) over TX/FL/PA:
- A teal density glow appears over populated metros (not red circles, not numbers).
- The glow does NOT bleed into the Gulf/Atlantic, Cuba, or Mexico — it stops at the coastline and border.
- Country/state labels and roads still render on top of the glow.
- Zoom INTO a border area (e.g. El Paso/Juárez): Mexico renders as normal basemap (the mask has faded out by metro zoom), not flat cream.

If the glow renders over the ocean, the water-id resolution or `belowLayerId` ordering is wrong — debug `getLayerIds()` output before continuing.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): clip heatmap to US land via water layer + land mask"
```

---

## Task 5: Fade mine/cached pins out at low zoom

Pins are a fixed 12px; at country zoom a personal pin is a sharp dot floating over a state. Drive pin (and label) visibility by a `circle-opacity`/`text-opacity` zoom ramp and delete the old cluster-presence visibility toggle.

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Add a zoom-opacity ramp to both circle layers**

In `_updatePinsLayer`, the `mine-pins-layer` and `cached-pins-layer` are created with `circleOpacity: 0.8` (around lines 419–451). For BOTH `addCircleLayer` calls, replace:

```dart
          circleOpacity: 0.8,
```

with:

```dart
          // Fade pins out at low zoom so the country/region view is pure
          // density glow; fade them in by metro zoom where users drop/find
          // them. Replaces the old cluster-presence visibility toggle.
          circleOpacity: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            10, 0.0,
            12, 0.8,
          ],
```

(There are two occurrences — apply to both. The surrounding `filter` on `isMine` differs between them; leave the filters unchanged.)

- [ ] **Step 2: Add a zoom-opacity ramp to both label layers**

For both `addSymbolLayer` calls that create `mine-pins-labels-layer` and `cached-pins-labels-layer` (around lines 457–508), add a `textOpacity` to each `SymbolLayerProperties(...)` (e.g. directly after the `textIgnorePlacement`/`textAllowOverlap` block, before the closing `)` of `SymbolLayerProperties`):

```dart
          textOpacity: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            11, 0.0,
            12.5, 1.0,
          ],
```

- [ ] **Step 3: Remove the `_applyCachedPinsVisibility` calls**

In `_updatePinsLayer`, remove the fast-path call (around line 364):

```dart
      if (_pinLayersCreated) {
        await _mapController!.setGeoJsonSource('pins-source', geojson);
        await _applyCachedPinsVisibility();
        return;
      }
```

becomes:

```dart
      if (_pinLayersCreated) {
        await _mapController!.setGeoJsonSource('pins-source', geojson);
        return;
      }
```

And remove the post-creation call (around line 510):

```dart
      await _applyCachedPinsVisibility();
      _pinLayersCreated = true;
```

becomes:

```dart
      _pinLayersCreated = true;
```

- [ ] **Step 4: Delete the `_applyCachedPinsVisibility` method**

Remove the entire `_applyCachedPinsVisibility` method (its doc comment + body, around lines 672–695).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/presentation/screens/map_screen.dart`
Expected: No errors and no "unused" warning for `_applyCachedPinsVisibility` (it's gone).

- [ ] **Step 6: Manual smoke test (zoom transition + mine pins)**

Run `flutter run`. While signed in with at least one of your own pins:
- At country/region zoom: no sharp pin dots float over states — only the glow.
- Zoom into a metro (zoom ~11–13): the glow dims/clears as individual green/yellow/red pins fade in; your own pins appear too.
- In a dense downtown, the glow persists a little longer until pins resolve (density fallback) — expected.

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): fade pins by zoom; drop cluster-presence visibility toggle"
```

---

## Task 6: Remove cluster tap routing and dead code

The heatmap is non-interactive — there are no cluster circles to tap. Remove the cluster tap branch and the now-unused `_onClusterTapped`, and fix the stale doc comment.

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Remove the cluster tap branch in `_onFeatureTapped`**

Remove this block at the top of `_onFeatureTapped` (around lines 225–232):

```dart
    // Cluster taps zoom in on the centroid; the resulting onCameraIdle
    // re-fetches the viewport so the user sees finer detail (either a
    // sub-cluster or individual pins).
    if (layerId == 'clusters-circle-layer' ||
        layerId == 'clusters-count-layer') {
      await _onClusterTapped(coordinates);
      return;
    }

```

- [ ] **Step 2: Delete the `_onClusterTapped` method**

Remove the entire `_onClusterTapped` method (its doc comment + body, around lines 312–322).

- [ ] **Step 3: Fix the `_onFeatureTapped` doc comment**

In the `_onFeatureTapped` doc comment, update the `layerId` line (around lines 215–216):

```dart
  /// - layerId: Layer ID (one of 'mine-pins-layer', 'cached-pins-layer',
  ///   'clusters-circle-layer', or 'clusters-count-layer')
```

to:

```dart
  /// - layerId: Layer ID (one of 'mine-pins-layer' or 'cached-pins-layer')
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/presentation/screens/map_screen.dart`
Expected: No errors, no unused-element warnings (`_onClusterTapped` is gone; `coordinates` is still used elsewhere in `_onFeatureTapped`).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "refactor(map): remove cluster tap routing (heatmap is non-interactive)"
```

---

## Task 7: Docs, full test suite, and device verification

**Files:**
- Modify: `docs/dev/CLUSTER_RENDERING.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Record the decision in CLUSTER_RENDERING.md**

At the top of `docs/dev/CLUSTER_RENDERING.md`, under the `**Status:**` line, add:

```markdown
> **UPDATE 2026-06-17:** Low-zoom rendering changed from Option B cluster
> bubbles to a **teal density heatmap clipped to US land** — see
> `docs/superpowers/specs/2026-06-17-heatmap-density-lowzoom-design.md`.
> Cluster circles, count labels, and tap-to-zoom were removed; the server
> `get_pins_in_view` cluster output now feeds a MapLibre heatmap layer
> (weighted by `count`), inserted beneath the basemap `Water` fill and a
> bundled non-US land mask. Mine/cached pins fade out at low zoom via a
> `circle-opacity` zoom ramp. The Option A/B/C analysis below is retained for
> historical context. A pixel-perfect glow→pins cross-fade and server-side
> grid-size tuning for a smoother glow remain deferred follow-ups.
```

- [ ] **Step 2: Update the CLAUDE.md status line**

In `CLAUDE.md`, in the `**Current Status:**` paragraph (under "Project Overview"), append this sentence at the end of the paragraph:

```markdown
Low-zoom map rendering replaced cluster bubbles with a US-land-clipped teal density heatmap (spec `docs/superpowers/specs/2026-06-17-heatmap-density-lowzoom-design.md`) ahead of Phase 7 prod rollout.
```

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, including the new `map_render_helpers_test.dart`. The existing cluster data-layer tests (`map_item_test.dart`, `viewport_pins_manager_test.dart`, `get_pins_in_view_row_test.dart`, `map_viewmodel_viewport_test.dart`) are unaffected — confirm they still pass.

- [ ] **Step 4: Full analyze + format**

Run:

```bash
flutter analyze
dart format lib/presentation/map/map_render_helpers.dart lib/presentation/screens/map_screen.dart test/presentation/map/map_render_helpers_test.dart
```

Expected: analyze reports no issues; format reports the files unchanged or formats them.

- [ ] **Step 5: Final device verification (Android)**

Run `flutter run` on an Android device/emulator against staging and confirm the full journey end to end:
- Country zoom → teal glow over TX/FL/PA, clipped to land (no ocean/Mexico/Cuba bleed), no numbers, no red blobs.
- Pinch in → glow hands off to green/yellow/red pins; your own pins appear at metro zoom, not before.
- Pan around the Gulf/Florida coast specifically to confirm no coastline bleed.
- Tapping the glow does nothing (non-interactive); tapping a resolved pin opens its dialog as before.

- [ ] **Step 6: Commit**

```bash
git add docs/dev/CLUSTER_RENDERING.md CLAUDE.md
git commit -m "docs(map): record heatmap low-zoom rendering decision"
```

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** §1 data flow → Tasks 2–3; §2 heatmap/color → Task 3; §3 ocean+foreign-land clip → Tasks 1, 4; §4 density-driven transition → Tasks 3, 5 (constant-zoom swap is a hard cut by design; smooth cross-fade deferred); §5 mine-pin fade → Task 5; §6 code-touched/removed → Tasks 3–7; §7 tests → Tasks 2, 7.
- **Deferred (not in this plan, per spec):** server grid-size tuning for a smoother glow, pixel-perfect cross-fade animation, mine pins contributing to the heatmap.
- **Type consistency:** layer/source ids are centralized as constants in `map_render_helpers.dart` (`kHeatmapSourceId`, `kHeatmapLayerId`, `kLandMaskSourceId`, `kLandMaskLayerId`); the heatmap updater is `_updateHeatmapLayer`; flags are `_heatmapLayerCreated`/`_isUpdatingHeatmap`/`_pendingHeatmapUpdate`/`_landMaskCreated`/`_waterLayerId`.
- **Risk to watch during impl:** the `belowLayerId` insertion order in Task 3/4 — the land mask must end up ABOVE the heatmap and BELOW water. Achieved by adding the mask first (below `Water`) and anchoring the heatmap below the mask (`kLandMaskLayerId`). Verify visually in Task 4 Step 6.
```
