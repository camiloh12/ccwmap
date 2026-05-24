# Pre-Populate Pins Design

**Date:** 2026-05-10
**Status:** Draft — pending implementation plan via writing-plans

## Background

The CCW Map app currently relies entirely on user contribution: every pin in the database was added by a user. As of this design's drafting there are 199 pins in production. The cold-start problem is real — a new user opens the app and sees almost nothing useful for their location. Posted! (the dominant incumbent per the May 2026 competitive landscape research) ships with ~31k pre-existing pins; users compare us against that.

This project pre-populates the database with a high-confidence baseline of pins drawn from public-domain US government datasets and OpenStreetMap, classified per a maintained state-by-state legal lookup table. The goal is to bootstrap utility (any user opens the app to a useful map), establish a legal floor (every federally-mandated NO_GUN location is on the map), and approach competitive data depth — without abandoning the crowd-sourced model that lets users refine and correct the data.

Pre-population introduces architectural pressure that the current sync model wasn't designed for. The existing offline-first pattern (every pin in local DB on every device) does not scale beyond hundreds of pins. This spec accordingly redefines offline-first along a tier boundary: *your* pins remain fully local; everything else is fetched on-demand based on map viewport.

## Scope

This spec covers the pilot ship: TX + FL + PA only, all source datasets, all 10 restriction-tag categories. The pipeline, schema, sync model, and tooling built here apply unchanged to subsequent national rollout, which is sequenced after pilot validation as a categorical wave (federal → K-12 → airports + colleges → OSM long-tail).

**In scope:**

- Schema additions for pin provenance, source tracking, and idempotent re-import safety.
- A standalone Python importer (separate from the Flutter codebase, same monorepo) that reads source datasets, applies state-law classification, dedupes, and writes via Supabase service-role.
- Source ingestion modules for: NCES (K-12), IPEDS (colleges), FAA NPIAS (airports), GSA FRPP (federal property), HIFLD (courthouses, hospitals, military), OSM (long tail via Overpass).
- A maintained state-law lookup table at `data/state_laws/states.yaml` covering the pilot states × all 10 categories plus federal-uniform rows.
- A new sync model splitting pins into "mine" (full sync, offline-first) and "everything else" (bbox-on-demand with LRU cache). Server-side `get_pins_in_view` RPC with PostGIS-backed spatial query and grid-based clustering at low zoom.
- ODbL compliance pipeline: in-app attribution, per-pin source links for OSM data, periodic public derived-database dump.
- Observability: per-import-run reports, daily database health-check cron, server-side rate limiting on DELETE per user.
- A staging Supabase project (separate free-tier project) so importer and migration changes are validated before they touch production.

**Out of scope (explicitly deferred):**

- **Pre-populating ALLOWED (green) pins** — places where carry is affirmatively permitted (gun shops, ranges, pro-2A businesses). Different data sources, legal posture, and UX implications. Deferred to a separate brainstorming session.
- **PRIVATE_PROPERTY pin inference** — by definition the owner's posted decision is the legal trigger; we cannot know that from external data. Exception: OSM venues with explicit `access:firearms=no` tags are ingested with attribution.
- **National rollout** — pilot must validate the pipeline first. National waves are a separate project per the rollout plan in §8.
- **System-tier RLS pin protection** — pre-populated pins remain user-deletable per the existing crowd-sourced cleanup model. Manual mass-deletion is impractical (4 taps per pin); scripted abuse is mitigated by server-side rate limiting in §7. Provenance + idempotent re-import handle the data-integrity case.
- **Moderation/admin UI for pre-populated pins** — corrections go through user edits like any other pin. The importer is the only writer.
- **Persistent web storage** — under the new bbox sync model, web's in-memory SQLite is acceptable. Migrating Drift web to IndexedDB-backed storage is a defensible follow-up but not required by this work.
- **Sentry/telemetry on the app side** — recommended as a follow-up; absence does not block pilot but means app-side errors are invisible to us.

## Constraints

- Solo-dev sustainability — the importer must be small enough to maintain alongside the Flutter app indefinitely.
- Apple App Store firearms policy — framing leans "legal compliance / safety," never politicized. Pre-asserting NO_GUN status with citations strengthens this posture.
- Existing offline-first pattern is preserved for *user-created* pins. Bbox-on-demand applies only to pins not created by the current user.
- Schema migrations bump `AppDatabase.schemaVersion` in `lib/data/database/database.dart` and add an `onUpgrade` branch. Supabase migrations in `supabase/migrations/` follow the existing numbered convention (next is `008`).
- All new domain models, mappers, and validators must be 100% unit-tested per `docs/dev/TESTING_GUIDELINES.md`.
- ODbL share-alike obligation, accepted as the cost of OSM inclusion: in-app attribution + per-pin source links + public derived-DB dump.

## Success criteria

- Pilot ships with ~25-50k pins across TX + FL + PA without first-launch sync regressions on Android, iOS, or web.
- Cross-source duplicate rate < 1% (same physical venue appearing twice from different sources).
- Coordinate accuracy ≥ 95% of pins within 100m of the actual venue centroid.
- Re-running the importer with refreshed source data does not resurrect user-deleted pins or overwrite user-edited fields.
- ODbL compliance verified: attribution surfaced in-app, derived database dump publicly accessible.
- Staging environment used for every importer run before any production apply.

---

## §1 — Sources, classification, and the state-law lookup table

### Sources for pilot

