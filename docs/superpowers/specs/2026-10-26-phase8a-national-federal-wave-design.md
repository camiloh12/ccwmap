# Phase 8a: national federal wave — design

**Status:** draft for owner approval (2026-10-26)
**Scope:** importer + CI workflow + data table. No app change, no migration.
**Legal basis:** `docs/importer/LEGAL_FEDERAL_CARRY_2026-10.md` (owner marked the
lawyer review done 2026-10-26).

## 1. Intent

Someone who carries anywhere in the continental US opens the app and sees the
known no-carry zones in red. This wave ships the places federal law treats the
same in every state: federal buildings, military installations and the secured
areas of commercial airports. State-law categories (schools, state courts,
colleges, bars) stay pilot-only until each state's law is researched.

The owner's bar: red only where the prohibition is clearly known. Missing a
few real ones beats showing false reds. A wrong red costs a user convenience; a
wrong green could cost them a conviction, so where the law is unsettled we stay
red but lower the confidence so users can correct the pin.

## 2. Goals, non-goals, anti-goals

**Goals**
1. GSA (FRPP), MIRTA military and FAA commercial-service pins in all 48
   continental states plus DC, written to prod by the existing pipeline.
2. Red pins only on buildings the statute covers (employees regularly work
   there); unstaffed federal buildings get no pin.
3. Per-pin confidence that reflects the 2026 legal picture: `high` where no
   exception reaches, `medium` where the DOJ now reads an exception.
4. The pilot states converge on the same rules, including deleting their
   pins that the new filter excludes.
5. Everything the final review of the identity work listed as a Phase 8
   prerequisite: a 50-state locator, write retries, "unusable record ≠
   orphan", dedup survivor stickiness.

**Non-goals**
- Post offices (no bulk dataset; and after the OLC opinion they would be
  UNCERTAIN, not red). Separate round.
- State-law categories outside TX/FL/PA.
- Alaska, Hawaii, territories. The app's US boundary check already refuses
  user pins there; imported pins follow the same box. (Claude's call.)
- Any app change. Medium-confidence pins already show the orange "verify
  locally" caveat (Phase 7 Stage A).
- Cluster-rendering changes. Prod lands near 40k pins; the spec's revisit
  threshold is ~50k.
- Army Corps recreation areas, National Wildlife Refuge grounds and other
  land-based federal rules: they are not buildings.

**Anti-goals** (failure even if it runs)
- A red pin on a restroom, housing, barracks or radio site.
- A user pin deleted or overwritten.
- Any write before every source in the run has been fetched and validated.
- A prod apply whose deletions were not first seen in a dry-run report.

## 3. Scope and expected size

Measured on the cached FY24 FRPP file (2026-10-25):

| | National | Pilot (TX/FL/PA) |
|---|---|---|
| FRPP buildings, not Disposed | 112,123 | 9,733 |
| After the use filter (§4.2) | ~29,000 | ~3,100 |
| Pins after dedup (estimate: pilot ratio 4,184 / 9,733) | ~13,000–15,000 | ~1,400 |
| MIRTA sites (all components) | 825 boundaries | 101 pins today |
| FAA commercial-service airports | ~500 | 60 pins today |

Prod goes from 23,904 system pins to roughly 40,000. The pilot states lose
about 2,700 GSA pins (housing, restrooms, barracks, communications,
navigation aids, zero-employee buildings).

FRPP's public file excludes DoD buildings, so GSA and MIRTA do not overlap.
The dedup priority order is unchanged (`user > nces > ipeds > faa > gsa >
hifld_* > osm`).

## 4. What changes

### 4.1 State locator: all 50 states + DC

`importer/cli.py` builds the locator from `tests/fixtures/states_sample.geojson`
(TX/FL/PA only). Replace it with a Census cartographic boundary file for states
(`cb_<year>_us_state_500k`, converted to GeoJSON with `STUSPS` properties)
kept under `data/geo/` and referenced from `config.yaml`. Use the 500k
(finest) resolution: a point outside every polygon resolves to `None`, which
drops the candidate and takes the pin out of orphan scope, so a coarse
coastline would silently lose piers, Coast Guard stations and Kennedy Space
Center. The current fixture is already 500k precision. Tests keep the small
fixture. The file is public domain; record its vintage in
`docs/importer/SOURCES.md`. The first staging dry-run compares
`coord_state_mismatch` counts with the pilot's as a check.

The locator is also what scopes orphan detection to the run's states
(`stages/orphans.py: scope_to_states`), so a national run scopes nationally.

### 4.2 GSA: keep only buildings where federal employees work

`sources/gsa.py` already keeps `Real Property Type == Building` and drops
`Asset Status == Disposed`. Add, in this order:

1. **Drop by use.** `Real Property Use` in: Family Housing, Comfort
   Station/Restrooms, Dormitories/Barracks, Communications Systems,
   Navigation and Traffic Aids. Skip count `use_unstaffed`. Also drop
   `Post Office` (19 rows nationally): post offices are a later round and,
   after the OLC opinion, would not be red. Skip count `use_post_office`.
2. **Drop zero-employee buildings.** `Number of Federal Employees` parses to
   `0` → skip count `zero_employees`. Blank is not zero (68% of rows are blank).
3. **Keep by use** (no employee data needed): Office, Courthouse,
   Laboratories, Hospital, Outpatient Healthcare Facility, Prisons and
   Detention Centers, Land Port of Entry, Border/Inspection Station, Aviation
   Security Related, Facility Security, Public Facing Facility, School,
   Museum, Child Care Center, Data Centers.
4. **Gray uses need evidence.** Warehouses, Service, Industrial, All Other,
   Other Institutional Uses: keep only when `Number of Federal Employees`
   parses to a number > 0. Otherwise skip count `use_unverified`.
5. Any use value not in the three lists above → skip count `use_unknown`,
   and the dry-run report lists the distinct unknown values so a new FRPP
   vintage can't silently add a category.

The use lists live as module constants next to the existing column
constants, with the legal memo cited in the comment. The dry-run report's GSA
section shows the skip counts and a per-use count of kept rows.

### 4.3 Per-candidate confidence override

Today `stages/apply.py` takes `confidence` from the state-law cell. Add an
optional `confidence_override: Literal["high", "medium"] | None` to
`Candidate` (default `None`); `apply.py` writes
`candidate.confidence_override or cell.confidence`. The cell's
`default_status`, citation and verified date are unchanged by the override.
The override may only lower confidence (`high → medium`); a source that sets
`high` on a `medium` cell is a bug, so `apply.py` raises.

Sources set it as follows:

**GSA** (`medium` unless listed as high)
- `high`: Courthouse, Prisons and Detention Centers, Land Port of Entry,
  Border/Inspection Station, Aviation Security Related, Facility Security,
  School (BIE schools are the only federal "School" rows); and Hospital or
  Outpatient Healthcare Facility **only when `Reporting Agency Code` is
  `36` (Veterans Affairs)**, because the `high` rests on VA's own rule
  (38 CFR 1.218). Other agencies' clinics (Indian Health Service, for
  example) are ordinary federal facilities and get `medium`.
