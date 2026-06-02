# Phase 4 — Pilot Wave 1: Federal Floor

**Date:** 2026-06-02
**Status:** Draft — pending implementation plan via writing-plans
**Parent spec:** [`2026-05-10-pre-populate-pins-design.md`](2026-05-10-pre-populate-pins-design.md) §8, phase 4

## Background

Phases 0–3 of the pre-populate-pins project are complete: the provenance schema
(migration `008`) is in production, the viewport sync model (`MyPinsSync` +
`ViewportPinsManager`) shipped in v0.6.0, the importer skeleton runs HIFLD
courthouses end-to-end, and the state-law table is seeded for TX/FL/PA + the
federal-uniform `US` cells.

Phase 4 ships the **federal floor**: the categorically-prohibited federal
locations that every CCW map must show. Per the parent spec §8 the sources are
HIFLD courthouses (already built in Phase 2), **GSA federal property**, and
**HIFLD military installations**, scoped to TX/FL/PA (~3–5k pins).

This is the first phase where *more than one source runs in a single pipeline
invocation*, which makes it the natural home for the cross-source dedup that the
parent spec §4 describes but Phase 2 left as a pass-through stub. GSA FRPP lists
many federal courthouses that also appear in HIFLD courts; without dedup those
ship twice (once as `STATE_LOCAL_GOVT`, once as `FEDERAL_PROPERTY`), violating
the parent spec's `<1%` cross-source duplicate success criterion.

## Scope decisions (settled in brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| How far this round lands | **Staging apply only** | Matches the "real prod import deferred until app release is proven" memory. Prod apply becomes its own gated step later. |
| GSA geocoding | **US Census batch geocoder** | Free, no API key, public-domain, US-only — clean license/posture fit for federal data; best solo-dev sustainability. |
| ODbL attribution UI | **Deferred to Phase 6** | No `source='osm'` pin exists until Phase 6; wiring the UI now means it ships dormant and untestable. |
| Pipeline structure | **Multi-source + real cross-source dedup** | The shape §4 already describes; reusable for Phases 5–6; avoids knowingly shipping duplicate federal courthouses even to staging. |

**In scope:** `sources/hifld_military.py`, `sources/gsa.py`, `geo/census_geocode.py`,
a real `stages/dedup.py`, a multi-source `run_pipeline`, CLI/config/report
updates, tests, docs.

**Out of scope:** prod apply; any Flutter change (ODbL/attribution UI, pin-dialog
provenance badge); migration `009` (none needed — `008` already added every
provenance column the floor writes); Overpass coordinate refinement
(`refine_coords` stays pass-through — courts/military carry precise coords, GSA
gets Census address-centroids, both adequate for the floor); state widening
beyond TX/FL/PA.

## Constraints

- No schema migration. The federal floor writes only columns added by `008`
  (`source`, `source_external_id`, `source_dataset_version`, `imported_at`,
  `confidence`, `legal_citation`, `legal_citation_verified_date`).
- TX/FL/PA only, via the existing `importer/tests/fixtures/states_sample.geojson`
  boundary fixture. No full-50-state file required at this scope.
- All new modules/stages 100% unit-tested against frozen fixtures per
  `docs/dev/TESTING_GUIDELINES.md`.
- The non-negotiable rule from parent spec §7 holds: **apply never targets prod
  from a developer machine.** This round, apply targets staging only.
- The importer reads its service-role key from
  `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`; staging applies use
  `STAGING_SUPABASE_SERVICE_ROLE_KEY` (GitHub Actions secret) or the operator's
  local equivalent. MCP is bound to prod, so the staging write is operator-run,
  not agent-run.

## Success criteria

- `python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts,gsa,hifld_military --project-ref staging`
  produces a coherent combined report: per-source candidate counts, cross-source
  dedup drops by source pair, GSA geocode match/miss counts.
- Apply mode against **staging** inserts federal-floor pins with correct
  `source`, `restriction_tag`, `confidence`, and `legal_citation`, and is
  idempotent (a second run is all-SKIP).
- Federal courthouses appearing in both GSA and HIFLD courts resolve to a single
  pin (GSA wins per priority); cross-source duplicate rate `<1%`.
- User-created pins (`source='user'`) are never clobbered by dedup.
- Full importer test suite stays green.

---