| Source | Coverage | License | Has lat/lng? | Module |
|---|---|---|---|---|
| NCES (Common Core / PSS) | Public + private K-12 schools | Public domain (US Gov) | Yes | `importer/sources/nces.py` |
| IPEDS | Colleges and universities | Public domain (US Gov) | Yes | `importer/sources/ipeds.py` |
| FAA NPIAS | Public-use airports | Public domain (US Gov) | Yes (airport reference point) | `importer/sources/faa.py` |
| GSA FRPP | Federal owned/leased property | Public domain (US Gov) | Address-only — must geocode | `importer/sources/gsa.py` |
| HIFLD courthouses | Federal/state/local courthouses | Public domain (DHS open data) | Yes | `importer/sources/hifld_courts.py` |
| HIFLD hospitals | Hospitals | Public domain | Yes | `importer/sources/hifld_hospitals.py` |
| HIFLD military | Military installations | Public domain | Yes | `importer/sources/hifld_military.py` |
| OSM (via Overpass) | Bars, places of worship, sports venues, healthcare-not-in-HIFLD | **ODbL — share-alike** | Yes (polygon centroids or nodes) | `importer/sources/osm.py` |

USPS post offices deferred — no clean bulk public dataset; partial coverage via HIFLD is sufficient for pilot.

### State-law lookup table

A maintained YAML file at `data/state_laws/states.yaml`, git-versioned, edited by humans with PR review. Defines per-`(state, category)` cell: default status, restriction tag, confidence, conditions, citation, last-verified date, optional source filter.

Schema per row:

```yaml
- state: TX                                # Two-letter USPS code, or 'US' for federal-uniform
  category: BAR_ALCOHOL                    # Matches restriction_tag_type Postgres enum
  default_status: NO_GUN                   # ALLOWED | UNCERTAIN | NO_GUN
  confidence: medium                       # high | medium | low
  conditions:
    - "Premises deriving 51%+ revenue from on-premises alcohol sales"
    - "Must display TABC 51% sign"
  citation: "TX Penal Code §46.035(b)(1); TX Alcoholic Beverage Code §11.041"
  last_verified_date: 2026-01-15
  source_filter:                           # Optional: which import sources this row applies to
    - osm
  notes: |
    Generic "bar" classification in OSM isn't sufficient — needs TABC
    designation. Confidence is medium because we're inferring from OSM tags.
```

**Confidence levels (precise definitions):**

- **high** — Statutory prohibition applies categorically to every member of this category in this state, with no per-venue conditions to verify (federal courthouses, K-12 schools, secure airport areas, state courthouses in TX/FL/PA).
- **medium** — Prohibition exists but applies under conditions we cannot fully verify externally (TX 51% bars, FL "primary business" alcohol rule).
- **low** — Prohibition is venue-specific and depends on owner posting or per-institution policy; the category only increases likelihood (campus carry where state allows but private institutions opt out).

**Federal-uniform rows** use `state: US` and apply nationwide. Importer joins on `(state, category)` first, falls back to `(US, category)`, drops + warns if neither exists. No silent defaults — missing rows surface as "needs research" in the dry-run report.

**Maintenance:** quarterly review. Maintainer reviews each cell, bumps `last_verified_date` even if unchanged (proves it was checked). Stale cells (`last_verified_date` > 6 months) flagged in dry-run reports; > 12 months trigger UI warnings on the affected pins.

**Pilot scope:** TX + FL + PA × 10 categories + 3 federal-uniform US cells = 33 entries to research and write.

**Texas-specific caveat:** TX is one of three states (TX, KS, IL) where signage is only legally binding if it matches the statutory format (Penal Code 30.05/30.06/30.07/51%, 1-inch block letters, English+Spanish, conspicuous placement). External datasets cannot tell us whether a venue has format-compliant signage, so all pre-populated TX pins default `has_posted_signage = false`. Users verify with photos.

### Status assignment is deterministic per cell

The importer never invents a status. Every pre-populated pin's status, restriction tag, confidence, citation, and verified date come from a specific row in `states.yaml`. The whole stack — including legal liability posture in §7 — depends on this being traceable.

---

## §2 — Architecture and where the importer lives

The importer is a separate Python program in the same monorepo as the Flutter app. It is not part of the Flutter build, runs only via GitHub Actions or local developer invocation, and writes to Supabase using the service-role key (bypassing RLS).

### Why same repo, not separate

- The Supabase schema is the contract between importer and app. Schema migrations need to land in lockstep with importer changes that depend on the new columns. One repo = one PR.
- The state-law table is referenced by both the importer (status assignment) and the Flutter app (citation display on pre-populated pins). Single source of truth.
- Solo-dev pace per memory; no team-coordination benefit to splitting.
- Existing CI/secrets infrastructure pattern is extended, not forked.

