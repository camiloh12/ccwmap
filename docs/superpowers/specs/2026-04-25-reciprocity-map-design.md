# Reciprocity Map — Design

**Date:** 2026-04-25
**Status:** Draft — pending user review
**Branch:** `feature/reciprocity`
**Scope:** Add a state-by-state CCW reciprocity map as a new top-level screen, separate from the existing pin map, sourced from a self-curated dataset maintained by an LLM-assisted weekly extraction pipeline in a separate repo.

## Motivation

CCW reciprocity — when a state honors a concealed-carry license issued by another state — is one of the most common and highest-stakes questions a permit holder asks before traveling. Existing aggregators (USCCA, Handgunlaw.us) are paid, app-locked, or HTML-only, and no free machine-readable source exists. State Attorney General sites are the authoritative source but publish only HTML/PDF.

This screen lets a user pick their permit's home state and see a choropleth-colored U.S. map: green for "honors my permit," yellow for "partial / conditional," red for "does not honor," gray for "unknown." Tapping a state surfaces an info card with conditions (resident-only, age minimum, must-inform) and a link to the source AG page.

The data acquisition cost — not the engineering — is the hard part. The design isolates that cost in a separate repo with a weekly cron-driven LLM extractor and a human-in-the-loop review gate, so the Flutter app stays simple and consumes a finalized JSON file.

## Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Data scope for v1 | Structured: status + `resident_only` (bool), `min_age` (int?), `must_inform` (bool), `notes` (String?), `source_url`, `last_verified_at`. **Not** location-restriction rules, magazine caps, or open-carry interactions (deferred). |
| 2 | Entry point | Bottom navigation. `_AppRoot` becomes a `Scaffold` with `IndexedStack` of two screens: "Pins" (existing `MapScreen`) and "Reciprocity" (new). |
| 3 | Auth & home-state persistence | Guest-accessible, no auth required. Home state stored in `SharedPreferences` only. |
| 4 | Data acquisition | Separate `ccwmap-reciprocity-pipeline` repo. Weekly GitHub Action fetches AG pages, runs Gemini 2.5 Flash extractor, validates against JSON schema, diffs vs. prior snapshot, opens GitHub issue on changes for human review. |
| 5 | Delivery & staleness UX | Bundled `assets/reciprocity.json` baseline + Supabase Storage override. App loads cache → bundled fallback → opportunistic remote upgrade. Persistent freshness banner; per-cell `last_verified_at`; banner turns yellow at >30 days. One-time dismissible disclaimer modal mirroring the existing EULA pattern. |

## Architecture

Two physically separate repos with one runtime data hop:

```
┌─────────────────────────────────────────┐        ┌────────────────────────────┐
│  ccwmap-reciprocity-pipeline (new repo) │        │  ccwmap (existing app)     │
│  ─────────────────────────────────────  │        │  ────────────────────────  │
│  GitHub Action (weekly cron)            │        │  Flutter app               │
│   1. fetch 50 AG URLs                   │        │   ┌────────────────────┐   │
│   2. text-extract + sha256              │        │   │ Bottom nav         │   │
│   3. Gemini 2.5 Flash → JSON schema     │        │   │   • Pins (existing)│   │
│   4. JSON-Schema validate               │        │   │   • Reciprocity    │   │
│   5. diff vs prev snapshot              │        │   └────────────────────┘   │
│   6. on diff → open GitHub issue        │        │                            │
│   7. human reviews & merges PR          │        │  Reciprocity layer reads   │
│   8. merge → publish pipeline           │        │   from local cache, falls  │
│        ↓                                │        │   back to bundled asset    │
│  Publishes:                             │        │        ↑                   │
│   • assets/reciprocity.json (bundled    │        │        │                   │
│     into next app release)              │ ─────► │  HTTP fetch on screen open │
│   • Supabase Storage:                   │        │   if cache stale or empty  │
│     reciprocity/v{N}.json (live update) │        │                            │
└─────────────────────────────────────────┘        └────────────────────────────┘
```

**Boundary properties:**

