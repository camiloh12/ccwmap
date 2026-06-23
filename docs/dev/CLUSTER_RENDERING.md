# Cluster rendering: approach, alternatives, and revisit triggers

**Status:** Option B implemented in Phase 1 (commit `fbb3724` + follow-up),
**refined 2026-06-19** on `feature/cluster-bubbles` — uniform blue bubbles,
small capped radius, abbreviated counts (see "2026-06-19 refinement" below).
A low-zoom density-**heatmap** variant was explored and **parked** (it crashed
Android — see that section). Last updated 2026-06-19.

This note captures the three viable approaches to rendering pins and
clusters across zoom levels, the trade-offs that led us to Option B for
the pilot ship, and the conditions under which we should revisit each.

## Context

CCW Map ships a tiered sync model (see spec §5):

- **Mine pins** — full bidirectional sync, never cluster; rendered as
  individual dots that are hidden at cluster zoom (in step with the cached
  pins) so they don't linger over the bubbles on zoom-out — see the
  rendering section below.
- **Cached non-mine pins** — fetched by viewport bbox, LRU-evicted.
- **Everywhere else** — fetched on demand at the current zoom.

At low zoom the server returns *clusters* (server-side `ST_SnapToGrid`
aggregation via the `get_pins_in_view` RPC, with the centroid set to
the mean of the constituent pins). At high zoom it returns individual
pins. The client must avoid double-rendering pins that are simultaneously
shown as members of a cluster — that was the visual bug surfaced by
Phase 1 Task 18 staging verification.

## Option A — Hard zoom cutoff: render nothing below zoom N

**Idea.** Below zoom ~10, the map is blank (or shows only a heatmap /
density gradient). At zoom ≥ N, individual pins render. No
server-side clustering at all.

**Pros.**
- Simplest possible code: delete the RPC's cluster branch entirely.
- No double-render is possible because there is nothing to double-render.
- Honest about the use case: country-zoom doesn't help anyone decide
  whether to carry into a specific courthouse.

**Cons.**
- First-launch view feels broken: the user opens the app, sees an
  empty map, doesn't know whether the app has data.
- Loses the "see total coverage" demo value of pre-populated data —
  especially weak once Phase 4+ adds 100k+ pins that we *want* to
  show off at country zoom.
- Marketing screenshots and App Store assets look thinner.

**When to revisit.** If post-pilot user feedback shows that the
country-zoom view confuses more users than it informs, or if cluster
rendering keeps producing visual artifacts that are expensive to fix.
A heatmap overlay at low zoom is a cheap middle ground (`addHeatmapLayer`
is supported by `maplibre_gl` 0.24.1 — see `references/copilot-tools.md`).

## Option B — Server-side clusters + split pins layer (chosen)

**Idea.** Server-side clustering as today (centroid = AVG of
constituent pins). The client splits its pin layer into two layers
sourced from the same GeoJSON via filter expressions:

Both individual-pin layers are governed by `individualPinsVisible(zoom,
hasClusters)` (`lib/presentation/map/pin_visibility.dart`): visible only at
zoom ≥ `kClusterCutoverZoom` (12) **and** when `viewportClusters` is empty. The
zoom term is load-bearing — see "sparse viewports" below.

- `mine-pins-layer` — features where `isMine == true`. Hidden (whole-layer
  visibility) below the cutover or when clusters are present, in lockstep with
  the cached pins. The RPC excludes my pins from its clusters (they sync via
  MyPinsSync), so hiding them isn't about double-render — it's so the user's
  own pins vanish at the cluster cutover instead of lingering as lone dots over
  the bubbles on zoom-out. Toggling visibility (not fill opacity) also drops the
  white circle stroke — a fill-opacity ramp left the ring drawn at low zoom.
- `cached-pins-layer` — features where `isMine == false`. Hidden below the
  cutover or when clusters are present.

**Sparse viewports (why the zoom term matters).** `get_pins_in_view` returns no
cluster rows when the bbox holds no *other-user* pins — prod before the data
import, or any region containing only the caller's own pins. An earlier version
gated visibility on cluster presence alone, so in those viewports the individual
pins never hid and lingered at continental zoom (regression from commit
`a906f72`, which dropped the zoom-keyed fade added in `1f698bf`). Gating on
`_lastIdleZoom` restores the cutover behavior while keeping the hard whole-layer
toggle (no lingering stroke ring). `_applyIndividualPinsVisibility` is also
re-run from `_onCameraIdle`, so the hide happens on the zoom gesture rather than
waiting for the debounced bbox fetch.

Cluster rendering (refined 2026-06-19 — see that section below):

- Bubbles are **uniform blue** (`#2563EB`), not colored by dominant
  status. Most pre-populated pins are `NO_GUN`, so status coloring made
  the whole zoomed-out map a red smear; blue reads as "zoom in for
  detail" and stays distinct from the green/yellow/red individual pins.
- Radius is **small and capped** (~7 px at count 1, plateauing ~24 px),
  so dense low-zoom views no longer merge into an overlapping blob.
