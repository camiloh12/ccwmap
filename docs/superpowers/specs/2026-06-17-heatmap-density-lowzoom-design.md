# Low-Zoom Heatmap Density View Design

**Date:** 2026-06-17
**Status:** Draft — pending implementation plan via writing-plans
**Supersedes:** the cluster-bubble rendering decision in `docs/dev/CLUSTER_RENDERING.md` (Option B) at low zoom.

## Background

The pre-populate pilot (Phases 0–6, TX/FL/PA, ~23,825 system pins) made the low-zoom map ugly. At country/regional zoom the `get_pins_in_view` RPC aggregates pins into grid clusters, and the client renders each cluster as a status-colored circle whose radius scales with `count`. With thousands of pins concentrated in three states, adjacent cells produce large overlapping red circles with raw counts (2520, 1753, 1077…) — a mess of overlapping blobs that reads as one alarming red smear and conveys no useful information. See the 2026-06-17 screenshot that triggered this work.

Two root problems compound the look:

1. **Overlap + size:** grid cells are adjacent, centroids are close, radii are large and cap out, so circles pile up.
2. **All red:** clusters color by `dominant_status`, and almost every pre-populated pin is `NO_GUN` (red), so the entire zoomed-out map is red regardless of what the user can actually do anywhere.

This redesign is sequenced **before Phase 7 (prod rollout)** and pulls forward the spec's Phase 8 note ("revisit cluster rendering before total pin count crosses ~50k") — we move to a density visualization that scales *up* with data instead of degrading.

## Goal

At a glance, answer **"does this region have enough data that the app is useful if I travel there?"** — a coverage/presence signal, not a precise density readout. The owner explicitly does **not** want users judging exact regional density; the zoomed-out view exists mostly to reassure first-launch / prospective users that an area is populated, so an empty map (a hard zoom cutoff) is *excluded* because empty reads as "no data here."

## Approach (decided via brainstorming, 2026-06-17)

Replace the low-zoom cluster bubbles with a **teal density heatmap clipped to US land**, handing off to the existing green/yellow/red status pins as the user zooms into a specific place.

Decisions locked during the brainstorm:

| Decision | Choice | Rationale |
|---|---|---|
| Low-zoom treatment | **Heatmap density glow** (not refined cluster dots, not hard cutoff) | Smooth coverage glance; no overlap, no meaningless big numbers; looks *better* at 400k+ pins. |
| Horizon | **National-ready** | The ugliness only worsens with more pins; solve once. |
| Color ramp | **Cool teal** (`#0ea5a5` → `#2dd4bf` → transparent) | Map-native, neutral, clearly distinct from status green/yellow/red; App-Store-safe (not alarming, not red). |
| Semantic split | Low zoom shows **coverage** (teal density); high zoom shows **status** (green/yellow/red pins) | "How much data is here" and "how restrictive is each place" are different questions; don't conflate. |
| Land clipping | **Both** ocean clip and foreign-land clip, built now | Glow must not spill into ocean or neighboring countries. |
| Glow → pins transition | **Density-driven**, mutually exclusive per fetch, with a short opacity fade | Reuses the existing >2000-pins density fallback; dense downtowns hold the glow longer. |
| "Mine" pins at low zoom | **Fade out** with everything else (no always-visible special case) | Pins are fixed 12px; a sharp dot floating over a state amid soft glow looks out of place. |
| Cross-fade fidelity | Quick opacity fade for v1; pixel-perfect cross-fade is a follow-up | Owner-approved v1 scope. |

## Non-goals

- **No schema or RPC migration.** This is a client rendering change; the existing `get_pins_in_view` output is reused as-is. (Optional finer-grid tuning is deferred, not required.)
- **No change to high-zoom pin rendering, tap-to-edit, or the tiered sync model.**
- **No new server-side clustering algorithm.** The existing `ST_SnapToGrid` aggregation feeds the heatmap unchanged.
- **Pixel-perfect cross-fade animation** between glow and pins — deferred follow-up.
- **Mine pins contributing to the heatmap** — deferred; negligible at pilot scale where system pins blanket the region.

---

## §1 — Data flow (no migration)

`get_pins_in_view(sw_lat, sw_lng, ne_lat, ne_lng, zoom)` already returns one of two row types per fetch:

- **Cluster rows** (low zoom, or any viewport with >2000 candidate pins): `{ centroid_lat, centroid_lng, cluster_count, dominant_status, … }`.
- **Individual pin rows** (zoom ≥ 12 with ≤2000 pins in view): full pin fields.

The redesign maps these to two **mutually exclusive** client layers:

- **Cluster rows → heatmap points.** Each cluster centroid becomes a heatmap point weighted by `cluster_count`. `dominant_status` is ignored at low zoom (coverage, not status).
- **Individual pin rows → status-pin markers.** Unchanged from today.

Because the RPC returns exactly one type per fetch, the heatmap source and the cached-pins source are never both populated from the same response — the glow↔pins switch is automatic and density-driven. The existing `BboxRequestDebouncer` (500 ms) and `ViewportPinsManager` plumbing are reused.

Existing `MapItemCluster` is **repurposed** to carry `centroidLat/Lng` + `count` into the heatmap-feeding path (kept, not deleted). `dominant_status` remains on the model but is unused by the heatmap.

*(Optional deferred tuning: the low-zoom grid sizes in `008_provenance_and_view_rpc.sql` were chosen for circle clustering; a finer grid yields a smoother glow with more centroids. Not required for v1 — the Gaussian-blurred heatmap reads smoothly even from coarse cells.)*

---

## §2 — Heatmap layer & color

A single MapLibre **heatmap layer** sourced from the cluster centroids:

- **`heatmap-weight`** interpolated from `cluster_count` so a dense cell glows brighter than a sparse one (exact stops tuned during implementation).
- **`heatmap-color`** ramp, density 0 fully transparent so the basemap shows through:
  - `0.0` → `rgba(14,165,165,0)` (transparent)
  - low → light teal at low alpha (`#2dd4bf`)
  - high → deep teal (`#0ea5a5`)
- **`heatmap-radius`** and **`heatmap-intensity`** zoom-interpolated (larger radius at low zoom for a regional glow; tuned in implementation).
- **`heatmap-opacity`** ~1 at low zoom. A zoom ramp toward 0 at high zoom is redundant given mutual exclusivity (the heatmap source is empty when the RPC returns individual pins) but may be applied as belt-and-suspenders.

Status colors (`#4CAF50` / `#FFC107` / `#F44336`) remain reserved strictly for individual pin markers.

---

## §3 — Clipping the glow to US land

Two complementary mechanisms keep the glow off the ocean and off foreign land.

### Ocean clip (free, exact)

Insert the heatmap layer **beneath the basemap's water fill layer** rather than on top. The basemap (`streets-v4`) renders water as a fill over its background; placing the heatmap below it means water repaints over any glow that bleeds past the shoreline. The glow is therefore clipped along the **true** coastline — including the Great Lakes, bays, and rivers — with no bundled asset.

Implementation note: the exact water layer id must be resolved from the live style at style-load (enumerate layer ids; find the water fill), because hardcoding a `streets-v4` internal id is brittle. The heatmap is inserted with `belowLayerId` = that water layer (or a stable anchor just below it).

### Foreign-land clip (bundled asset)

A simplified **Natural Earth Admin-0 "countries minus US"** polygon, dissolved and simplified to ~50–150 KB, bundled at `assets/geo/world_minus_us.geojson`. Rendered as a **fill layer colored to match the basemap land**, placed above the heatmap but below water, boundaries, roads, and labels. This covers glow bleeding into Mexico/Canada/Cuba while leaving foreign country labels and roads visible on top.

### Layer stack (low → high)

```
basemap background + land/landcover fills
heatmap (density glow)
foreign-land mask fill        ← clips international borders
basemap water fill            ← clips coastline
basemap boundaries / roads / labels
status-pin markers (high zoom)
location puck + app UI
```

### Basemap fallback

When no MapTiler key is configured the app falls back to MapLibre demotiles (dev/testing only), whose layer ids differ. The clip degrades gracefully there — if the water layer can't be resolved, the heatmap renders without the ocean clip (acceptable for the dev-only fallback). The foreign-land mask still applies.

---

## §4 — Glow → pins transition

The transition is **density-driven**, a direct consequence of §1's mutual exclusivity:

- Viewport holds >2000 pins (or low zoom) → RPC returns clusters → heatmap glows, no markers.
- Viewport holds ≤2000 pins at zoom ≥ 12 → RPC returns individual pins → status markers render, no glow.

So a dense downtown keeps glowing until the user zooms in far enough that the viewport holds <2000 pins, then resolves to markers — "downtowns hold the glow a bit longer," with no hard zoom threshold to tune.

**v1 polish:** apply a short opacity fade when a fetch swaps the data type, so the glow doesn't hard-cut to markers. A pixel-perfect cross-fade (rendering a transient heatmap from the individual points while markers fade in) is a **deferred follow-up** if the fade feels abrupt in device testing.