- The Flutter app never sees raw AG HTML or LLM output. It consumes a finalized JSON file with a stable schema.
- The pipeline never imports app code. Its only contract is the JSON schema + the Supabase Storage path.
- Schema versioning (`schema_version` field in JSON) prevents the pipeline shipping incompatible updates to old app builds — the app refuses to load a JSON whose `schema_version > SUPPORTED_SCHEMA_VERSION`.
- Reciprocity does **not** participate in the existing pin sync queue, Drift database, or `SyncManager` — different domain, different lifecycle, read-only.

## Components

### App-side (Flutter, in `ccwmap` repo)

#### Domain layer (`lib/domain/`)

- `models/state_reciprocity.dart` — value object: `homeState` (CHAR(2)), `targetState` (CHAR(2)), `status` (`RecipStatus`), `residentOnly` (bool), `minAge` (int?), `mustInform` (bool), `notes` (String?), `sourceUrl` (String), `lastVerifiedAt` (DateTime).
- `models/recip_status.dart` — enum `{ honors, doesNotHonor, partial, unknown }` with display color mapping.
- `models/reciprocity_dataset.dart` — wraps `Map<(homeState, targetState), StateReciprocity>` plus dataset-level `version`, `schemaVersion`, `globalLastVerifiedAt`. Lookup misses return `unknown`.
- `repositories/reciprocity_repository.dart` — interface: `Future<ReciprocityDataset> load()`, `Stream<ReciprocityDataset> watch()` (emits when remote refresh completes).

#### Data layer (`lib/data/`)

- `datasources/bundled_reciprocity_data_source.dart` — reads `assets/reciprocity.json` via `rootBundle`. Always succeeds (asset is part of bundle).
- `datasources/remote_reciprocity_data_source.dart` — fetches `<supabase>/storage/v1/object/public/reciprocity/latest.json`. Throws on network failure.
- `datasources/cached_reciprocity_data_source.dart` — reads/writes `<app docs>/reciprocity_cache.json` via `path_provider`.
- `repositories/reciprocity_repository_impl.dart` — orchestrates the three sources. On load: try cache → fall back to bundled → emit. In parallel: fetch remote; if `version > current.version && schemaVersion <= SUPPORTED_SCHEMA_VERSION`, write cache and emit via stream. App-side validation is lightweight (presence of required top-level keys, supported schema version, well-formed cells map); deeper validation (field bounds, cross-cell consistency) lives in the pipeline. The app trusts a published JSON because every published JSON has already passed pipeline JSON-Schema validation and human review.

#### Presentation layer (`lib/presentation/`)

- `viewmodels/reciprocity_viewmodel.dart` — `ChangeNotifier`. State: `homeState` (read/write, persisted to `SharedPreferences` key `reciprocity_home_state`), `dataset`, `selectedTargetState`, `loading`/`error`. On construction: load home state from prefs, subscribe to `repo.watch()`.
- `screens/reciprocity_screen.dart` — `Scaffold` containing a `MapLibreMap` with U.S.-states GeoJSON fill layer, top home-state picker, freshness banner, and a `DraggableScrollableSheet` info card on tap.
- `widgets/state_picker.dart` — extracted home-state dropdown (also used in the empty-state view when no home state has been picked yet).
- `widgets/reciprocity_info_sheet.dart` — info card: target state name, status pill, condition chips (resident-only, age, must-inform), notes, "View source" link, per-cell `last_verified_at`.
- `widgets/reciprocity_disclaimer_modal.dart` — first-visit dismissible modal mirroring the `EulaModal` pattern. Flag: `SharedPreferences` key `reciprocity_disclaimer_acknowledged_v1`.

#### Bottom nav restructure (`lib/main.dart`)

`_AppRoot.build()` returns a `Scaffold` with:

- `body: IndexedStack(index: _tabIndex, children: [MapScreen, ReciprocityScreen])` — both screens stay mounted to preserve state across tab switches.
- `bottomNavigationBar: BottomNavigationBar(items: [...])` with icons `Icons.location_on` ("Pins") and `Icons.map_outlined` ("Reciprocity").

The retroactive-EULA and deep-link logic in `_AppRoot` remains unchanged; both fire regardless of which tab is active.

#### Asset & config