- Count `≥ 5` → shows an **abbreviated** count label (`4.5k`, `23k`,
  `1.5M`) via `abbreviateCount` (`lib/presentation/map/cluster_label.dart`,
  unit-tested). Count `< 5` → small unlabeled blue dot.

**Pros.**
- Eliminates double-render (cached pins are hidden when clusters cover
  the viewport).
- The user's own pins read clearly at metro zoom (the "I just dropped a
  pin" loop) but disappear in step with the cached pins on zoom-out, so the
  country/region view collapses to clean cluster bubbles instead of leaving
  lone dots scattered on top.
- Single server response type (always cluster rows) — simpler RPC
  surface, simpler client parser path.
- No grid artifacts (AVG centroid stays from prior fix).
- "Cluster of 1" visually reads as a pin instead of a fake cluster bubble.

**Cons.**
- Small "single-pin clusters" still tap-to-zoom rather than tap-to-open
  the pin — slightly surprising UX but consistent: any cluster tap zooms
  in, and at zoom ≥ 12 individual pins take over.
- Requires the split-layer plumbing in the client; not free.

**When to revisit.**
- If the "single-pin cluster" tap UX becomes a complaint, special-case
  cnt=1 clusters to open the pin instead of zooming in.

## Option C — Client-side Supercluster (Airbnb / Uber pattern)

**Idea.** Replace server-side clustering with `MapLibre`'s built-in
`cluster: true` source config (powered by the Supercluster algorithm).
The server returns up to ~2000 raw pin points for the viewport. The
client passes them to a clustered GeoJSON source. MapLibre auto-renders
clusters or pins based on the current zoom, with smooth split/merge
animations.

**Pros.**
- Industry-standard look and feel — what Airbnb, Uber, Google Maps for
  places all use under the hood.
- Smooth zoom-driven cluster transitions out of the box (animated
  split/merge, no flicker, no 500ms gap).
- Significantly less server code: the RPC degenerates to "give me the
  pins in this bbox, up to N."
- Eliminates the entire pin-vs-cluster heterogeneous-response design
  in `GetPinsInViewRow` and `MapItem`.

**Cons.**
- 2000-point ceiling per viewport is a sample, not the dataset, at
  Phase 4+ scale (~100k+ pins nationally). Country zoom would silently
  underrepresent density.
- Requires a *hybrid* to work correctly: server clusters at zoom < 8
  (so total counts reflect the full dataset), client Supercluster at
  zoom ≥ 8 (where bbox is small enough that 2000 pins is the truth).
  That hybrid is a real architectural change.
- The `maplibre_gl` Dart binding (0.24.1) supports the source-level
  cluster API but not all of Supercluster's tuning knobs. Verify before
  committing.

**When to revisit.** This is the right approach **before national rollout
in Phase 8+**, specifically once total pin count crosses ~50k–100k and
the cluster RPC's `ST_SnapToGrid` aggregation starts feeling slow or
visually janky on the client. Mid-pilot is too early; mid-national is
too late. The decision point is whatever ships first between:

1. The first reported "cluster transitions are choppy" issue from a
   real user post-pilot, OR
2. Total pin count crossing ~50k.

At that point, expect ~2 weeks of work to implement the hybrid and
~1 week of UX tuning. See spec §8 phase 8+.

## Decision

Option B is implemented for the pilot. It is the smallest change that
fixes both visual problems (lingering cached pins on zoom-out, and
fake "cluster of 1" bubbles) without changing the sync architecture
or RPC surface. Option C is deferred to Phase 8+ as referenced from
the spec's rollout plan.

If the visual issues recur in a way Option B can't easily resolve, jump
straight to Option C rather than iterating further on B.

## 2026-06-19 — heatmap variant explored and parked, Option B refined

The pre-populate data (~23,825 pins concentrated in TX/FL/PA) made the
original Option B bubbles ugly at country zoom for two reasons: (1) adjacent
grid cells with large count-scaled radii **overlapped into a blob**, and
(2) bubbles colored by `dominant_status` were **almost all red** (most
pre-populated pins are `NO_GUN`), reading as one alarming smear.

The "heatmap overlay" middle ground (floated under Option A above) was built
and tested on-device, then parked:

- A **native MapLibre heatmap layer** (`addHeatmapLayer`) SIGSEGVs the Android
  TextureView render thread on zoom (offscreen render pass; matches unfixed
  upstream maplibre-react-native#954). It can't ship on Android with
  `maplibre_gl` 0.24.1, and upgrading is blocked by an unverified iOS-18 Metal
  regression.
- A crash-free **blurred circle "glow"** replacement was then tried and set
  aside — the owner preferred discrete, readable bubbles over a glow.

Both variants live on the `feature/heatmap-lowzoom` branch in case we revisit.

The shipped answer **refines Option B** to fix the two root problems directly:
**uniform blue** (kills the red smear) and a **small capped radius** (kills the
blob), with **abbreviated counts** so the number — not the size — conveys
magnitude. Implemented in `_updateClustersLayer` (`map_screen.dart`) +
`abbreviateCount` (`lib/presentation/map/cluster_label.dart`).
