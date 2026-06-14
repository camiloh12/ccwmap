# Phase 5 — Pilot Wave 2: Schools + Airports

**Date:** 2026-06-14
**Status:** Draft — pending implementation plan via writing-plans
**Parent spec:** [`2026-05-10-pre-populate-pins-design.md`](2026-05-10-pre-populate-pins-design.md) §8, phase 5

## Background

Phases 0–4 of the pre-populate-pins project are complete. The provenance schema
(migration `008`) is in production; the viewport sync model (`MyPinsSync` +
`ViewportPinsManager`) shipped in v0.6.0; the importer runs a multi-source
pipeline with real cross-source dedup; the federal floor (HIFLD courthouses + GSA
federal property + HIFLD military) is staging-applied and idempotency-verified for
TX/FL/PA. The state-law table is seeded for TX/FL/PA + the federal-uniform `US`
cells.

Phase 5 ships the **second pilot wave: schools + airports** — per parent spec §8
the sources are NCES K-12, IPEDS colleges, and FAA airports for TX/FL/PA
(~15–25k pins). This is the largest pin wave of the pilot and the first real
clustering stress test (Houston, Miami, Philadelphia at neighborhood zoom).

Architecturally this phase adds **nothing new** — it reuses the multi-source
pipeline, the cross-source dedup, the `Candidate` contract, the CLI source-factory
registry, and the frozen-fixture test pattern that Phase 4 established. The work is
three new `Source` subclasses plus their wiring, fixtures, tests, and docs.