- `assets/reciprocity.json` — bundled baseline, ~200 KB. Listed in `pubspec.yaml` under `flutter.assets`.
- `assets/us_states.geojson` — simplified state polygons (Census TIGER simplified to ~150 KB), used by MapLibre fill layer.
- New env var: `RECIPROCITY_REMOTE_URL` in `.env`. If absent or empty, `RemoteReciprocityDataSource.fetch()` returns null without making a network call (no-op); the app continues on cached or bundled data. Production builds set the value; local dev can omit it without breakage.

### Pipeline-side (`ccwmap-reciprocity-pipeline`, new repo)

- `sources.yaml` — list of 50 entries: `{ state: "WA", url: "https://www.atg.wa.gov/concealed-pistol-license-reciprocity" }`. Hand-curated. Each AG page typically describes both directions ("states we honor" and "states that honor us"); the LLM prompt extracts whatever directional data is present.
- `extract.py` — fetches a URL, runs trafilatura for text extraction, sends to Gemini 2.5 Flash with a fixed system prompt + JSON schema, parses & validates response.
- `pipeline.py` — orchestrator: iterate `sources.yaml`, call `extract.py`, write per-state JSON to `data/states/<XX>.json`, compute global `data/reciprocity.json`, sha256 each page text into `data/hashes.json`.
- `diff.py` — compare new JSON to last snapshot in git history; if changed, build a markdown report.
- `.github/workflows/weekly-extract.yml` — Mon 06:00 UTC cron: run pipeline, if diff exists open issue with report, else exit clean. Manual `workflow_dispatch` trigger also available.
- `.github/workflows/publish.yml` — on push to `main`: upload `reciprocity.json` to Supabase Storage at `reciprocity/latest.json` (and a versioned `reciprocity/v<N>.json` for audit).
- `schemas/reciprocity.schema.json` — JSON Schema authoritative for both pipeline output and app input. Contract between the two repos.
- `prompts/extract.md` — system prompt for the LLM, version-controlled.
- Secrets: `GEMINI_API_KEY`, `ANTHROPIC_API_KEY` (fallback), `SUPABASE_SERVICE_ROLE_KEY` (publish only).

## Data flow

### Flow A — Weekly pipeline run

```
Mon 06:00 UTC, GitHub Actions
  │
  ├─ For each entry in sources.yaml (50 states):
  │    fetch URL → trafilatura.extract(html) → text
  │    sha256(text) → compare to data/hashes.json
  │    if hash unchanged → skip LLM call (cost saver)
  │    if hash changed (or first run):
  │        call Gemini 2.5 Flash with prompts/extract.md + text
  │        validate response against schemas/reciprocity.schema.json
  │        on validation fail → retry once → still fail → flag state in report
  │        on success → write data/states/<XX>.json
  │
  ├─ Aggregate all states → data/reciprocity.json
  │   { schema_version: 1, version: <N+1>,
  │     global_last_verified_at: <now>,
  │     cells: { "TX": { "FL": { status, ... }, ... }, ... } }
  │
  ├─ git diff data/  → if no diff → exit clean (no issue, no PR)
  │
  └─ if diff exists:
        open GitHub issue titled "[reciprocity] N states changed YYYY-MM-DD"
        body lists per-state before/after JSON + source URL + text excerpt
        human reviewer reads issue, opens PR if data is genuinely correct,
          edits PR if LLM got it wrong, closes if wording-only
        on PR merge to main → publish.yml uploads reciprocity.json to
          Supabase Storage as reciprocity/latest.json (and v<N>.json for audit)
```

The hash short-circuit (skip LLM if page text unchanged) keeps Gemini calls to ~5–10/week typical, comfortably inside free tier.

### Flow B — App startup and refresh

```
User taps "Reciprocity" in bottom nav (first time this session)
  │
  ReciprocityScreen.initState()
    │
    ├─ ReciprocityViewModel constructs:
    │    homeState = SharedPreferences.getString('reciprocity_home_state')
    │    if null → show home-state picker as full-screen empty state
    │
    └─ ReciprocityRepositoryImpl.load() / watch():
         ┌─ try cached_reciprocity_data_source (app docs dir)
         │   └─ if present and schema_version supported → emit immediately
         ├─ else fall back to bundled_reciprocity_data_source (asset)
         │   └─ emit
         │
         └─ in parallel: remote_reciprocity_data_source.fetch()
              └─ on success:
                  if remote.version > current.version
                    and remote.schema_version <= SUPPORTED_SCHEMA_VERSION:
                      write cache file
                      emit via Stream → ViewModel rebuilds → choropleth recolors
                  else: discard
              └─ on failure (network/timeout): silent; existing data remains
```