- `medium`: every other kept use (Office, Laboratories, Public Facing
  Facility, Museum, Child Care Center, Data Centers, non-VA health
  facilities, and the gray uses kept by employee count).
- `medium` regardless of use when `Legal Interest Indicator` is not `Owned`
  (leased floors in private buildings: only the leased part is a federal
  facility), **except** Courthouse, which stays `high` (18 USC 930(e) has no
  lawful-purposes exception).
- `medium` regardless of use when `Reporting Agency Code` is Interior (`14`)
  or Agriculture (`12`) and the use is Public Facing Facility, Museum or a
  gray use: park and forest visitor buildings, where DOJ has said self-defense
  carry is permitted.

**MIRTA** (`high` unless Guard)
- `medium` when `SITEREPORTINGCOMPONENT` is `armyNationalGuard` or
  `airNationalGuard` (262 of 825 sites). Guard sites are state-controlled and
  carry there follows state law.

**FAA**: no override (`high`).

**Dedup clusters.** When same-source GSA rows collapse into one pin (5,501
of 9,690 did in the last prod run), the surviving *record* is chosen by
§4.5.3 (sticky key, then the existing tie-break), and the pin's confidence
is the **highest** among the collapsed rows: the pin stands for the whole
complex, and a courthouse with an office annex is a courthouse. Status is
never affected (every row in this wave is NO_GUN). Confidence never
influences which record survives, so it adds no insert/delete churn.

The dry-run report shows, per source, how many candidates carry each
confidence.

### 4.4 `data/state_laws/states.yaml`

The `US / FEDERAL_PROPERTY` cell keeps `default_status: NO_GUN` and
`confidence: high`. Update:
- `citation`: `18 USC §930(a); §930(d)(3) as read by OLC, Application of
  18 U.S.C. § 930(a) to Post Offices (Aug. 12, 2026)`.
- `last_verified_date: 2026-10-25`.
- `notes`: state that the importer lowers confidence to `medium` per §4.3,
  and name the watch list (Zimmerman v. Blanche, Hornbake v. Blanche, any
  Fifth Circuit ruling on §930(a), withdrawal of the OLC opinion, VA changes
  to 38 CFR 1.218).

`importer/tests/test_state_laws.py` keeps the citation and date under test.
`docs/importer/OMISSIONS.md` gets a short "federal buildings not pinned"
entry pointing at §4.2 and the memo.

### 4.5 Prerequisites from the identity-work review

1. **Write retries.** `SupabaseClient` retries POST/PATCH/DELETE on
   `httpx.TransportError` and HTTP 429/5xx, bounded (3 attempts, 1 s/2 s
   backoff, like `osm.py`). Upserts are idempotent (`ON CONFLICT`), deletes
   are idempotent, `patch_external_id` is idempotent. `insert_import_run` is
   not: on a retry after an ambiguous failure it may create a second run
   row; acceptable, the health check reads only completed runs.