**Tap behavior:** the heatmap is **non-interactive** — there is no longer a tap-a-cluster-to-zoom affordance; users pinch-zoom to resolve detail. (Optional future nicety: tap the glow to ease the camera toward that point.) High-zoom pin taps (open edit dialog) are unchanged.

---

## §5 — "Mine" and cached pins at low zoom

Pin markers are a fixed 12 px on screen (`circleRadius: 12.0`) — they do not scale with zoom. A personal pin at country zoom is therefore a crisp dot floating over a whole state, visually clashing with the soft glow.

Fix: apply a **`circle-opacity` zoom ramp** to both the `mine-pins-layer` and `cached-pins-layer` — opacity 0 below ~z10–11, ramping to the current 0.8 by ~z12. Country/regional zoom is then pure, consistent glow; pins fade back in at metro zoom, which is where users actually drop and look for them (you are always zoomed in when dropping a pin).

This **replaces** the existing `_applyCachedPinsVisibility` logic (which hid cached pins when cluster bubbles were present). Visibility is now driven by the zoom-opacity ramp plus the data-driven mutual exclusivity, so the explicit show/hide toggle is removed.

Mine pins are not fed into the heatmap in v1 (negligible at pilot scale; deferred).

---

## §6 — Code touched

- **`lib/presentation/screens/map_screen.dart`**
  - Replace `_updateClustersLayer`'s circle + count layers (`clusters-circle-layer`, `clusters-count-layer`) with a heatmap layer fed by cluster centroids weighted by `count`.
  - Insert the heatmap below the resolved basemap water layer; add the foreign-land mask fill above it.
  - Remove cluster tap-to-zoom routing for the cluster layers in `_onFeatureTapped`.
  - Remove `_applyCachedPinsVisibility`; add `circle-opacity` zoom ramps to `mine-pins-layer` and `cached-pins-layer`.
  - Resolve the water layer id from the live style at style-load.
- **`lib/domain/models/map_item.dart`** — `MapItemCluster` repurposed to feed the heatmap; `dominantStatus` retained but unused at low zoom.
- **`assets/geo/world_minus_us.geojson`** + **`pubspec.yaml`** — bundle the simplified foreign-land polygon.
- **`docs/dev/CLUSTER_RENDERING.md`** — record this heatmap decision as superseding Option B at low zoom; note the deferred smooth cross-fade and grid-tuning follow-ups.

---

## §7 — Testing

- **Transform tests:** cluster rows → weighted heatmap GeoJSON FeatureCollection (centroid coordinates + `count` weight); individual rows → pin features unchanged.
- **Zoom-opacity logic:** mine/cached pin opacity ramp produces 0 below the low-zoom threshold and full opacity at high zoom.
- **Asset load:** `world_minus_us.geojson` parses and loads as a fill source.
- **Removed assertions:** delete tests asserting cluster-circle radii / count-label rendering.
- **Smoke:** map renders heatmap at low zoom and pins at high zoom on Android (per the project's per-SP Android verification cadence; iOS deferred to end-of-branch).
- Mappers/models keep 100% coverage per `docs/dev/TESTING_GUIDELINES.md`.

---

## §8 — Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Water layer id not resolvable on a future MapTiler style revision | Low | Medium (ocean clip silently off) | Resolve at runtime by scanning layer ids; log if not found; foreign-land mask still applies; coastline glow is a soft degrade, not a crash. |
| Coarse low-zoom grid yields blobby glow | Low | Low | Gaussian blur smooths it; finer grid available as deferred tuning. |
| Opacity-fade swap feels abrupt on device | Medium | Low | v1 accepts it; smooth cross-fade is a scoped follow-up. |
| Foreign-land polygon too coarse near border metros (San Diego/El Paso/Detroit/Buffalo) at national scale | Medium (national) | Low | Use 1:50m (not 1:110m) Natural Earth; revisit fidelity before national waves. |
| Demotiles fallback can't clip | Low | Low (dev-only) | Degrade gracefully; production always has a MapTiler key. |

## References

- `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` §5 (sync model), §8 (Phase 8 cluster-rendering revisit trigger this pulls forward).
- `docs/dev/CLUSTER_RENDERING.md` — the Option A/B/C analysis this supersedes at low zoom.
- `supabase/migrations/008_provenance_and_view_rpc.sql` — the `get_pins_in_view` RPC reused unchanged.
- MapLibre heatmap layer: https://maplibre.org/maplibre-style-spec/layers/#heatmap
- Natural Earth Admin-0 countries (1:50m): https://www.naturalearthdata.com/downloads/50m-cultural-vectors/