App has usable data within one frame (cache or asset); remote upgrade is opportunistic.

### Flow C — User interaction

```
ReciprocityScreen built with current dataset + homeState
  │
  ├─ MapLibre fill layer paint expression:
  │    fill-color = match feature.id (state code):
  │      for each cell where cells[homeState][state] exists:
  │        green if status == honors
  │        yellow if status == partial
  │        red if status == doesNotHonor
  │        gray if unknown
  │
  ├─ User changes home state in dropdown:
  │    ViewModel.setHomeState('TX')
  │     ↓
  │    SharedPreferences.setString('reciprocity_home_state', 'TX')
  │     ↓
  │    notifyListeners() → screen rebuilds
  │     ↓
  │    one MapLibre setPaintProperty call with new match expression
  │    no re-fetch, no network — pure client-side filter on in-memory dataset
  │
  ├─ User taps a state polygon:
  │    onFeatureTapped(featureId) → state code 'FL'
  │     ↓
  │    ViewModel.selectedTargetState = 'FL'
  │     ↓
  │    DraggableScrollableSheet shows ReciprocityInfoSheet:
  │      "Texas → Florida"
  │      Status pill (Honors / Does not honor / Partial)
  │      Condition chips (resident-only badge, "21+ only", etc.)
  │      Notes (free-text)
  │      [View source] → launches sourceUrl in external browser
  │      "Verified 2026-04-22" (from cell or global)
  │
  └─ First visit on a fresh install:
       reciprocity_disclaimer_acknowledged_v1 == false
       → show ReciprocityDisclaimerModal (one-time, dismissible)
       → on accept: SharedPreferences.setBool(..._v1, true)
```

### Schema versioning rule

`schema_version` lives in both the bundled asset and every remote fetch. The app declares `SUPPORTED_SCHEMA_VERSION = 1`. The repository refuses any remote dataset whose `schema_version > 1` — protects users on old app builds when a future pipeline release introduces a breaking schema change. On a breaking change we'd bump app `SUPPORTED_SCHEMA_VERSION` and force a release.

## Error handling

### Pipeline-side

| Failure | Handling |
|---|---|
| AG URL returns non-200 / timeout | Retry once with 30 s backoff; on second failure, keep last-known JSON for that state, append `pipeline_warnings` to dataset listing the stale URL. State stays in next-week's queue. |
| Page returns 404 (URL moved) | Same as above, but emits a high-priority issue: "URL dead — manual fix needed in `sources.yaml`." |
| trafilatura returns empty text | Log + flag; treat as content unchanged (no LLM call); raise warning if persists 2 runs. |
| Gemini API rate limit / 5xx | Retry with exponential backoff (1 s, 2 s, 4 s). After 3 fails, fall back to **Anthropic Haiku 4.5** on the same input. After both fail, keep last-known JSON. |
| LLM returns invalid JSON | One re-prompt with `"Your last response failed JSON validation: <error>. Return only valid JSON matching the schema."` Then fall back to alternate model. Then keep last-known. |
| LLM returns valid JSON but fields out of bounds (e.g., `min_age: 999`) | JSON Schema bounds (`minimum: 18, maximum: 25`) catch this — treated like a validation failure. |
| `git diff` shows >25% cells changed | Pipeline opens issue titled `[ANOMALY] N% of cells changed — manual review required` and exits non-zero. Prevents a single bad LLM run from auto-publishing a corrupted dataset. |
| Supabase upload fails in `publish.yml` | Workflow fails loudly. A published dataset is never partially overwritten because we upload to a versioned key first, then rename `latest.json`. |

### App-side