The importer directory is added to `.flutterignore` (and is invisible to Flutter builds anyway, since it's not referenced from `pubspec.yaml`). CI workflows use `paths:` filters so importer changes don't trigger Flutter PR checks and vice versa.

### Where it runs

| Environment | Trigger | Mode | Target Supabase project |
|---|---|---|---|
| Developer laptop | Manual `python -m importer.cli` | Either | Staging by default; prod requires explicit flag |
| `.github/workflows/importer-dry-run.yml` | Cron (weekly) | Dry-run | Staging |
| `.github/workflows/importer-apply.yml` | Manual `workflow_dispatch` | Apply | Operator-selected from inputs (no default) |
| `.github/workflows/importer-pr-validate.yml` | Pull request touching `importer/**` or `data/state_laws/**` | Dry-run | Staging |

Service-role key for each environment stored as a GitHub Actions secret. The CLI accepts `--project-ref <ref>` so the same binary targets prod, staging, or any future environment.

### Repository layout

```
ccwmap/
├── lib/                              # Flutter app (existing)
├── supabase/migrations/              # Existing pattern; adds 008
├── docs/                             # Existing
│   └── importer/                     # NEW — importer docs, ODbL roster
├── data/                             # NEW — gitignored except state_laws/
│   ├── state_laws/
│   │   ├── states.yaml               # The maintained legal table
│   │   └── LICENSE                   # CC0
│   └── sources/                      # Cached source datasets (gitignored)
├── importer/                         # NEW — Python project
│   ├── pyproject.toml
│   ├── README.md
│   ├── importer/
│   │   ├── cli.py
│   │   ├── candidate.py
│   │   ├── pipeline.py
│   │   ├── stages/
│   │   │   ├── normalize.py
│   │   │   ├── apply_state_law.py
│   │   │   ├── refine_coords.py
│   │   │   ├── dedup.py
│   │   │   ├── diff.py
│   │   │   ├── apply.py
│   │   │   └── odbl_dump.py
│   │   ├── sources/                  # nces, ipeds, faa, gsa, hifld_*, osm
│   │   ├── geo/                      # state PIP, Overpass client, R-tree
│   │   ├── supabase_client.py
│   │   ├── state_laws.py
│   │   └── reports/
│   └── tests/                        # Frozen fixtures + e2e against staging
└── .github/workflows/
    ├── importer-dry-run.yml          # NEW
    ├── importer-apply.yml            # NEW
    └── importer-pr-validate.yml      # NEW
```

### Why Python over Dart for the importer

Python's data ecosystem (pandas, geopandas, shapely, requests, rapidfuzz, rtree) is dramatically better suited for ETL than Dart's. The Flutter team's Dart skills aren't wasted — the importer is a small separate codebase with a different lifecycle.

---

## §3 — Schema additions for provenance and re-import safety

Goal: track where each pin came from, whether a user has touched it, and how confident we are — so the importer can re-run safely without overwriting user edits or resurrecting deleted pins.

### Verified existing schema (via Supabase MCP, 2026-05-10)

The `pins` table has 199 rows. Confirmed columns include `created_by uuid` (nullable, FK `pins_created_by_fkey → auth.users.id`), `restriction_tag` as a real Postgres enum (`restriction_tag_type` with all 10 values matching the Dart enum), `name text` with `CHECK char_length(name) <= 60`, `status integer` with `CHECK status IN (0, 1, 2)`, and `location` as a generated `geography` column from lat/lng (importer never writes it directly). Unused-by-this-project columns: `notes`, `photo_uri`, `votes`.

Existing local Drift schema is at v2; this work bumps to v3.

### Migration `008_provenance_and_view_rpc.sql`

New columns on `pins`:

| Column | Type | Purpose |
|---|---|---|
| `source` | TEXT NOT NULL DEFAULT `'user'` | One of: `user`, `nces`, `gsa`, `faa`, `usps`, `hifld_courts`, `hifld_hospitals`, `hifld_military`, `ipeds`, `osm`. |
| `source_external_id` | TEXT NULL | Stable per-source identifier. Used as the upsert key. NULL for `source='user'`. |
| `source_dataset_version` | TEXT NULL | Version/snapshot of the source data (e.g., `NCES-2024-25`, `OSM-2026-05-09`). |
| `imported_at` | TIMESTAMPTZ NULL | When the importer last touched this row. Distinct from `created_at` and `last_modified`. |
| `user_modified` | BOOLEAN NOT NULL DEFAULT `false` | TRUE when any non-importer write hits the row. Set automatically by trigger. |
| `confidence` | TEXT NULL | `'high'` / `'medium'` / `'low'` from the state-law table cell. |
| `legal_citation` | TEXT NULL | E.g., `'18 USC 930(a)'` or `'TX Penal Code §46.035(b)(1)'`. |
| `legal_citation_verified_date` | DATE NULL | When the citation was last reconciled against current statute. |
| `source_orphaned_at` | TIMESTAMPTZ NULL | Set when a previously-imported pin no longer appears in upstream source. Does NOT auto-delete. |
| `cached_at` | TIMESTAMPTZ NULL | NULL for user pins; set for pins fetched via bbox cache. Used for LRU eviction. |

Backfill: `UPDATE pins SET source = 'user', user_modified = true WHERE source IS NULL` — all 199 existing pins were created by users; subsequent importer runs must not touch them.

New tables:

- **`pin_deletions`** `(pin_id uuid PRIMARY KEY, deleted_at timestamptz NOT NULL DEFAULT now(), deleted_by uuid NULL, original_created_by uuid NULL)` — populated by a trigger on `pins` DELETE. `deleted_by` is nullable because service-role deletes have no `auth.uid()`. Enables `MyPinsSync` to detect deletions of pins the user created.
- **`import_runs`** `(run_id uuid PRIMARY KEY, started_at timestamptz, completed_at timestamptz, mode text, source_filter text, candidates_processed int, inserts int, updates int, skips int, orphans_marked int, errors_json jsonb, report_artifact_url text)` — audit log of every importer apply run.
- **`recent_deletes`** `(user_id uuid NOT NULL, deleted_at timestamptz NOT NULL DEFAULT now())` with index on `(user_id, deleted_at)` — rolling counter for the rate-limit trigger. Pruned by the same daily `pin-health-check` Edge Function in §6 (`DELETE FROM recent_deletes WHERE deleted_at < now() - interval '24 hours'`).

New triggers:

- **`set_user_modified`** on `pins` UPDATE: if `current_user != 'service_role'`, set `user_modified = true` and refresh `last_modified = now()`.
- **`record_pin_deletion`** on `pins` DELETE: insert into `pin_deletions`.
- **`enforce_delete_rate_limit`** on `pins` DELETE: count entries in `recent_deletes` for the deleting user in the last hour; if > 100, RAISE EXCEPTION. Permissive enough that legitimate cleanup works; tight enough that scripted attacks fail.

### Service-role user (system pin owner)

A single Supabase auth user owns every pre-populated pin. Setup is one-time:

1. Create email account `system+ccwmap@kyberneticlabs.com` (uses your domain for deliverability/control).
2. Pre-generate one UUID (`uuidgen` or equivalent). This is the *system user UUID*, used identically in both prod and staging Supabase projects so the Flutter app's `kSystemUserId` constant is environment-agnostic.
3. In each project (prod first, then staging), call Supabase's admin API `auth.admin.createUser({ id: <pre-generated UUID>, email, password, email_confirm: true })` with a long random password — stored only in the importer's GitHub Actions secret. Passing the explicit `id` reuses the same UUID across projects.
4. Store the UUID in `importer/config.yaml` (`system_user_id`) and as `kSystemUserId` constant in `lib/core/system_constants.dart`. The constant is the same across debug/release/staging/prod app builds.

Hardening: an RLS policy explicitly denies the system user from app-side writes — only `service_role` (used by the importer) can write rows attributed to this user. Even if the password leaks, an authenticated session can only read.

### RLS column-level grants

Replace the existing blanket UPDATE grant with column-level grants. Authenticated users can update `name`, `latitude`, `longitude`, `status`, `restriction_tag`, `has_security_screening`, `has_posted_signage`, `notes`, `photo_uri`, `votes`. Provenance columns (`source`, `source_external_id`, `source_dataset_version`, `imported_at`, `confidence`, `legal_citation`, `legal_citation_verified_date`, `source_orphaned_at`) are writable only by `service_role`.

### App-side updates

- `map_screen.dart:922` — replace `pinCreatorId != 'anonymous'` with helper `_isOtherUserPin(creatorId)` returning false for null, current user's id, and `kSystemUserId`. Affects whether report/block buttons appear on a pin's edit dialog.
- Pin dialog: "Pre-populated from {source}" badge for pins where `created_by == kSystemUserId`, with the citation and verified date below the status. Distinct from "by you" / "by another user" framing.
- Pin dialog: hide the report-user button on system pins. Reports against system pins go through a "report incorrect data" mechanism (surfaces alongside `source_orphaned_at` review items).
- Investigate and remove the `'anonymous'` sentinel for `created_by` if confirmed dead code (guest users cannot create pins under the current auth-required-write model).

### Importer reconciliation logic per source row

1. Look up existing pin by `(source, source_external_id)`.
2. **No match** → INSERT with all fields, `imported_at = now()`, `user_modified = false`.
3. **Match + `user_modified = true`** → SKIP non-trivial updates. Only refresh `source_dataset_version`, `imported_at`, clear `source_orphaned_at`.
4. **Match + `user_modified = false`** → UPDATE safe fields (name, coords, restriction tag, citation, confidence) to current source values, refresh `imported_at`.
5. After all source rows processed: any pin with this source whose `source_external_id` was not seen → `source_orphaned_at = now()`. Surfaces in dry-run reports for human review; never auto-deletes.

### Local Drift schema v3 parity

Same column additions on the local `pins` table (TEXT for source, INT for booleans, ISO text for dates per Drift conventions). New local tables for `fetched_bboxes` (per §6) and `pin_deletions` (mirrored from server). Mapper in `SupabaseRemoteDataSource` ferries new fields. ViewModel needs `source`, `confidence`, `legal_citation`, `legal_citation_verified_date` for display logic; the rest are bookkeeping.

---

## §4 — Importer pipeline and dedup logic

### Common intermediate format

Every source normalizes to a `Candidate` dataclass:

```python
@dataclass
class Candidate:
    source: str
    source_external_id: str
    source_dataset_version: str
    name: str                          # raw, pre-truncation
    latitude: float
    longitude: float
    coord_quality: str                 # 'precise', 'address_centroid', 'building_polygon'
    category: RestrictionTag           # Python enum mirroring Dart
    state: str                         # 2-letter, derived via point-in-polygon
    extra: dict                        # source-specific fields for dedup hints
```

Each source module exports `SOURCE_NAME`, `fetch()` (cached to `data/sources/{source}/`), and `iter_candidates(state_filter)` yielding `Candidate`s. Tests against checked-in fixture rows ensure mapping changes break tests rather than silently shipping bad data.

### Pipeline stages

Each stage is a separate module with clean input/output contracts; testable in isolation.

1. **Normalize** — sources yield `Candidate`s. Names truncated to 60 chars (DB constraint), with truncations logged.
2. **Apply state-law table** — joins on `(state, category)` with fallback to `(US, category)`. Sets status, restriction_tag, confidence, citation, verified_date. Drops candidates with no matching cell + warns.
3. **Refine coordinates** — for each `(state, category)` requiring refinement (source supplied address-centroid only), one Overpass query for all matching building polygons within state bbox. Build in-memory R-tree (`shapely` + `rtree`). For each candidate, snap to nearest polygon within 200m if found; otherwise keep source coords with `coord_quality='address_centroid'`. ~30 Overpass calls per pilot run total, not per pin.
4. **Dedup** — within-source (trust source ID; second occurrence is logged error). Cross-source: priority order NCES > IPEDS > FAA > GSA > HIFLD > USPS > OSM. Match criteria: within 100m AND `rapidfuzz.token_set_ratio` ≥ 0.7. Lower-priority candidate dropped. User-created pins (`source='user'`) are highest priority — never imported on top of.
5. **Diff** — for each candidate, look up by `(source, source_external_id)`. Classify INSERT / UPDATE / SKIP. After batch, mark orphans.
6. **Apply** — write to Supabase via service-role, batched 500 rows per Postgrest request. Skipped entirely in dry-run mode.
7. **ODbL dump** — runs after successful apply. Writes `dump-YYYY-MM-DD.csv.gz` of `source = 'osm'` rows to a public Supabase Storage bucket with ODbL header.

### Dry-run vs apply modes

**Dry-run** (default in scheduled runs): pipeline through diff stage. Writes a Markdown + JSON report to a workflow artifact: counts per source, dedup stats, orphan list, stale-citation list (`last_verified_date` > 6 months), candidates skipped due to missing state-law cells, sample diffs. Does NOT touch Supabase.

**Apply** (manual `workflow_dispatch`): same pipeline + writes. Generates ODbL dump. Posts notification on completion via `send-moderation-email` Edge Function pattern.

### Idempotency and failure handling

- Re-running with same source data produces zero changes (same `(source, external_id)` keys, identical fields → all SKIP).
- Mid-run failure: partial writes are fine; re-run picks up via the upsert-by-key model.
- Each source's `fetch()` is cached; subsequent runs skip download unless `--refetch`.

### Testing strategy

- **Unit:** per-source mappers tested against frozen fixture rows (5-10 real records per source, captured once, refreshed only via deliberate PR review).
- **Stage tests:** dedup, state-law application, diff each tested with synthetic candidates.
- **End-to-end:** against the staging Supabase project. Workflow seeds a known starting state, runs the importer at small scale, asserts final state. Concurrency-grouped to prevent two PRs racing on the shared staging resource.

### Performance bounds (pilot, ~50k candidates)

- Overpass: ~30 queries × 1s throttle = ~30s + processing.
- Supabase writes: 50k / 500 batch = 100 requests, sequential, few minutes.
- Memory: R-trees of building polygons + existing pins easily under 1 GB.
- End-to-end well under 30 minutes per state.

---

## §5 — Sync model: redefining offline-first

### Three pin tiers

| Tier | Definition | Sync model | Local storage | Offline access |
|---|---|---|---|---|
| **Mine** | `created_by = auth.uid()` | Full bidirectional sync, write-queue, conflict resolution — existing offline-first model preserved | All of them, forever | Always |
| **Visited (cached)** | Fetched via bbox query, `created_by != auth.uid()` | Read-cached, evictable | Up to ~20k rows, LRU on `cached_at` | Where you've been |
| **Everywhere else** | Not in current viewport, not previously cached | Fetched on demand by viewport bbox + zoom | Not stored | Requires connectivity |

### Two distinct sync flows in `SyncManager`

**`MyPinsSync` — full sync, offline-first preserved.**

- Triggered on app start, auth state change, every N minutes background.
- `getMyPinsModifiedSince(last_synced_at)` — small delta query bounded by user's own pin count. First-ever sync uses `last_synced_at = '1970-01-01T00:00:00Z'` so the full set of the user's own pins is downloaded once.
- Includes my-pin tombstones from `pin_deletions` mirrored to local.
- Writes always go local-first → write queue → cloud (existing behavior).
- Anonymous browsers: no-op.

**`ViewportPinsManager` — bbox-on-demand, cached.**

- Triggered on `onCameraIdle` after debounce.
- Calls `get_pins_in_view(bbox, zoom)` RPC.
- Writes results to local DB with `cached_at = now()`.
- LRU eviction on `cached_at` when system+other pin count exceeds ~20k. Mine pins never evicted.

### Server-side `get_pins_in_view` RPC

```sql
get_pins_in_view(
  sw_lat double precision, sw_lng double precision,
  ne_lat double precision, ne_lng double precision,
  zoom integer
) RETURNS SETOF pin_or_cluster
```

- **Zoom ≥ 12** (street/neighborhood): individual pins via `ST_Intersects(location, ST_MakeEnvelope(...))` filtered to `created_by != auth.uid()`. LIMIT 2000.
- **Zoom < 12** (regional/national): server-side cluster aggregates via `ST_SnapToGrid` bucketing by zoom-dependent grid size. Each cluster: `{centroid_lat, centroid_lng, count, dominant_status, dominant_restriction_tag}`. Single-pin grid cells return as full pins (so isolated rural school still renders distinctly).
- **Density fallback:** `if pin_count > 2000 then return clusters` even at zoom 12. Prevents pathological viewports (downtown LA at street zoom).

The RPC is exposed via Postgrest automatically. Migration `008` includes `CREATE INDEX IF NOT EXISTS pins_location_gist ON pins USING GIST (location)` so the index is guaranteed to exist regardless of pre-existing schema state. Sub-100ms queries are the norm.

### Client-side flow

1. App opens → camera animates to user location (existing BUG-003 fix).
2. Map idles after pan/zoom → `BboxPinManager` computes bbox + zoom, calls `get_pins_in_view`.
3. Results merged into map's GeoJSON source. Clusters render as numbered circles (MapLibre native style); pins render as today.
4. Cluster taps zoom camera into cluster's bbox, triggering another fetch.
5. Bbox fetches debounced 500ms after `onCameraIdle`. In-flight requests cancelled when viewport changes.

### Local Drift schema v3 additions for sync

- `pins.cached_at` column (already in §3).
- `fetched_bboxes` table: `{bbox, zoom, fetched_at, pin_count}` for eviction bookkeeping.
- `pin_deletions` table mirrored from server.

### What changes in existing code

- `SupabaseRemoteDataSource.getAllPins()` repurposed to `getMyPinsModifiedSince(timestamp)` filtered to `created_by = auth.uid()`.
- New methods: `getPinsInView(bbox, zoom)`, `getMyPinDeletionsSince(timestamp)`.
- `SyncManager` splits into `MyPinsSync` and `ViewportPinsManager`.
- `PinRepository` interface unchanged — UI reads from local DB, doesn't know which sync flow populated it.
- `MapScreen` hooks `onCameraIdle`, drives `BboxPinManager`. Existing pin-rendering layer unchanged.

### What this kills

- "Sync everything to local DB" model — replaced by tiered sync.
- Web platform downscoping — bbox fetches are small; web becomes first-class again under this model. In-memory SQLite acceptable; persistence migration deferred.
- First-launch progress banner — first launch fetches only the user's surroundings (~hundreds of pins), instant.
- Baked-in seed bundle — not needed at this granularity.

### Subtleties

- Pins the user *edited but didn't create* are not "mine" — they're cached if area is cached, otherwise bbox-fetched. Future "save/star" feature could let users force-cache any pin.
- Mass-deletion vulnerability surfaces here (cloud truth gone if scripted). Mitigation: server-side rate limit per user (§7).
- Realtime subscriptions, when added, naturally bbox-scoped: subscribe to events for current viewport.

---

## §6 — Error handling, observability, ODbL compliance

### Importer-side failure handling

| Failure | Behavior |
|---|---|
| Source `fetch()` fails | Use cached data if available; otherwise skip that source for the run, importer continues. Report flags missing source. |
| State-law table missing `(state, category)` cell | Skip candidate, log to "needs research" section. Never silent default. |
| Coordinate refinement times out / Overpass rate-limit | Fall back to source coords, mark `coord_quality='address_centroid'`. |
| Dedup match ambiguous | Drop lower-priority candidate; flag in "manual review" report section. |
| Postgrest write fails mid-batch | Retry with exponential backoff (1s/2s/4s/8s), max 4 attempts. After exhaustion, abort with failure report. Idempotency means next run resumes. |
| Service-role key invalid/expired | Fast-fail at startup with clear error naming the env var. |
| Source row malformed | Skip row, increment per-source counter. Threshold alert if > 5% rows in a source malformed. |

### App-side failure handling

| Failure | Behavior |
|---|---|
| `getPinsInView` RPC fails/times out | Show cached pins for bbox; transient error toast; auto-retry on next `onCameraIdle`. |
| `MyPinsSync` fails | Existing SyncManager retry (max 3 with exponential backoff). Offline write queue continues. |
| LRU eviction fails | Log only, not user-visible. |
| Pathological cache growth | Hard fallback on app start: if cached count > 2× soft limit, drop all `created_by != me` rows, rebuild via bbox. |

### Server-side failure handling

| Failure | Behavior |
|---|---|
| `get_pins_in_view` errors (bad params) | Return empty set with error code; client treats as "no data for area" + logs. |
| `pins` DELETE trigger fails | Whole DELETE rolls back via transaction. Client retries. We never have a deleted pin without tombstone. |
| Spatial index missing/corrupted | Query slows but doesn't fail. Surfaced in observability. |

### Observability

**Importer observability** (new):

- Structured JSON logs to stdout — GitHub Actions captures.
- Per-run summary report as workflow artifact (Markdown for humans, JSON sidecar for tooling).
- `import_runs` table on Supabase records every run.
- Failed runs email support address via existing `send-moderation-email` Edge Function pattern.

**Database/Supabase observability** (new):

A daily cron-via-Edge-Function (`pin-health-check`):

- Counts pins by source, status, state. Alert if any category drops > 10% day-over-day (mass-delete or mass-orphan signal).
- Counts deletions in last 24h via `pin_deletions`. Alert if > 1000 (scripted attack signal).
- Counts pins with `source_orphaned_at IS NOT NULL`. Email if > 100 (review queue).
- Counts pins with `legal_citation_verified_date < now() - 12 months` monthly (staleness report).
- Output: emails support address (per memory: `camilo@kyberneticlabs.com`) with markdown digest.

**Server-side rate limit on DELETE per user:**

- `recent_deletes` table populated by DELETE trigger.
- If a single `auth.uid()` has deleted > 100 pins in the last hour, trigger raises EXCEPTION.
- Permissive for legitimate cleanup, tight against scripted attacks.
- Doubles as monitoring signal (exception logs alertable via daily health-check).

**App observability:**

- Console-log RPC durations and error counts in debug builds (`kShowDebugUI` gated).
- Track per-session `getPinsInView` failure rate; if > 20%, one-time banner.
- Recommend Sentry or equivalent as a follow-up — out of scope here, flagged as "should do soon."

### ODbL compliance (for OSM-sourced pins)

1. **Attribution in-app on the map view.** Bottom-right overlay: "© OpenStreetMap contributors". Always visible when map renders. Distinct from MapTiler tile attribution.
2. **Per-pin attribution.** Pin detail dialog for `source = 'osm'` shows "Data: OpenStreetMap (ODbL)" with deep link to the OSM way/node.
3. **Public derived-database dump.** `odbl_dump` stage produces `dump-YYYY-MM-DD.csv.gz` of `source = 'osm'` rows to a public Supabase Storage bucket. Includes ODbL license header. Linked from app About / Legal page and project README.
4. **Cadence:** dump regenerated after every successful apply run. Dumps older than 90 days auto-pruned.
5. **What's NOT in the dump:** federal-source pins (public domain), state-law-derived classifications applied to OSM pins (our work product), user-created pins (not derived).
6. **State-law table licensing:** `data/state_laws/states.yaml` is our work product citing public-domain primary sources. License the file CC0 in `data/state_laws/LICENSE`.
7. **README addition:** "Data Sources & Licenses" section listing each source, its license, and our compliance posture.

---

## §7 — Staging environment via separate free-tier Supabase project

The Pro-plan Supabase Branches feature is the cleanest way to validate schema and importer changes before they touch production, but its $25/mo cost is out of budget. We instead stand up a second free-tier Supabase project as a permanent staging environment.

### Setup (one-time)

1. Create a new Supabase project named `ccwmap-staging` on the free tier.
2. Enable the same extensions as prod (PostGIS).
3. Apply every existing migration (001-007) to staging via `mcp__supabase__apply_migration` so the schema mirrors prod from day 1.
4. Create the service-role system user in staging using the **same pre-generated UUID** as prod (per §3 setup) but a separate password. Same `kSystemUserId` works for both environments because we pass the explicit `id` to `auth.admin.createUser` rather than letting Supabase generate one.
5. Add GitHub Actions secrets: `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, `STAGING_SUPABASE_PROJECT_REF`. Existing prod secrets stay unchanged.
6. Document the workflow in `docs/importer/STAGING.md`.

### Workflow

- **Schema migrations:** every PR that adds a migration runs `apply_migration` against staging via `importer-pr-validate.yml`. Merge to `master` triggers `apply_migration` against prod. Schema drift detected by an additional check that compares migration counts between projects.
- **Importer changes:** PRs touching `importer/**` or `data/state_laws/**` trigger `importer-pr-validate.yml` which runs the importer in dry-run mode against staging. Apply mode against staging is the manual smoke test before promoting to prod.
- **Periodic refresh of staging data:** small dataset (199 pins today, ~50k post-pilot), refreshed manually from prod via `pg_dump` + `pg_restore` when staging drifts unhelpfully. Not automated for v1.
- **Free-tier project pause:** free-tier projects pause after 7 days of inactivity. The daily `pin-health-check` cron pings staging too (read-only query) to keep it active.
- **Free-tier storage limit (500 MB):** at pilot scale (~50k pins) we're well under. National scale (~400k pins) gets close — flag for revisit before scaling.

### The non-negotiable rule

**The importer's `apply` mode never targets prod from a developer's local machine.** Prod applies only via the manual GitHub Actions workflow, with the target ref explicitly selected (no default), and ideally only after the same import has run cleanly against staging.

### Limitations vs Branches

- No automatic per-PR DB. PRs share the staging project. Mitigation: serialize importer e2e tests via a GitHub Actions concurrency group (`concurrency: importer-staging`).
- Staging schema must be kept in sync manually via the migration workflow above. Automated drift check in PR validation.
- No ephemeral test environments — all integration testing uses the shared staging.

These limitations are acceptable for solo-dev pace and pilot scope. Revisit if/when a Pro plan upgrade becomes affordable or if multi-developer coordination becomes a bottleneck.

---

## §8 — Rollout plan and risks

### Phasing

Each phase completes before the next starts. The first three are foundation and must land before any pre-pop data does.

| # | Phase | Scope | Exit criteria | Rough effort |
|---|---|---|---|---|
| 0 | **Schema foundation + staging setup** | Migration `008_provenance_and_view_rpc.sql` (provenance columns, `pin_deletions`, `import_runs`, `recent_deletes`, triggers, `get_pins_in_view` RPC, GIST index verify). Service-role user creation in prod + staging. `kSystemUserId` constant. `'anonymous'` sentinel cleanup if dead. Staging Supabase project setup per §7. PR-validate workflow. | Migration applied to staging + prod; existing 199 pins still load; system users exist with deny-write RLS; staging project mirrors prod schema; PR validation runs against staging. | 2-3 weeks |
| 1 | **Sync model rewrite** | Split `SyncManager` into `MyPinsSync` + `ViewportPinsManager`. New local `fetched_bboxes` table. LRU eviction. Bbox-fetch on `onCameraIdle`. Server-side clustering RPC implementation. | App works end-to-end with existing 199 pins under new sync model. No regressions in TestFlight + Play Internal. | 2-3 weeks |
| 2 | **Importer skeleton** | `importer/` directory, CLI, `Candidate`, pipeline stages as wired-up stubs, Supabase service-role wrapper, state-law YAML loader. ONE source module end-to-end (HIFLD courthouses — smallest, GeoJSON-native, federal-uniform). Dry-run report generation. Workflow files. | `python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts` produces coherent report. Apply mode against staging produces correct rows. | 1-2 weeks |
| 3 | **State-law table seeding** | Research + write 33 cells (TX + FL + PA × 10 categories + 3 federal-uniform US cells). | All cells filled with `last_verified_date`, citations validated. | 1 week (mostly legal research; can parallel with other work) |
| 4 | **Pilot wave 1: federal floor** | HIFLD courthouses + GSA federal property + HIFLD military for TX/FL/PA (~3-5k pins). ODbL attribution UI wired up in advance. | Federal pins visible. Bbox sync stable. No app perf regressions. | 1 week |
| 5 | **Pilot wave 2: schools + airports** | NCES K-12 + IPEDS colleges + FAA airports for TX/FL/PA (~15-25k pins). | Realistic clustering test in dense areas (Houston, Miami, Philadelphia). | 1 week |
| 6 | **Pilot wave 3: OSM long-tail** | Bars, places of worship, sports venues, healthcare-not-in-HIFLD via Overpass for TX/FL/PA. ODbL dump generator wired up. | Dedup against waves 1-2 working correctly. Dump file accessible from public Supabase Storage URL. | 2 weeks |
| 7 | **Pilot ship** | Merge to `release/v*` per existing GIT_FLOW. Ship TestFlight + Play Internal, then promote via `v*.*.*` tag. Monitor health-check daily. | Pilot live. ≥ 7 days clean health-check before declaring stable. | 1 week active + ongoing observation |
| 8+ | **National rollout (separate project)** | Categorical waves nationwide: federal → K-12 → airports + colleges → OSM. Each wave needs state-law table extended to all 50 states. **Cluster rendering revisit:** before total pin count crosses ~50k, evaluate migrating from server-side `ST_SnapToGrid` clustering (Option B) to client-side Supercluster (Option C — see [`docs/dev/CLUSTER_RENDERING.md`](../../dev/CLUSTER_RENDERING.md)). Option C handles smooth zoom-driven cluster transitions natively and shifts aggregation work off the server, but needs a hybrid (server clusters at zoom <8, client Supercluster at zoom ≥8) to preserve total-count accuracy at country zoom. | TBD per wave | TBD |

**Total pilot effort: ~10-13 weeks active work.** Solo-dev pace; calendar time longer if part-time.

### Dependencies

- Phase 0 blocks everything (schema is the contract).
- Phase 1 blocks Phases 4-6 (sync model handles scale before data requires it).
- Phase 2 blocks Phases 4-6 (no importer = no data).
- Phase 3 blocks Phase 4 (no state-law cells = importer skips all candidates).
- Phases 4-6 sequential because each tests dedup against the previous wave.

### Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Legal liability from pre-asserting NO_GUN status based on state-law inference being wrong | Low per error; non-zero in aggregate | High | Confidence levels + "verify locally" copy on low-confidence pins + per-pin citations. Recommend lawyer consult before first national wave (not gating pilot). |
| Apple App Store rejection flagging state-law assertions as political | Low | Could delay ship | Store-listing framing emphasizes "informational legal references." Existing pre-pop pins look like normal pin data; UI changes are minor additions to existing dialog. |
| Source data quality (closed schools in NCES, mistyped OSM venues) | High | Medium per pin | Orphan tracking + human review queue + low-confidence rendering + user correction sets `user_modified=true` so importer respects it. |
| Dedup miscalibration (similarity threshold 0.7 too tight or loose) | Medium | Medium | Pilot validates against real data; tune before national. Per-source priority order means OSM gets suppressed against canonical sources, not inverse. |
| State-law table maintenance burden (quarterly × 50 states × 10 categories = 500 cells) | Medium | Medium | Prioritize federal-uniform + state courthouse cells (rarely change). Accept long-tail decay. Stale-citation alerts in UI mean users see staleness before we do. |
| Mass-deletion attack via scripted Postgrest | Low | Medium (cloud truth lost; clients re-fetch) | Server-side rate limit per user + daily health-check alert + cloud restore from latest dump. |
| TestFlight/Play Internal regression from sync model change | Medium | High | Phases 0+1 tested with existing 199 pins as regression baseline before any new data lands. |
| Web first-launch UX under bbox model | Low | Low | Test on slow connections; if jarring, brief "loading nearby pins…" indicator. |
| Solo-dev burnout from dual codebases | Medium per memory's "burnout kills mature apps" finding | Project death | Importer kept small and modular; quarterly state-law review is bounded calendar work. |
| Staging project drift from prod | Medium (especially over months) | Low (caught by PR validation) | Migration workflow applies to both; periodic schema-diff check; manual data refresh when drift becomes unhelpful. |
| Free-tier staging storage limit (500 MB) at national scale | Low for pilot; Medium for national | Medium (importer testing breaks) | Revisit before scaling beyond pilot. Either upgrade staging to Pro or partition the test dataset. |

### Open questions deferred to writing-plans

- Exact JSON shape for `get_pins_in_view` RPC return (pins vs clusters discrimination on the wire).
- Cache eviction threshold tuning (20k? 10k? device-dependent?).
- Pilot version number (`v0.5.0`? `v0.4.x` patch?).
- Whether to add a one-time onboarding modal explaining the new pre-populated data on first launch post-pilot.
- Specific spec for the staging-data-refresh workflow.

---

## References

- `docs/superpowers/specs/2026-05-02-market-driven-recommendations-design.md` — competitive landscape framing this work responds to.
- `CLAUDE.md` — current architecture, sync model, schema baseline.
- ODbL: https://opendatacommons.org/licenses/odbl/
- Source datasets (linked in `docs/importer/SOURCES.md` once written):
  - NCES Common Core: https://nces.ed.gov/ccd/
  - NCES Private School Survey: https://nces.ed.gov/surveys/pss/
  - IPEDS: https://nces.ed.gov/ipeds/
  - FAA NPIAS: https://www.faa.gov/airports/planning_capacity/npias/
  - GSA FRPP: https://www.gsa.gov/policy-regulations/policy/real-property-policy/asset-management/federal-real-property/federal-real-property-profile-frpp
  - HIFLD Open: https://hifld-geoplatform.opendata.arcgis.com/
  - OpenStreetMap Overpass: https://overpass-api.de/