## §1 — New source modules

### `sources/hifld_military.py`

HIFLD Military Installations dataset on the ArcGIS Hub (GeoJSON), fetched with
the same `httpx` + `follow_redirects` + on-disk cache pattern as
`hifld_courts.py`. The pinned hub URL lives in `config.yaml`; signed blob URLs
are never hard-pinned.

Key difference from courts: features are **polygons** (`Polygon` /
`MultiPolygon`), not points. The source computes the centroid with `shapely`
(already a dependency) and emits `coord_quality=BUILDING_POLYGON`. Category is
`FEDERAL_PROPERTY`. `external_id` falls back through the dataset's stable GUID
field(s) (`GLOBALID` / `OBJECTID`), mirroring the courts `_external_id` helper.
A frozen polygon fixture drives the tests.

State assignment uses the same `StateLocator` point-in-polygon on the centroid;
`last_skip_counts` tracks `missing_geometry`, `state_pip_miss`, `filtered_out`,
`missing_external_id`, `missing_name`.

### `geo/census_geocode.py`

A thin client over the **US Census Geocoding Services batch API**
(`https://geocoding.geo.census.gov/geocoder/locations/addressbatch`,
`benchmark=Public_AR_Current`). No API key. Accepts a list of
`(id, street, city, state, zip)` records, POSTs them as the CSV the API expects
(batches ≤ 10k), parses the returned match status + coordinates, and returns a
`{id: (lat, lng)}` map. Unmatched ids are reported, not coordinate-faked.

Results cache to `data/sources/gsa/geocoded.json` keyed by a hash of the
normalized address, so re-runs skip already-geocoded rows. `--refetch` busts the
cache. Tested with `pytest-httpx` mocking the batch response.

### `sources/gsa.py`

GSA FRPP public dataset (CSV; URL pinned in `config.yaml` at pre-flight). The
source:

1. `fetch()` downloads + caches the CSV (same cache discipline as HIFLD).
2. `iter_candidates()` filters rows to the requested states on the dataset's own
   state column **before geocoding** (so only pilot rows hit the Census API),
   builds address records, calls `census_geocode`, and yields one Candidate per
   successfully-geocoded row with `coord_quality=ADDRESS_CENTROID`,
   `category=FEDERAL_PROPERTY`, `external_id` = FRPP Real Property Unique
   Identifier.
3. Skip counters: `filtered_out`, `missing_address`, `geocode_miss`,
   `missing_external_id`, `missing_name`.

Frozen fixture = a handful of real FRPP rows + a mocked Census response.

---

## §2 — Cross-source dedup (`stages/dedup.py`)

Replaces the Phase 2 pass-through. Operates on `list[ClassifiedCandidate]` (dedup
runs after `apply_state_law` in the pipeline) plus the existing `source='user'`
pins fetched from Supabase.

- **Index:** `shapely.STRtree` over candidate + user-pin points (no separate
  `rtree` dep — shapely 2.0 ships STRtree).
- **Match rule (spec §4):** two records match when they are within **100 m** AND
  `rapidfuzz.fuzz.token_set_ratio(name_a, name_b) ≥ 70`. On a match the
  lower-priority record is dropped.
- **Priority (highest first):** `user` > `nces` > `ipeds` > `faa` > `gsa` >
  `hifld_courts` = `hifld_hospitals` = `hifld_military` > `osm`. User pins are
  never dropped; a candidate matching a user pin is dropped.
- **Within-source duplicates** (same `(source, external_id)`): the second
  occurrence is logged as an error and dropped.
- Emits dedup stats: total dropped, and drops bucketed by `(winner_source,
  loser_source)` for the report.

The 100 m test uses an equirectangular metric approximation around each point's
latitude (adequate at CONUS latitudes and the 100 m scale); no projection
library needed.

---

## §3 — Pipeline, CLI, config, reports

### `run_pipeline(sources: list[Source], ...)`

Refactored from single-source. Flow:

1. For each source: `fetch` → `iter_candidates(state_filter)` → `normalize` →
   `refine_coords` (pass-through) → `apply_state_law`, accumulating
   `ClassifiedCandidate`s.
2. Fetch existing `source='user'` pins once via the Supabase client.
3. **One** combined `dedup` pass over all classified candidates + user pins.
4. Diff: group survivors by source, query existing rows by
   `(source, external_id)` per source, classify INSERT/UPDATE/SKIP, mark
   per-source orphans.