| Failure | Handling |
|---|---|
| No network on cold launch, no cache yet | Bundled asset is always present → user sees v0 dataset with banner: `Showing data from app install. Last verified <bundled date>. Connect to refresh.` |
| Remote fetch times out | Silent. Existing in-memory dataset stays. Retry next time the screen is opened. |
| Remote JSON malformed (parse error) | Caught in `RemoteReciprocityDataSource`. Logged. Cache **not** overwritten. App falls back to whichever older valid source it had. |
| Remote `schema_version > SUPPORTED_SCHEMA_VERSION` | Reject silently with debug log. App continues on older valid data. Surface via banner: `Update the app for the latest reciprocity data.` (subtle, non-blocking). |
| Cache file corrupted on disk | `RepositoryImpl` catches `FormatException`, deletes the cache file, falls back to bundled asset, attempts remote fetch fresh. |
| User has no home state selected | ReciprocityScreen renders the `StatePicker` as a centered empty-state with helper text: `Pick your permit's home state to see reciprocity.` No map, no banner. |
| Tapped state has no cell data | Info sheet shows `unknown` status with note: `No data available for <home> → <target>. Verify directly with the destination state's Attorney General.` |
| Offline mode, all network calls fail | Behaves identically to "no network on cold launch" — bundled or cached data, banner, no error toast. |
| Tapped state is DC or territory | DC is in the dataset. Territories are filtered out of the polygon layer at build time — they're not interactable. |

### What the user never sees

- Network-error toasts on the reciprocity screen. The screen always has *some* data (bundled asset is the floor).
- LLM/extraction errors. Those are pipeline-internal — the user only ever sees a finalized, human-reviewed JSON.
- Schema-version mismatches as errors. They surface as a soft "update available" hint at most.

### Pipeline observability

- All pipeline errors → GitHub Issues (free, already wired into the repo).
- Each weekly run posts a summary comment on a long-lived `[Pipeline status]` issue: states updated, hash-skipped, fallback-model used, warnings — even on no-change runs, so silence-equals-down is detectable.

## Testing

Existing app has 109 tests with coverage targets in CLAUDE.md (domain 100%, mappers 100%, repos 90%+, viewmodels 80%+, UI 50%+). New code follows the same bar.

### App-side test plan

**Domain (target 100%)**

- `state_reciprocity_test.dart` — value-object equality, copy-with semantics, validation (status/condition consistency: e.g., `status == doesNotHonor` ⇒ `residentOnly`/`minAge` ignored).
- `recip_status_test.dart` — enum mapping to display colors and labels.
- `reciprocity_dataset_test.dart` — lookup by `(home, target)`, fallback to `unknown` on miss, version comparison.

**Data — JSON parsing & schema versioning (target 100%)**

- `reciprocity_dataset_parse_test.dart` — golden test files in `test/fixtures/reciprocity/`:
  - `valid_v1.json` — parses cleanly, all 2,550 cells.
  - `valid_v1_with_unknowns.json` — sparse dataset with missing pairs, lookups return `unknown`.
  - `malformed.json` — invalid JSON → `FormatException`.
  - `schema_v2.json` — `schema_version: 2` → repository refuses to load.
  - `cell_out_of_bounds.json` — `min_age: 99` rejected by validator.