## Scope decisions (settled in brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Airport scope | **Commercial-service / TSA-screened airports only** | The `AIRPORT_SECURE` cell asserts NO_GUN for the TSA sterile area *past a screening checkpoint*. Most NPIAS entries are general-aviation fields with no screening; pinning those asserts a restriction that legally does not exist there. ~50 airports across TX/FL/PA. |
| K-12 scope | **Public schools only (NCES CCD + EDGE geocodes)** | ~16k pins across TX/FL/PA already roughly fills the wave's pin target; CCD/EDGE coords are precise and the dataset is annual. Private schools (PSS) add coarser coordinates and a second biennial dataset — deferred to a later wave. |
| Landing target | **Staging apply only** | Same posture as Phase 4. Prod apply remains deferred until the new app version is proven live with users (per the project's standing rule). |
| New phases/sub-phases | **One combined phase, three sources** | The sources are independent and small; Phase 4 already proved the multi-source shape. No 5a/5b split. |
| Schema | **No new migration** | `008` already added every provenance column these sources write, and its `source` enum already includes `nces`, `ipeds`, `faa`. |
| Coordinate refinement | **`refine_coords` stays pass-through** | All three sources carry native coordinates (NCES EDGE LAT/LON, IPEDS HD LATITUDE/LONGITUD, FAA airport reference point). No Overpass refinement needed. |
| ODbL attribution UI | **Still deferred to Phase 6** | No `source='osm'` pin exists until Phase 6; wiring the UI now ships it dormant and untestable. |

**In scope:** `sources/nces.py`, `sources/ipeds.py`, `sources/faa.py`; their
`config.yaml` blocks and CLI registry entries; frozen fixtures + unit tests;
pipeline/CLI/report extension for the new sources; docs.

**Out of scope:** prod apply; any Flutter change; migration `009` (none needed);
private K-12 (PSS); general-aviation airports; Overpass coordinate refinement;
state widening beyond TX/FL/PA; the OSM long tail and ODbL dump/attribution
(Phase 6).

## Constraints

- No schema migration. These sources write only columns added by `008`
  (`source`, `source_external_id`, `source_dataset_version`, `imported_at`,
  `confidence`, `legal_citation`, `legal_citation_verified_date`).
- TX/FL/PA only, via the existing `importer/tests/fixtures/states_sample.geojson`
  boundary fixture. No full-50-state file required at this scope.
- All new modules 100% unit-tested against frozen fixtures per
  `docs/dev/TESTING_GUIDELINES.md`.
- The non-negotiable rule from parent spec §7 holds: **apply never targets prod
  from a developer machine.** This round, apply targets staging only.
- The importer reads its service-role key from
  `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`; staging applies use the staging
  service-role key (GitHub Actions secret or the operator's local equivalent).
- The Supabase MCP is now bound to **staging** (`.mcp.json`,
  `project_ref=miihmfhnsfmwgrvgayns`), so post-apply verification queries
  (counts, idempotency, advisors) can run directly over MCP rather than through
  the dashboard. MCP access to prod has been removed.

## Success criteria

- `python -m importer.cli --dry-run --states TX,FL,PA --sources nces,ipeds,faa --project-ref staging`
  produces a coherent combined report: per-source candidate counts, the
  IPEDS TX/PA "missing cell" drops as *expected* noise, and cross-source dedup
  drops by source pair.
- Apply mode against **staging** inserts school/college/airport pins with correct
  `source`, `restriction_tag`, `confidence`, and `legal_citation`, and is
  idempotent (a second run is all-SKIP).
- A combined staging apply of *all six* sources (`hifld_courts,gsa,hifld_military,nces,ipeds,faa`)
  exercises cross-wave dedup; the drops-by-pair report is reviewed and shows no
  spurious collapses.
- Cross-source duplicate rate `<1%`; user-created pins (`source='user'`) are never
  clobbered.
- The app, pointed at staging, renders sensible clustering in Houston, Miami, and
  Philadelphia at regional and neighborhood zoom (parent spec §8 Phase 5 exit
  criterion).
- Full importer test suite stays green.

---

## §1 — New source modules

All three subclass `Source`, expose a stable `SOURCE_NAME`, implement
`fetch(refetch=...)` (httpx + on-disk cache, same discipline as Phase 4) and
`iter_candidates(state_filter)` yielding `Candidate`s, and populate a
`last_skip_counts: Counter` exhausted-iterator side effect. Each carries native
coordinates, so every Candidate is `coord_quality=PRECISE`. State assignment
validates the source's own state field against `StateLocator` point-in-polygon on
the emitted coordinate (the GSA pattern: trust geometry, drop coord/state
mismatches) — this also enforces the TX/FL/PA fixture scope.

### `sources/nces.py` (public K-12 → `category=SCHOOL_K12`)

NCES distributes public-school identity in the **Common Core of Data (CCD)**
directory file and geographic coordinates in the separate **EDGE** geocode file.
Plan:

1. **Primary file — EDGE public-school geocode** (single national file:
   `NCESSCH` stable id, school name, `STATE`/state-FIPS, `LAT`/`LON`, address).
   Native coords → `PRECISE`.
2. **Operational filter — CCD directory `STATUS`**, joined on `NCESSCH`, keeping
   only open schools. This protects the ≥95% coordinate-accuracy criterion by
   not plotting closed campuses. (Exact CCD status codes pinned at pre-flight
   against the live file; if the EDGE file alone proves to already exclude closed
   schools in the current release, the join is dropped and noted.)
3. `external_id = NCESSCH`. `category = SCHOOL_K12` (cells exist for TX/FL/PA).
4. Skip counters: `missing_coords`, `coord_state_mismatch`, `filtered_out`,
   `missing_external_id`, `missing_name`, `not_operational`.

Residual closed-school drift beyond the status filter is caught by the existing
orphan tracking (`source_orphaned_at`) and user correction.

### `sources/ipeds.py` (colleges → `category=COLLEGE_UNIVERSITY`)

Single IPEDS **HD** ("directory information") CSV per year: `UNITID` (stable id),
`INSTNM` (name), `STABBR` (state), `LATITUDE`/`LONGITUD`, plus operating-status
fields. Native coords → `PRECISE`.

- Filter to currently-operating institutions (drop closed/inactive via the HD
  status field).
- `external_id = UNITID`. `category = COLLEGE_UNIVERSITY`.
- **Only FL has a `COLLEGE_UNIVERSITY` cell.** TX and PA college candidates are
  therefore dropped by `apply_state_law` (no matching cell) and surface in the
  dry-run "missing cells / needs research" list — this is *designed behavior*,
  cross-referenced in `docs/importer/OMISSIONS.md` (TX campus-carry; PA depends
  on institution policy). The report reader must not treat these as gaps.
- Skip counters: `missing_coords`, `coord_state_mismatch`, `filtered_out`,
  `missing_external_id`, `missing_name`, `not_operating`.

### `sources/faa.py` (commercial-service airports → `category=AIRPORT_SECURE`)

The `AIRPORT_SECURE` prohibition attaches to the TSA sterile/secured area, which
exists only at airports with passenger screening. Phase 5 therefore pins the
**commercial-service subset only**, not all NPIAS:

1. **Commercial-service list** — the authoritative FAA set of commercial-service
   airports (`LOCID` + state + service-level/enplanements flag). Public domain
   (US Gov).
2. **Coordinates** — joined from the FAA **NASR APT** ("Airport Data & Contact
   Information") dataset on `LOCID` → airport reference point (ARP) lat/lon. Public
   domain.
3. `external_id = LOCID`. `category = AIRPORT_SECURE` (federal-uniform `US` cell).
   ~50 pins across TX/FL/PA.
4. Skip counters: `missing_coords`, `coord_state_mismatch`, `not_commercial_service`,
   `missing_external_id`, `missing_name`.

Exact dataset URLs (commercial-service list + NASR APT release) are pinned in
`config.yaml` with a `dataset_version` at pre-flight, the same way Phase 4 pinned
the FRPP and MIRTA URLs. The small count makes the two-file join cheap to verify
by hand.

---

## §2 — Dedup interaction (no code change)

`stages/dedup.py` is unchanged. Its priority order already reserves the Phase 5
tiers: `user(0) > nces(1) > ipeds(2) > faa(3) > gsa(4) > hifld_*(5) > osm(6)`. Two
records collapse only when within **100 m AND** `token_set_ratio(name) ≥ 70`; the
higher-priority source wins.

Notes specific to this wave, to validate in the staging drops-by-pair report:

- **"Airport" pins already visible from Phase 4 are `FEDERAL_PROPERTY`** — GSA
  federal facilities (FAA/TSA offices, control towers, federal inspection
  stations) and HIFLD military airfields/bases — not `AIRPORT_SECURE`. A Phase 5
  FAA pin sits at the runway-center ARP, typically hundreds of meters to
  kilometers from any building/base centroid on the same property, so the 100 m
  gate usually leaves them **coexisting** — which is correct: a base-wide
  18 USC 930 prohibition and a TSA sterile-area assertion are distinct legal
  claims at distinct points. Genuine same-spot/same-name duplicates still resolve
  automatically, with the FAA pin winning (priority 3 beats 4 and 5).
- **Schools vs colleges:** an NCES K-12 campus and an IPEDS institution rarely
  share a location; where they do, `nces` wins. Low risk.
- The 100 m / 70 thresholds are one-line constants; if the staging dry-run shows
  mis-tuned collapses for this wave, tune before any apply.

---

## §3 — Wiring: CLI, config, reports

- **`cli.py`:** add `nces`, `ipeds`, `faa` to `SUPPORTED_SOURCES`; extend the
  `_build_source` registry with their constructors (reading `cache_dir`,
  `dataset_version`, `url`(s) from `config.yaml`), mirroring the existing
  `gsa`/`hifld_military` branches.
- **`config.yaml`:** add `nces`, `ipeds`, `faa` blocks under `sources:` with
  `cache_dir`, `dataset_version`, and pinned URL(s). NCES and FAA each reference
  two upstream files (geocode + directory / commercial-service + NASR), so their
  blocks carry the two URLs they need.
- **Pipeline:** unchanged — `run_pipeline` already accepts an arbitrary
  `list[Source]` and produces per-source breakdowns + combined dedup. No
  source-specific branches added beyond the existing GSA geocode-stat special
  case (the new sources need none).
- **Reports (`reports/markdown.py`, `reports/json_report.py`):** the existing
  per-source + dedup report structure already covers the new sources. Confirm the
  "missing cells" section renders the expected IPEDS TX/PA drops clearly so a
  report reader recognizes them as intentional.

---

## §4 — Testing, docs, dependencies

### Tests (frozen fixtures, mirroring `test_gsa.py` / `test_hifld_military.py`)

- `tests/sources/test_nces.py` — frozen EDGE + CCD-status fixture rows: coord/
  state/category/external_id; `not_operational` drop; `coord_state_mismatch`
  drop; TX/FL/PA filtering.
- `tests/sources/test_ipeds.py` — frozen HD rows: FL institution classified
  `COLLEGE_UNIVERSITY`; a TX and a PA institution that survive the source but get
  **dropped at `apply_state_law`** (assert the "missing cell" path, not a source
  skip); closed-institution drop.
- `tests/sources/test_faa.py` — frozen commercial-service + NASR fixture rows:
  a commercial-service airport emitted with `AIRPORT_SECURE`; a general-aviation
  field **excluded** (`not_commercial_service`); `LOCID` external_id; coord join.
- `tests/test_pipeline.py` — extend with a multi-source run including the new
  sources, asserting the combined result and that IPEDS TX/PA drops land in the
  missing-cells report rather than as inserts.
- `tests/test_cli.py` — extend for the new source names + combined report.

### Docs

- `docs/importer/SOURCES.md` — mark NCES (public K-12), IPEDS, FAA
  (commercial-service) as Phase 5 (built); record dataset files, the
  commercial-service rationale, and the EDGE+CCD / commercial-service+NASR join
  notes.
- `docs/importer/OMISSIONS.md` — already documents TX/PA `COLLEGE_UNIVERSITY`;
  add a one-line pointer that IPEDS now actively produces those expected drops.
- `docs/superpowers/plans/2026-06-14-phase5-schools-airports-plan.md` — the
  implementation plan (written next via writing-plans).
- `CLAUDE.md` status line bumped when the phase lands.

### Dependencies

None new. NCES/IPEDS files parse with the stdlib `csv` module (or `openpyxl` if a
release ships `.xlsx`, already a dependency); FAA NASR parses the same way;
`shapely`/`rapidfuzz` are already present and untouched.

### Running (operator + agent split)

The agent builds + greens all tests locally. The staging dry-run and apply need
the staging service-role key in `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`:

- If the operator provides the staging key in the agent's environment, the agent
  can run the dry-run/apply directly.
- Otherwise the dry-run/apply is operator-run; the agent reviews the report and
  verifies the resulting staging state over the now-staging-bound MCP (row
  counts, idempotency on a second run, advisors).

The dry-run report is reviewed together before any apply. The clustering eyeball
(Houston/Miami/Philadelphia) is an app-side step against staging.

---

## §5 — Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| NCES coordinate file shape differs from assumption (EDGE vs CCD-directory; column names; FIPS vs USPS state) | Medium | Medium | Pin exact files + columns at pre-flight against the live release, as Phase 4 did for FRPP; `coord_state_mismatch` guard drops mis-located rows; dry-run exposes TX/FL/PA counts. |
| NCES includes closed schools the status filter misses | Medium | Medium per pin | CCD `STATUS` join + orphan tracking + user correction (`user_modified` respected on re-import). |
| FAA two-file join (commercial-service × NASR) keys don't line up cleanly on `LOCID` | Medium | Low | Tiny count (~50) makes the join hand-verifiable; unmatched airports reported, not coordinate-faked. |
| IPEDS TX/PA "missing cell" drops misread as a bug | Medium | Low | Documented as designed behavior here and in `OMISSIONS.md`; report renders them in a clearly-labeled section. |
| Dense-area clustering (Houston/Miami/Philadelphia) regresses app perf at the new pin volume | Low–Medium | Medium | `get_pins_in_view` server-side clustering already handles this; staging is the realistic test; revisit cluster strategy (parent spec §8 Option C) only if needed. |
| FAA airport pin spuriously deduped against a Phase 4 federal-property pin | Low | Low | 100 m gate + ARP placement keep them distinct; staging drops-by-pair report is the checkpoint; thresholds are one-line tunables. |

## References

- Parent spec: `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` §1, §3, §4, §8.
- Phase 4 spec: `docs/superpowers/specs/2026-06-02-phase4-federal-floor-design.md`.
- Intentional omissions: `docs/importer/OMISSIONS.md`.
- NCES Common Core of Data: https://nces.ed.gov/ccd/
- NCES EDGE geocodes: https://nces.ed.gov/programs/edge/Geographic/SchoolLocations
- IPEDS: https://nces.ed.gov/ipeds/
- FAA NPIAS / commercial-service airports: https://www.faa.gov/airports/planning_capacity/npias/
- FAA NASR (Airport Data): https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/