2. **Unusable record ≠ orphan.** A source that *saw* a record but dropped it
   for a data problem (coordinate outside its state, geocode miss, missing
   name) must not cause the existing pin for that key to be deleted as an
   orphan; the pin should be **kept and marked** (`source_orphaned_at`) and
   counted separately in the report (`unusable_kept`). Sources expose the
   keys they saw-but-dropped; `plan_orphans` treats them like user-modified
   pins (keep, never delete). Rows dropped by the §4.2 use filter are *not*
   "unusable": they are deliberately excluded and their pins are real orphans.
3. **Dedup survivor stickiness.** When two candidates match in
   `stages/dedup.py` and have equal source priority, prefer the one whose
   `(source, source_external_id)` already exists in the database, so a pin
   does not flip to the other record (and get deleted + re-inserted) on
   alternate runs. Existing keys are already loaded for the diff; pass them
   in. Cross-source matches keep the priority order.

### 4.6 Workflow: one-time cap override

`.github/workflows/importer-apply.yml` gets an input `orphan_delete_cap`
(string, default empty). Empty → unchanged behaviour. The value is
**per source**, `gsa=2700` (comma-separated for several), so lifting GSA's
cap for the one-time cleanup leaves MIRTA's and FAA's caps in place: a bad
fetch of a small source in that run still cannot wipe it. The CLI's
`--orphan-delete-cap` takes the same form (a bare integer stays accepted for
local runs and applies to every source). It is honoured only together with
`delete_orphans`; the run summary prints the value in bold. The `states` input default stays
`TX,FL,PA`; the national runs pass the 49-code list explicitly, and the
runbook carries it so nobody retypes it. `tests/test_apply_workflow.py` locks
the new input and the "only with delete_orphans" rule.

### 4.7 Scale checks (builder verifies, not design decisions)

- FRPP parse is ~90 s single-pass; the pipeline reads it once. Fine.
- `select_pins_by_keys` / `mark_orphans` / `delete_pins` already chunk at
  200 ids; the national diff loads ~40k system pins via
  `select_system_pins` pages of 1,000. Fine.
- Dedup STRtree over ~30k candidates: seconds.
- The CI job's 6-hour limit is far above the pilot's 9 minutes; expect
  under 30 minutes.

## 5. Rollout (operator runbook, to be added to `docs/importer/PROD_APPLY.md`)

Every step is a run you approve; nothing below is automatic.

1. **Staging dry-run**, sources `gsa,hifld_military,faa`, all 49 codes,
   `--refetch`. Read the report: skip counts, per-use kept counts,
   confidence counts, deletes per source (expect GSA ≈ 2,700 in the pilot
   states, far over the cap), no `unusable_kept` surprises, no unknown uses.
2. **Staging apply** with `delete_orphans` and `orphan_delete_cap` set to
   `gsa=<the dry-run's GSA delete count, rounded up>`; the other sources
   keep their default caps. Second dry-run must be all zeros.
3. Next day's health check green (its 24 h window will hold the deletions,
   inside the apply's `import_runs` window).
4. **Prod dry-run** (read-only, local, with the prod service-role key; same
   flags). Numbers must match staging within source churn.
5. **Prod apply** with the same `orphan_delete_cap`; then a prod dry-run
   that returns all zeros, and a spot check of clusters at zoom 5 over the
   West (California, Arizona, New Mexico carry most federal buildings).
6. Update `docs/importer/PROD_HEALTH_CHECK.md`'s baseline table, CLAUDE.md's
   status line, and archive the report under `.local/importer-reports/`.

Rollback stays the one `DELETE … WHERE created_by = <system user>`; the
pilot-state pins would come back with a TX/FL/PA re-apply.

## 6. Tests

TDD throughout. At minimum:
- GSA: each skip bucket; blank vs `0` employees; unknown use listed; each
  override rule (use, leased, Interior/USDA, courthouse stays high).
- MIRTA: Guard component → medium; others high.
- `apply.py`: override lowers only; raising on an illegal raise.
- Locator: a national file resolves a point in each of three non-pilot
  states and `None` offshore.
- Orphans: a saw-but-dropped key is kept and marked, never deleted; a
  use-filtered key is a real orphan.
- Dedup: an equal-priority match keeps the existing key.
- Client: a 503 then 201 succeeds; four 503s raise; no retry on 4xx other
  than 429.
- Workflow structure test for the new input.

## 7. Left to the builder

- Exact Census file vintage and the conversion script (keep it in
  `importer/scripts/` with a one-line README).
- How sources expose saw-but-dropped keys (a set on the source, like
  `last_skip_counts`).
- Report layout for the new counts.
- Whether the override is a field on `Candidate` or a wrapper; the behaviour
  in §4.3 is what matters.

## 8. Open items after this wave

- Post offices (yellow), once a dataset exists.
- State-law research for the other 47 states (schools, courts, colleges,
  bars).
- Leased-space caveat text in the app ("applies to the federal offices
  inside"), which needs an app release.
- Cluster rendering before the K-12 wave pushes past ~50k.