- `reciprocity_repository_impl_test.dart` — uses fakes for all three data sources:
  - cache present, valid → emit cache, then remote upgrade replaces it.
  - cache absent → emit bundled, then remote upgrade.
  - remote network failure → silent, existing data stays.
  - remote `schema_version > supported` → silent reject, existing data stays.
  - corrupted cache file → delete cache, fall back to bundled, attempt remote.
  - remote version ≤ current → no-op (don't downgrade).

**Presentation (target 80%+ for VM, 50%+ for screen)**

- `reciprocity_viewmodel_test.dart` — uses fake repository:
  - construction reads home state from `SharedPreferences` (use `setMockInitialValues`).
  - `setHomeState` writes to prefs and notifies listeners.
  - selecting a target state populates `selectedTargetState`; clearing nullifies it.
  - dataset stream updates trigger `notifyListeners`.
- `reciprocity_screen_test.dart` — widget smoke tests:
  - empty state (no home state) shows `StatePicker` and no map.
  - with home state, choropleth fill expression matches dataset cells.
  - tapping a state polygon shows info sheet with correct content.
  - first visit shows disclaimer modal once; flag persists.
  - banner shows global `last_verified_at`; turns yellow at >30 days.

**Bottom nav (regression-sensitive)**

- `app_root_navigation_test.dart`:
  - tab switch preserves `MapScreen` camera position (`IndexedStack` keeps both mounted).
  - tab switch preserves `ReciprocityScreen` home-state selection.
  - existing pin-screen behavior (auth, FABs, dialogs) survives the nav restructure.

**Visual regression**

- One golden-image test for the choropleth in a known state (e.g., `homeState=TX`, fixed dataset). Detects accidental fill-color regressions.

### Pipeline-side test plan (separate repo)

**Schema validity**

- `tests/test_schema.py` — assert `schemas/reciprocity.schema.json` is itself valid JSON Schema; assert a hand-written reference dataset validates against it.

**Extractor**

- `tests/test_extract.py` — run `extract.py` against ~5 fixture HTML pages (saved snapshots from real AG sites) with **mocked** Gemini responses. Verify:
  - schema-valid LLM output is accepted and written.
  - schema-invalid output triggers one retry.
  - second failure triggers Haiku fallback (mocked).
  - both failing keeps last-known data.
  - hash-unchanged short-circuits the LLM call entirely (asserted by mock not being called).

**Diff & anomaly detection**

- `tests/test_diff.py` — synthetic before/after datasets:
  - identical inputs → no issue body, exit 0.
  - one cell changed → issue body lists exactly that cell.
  - >25% cells changed → anomaly path triggers, exit non-zero.

**End-to-end (integration, opt-in)**

- A manually-triggered job that runs the real pipeline against one real AG URL with a real Gemini call, asserting output validates against the schema. Run rarely (monthly) to detect prompt drift; not on every PR.

**No live LLM calls in CI by default.** All unit tests mock both Gemini and Anthropic SDKs. Extraction prompt lives in `prompts/extract.md` so changes are reviewable, but prompt-quality regressions are caught via the opt-in integration job, not unit tests.

### Coverage targets for v1

| Layer | Target | Existing app target |
|---|---|---|
| Domain (reciprocity models) | 100% | 100% |
| Data (parser + repo + schema versioning) | 100% on schema/version paths; 90%+ overall | 90%+ |
| ViewModel | 85%+ | 80%+ |
| Screen widgets | 60% | 50%+ |
| Pipeline extractor + diff (separate repo) | 90%+ (mocked) | n/a |

Total expected new tests in the Flutter app: **~35–45** (taking app from 109 → ~150).

## Out of scope for v1 (deferred)

- Location-restriction rules (schools, bars, government buildings, federal property).
- Magazine capacity caps.
- Open-carry interactions.
- Per-permit-type granularity beyond resident vs. non-resident.
- Cross-device home-state sync (would require auth gating, deferred indefinitely).
- Real-time legal-change notifications / push.
- Heat-map of permitless-carry states layered on top.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| LLM hallucinates a flipped reciprocity status, dataset gets published with bad data | Anomaly threshold (>25% cells changed → block auto-publish). Human-in-the-loop on every diff. Per-cell `source_url` lets us verify against the AG page on demand. |
| AG site changes URL silently; pipeline stops noticing changes | 404 / non-200 raises a high-priority issue. Hash-unchanged-for-N-runs would also be a tell (unusual for a real page); we can add a "stale page" check later if needed. |
| User relies on app for legal compliance and gets a wrong cell | First-visit disclaimer modal (`This is informational, not legal advice`). Persistent footnote on info sheet. Per-cell `source_url` always shown. Yellow banner at >30 days reinforces verify-yourself. |
| Schema migration breaks old app builds | `schema_version` field; app refuses to load `schema_version > SUPPORTED_SCHEMA_VERSION`; fallback to bundled asset always works. |
| Pipeline cost spike (LLM API) | Hash short-circuit caps typical LLM calls to ~5–10/week. Free tier covers it. Hard ceiling: switch to text-hash-only "manual extraction" mode if costs ever spike. |

## Open questions

None at design time. Implementation-phase questions go in the implementation plan, not here.