5. Apply per source (no-op in dry-run).
6. Return one combined `PipelineResult` carrying per-source breakdowns + dedup
   + geocode stats.

### CLI

- `SUPPORTED_SOURCES = ('hifld_courts', 'gsa', 'hifld_military')`.
- Replace the hardcoded `if source_name != 'hifld_courts'` block with a small
  source-factory registry mapping name → constructor (reads cache_dir /
  dataset_version / url from `config.yaml`).
- Build all requested sources and pass the list to `run_pipeline`.
- Write **one** combined report (`report-<run_id>.md` + `.json`), fixing the
  current per-source overwrite.

### `config.yaml`

Add `gsa` and `hifld_military` blocks under `sources:` (cache_dir,
dataset_version, pinned URL), matching the existing `hifld_courts` shape.

### Reports (`reports/markdown.py`, `reports/json_report.py`)

Extend `PipelineResult` + renderers to show: per-source candidate /
classified / dropped counts, cross-source dedup drops by source pair, and GSA
geocode match/miss counts. Existing single-source reports stay valid (one
source in the list).

---

## §4 — Testing, docs, dependencies

### Tests

- `tests/sources/test_hifld_military.py` — frozen polygon fixture; centroid
  extraction; category/coord_quality; skip counters.
- `tests/sources/test_gsa.py` — frozen FRPP rows + mocked Census response;
  state pre-filter; geocode-miss drop; external_id.
- `tests/geo/test_census_geocode.py` — mocked httpx batch response; cache
  hit/miss; unmatched handling.
- `tests/stages/test_dedup.py` — cross-source priority resolution; user-pin
  protection; 100 m and 0.7 boundary cases; within-source duplicate drop.
- `tests/test_pipeline.py` — extend with a multi-source run asserting combined
  result + dedup interaction.
- `tests/test_cli.py` — extend for the new sources + combined report.

### Docs

- `docs/importer/SOURCES.md` — mark GSA FRPP + HIFLD Military as Phase 4 (built);
  correct the stale "NCES = Phase 4" row to Phase 5; add Census geocoder note.
- `docs/importer/` — dataset URLs, FRPP caveats, Census geocoder usage.
- `docs/superpowers/plans/2026-06-02-phase4-federal-floor-plan.md` — the
  implementation plan (written next via writing-plans).
- `CLAUDE.md` status line bumped when the phase lands.

### Dependencies

- `pyproject.toml`: add `rapidfuzz`. `shapely` already present; no `rtree`
  needed (shapely STRtree).

### Running (operator step)

The agent builds + tests everything locally. The **staging dry-run then apply is
operator-run** — the user runs `importer-apply` (workflow_dispatch) or the local
command with `STAGING_SUPABASE_SERVICE_ROLE_KEY`, since MCP is bound to prod. The
dry-run report is reviewed together before any apply.

---

## §5 — Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GSA FRPP public data omits/redacts federal locations or has dirty addresses | Medium–High | Medium | Dry-run report exposes TX/FL/PA counts + geocode-miss rate; if poor, drop GSA to a focused follow-up without touching courts+military. |
| Census geocoder low match rate on government addresses | Medium | Low–Medium | Count misses; keep unmatched rows out (no fabricated coords); cache successes. |
| Dedup threshold (100 m / 0.7) mis-tuned for federal venues | Low–Medium | Low | Staging dry-run validates against real overlap; thresholds are constants, easy to tune before any prod apply. |
| Military polygons with odd geometry (MultiPolygon, holes) yield bad centroids | Low | Low | `shapely` centroid handles MultiPolygon; fixture covers a MultiPolygon case; out-of-state centroids fail PIP and are skipped. |

## References

- Parent spec: `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` §1, §3, §4, §8.
- Phase 2 plan: `docs/superpowers/plans/2026-05-24-pre-populate-pins-phase-2.md`.
- HIFLD Open: https://hifld-geoplatform.opendata.arcgis.com/
- GSA FRPP: https://www.gsa.gov/policy-regulations/policy/real-property-policy/asset-management/federal-real-property/federal-real-property-profile-frpp
- US Census Geocoder: https://geocoding.geo.census.gov/geocoder/
