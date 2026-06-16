# Phase 6 — OSM long-tail + ODbL dump + label title-casing (importer-only)

**Status:** design approved 2026-06-16. Implements rollout-plan Phase 6 ("Pilot
wave 3: OSM long-tail") from `2026-05-10-pre-populate-pins-design.md` §8.

**Branch:** `feature/pre-populate` (long-lived; PR'd to master once per phase).

**Parent spec:** `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md`
(§1 sources, §4 pipeline, §6 ODbL compliance, §8 rollout). This document refines
Phase 6 only; the parent governs everything else.

---

## §0 — Context and the central scoping fact

The parent spec lists the OSM source as covering "bars, places of worship, sports
venues, healthcare-not-in-HIFLD." That is the **national** aspiration. For the
**pilot states (TX/FL/PA)**, `docs/importer/OMISSIONS.md` already records the
researched conclusion that PLACE_OF_WORSHIP, SPORTS_ENTERTAINMENT, and HEALTHCARE
have **no categorical statutory prohibition** in any of the three states (they are
owner-posting or event-specific), and PA has no bar prohibition either. The only
OSM-filtered cells in `data/state_laws/states.yaml` are **TX + FL `BAR_ALCOHOL`**
(both `medium` confidence).

Therefore an OSM run over TX/FL/PA produces surviving pins for **bars in TX and FL
only**. Everything else either drops at `apply_state_law` (PA bars) or is never
queried at all (worship/sports/healthcare). This is by design, not a gap, and the
design below leans into it rather than fighting it.

No new migration is required: `get_pins_in_view` (migration 008) already returns
`source`, `source_external_id`, `confidence`, `legal_citation`, and the
`pins(source, source_external_id)` unique index (migration 009) already exists.

---

## §1 — Scope and non-goals

### In scope (all importer, staging-tested; no prod write)
1. `importer/importer/sources/osm.py` — Overpass-backed OSM source with **per-state,
   state-law-table-driven auto-scope**.
2. `importer/importer/stages/odbl_dump.py` — replace the Phase 2 stub with a real
   `dump-YYYY-MM-DD.csv.gz` generator + public Supabase Storage upload + 90-day
   pruning; wire it into the pipeline (apply mode only).
3. `importer/importer/supabase_client.py` — new Storage methods + an OSM-rows reader.
4. Title-casing pass in `importer/importer/stages/normalize.py` (all sources;
   all-caps-only guard). Resolves the deferred `importer-feedback.md` issue 5.
5. Config (`config.yaml`), CLI (`cli.py`), docs, tests, a live Overpass pre-flight,
   and a staging apply + idempotency verification (operator task).

### Non-goals (deferred to Phase 7 — pilot ship)
Every app-facing change is deferred so it ships as one coherent release when
pre-populated data first reaches users. Specifically:
- The "© OpenStreetMap contributors" map-view overlay (parent §6 item 1).
- Per-pin "Data: OpenStreetMap (ODbL)" row + deep link to the OSM way/node
  (parent §6 item 2). The server side is ready (the RPC returns `source` +
  `source_external_id`); only the Flutter domain model + dialog are missing.
- The About/Legal "Data Sources & Licenses" page in-app.
- The broader pre-pop provenance display (citation, confidence, "verify locally").

No Flutter changes. No migration. No production import. Consistent with the
importer-only discipline of Phases 4 and 5.

---

## §2 — OSM source module (`sources/osm.py`)

### Per-state auto-scope

The source must not query Overpass for a (state, category) combination that will
never become a pin. It derives its query plan from the state-law table.

New method on `StateLawTable` (`state_laws.py`):

```python
def osm_categories_for_state(self, state: str) -> set[RestrictionTag]:
    """Categories whose effective cell for `state` is OSM-filtered.

    Uses the same state->US fallback as lookup(), so a state-specific cell
    shadows the US cell exactly as classification will later resolve it.
    """
    cats: set[RestrictionTag] = set()
    for category in {row.category for row in self.rows}:
        cell = self.lookup(state, category)
        if cell and cell.source_filter and "osm" in cell.source_filter:
            cats.add(category)
    return cats
```

Resolution for the pilot: **TX → {BAR_ALCOHOL}, FL → {BAR_ALCOHOL}, PA → {}**.
PA therefore generates **zero Overpass queries**. This aligns with `OMISSIONS.md`
(PA-no-bar is a researched conclusion) and is politer to the free, shared Overpass
API than querying-then-dropping.

### Category → OSM tag map

A config-defined map (`config.yaml`, see §6) supplies the Overpass tag filters per
category. Pilot:

```yaml
categories:
  BAR_ALCOHOL:
    tags: ["amenity=bar", "amenity=pub"]
```

If auto-scope returns a category with no tag-map entry, the source logs a warning
and skips that category (a config gap, surfaced — never a silent default). For the
pilot only BAR_ALCOHOL is auto-scoped and it has a tag map.

### Fetch and query

One Overpass query **per state**, unioning the tag filters of that state's
auto-scoped categories. Cached as JSON per state at
`data/sources/osm/<state>.json`. `fetch(refetch=...)` skips a state whose cache
exists unless `refetch`. On fetch failure, fall back to cached data if present;
otherwise skip that state and flag it in the report (parent §6 importer-failure
table).

Overpass QL shape (`nwr` = node/way/relation; `out center tags` gives polygon
centroids + tags):

```
[out:json][timeout:180];
area["ISO3166-2"="US-TX"]->.a;
(
  nwr["amenity"="bar"](area.a);
  nwr["amenity"="pub"](area.a);
);
out center tags;
```

### Candidate extraction (`iter_candidates`)

| Field | Source |
|---|---|
| `name` | `tags.name`. Absent → skip, increment `missing_name`. |
| `latitude`/`longitude` | node: `lat`/`lon`. way/relation: `center.lat`/`center.lon`. Absent → skip, `missing_coords`. |
| `coord_quality` | node → `PRECISE`; way/relation → `BUILDING_POLYGON`. |
| `source_external_id` | `"node/<id>"` \| `"way/<id>"` \| `"relation/<id>"` — directly URL-composable for the deferred deep link (`https://www.openstreetmap.org/<id>`). |
| `category` | the category whose tag set matched the element. |
| `state` | the queried state, **validated** against `StateLocator`; mismatch → skip, `coord_state_mismatch` (matches FAA/GSA defensive pattern). |
| `source_dataset_version` | `OSM-2026-06` (from config). |
| `extra` | `{}` (the dump reads OSM ids from `source_external_id`, so no raw-tag retention is required). |

`last_skip_counts: Counter` mirrors the other sources for the report.

### Within-source dedup

The same OSM element can match more than one tag filter (e.g. a venue tagged both
`amenity=bar` and something else) but Overpass returns one element per id, so the
pipeline's existing within-source dedup on `(source, external_id)` is sufficient;
no extra handling.

---

## §3 — Cross-source dedup (no code change)

`stages/dedup.py` already lists `"osm": 6` as the lowest priority in
`SOURCE_PRIORITY`. Bars rarely collide with federal/school/airport pins (different
category, name, and the 100 m radius), but if one does, OSM loses and user pins are
protected — exactly the parent-spec contract. The exit criterion "dedup against
waves 1–2 working correctly" is satisfied by the existing pass. A test asserts OSM
loses a constructed cross-source tie.

---

## §4 — ODbL dump generator (`stages/odbl_dump.py`) + Storage

### What the dump is

The ODbL share-alike obligation requires publishing the **derived database** — the
subset of OSM data we used. Per parent §6.5 it **excludes** our work product
(status, restriction tag, citation, confidence). Columns:

```
osm_type, osm_id, name, latitude, longitude
```

`osm_type`/`osm_id` are split from `source_external_id` (`"way/123"` → `way`,`123`).
Anyone can re-derive our classification from these ids against OSM, which is the
point of share-alike.

File: `dump-YYYY-MM-DD.csv.gz`, gzip-compressed, with a leading `#`-comment **ODbL
license header** (license name, URL, generation date, attribution string) above the
CSV header row.

### SupabaseClient additions

`supabase_client.py` gains (all via the Storage REST API with the service-role key):

- `select_osm_pins_for_dump() -> list[OsmDumpRow]` — `GET /pins?source=eq.osm&select=source_external_id,name,latitude,longitude`, Range-paged if it ever exceeds 1000.
- `ensure_public_bucket(name: str)` — idempotent `POST /storage/v1/bucket` with `{"id": name, "public": true}`; treats "already exists" as success.
- `upload_object(bucket, path, data, content_type)` — `POST /storage/v1/object/{bucket}/{path}` with `x-upsert: true`.
- `list_objects(bucket)` / `delete_objects(bucket, paths)` — for 90-day pruning.

Public read URL: `{project_url}/storage/v1/object/public/{bucket}/{path}`.

### Generator API and pipeline wiring

The Phase 2 stub signature changes from `(out_dir, applied_source_counts)` to take
the client and return the public URL:

```python
def generate_and_upload(
    *, client: SupabaseClient, out_dir: Path, bucket: str = "odbl-dumps",
    today: date | None = None,
) -> str | None:
    """Returns the public URL of the uploaded dump, or None if no OSM rows exist."""
```

`pipeline.run_pipeline` gains **Phase D**, apply-mode only: after per-source apply,
if any `osm` rows were inserted or updated this run, call `generate_and_upload`,
store the URL on `PipelineResult.odbl_dump_url`, and surface it in the Markdown
report's ODbL section. Dry-run never touches Storage.

Bucket `odbl-dumps` is created idempotently by `ensure_public_bucket` on first run
(staging and, later, prod), so there is no manual setup step; the setup is also
documented in `STAGING.md` for operators.

---

## §5 — Label title-casing (`stages/normalize.py`)

Resolves `importer-feedback.md` issue 5 (all-caps labels), deferred 2026-06-05.

### The all-caps-only guard

Apply smart title-casing **only to names with no lowercase letter** (i.e. all-caps
source labels such as GSA's "UNITED STATES COURTHOUSE"). Names that already contain
a lowercase letter are assumed already well-cased (OSM "The Ginger Man", HIFLD/FAA
mixed-case, GSA's recomposed `Office Building — Tampa, FL`) and are left untouched.
This fixes the reported problem without risking damage to intentional casing.

### Smart title-case rules (`stages/_titlecase.py`, new)

Title-case each whitespace token, except:
- **Preserve-list** tokens kept verbatim (uppercase): 50 USPS state codes + federal
  acronyms (US, VA, SBA, FBI, IRS, FAA, GSA, DOD, USACE, NFH, USCG, TSA, DHS, FEMA,
  ATF, DEA, EPA, NOAA, NASA, USDA, …). Curated, maintained, documented in the module.
- **Particles:** `Mc`/`Mac` → `McDonald`; `O'` → `O'Brien`; hyphenated tokens
  title-cased per segment (`Winston-Salem`); apostrophe segments per segment.
- **Roman numerals** (II, III, IV, …) and **ordinals** (1st, 2nd) preserved.

Inserted in `normalize` after `strip()` and before the 60-char truncation (case
change preserves length, so truncation order is immaterial). Applies to **every
source's** candidates.

### Idempotency consequence

Title-casing changes `name` on existing all-caps staging rows, so the **first**
re-apply after this lands produces `UPDATE`s for those rows (expected, desired —
labels get fixed). The **second** apply is INSERT-0/UPDATE-0. This is called out in
the operator task (§8) so the UPDATE count is not mistaken for a bug.

---

## §6 — Config and CLI

`config.yaml` gains:

```yaml
sources:
  osm:
    cache_dir: "data/sources/osm"
    dataset_version: "OSM-2026-06"
    overpass_url: "https://overpass-api.de/api/interpreter"
    area_selector_template: '["ISO3166-2"="US-{state}"]'
    categories:
      BAR_ALCOHOL:
        tags: ["amenity=bar", "amenity=pub"]
```

`cli.py`:
- Add `"osm"` to `SUPPORTED_SOURCES`.
- `_build_source` gains a `state_laws` parameter (the loaded `StateLawTable`) and an
  `osm` branch constructing `OsmSource(cache_dir=…, state_locator=locator,
  state_laws=state_laws, dataset_version=…, overpass_url=…,
  area_selector_template=…, category_tags=…)`. The call site already has
  `state_laws` in scope.

OSM is the only source that depends on the state-law table at query time; this
coupling is intentional and isolated to the OSM branch.

---

## §7 — Tests and live pre-flight

- `tests/sources/test_osm.py` — real captured Overpass JSON fixture (small TX bars
  response with at least one node and one way). Assert: node extraction (`PRECISE`),
  way-center extraction (`BUILDING_POLYGON`), name-absent skip, external-id format,
  category mapping, and `coord_state_mismatch` skip. Plus a unit test of per-state
  auto-scope: TX/FL → {BAR_ALCOHOL}, PA → ∅.
- `tests/test_state_laws.py` — extend for `osm_categories_for_state` (state-specific
  hit, US-fallback behavior, no-cell empty set).
- `tests/stages/test_odbl_dump.py` — **replaces** `test_odbl_dump_stub.py`: no OSM
  rows → `None`; with OSM rows → gz written with license header + exact columns +
  `upload_object` called with the dated path + prune deletes only >90-day files.
  Uses a fake/stub `SupabaseClient`.
- `tests/stages/test_normalize.py` — extend: all-caps → title-cased; acronym and
  state-code preservation; `Mc`/`O'`/hyphen handling; mixed-case input passes
  through unchanged; truncation still applies post-case.
- `tests/stages/test_dedup.py` — add a constructed OSM-vs-higher-source tie asserting
  OSM is dropped.

**Live pre-flight (before writing fixtures):** run one real Overpass query for TX
bars to confirm the endpoint, QL, and `ISO3166-2` area selector behave, capture the
response as the test fixture, and sanity-check the candidate count. Same discipline
as the Phase 5 real-data pre-flight.

---

## §8 — Staging apply + idempotency (operator task)

Run by the operator on the Windows machine (holds the staging service-role key):

1. `python -m importer.cli --dry-run --states TX,FL,PA --sources osm --project-ref staging`
   — confirm bars resolve for TX/FL, PA yields nothing, report is coherent.
2. `--apply … --sources osm --i-know-this-writes-to-staging` — bars inserted for
   TX/FL only; ODbL dump generated and **publicly fetchable** at the printed URL.
3. Full re-apply of **all** sources (`--sources hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm`)
   to land title-casing — expect `UPDATE`s on previously all-caps rows (first time
   only).
4. Re-run step 3 — expect INSERT-0/UPDATE-0 (idempotent).
5. Eyeball clustering around a dense TX/FL metro (Houston/Miami) for the new bars.

Exit criteria (parent §8 Phase 6): dedup against waves 1–2 correct; dump file
accessible from the public Supabase Storage URL; no new security/performance
advisors.

---

## §9 — Documentation

- `docs/importer/SOURCES.md` — add the OSM row (Overpass, ODbL, area-query method,
  per-state auto-scope).
- `docs/importer/STAGING_REAPPLY.md` or `STAGING.md` — public-bucket note and the
  re-apply-for-title-casing step.
- `docs/importer/OMISSIONS.md` — note that under per-state auto-scope, worship/
  sports/healthcare are **never queried** (silent — they will *not* appear in the
  dry-run "missing cells" list, unlike IPEDS TX/PA colleges), and PA bars never
  become candidates at all.
- Repo/importer README — "Data Sources & Licenses" section (parent §6.7), listing
  each source + license + compliance posture. (The in-app legal page is Phase 7.)
- `CLAUDE.md` status line + `memory/project_pre_populate_roadmap.md` updated at close.

---

## §10 — Risks and open items

| Risk | Mitigation |
|---|---|
| Overpass downtime / rate-limit | Per-state JSON cache; one polite union query per state; `timeout` in QL; fall back to cache on fetch failure; report flags skipped states. |
| `ISO3166-2` area selector returns nothing for a state | Caught by the live pre-flight before fixtures are frozen; report shows zero candidates loudly. |
| Title-case preserve-list imperfection (low-priority polish) | Curated list + thorough tests + all-caps-only guard limits blast radius; documented as maintained. |
| Public-bucket creation differs staging vs prod | `ensure_public_bucket` is create-if-not-exists; documented for operators. |
| Storage upload auth (service-role vs Storage API) | One `SupabaseClient` Storage path with the same key; covered by the dump test against a fake client and verified live in the staging apply. |

**Open (resolve in writing-plans):** exact ODbL header text/attribution string;
whether the dump filename should include the project ref to avoid staging/prod
collisions in shared tooling (leaning no — separate buckets per project).
