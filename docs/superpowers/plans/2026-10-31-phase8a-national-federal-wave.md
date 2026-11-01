# Phase 8a National Federal Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import GSA federal buildings, MIRTA military sites and FAA commercial-service airports for the 48 contiguous states plus DC, with red pins only on staffed federal buildings and a per-pin confidence that reflects the 2026 legal picture.

**Architecture:** A committed Census 500k state file replaces the TX/FL/PA test fixture as the state locator, so sources and orphan scoping work nationally. GSA gains a use and employee-count filter; GSA and MIRTA set a per-candidate `confidence_override` that can only lower the state-law cell's confidence, and dedup carries the highest confidence through same-source clusters while preferring keys already in the database on ties. Orphan planning keeps and marks pins whose record the source saw but could not use, client writes retry transient failures, and the apply workflow gains a one-time per-source cap override.

**Tech Stack:** Python 3.12 importer (pydantic 2, shapely 2, httpx 0.27, openpyxl, rapidfuzz, pytest 8, pytest-httpx 0.30), pyshp for the one-off boundary conversion only (ad hoc via `uv run --with pyshp`, not a project dependency), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-26-phase8a-national-federal-wave-design.md`. Legal basis: `docs/importer/LEGAL_FEDERAL_CARRY_2026-10.md`. Read the spec first; this plan argues from it.

## Global Constraints

- **No app change, no migration, no schema change.** `pins.confidence` already exists; medium-confidence pins already show the "verify locally" caveat.
- **System user:** `81775f8b-1a6a-47d6-b793-e9ab7e38634e`. Deletes still touch only pins with `created_by` = this UUID and `user_modified = false`.
- **Geography:** 48 contiguous states plus DC. The national `--states` value (49 codes) is `AL,AZ,AR,CA,CO,CT,DE,DC,FL,GA,ID,IL,IN,IA,KS,KY,LA,ME,MD,MA,MI,MN,MS,MO,MT,NE,NV,NH,NJ,NM,NY,NC,ND,OH,OK,OR,PA,RI,SC,SD,TN,TX,UT,VT,VA,WA,WV,WI,WY`. The workflow's `states` default stays `TX,FL,PA`.
- **Dedup priority is unchanged:** `user > nces > ipeds > faa > gsa > hifld_* > osm`.
- **Confidence only goes down.** An override is `"high"`, `"medium"` or `None`. It may never rank above the cell's confidence (`low < medium < high`). Status never changes: every row in this wave is `NO_GUN`.
- **FRPP values are strings.** Agency codes: Veterans Affairs `"36"`, Interior `"14"`, Agriculture `"12"`. Owned legal interest is `"Owned"`. `Number of Federal Employees` is text and uses thousands separators (`"1,951"`).
- **MIRTA Guard components:** `armyNationalGuard`, `airNationalGuard` (262 of 825 boundaries, checked 2026-10-31).
- **Retries:** 3 attempts, sleeping 1 s then 2 s, on `httpx.TransportError` and HTTP 429, 500, 502, 503, 504. Never on any other 4xx.
- **Delete cap:** default unchanged, `max(50, 5% of in-scope pins)`. Override is per source (`gsa=2700`, comma-separated) or a bare integer that applies to every source.
- **Prod is never written in this plan.** Staging is written only by `importer-apply.yml`, and only after the owner says go. The Supabase MCP is bound to staging.
- **Commands:** importer commands run from `importer/` (`uv run pytest`). CI tests run from the repo root: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`. Git runs from the repo root. Baseline before Task 1: **251** importer tests and **145** CI tests, all passing.
- **Appended test snippets** that start with imports or constants: move those to the top of the file with the existing ones.
- **Commits:** each commit command shows the subject line only. End every message with the attribution trailers from your session's system reminder, and check them before pushing (Haiku and Sonnet subagents have rewritten them before).

## Spec refinements (decided while planning; flag any you disagree with)

1. **An illegal override fails at classification, not only in `apply.py` (Task 2).** `ClassifiedCandidate` checks the override when it is built, so a bad source stops the run in Phase A. Raising only in `apply.py` would fail after earlier sources were already written, which is the spec's first anti-goal. `apply.py` still checks, for copies made without validation.
2. **The unknown-use check runs before the zero-employee rule (Task 3).** Both drop the row. Checking unknown first means every unfamiliar use value reaches the report, including rows that also report 0 employees.
3. **Employee counts drop thousands separators (Task 3).** `"1,951"` is 1,951. Any other unparseable value counts as blank, which is not zero.
4. **Cluster confidence counts same-source rows only, capped at the survivor's own cell (Task 8).** The spec's case is GSA rows collapsing into one pin. A cross-source loser does not lend its confidence, and nothing can rise above the cell, so the "only lowers" rule holds after dedup.
5. **A deliberate exclusion is checked before any data problem, in every source (Tasks 3 and 7).** GSA's use filter runs before the name, address, geocode and coordinate checks. MIRTA's closed-site check moves ahead of its geometry check. An excluded record therefore never counts as "unusable", and its pin is a real orphan.
6. **Saw-but-dropped keys come from `gsa`, `hifld_military` and `faa` only (Task 7).** The other sources keep today's behaviour.
7. **Three attempts in total (Task 10).** The spec's test "four 503s raise" becomes "a server that keeps answering 503 raises after exactly three requests". Every POST, PATCH and DELETE in the client retries, storage calls included. Reads do not.
8. **The workflow refuses `orphan_delete_cap` without `delete_orphans` (Task 11).** Ignoring it silently would hide an operator mistake. The CLI rejects a cap that names a source outside `--sources`, so a typo cannot fall back to the default cap unnoticed.
9. **The Interior/Agriculture rule is redundant today (Task 4).** None of the uses it names are on the high list. It is implemented anyway so a later change to the high list cannot make park visitor centers high.
10. **A merged MIRTA site takes the component of its first record (Task 5),** the same record `extra` already uses.
11. **Locator file (Task 1):** Census `cb_2025_us_state_500k`, 51 features (50 states plus DC, territories dropped), coordinates rounded to 6 decimals. Measured 2026-10-31 at 6,491,726 bytes, loading in 0.2 s. Census publishes NAD83, which is used as WGS84; the two differ by about 1–2 m in the contiguous states.
12. **Existing system pins load once, before dedup (Task 9).** Dedup needs their keys for stickiness, and the diff reuses the same lists.
13. **GSA rows with an unknown use count as unusable, not as real orphans (Task 4; decided at the final whole-branch review).** Their existing pins are kept and marked rather than deleted. This departs deliberately from the letter of spec §4.5.2: §4.2.5 exists so a new FRPP vintage can't silently change what is pinned, and a permanent deletion should need an operator decision. The other use filters (`use_unstaffed`, `use_post_office`, `zero_employees`, `use_unverified`) stay real orphans.

## Review Focus

The five inputs the spec implies but no spec-listed test covers, most likely first. Each has a test in the task named.

1. **Employee counts with a thousands separator.** About 100 FRPP rows read `"1,951"`. A staffed warehouse must be kept, not dropped as `use_unverified`. (Task 3)
2. **A deliberately excluded record that also has a data problem.** A Family Housing row with a coordinate outside its state, or a closed MIRTA site with no geometry, must count as excluded. Its pin must be deleted as an orphan, not kept as "unusable". (Tasks 3 and 7)
3. **Use values in a different case.** `"OFFICE"` must classify and count as `Office`, never as an unknown use. (Task 3)
4. **Operator-typed cap values.** `" gsa=2700 , faa=10 "` must parse. `gas=2700`, or a source missing from `--sources`, must be a usage error rather than a silent default cap. (Task 11)
5. **An illegal override in a later source.** The run must stop before anything is written, even when earlier sources were fine. (Task 9)

## File map

| File | Change | Task |
|---|---|---|
| `importer/importer/geo/states.py` | add `US_STATES_AND_DC` | 1 |
| `importer/scripts/make_state_boundaries.py`, `importer/scripts/README.md` | new | 1 |
| `data/geo/us_states_500k.geojson` | new (generated) | 1 |
| `importer/config.yaml`, `importer/importer/cli.py` | locator path; per-source cap | 1, 11 |
| `importer/importer/candidate.py` | `confidence_override` | 2 |
| `importer/importer/stages/apply_state_law.py` | `CONFIDENCE_RANK`, `ClassifiedCandidate.confidence` | 2 |
| `importer/importer/stages/apply.py` | write `cc.confidence`; mark unusable orphans | 2, 6 |
| `importer/importer/sources/gsa.py` (+ fixture script and `.xlsx`) | use filter, confidence, unusable keys | 3, 4, 7 |
| `importer/importer/sources/hifld_military.py` (+ fixture script and `.geojson`) | Guard confidence, check order, unusable keys | 5, 7 |
| `importer/importer/sources/faa.py`, `importer/importer/sources/base.py` | unusable keys | 7 |
| `importer/importer/stages/orphans.py` | `unusable` bucket, `cap_for` | 6, 11 |
| `importer/importer/stages/dedup.py` | stickiness, cluster confidence | 8 |
| `importer/importer/pipeline.py`, `importer/importer/reports/*` | wiring and report fields | 9, 11 |
| `importer/importer/supabase_client.py` | write retries | 10 |
| `.github/workflows/importer-apply.yml` | `orphan_delete_cap` input | 11 |
| `data/state_laws/states.yaml`, `docs/importer/OMISSIONS.md` | federal cell; omission entry | 12 |
| `docs/importer/PROD_APPLY.md`, `docs/importer/SOURCES.md`, `importer/README.md`, `CLAUDE.md` | runbook and docs | 1, 13 |

## Before Task 1

- [ ] From the repo root on an up-to-date `master`: `git switch -c feature/phase8a-national-federal-wave`.
- [ ] Commit the untracked spec and memo with this plan:

```bash
git add docs/superpowers/specs/2026-10-26-phase8a-national-federal-wave-design.md \
  docs/importer/LEGAL_FEDERAL_CARRY_2026-10.md \
  docs/superpowers/plans/2026-10-31-phase8a-national-federal-wave.md
git commit -m "docs: Phase 8a design, federal carry memo and plan"
```

---

### Task 1: National state locator

**Files:**
- Create: `importer/scripts/make_state_boundaries.py`, `importer/scripts/README.md`, `data/geo/us_states_500k.geojson` (generated)
- Modify: `importer/importer/geo/states.py`, `importer/config.yaml`, `importer/importer/cli.py:40-49,235`, `docs/importer/SOURCES.md`
- Test: `importer/tests/test_geo_states.py`, `importer/tests/test_cli.py`

**Interfaces:**
- Produces: `US_STATES_AND_DC: frozenset[str]` in `importer.geo.states`, the 50 USPS state codes plus `"DC"`. Config key `state_boundaries`, a repo-relative path. `cli.main` loads the locator from `REPO_ROOT / config["state_boundaries"]`.

- [ ] **Step 1: Write the failing locator tests** (append to `tests/test_geo_states.py`)

```python
import json

import pytest

from importer.geo.states import US_STATES_AND_DC, load_state_locator

NATIONAL = Path(__file__).resolve().parents[2] / "data" / "geo" / "us_states_500k.geojson"


@pytest.fixture(scope="module")
def national():
    return load_state_locator(NATIONAL)


@pytest.mark.parametrize("lat, lng, code", [
    (39.7392, -104.9903, "CO"),
    (47.6062, -122.3321, "WA"),
    (41.8781, -87.6298, "IL"),
    (38.8977, -77.0365, "DC"),
    (28.5729, -80.6490, "FL"),  # Kennedy Space Center: needs the 500k coastline
])
def test_national_file_resolves_states_outside_the_pilot(national, lat, lng, code):
    assert national.state_for(lat, lng) == code


def test_national_file_resolves_nothing_offshore(national):
    assert national.state_for(36.0, -72.0) is None


def test_national_file_holds_the_50_states_and_dc():
    raw = json.loads(NATIONAL.read_text(encoding="utf-8"))
    assert len(raw["features"]) == 51
    assert {f["properties"]["STUSPS"] for f in raw["features"]} == US_STATES_AND_DC
    assert NATIONAL.stat().st_size < 10_000_000
```

- [ ] **Step 2: Run them and see them fail**

Run: `uv run pytest tests/test_geo_states.py -q`
Expected: FAIL with `ImportError: cannot import name 'US_STATES_AND_DC'`.

- [ ] **Step 3: Add `US_STATES_AND_DC` to `importer/geo/states.py`**

A literal `frozenset` of the 51 codes, with a one-line comment that territories are excluded on purpose (no state-law cells, outside the app's US box).

- [ ] **Step 4: Write `scripts/make_state_boundaries.py`**

Signature: `main(argv: list[str] | None = None) -> int`, with one required argument, `--year` (int). It downloads `https://www2.census.gov/geo/tiger/GENZ{year}/shp/cb_{year}_us_state_500k.zip` with httpx (timeout 120 s, follow redirects) into a `tempfile.TemporaryDirectory()`, extracts it with `zipfile`, and reads `cb_{year}_us_state_500k.shp` with `shapefile.Reader` (pyshp). It keeps the records whose `STUSPS` is in `US_STATES_AND_DC`. Each feature keeps only the `STUSPS` and `NAME` properties, and its geometry comes from `shape.__geo_interface__` with every coordinate rounded to 6 decimals. It writes compact JSON (`separators=(",", ":")`, trailing newline) to `<repo>/data/geo/us_states_500k.geojson`. It returns 1 without writing if it kept anything other than 51 features, and otherwise prints the feature count and file size.

`scripts/README.md` is one line: `make_state_boundaries.py` rebuilds `data/geo/us_states_500k.geojson` from the Census cartographic boundary file; run `uv run --with pyshp python scripts/make_state_boundaries.py --year 2025` from `importer/`.

- [ ] **Step 5: Generate the file**

Run: `uv run --with pyshp python scripts/make_state_boundaries.py --year 2025`
Expected: `51 features`, about 6.5 MB (6,491,726 bytes when measured on 2026-10-31).

- [ ] **Step 6: Run the locator tests**

Run: `uv run pytest tests/test_geo_states.py -q`
Expected: PASS.

- [ ] **Step 7: Write the failing CLI tests** (append to `tests/test_cli.py`)

```python
def test_config_points_at_the_national_boundary_file():
    from importer.cli import REPO_ROOT, _load_config
    path = REPO_ROOT / _load_config()["state_boundaries"]
    assert path == REPO_ROOT / "data" / "geo" / "us_states_500k.geojson"
    assert path.exists()


def test_main_loads_the_locator_from_the_configured_file(monkeypatch, tmp_path):
    from importer.stages.orphans import OrphanCapExceeded

    def stop(**kw):
        raise OrphanCapExceeded("stop")

    cli, _ = _fake_main(monkeypatch, stop)
    seen = []
    monkeypatch.setattr(cli, "load_state_locator", lambda path: seen.append(path) or object())
    cli.main(APPLY_STAGING + ["--report-out", str(tmp_path / "r.md")])
    assert seen == [cli.REPO_ROOT / "data" / "geo" / "us_states_500k.geojson"]
```

- [ ] **Step 8: Run them and see them fail**

Run: `uv run pytest tests/test_cli.py -q -k "boundary or locator"`
Expected: FAIL with `KeyError: 'state_boundaries'`, and the second test sees the fixture path.

- [ ] **Step 9: Wire the config into the CLI**

In `config.yaml`, add a top-level `state_boundaries: "data/geo/us_states_500k.geojson"` with a comment naming the Census vintage (`cb_2025_us_state_500k`, public domain), the 6-decimal rounding and the rebuild script. In `cli.py`, delete `STATES_BOUNDARY_FIXTURE` and its "PHASE 2 SCOPE" comment, and build the locator from `REPO_ROOT / config["state_boundaries"]`.

- [ ] **Step 10: Run the whole importer suite**

Run: `uv run pytest -q`
Expected: PASS. Source and pipeline tests keep the small fixture.

- [ ] **Step 11: Record the vintage in `docs/importer/SOURCES.md`**

Add a table row, "US state boundaries", for `data/geo/us_states_500k.geojson`: Census `cb_2025_us_state_500k`, public domain, 50 states plus DC, coordinates rounded to 6 decimals, NAD83 read as WGS84, rebuilt with `importer/scripts/make_state_boundaries.py`. Add one license-notes bullet saying why it is the finest resolution: a point outside every polygon drops the candidate and takes its pin out of orphan scope.

- [ ] **Step 12: Commit**

```bash
git add importer/importer/geo/states.py importer/scripts data/geo importer/config.yaml \
  importer/importer/cli.py importer/tests/test_geo_states.py importer/tests/test_cli.py \
  docs/importer/SOURCES.md
git commit -m "feat(importer): national state locator from the Census 500k file"
```

---

### Task 2: Per-candidate confidence override

**Files:**
- Modify: `importer/importer/candidate.py`, `importer/importer/stages/apply_state_law.py`, `importer/importer/stages/apply.py:33-48`
- Test: `importer/tests/test_candidate.py`, `importer/tests/stages/test_apply_state_law.py`, `importer/tests/stages/test_apply.py`

**Interfaces:**
- Produces:
  - `Candidate.confidence_override: Literal["high", "medium"] | None = None`.
  - `CONFIDENCE_RANK: dict[str, int] = {"low": 0, "medium": 1, "high": 2}` in `importer.stages.apply_state_law`.
  - `ClassifiedCandidate.confidence -> str`, a property returning the override, else `cell.confidence`. It raises `ValueError` with "may only lower" in the message when the override outranks the cell. A model validator runs the same check at construction, so `apply_state_law` fails in Phase A.
  - `apply._to_upsert_row` writes `confidence=cc.confidence`. Status, citation and verified date still come from the cell.

- [ ] **Step 1: Write the failing tests**

In `tests/test_candidate.py`, build a minimal `Candidate` the way `test_candidate_round_trips_minimal_fields` does, then:

```python
def test_confidence_override_defaults_to_none():
    assert _minimal().confidence_override is None


def test_confidence_override_rejects_low():
    with pytest.raises(ValidationError):
        _minimal(confidence_override="low")
```

(`_minimal(**kw)` is a small helper you add that returns that minimal candidate with `kw` applied.)

In `tests/stages/test_apply_state_law.py`:

```python
def _fed_cell(confidence):
    return StateLawCell(
        state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
        confidence=confidence, citation="18 USC §930(a)", last_verified_date=date(2026, 10, 25),
    )


def _fed(override=None):
    return Candidate(
        source="gsa", source_external_id="47-00-1", source_dataset_version="v",
        name="Federal Building", latitude=30.27, longitude=-97.74,
        coord_quality=CoordQuality.PRECISE, category=RestrictionTag.FEDERAL_PROPERTY,
        state="TX", confidence_override=override,
    )


def test_override_lowers_confidence_and_leaves_the_cell_alone():
    cc = ClassifiedCandidate(candidate=_fed("medium"), cell=_fed_cell("high"))
    assert cc.confidence == "medium"
    assert (cc.cell.default_status, cc.cell.citation) == ("NO_GUN", "18 USC §930(a)")


def test_without_an_override_the_cell_decides():
    assert ClassifiedCandidate(candidate=_fed(), cell=_fed_cell("high")).confidence == "high"


def test_an_override_cannot_raise_confidence():
    with pytest.raises(ValueError, match="may only lower"):
        ClassifiedCandidate(candidate=_fed("high"), cell=_fed_cell("medium"))


def test_classification_fails_on_an_illegal_override():
    table = StateLawTable(rows=[_fed_cell("medium")])
    with pytest.raises(ValueError, match="may only lower"):
        list(apply_state_law([_fed("high")], table=table, stats=ApplyStateLawStats()))
```

In `tests/stages/test_apply.py` (import `_to_upsert_row`):

```python
def _with_override(cc, override):
    return cc.model_copy(update={"candidate": cc.candidate.model_copy(
        update={"confidence_override": override})})


def test_upsert_row_writes_the_override_and_the_cell_citation():
    row = _to_upsert_row(_with_override(_classified("e1"), "medium"), system_user_id=SYS)
    assert row.confidence == "medium"
    assert (row.status, row.legal_citation) == (2, "18 USC 930(a)")


def test_upsert_row_refuses_an_override_above_the_cell():
    medium = ClassifiedCandidate(candidate=_classified("e1").candidate,
                                 cell=CELL.model_copy(update={"confidence": "medium"}))
    bad = _with_override(medium, "high")  # model_copy skips validation
    with pytest.raises(ValueError, match="may only lower"):
        _to_upsert_row(bad, system_user_id=SYS)
```

- [ ] **Step 2: Run them and see them fail**

Run: `uv run pytest tests/test_candidate.py tests/stages/test_apply_state_law.py tests/stages/test_apply.py -q`
Expected: FAIL. `confidence_override` is an unknown field and `ClassifiedCandidate` has no `confidence`.

- [ ] **Step 3: Implement**

Add the field to `Candidate` with a comment: set by sources, may only lower the cell's confidence, never written by itself. Add `CONFIDENCE_RANK`, the property and the `model_validator(mode="after")` to `ClassifiedCandidate`. Point `_to_upsert_row` at `cc.confidence`.

- [ ] **Step 4: Run the importer suite**

Run: `uv run pytest -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add importer/importer/candidate.py importer/importer/stages/apply_state_law.py \
  importer/importer/stages/apply.py importer/tests/test_candidate.py \
  importer/tests/stages/test_apply_state_law.py importer/tests/stages/test_apply.py
git commit -m "feat(importer): per-candidate confidence override that can only lower"
```

---

### Task 3: GSA keeps only buildings where federal employees work

**Files:**
- Modify: `importer/importer/sources/gsa.py`, `importer/tests/fixtures/make_gsa_frpp_sample.py`, `importer/tests/fixtures/gsa_frpp_sample.xlsx` (regenerated)
- Test: `importer/tests/sources/test_gsa.py`

**Interfaces:**
- Produces, in `importer.sources.gsa`:
  - Column constants `_COL_EMPLOYEES = "Number of Federal Employees"` and `_COL_LEGAL = "Legal Interest Indicator"`, both added to `_NEEDED_COLS`. Task 4 reads `_COL_LEGAL`.
  - `UNSTAFFED_USES`, `STAFFED_USES` and `GRAY_USES` (`frozenset[str]`) and `POST_OFFICE_USE = "Post Office"`, holding the exact FRPP spellings below. The comment above them cites the memo and spec §4.2.
  - `_parse_employees(raw: str) -> int | None`: strip, drop commas, `""` is `None`, parse as a number and truncate to `int`, anything unparseable is `None`.
  - `_use_skip_reason(use: str, employees: int | None) -> str | None`: compares case-insensitively after stripping. The order is unstaffed (`"use_unstaffed"`), then post office (`"use_post_office"`), then a use in no list (`"use_unknown"`), then `employees == 0` (`"zero_employees"`), then staffed (keep, `None`), then gray (keep when `employees > 0`, otherwise `"use_unverified"`).
  - `GsaSource.last_kept_by_use: Counter[str]` counts yielded candidates by canonical use spelling. `GsaSource.last_unknown_uses: Counter[str]` counts rows whose use is in no list, keyed by the stripped original value. Both reset at the start of `iter_candidates`.
- The use check goes right after the `disposed` check and before `missing_name`. That keeps a deliberately excluded row out of the data-problem buckets (refinement 5).

The lists, verbatim:
- **Unstaffed:** Family Housing, Comfort Station/Restrooms, Dormitories/Barracks, Communications Systems, Navigation and Traffic Aids.
- **Staffed:** Office, Courthouse, Laboratories, Hospital, Outpatient Healthcare Facility, Prisons and Detention Centers, Land Port of Entry, Border/Inspection Station, Aviation Security Related, Facility Security, Public Facing Facility, School, Museum, Child Care Center, Data Centers.
- **Gray:** Warehouses, Service, Industrial, All Other, Other Institutional Uses.

- [ ] **Step 1: Extend the fixture script**

Add `"Number of Federal Employees"` and `"Legal Interest Indicator"` to `HEADER`. Every existing row gets `(None, "Owned")` appended, except `RPUID-TX-7` (a Warehouse), which gets `("3", "Owned")` so it stays kept. Append these rows. All use agency `"47"`, bureau `"00"`, status `OK`, legal `"Owned"` and city Austin, zip `"78701"`:

| RPUID | Use | Street | Lat, Lng | Installation Name | Employees | Exercises |
|---|---|---|---|---|---|---|
| `RPUID-TX-HOUSING` | Family Housing | 1 Housing Ln | 43.0392538, -87.9031992 (Milwaukee) | Federal Housing | None | use filter wins over a bad coordinate |
| `RPUID-TX-PO` | Post Office | 2 Mail St | 30.2700, -97.7400 | Austin Post Office | "40" | `use_post_office` |
| `RPUID-TX-ZERO` | Office | 3 Empty St | 30.2710, -97.7410 | Empty Federal Office | "0" | `zero_employees` |
| `RPUID-TX-UPPER` | OFFICE | 4 Caps St | 30.2720, -97.7420 | Caps Federal Office | None | case-insensitive use |
| `RPUID-TX-WH-STAFFED` | Warehouses | 5 Depot Rd | 30.2730, -97.7430 | Staffed Federal Depot | "1,951" | thousands separator |
| `RPUID-TX-WH-BLANK` | Warehouses | 6 Depot Rd | 30.2740, -97.7440 | Unstaffed Federal Depot | None | `use_unverified` |
| `RPUID-TX-SPACEPORT` | Spaceport | 7 Launch Rd | 30.2750, -97.7450 | Federal Spaceport | "12" | `use_unknown` |
| `RPUID-TX-NOGEO` | Office | 8 Nowhere Rd | None, None | Ungeocodable Federal Office | None | `geocode_miss` (Task 7) |
| `RPUID-TX-NONAME` | Office | 9 Blank St | 30.2760, -97.7460 | None | None | `missing_name` (Task 7) |

Regenerate: `uv run python tests/fixtures/make_gsa_frpp_sample.py`.

- [ ] **Step 2: Write the failing tests** (append to `tests/sources/test_gsa.py`)

```python
from importer.sources.gsa import (
    GRAY_USES, POST_OFFICE_USE, STAFFED_USES, UNSTAFFED_USES,
    _parse_employees, _use_skip_reason,
)

FRPP_FY24_USES = (  # every Building use in the FY24 file, not Disposed (2026-10-31)
    "All Other", "Warehouses", "Office", "Family Housing", "Service",
    "Other Institutional Uses", "Industrial", "Comfort Station/Restrooms",
    "Laboratories", "Dormitories/Barracks", "School", "Outpatient Healthcare Facility",
    "Public Facing Facility", "Prisons and Detention Centers", "Communications Systems",
    "Hospital", "Land Port of Entry", "Aviation Security Related", "Courthouse",
    "Border/Inspection Station", "Navigation and Traffic Aids", "Facility Security",
    "Museum", "Data Centers", "Child Care Center", "Post Office",
)


def test_every_fy24_use_is_in_exactly_one_list():
    lists = [UNSTAFFED_USES, {POST_OFFICE_USE}, STAFFED_USES, GRAY_USES]
    for use in FRPP_FY24_USES:
        assert sum(use in group for group in lists) == 1, use
    assert set().union(*lists) == set(FRPP_FY24_USES)


@pytest.mark.parametrize("raw, expected", [
    ("", None), ("0", 0), ("12", 12), ("1,951", 1951), ("12.0", 12), ("n/a", None),
])
def test_parse_employees(raw, expected):
    assert _parse_employees(raw) == expected


@pytest.mark.parametrize("use, employees, reason", [
    ("Family Housing", 40, "use_unstaffed"),
    ("Post Office", 40, "use_post_office"),
    ("Spaceport", 12, "use_unknown"),
    ("Spaceport", 0, "use_unknown"),
    ("Office", 0, "zero_employees"),
    ("Courthouse", 0, "zero_employees"),
    ("Office", None, None),            # blank is not zero
    ("OFFICE", None, None),
    (" courthouse ", None, None),
    ("Warehouses", 3, None),
    ("Warehouses", None, "use_unverified"),
    ("Warehouses", 0, "zero_employees"),
])
def test_use_skip_reason(use, employees, reason):
    assert _use_skip_reason(use, employees) == reason


def test_use_filter_skip_counts(source):
    cands = _by_id(source)
    skips = source.last_skip_counts
    assert (skips["use_unstaffed"], skips["use_post_office"], skips["zero_employees"],
            skips["use_unverified"], skips["use_unknown"]) == (1, 1, 1, 1, 1)
    for kept in ("RPUID-TX-1", "RPUID-TX-UPPER", "RPUID-TX-WH-STAFFED"):
        assert K(kept) in cands


def test_a_use_filtered_row_with_a_bad_coordinate_counts_as_use_filtered(source):
    assert K("RPUID-TX-HOUSING") not in _by_id(source)
    assert source.last_skip_counts["coord_state_mismatch"] == 1  # RPUID-TX-5 only


def test_unknown_uses_are_listed(source):
    list(source.iter_candidates(state_filter={"TX"}))
    assert dict(source.last_unknown_uses) == {"Spaceport": 1}


def test_kept_rows_are_counted_by_canonical_use(source):
    list(source.iter_candidates(state_filter={"TX"}))
    assert dict(source.last_kept_by_use) == {"Office": 7, "Courthouse": 1, "Warehouses": 2}
```

Update `test_filters_state_before_geocoding`: the expected call list gains `K("RPUID-TX-NOGEO")` at the end.

- [ ] **Step 3: Run them and see them fail**

Run: `uv run pytest tests/sources/test_gsa.py -q`
Expected: FAIL on the import of `UNSTAFFED_USES`.

- [ ] **Step 4: Implement the constants, the two helpers, the filter step and the two counters in `gsa.py`**

Build one lower-case lookup from all four lists to their canonical spelling, and use it both for `_use_skip_reason` and for the `last_kept_by_use` key.

- [ ] **Step 5: Run the GSA tests, then the suite**

Run: `uv run pytest tests/sources/test_gsa.py -q` and then `uv run pytest -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources/gsa.py importer/tests/fixtures/make_gsa_frpp_sample.py \
  importer/tests/fixtures/gsa_frpp_sample.xlsx importer/tests/sources/test_gsa.py
git commit -m "feat(importer): keep only staffed GSA buildings (use and employee filter)"
```

---

### Task 4: GSA confidence rules

**Files:**
- Modify: `importer/importer/sources/gsa.py`
- Test: `importer/tests/sources/test_gsa.py`

**Interfaces:**
- Consumes: `Candidate.confidence_override` (Task 2), `_COL_LEGAL` and the use lists (Task 3).
- Produces: `HIGH_USES`, `VA_HEALTH_USES` (`frozenset[str]`), `VA_AGENCY_CODE = "36"`, `PARK_FOREST_AGENCY_CODES = frozenset({"14", "12"})`, and `_confidence_override(use: str, agency: str, legal_interest: str) -> Literal["medium"] | None`. GSA candidates carry its result as `confidence_override`. `None` means the cell's `high`.

`HIGH_USES` is Courthouse, Prisons and Detention Centers, Land Port of Entry, Border/Inspection Station, Aviation Security Related, Facility Security and School. `VA_HEALTH_USES` is Hospital and Outpatient Healthcare Facility. The precedence matters, so apply it in this order (case-insensitive, stripped):

```
Courthouse                                     -> None (18 USC 930(e): owned or leased)
legal interest is not "Owned"                  -> "medium" (only the leased part is federal)
agency in PARK_FOREST_AGENCY_CODES and use in
  {Public Facing Facility, Museum} | GRAY_USES -> "medium" (park and forest visitor buildings)
use in HIGH_USES                               -> None
use in VA_HEALTH_USES and agency == "36"       -> None (38 CFR 1.218)
anything else                                  -> "medium"
```

- [ ] **Step 1: Write the failing tests**

```python
from importer.sources.gsa import _confidence_override


@pytest.mark.parametrize("use, agency, legal, expected", [
    ("Courthouse", "47", "Owned", None),
    ("Courthouse", "47", "Leased", None),
    ("Prisons and Detention Centers", "15", "Owned", None),
    ("Prisons and Detention Centers", "15", "Leased", "medium"),
    ("Land Port of Entry", "47", "Owned", None),
    ("School", "14", "Owned", None),                        # BIE school
    ("Hospital", "36", "Owned", None),
    ("Outpatient Healthcare Facility", "36", "Owned", None),
    ("Outpatient Healthcare Facility", "75", "Owned", "medium"),  # IHS clinic
    ("Hospital", "36", "State Government-Owned", "medium"),
    ("Office", "47", "Owned", "medium"),
    ("Public Facing Facility", "14", "Owned", "medium"),
    ("Museum", "12", "Owned", "medium"),
    ("Warehouses", "14", "Owned", "medium"),
    ("courthouse", "47", "leased", None),
])
def test_confidence_override(use, agency, legal, expected):
    assert _confidence_override(use, agency, legal) == expected


def test_candidates_carry_the_override(source):
    cands = _by_id(source)
    assert cands[K("RPUID-TX-2")].confidence_override is None       # Courthouse
    assert cands[K("RPUID-TX-1")].confidence_override == "medium"   # Office
```

- [ ] **Step 2: Run them and see them fail**

Run: `uv run pytest tests/sources/test_gsa.py -q -k confidence`
Expected: FAIL with `ImportError` for `_confidence_override`.

- [ ] **Step 3: Implement the constants, the function and the `confidence_override=` argument in `iter_candidates`**

Cite the memo and spec §4.3 in the comment above the constants.

- [ ] **Step 4: Run the GSA tests**

Run: `uv run pytest tests/sources/test_gsa.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add importer/importer/sources/gsa.py importer/tests/sources/test_gsa.py
git commit -m "feat(importer): GSA per-building confidence from use, agency and lease"
```

---

### Task 5: MIRTA Guard sites are medium confidence; FAA stays high

**Files:**
- Modify: `importer/importer/sources/hifld_military.py`, `importer/tests/fixtures/make_hifld_military_samples.py`, both MIRTA fixture `.geojson` files (regenerated)
- Test: `importer/tests/sources/test_hifld_military.py`, `importer/tests/sources/test_faa.py`

**Interfaces:**
- Consumes: `Candidate.confidence_override` (Task 2).
- Produces: `GUARD_COMPONENTS: frozenset[str] = frozenset({"armyNationalGuard", "airNationalGuard"})`. A MIRTA candidate gets `confidence_override="medium"` when its first record's `SITEREPORTINGCOMPONENT` matches case-insensitively, and `None` otherwise.

- [ ] **Step 1: Mark two fixture sites as Guard**

Give `boundary()` a `component="usa"` keyword. Pass `component="armyNationalGuard"` for "NG Camp Mabry" and `component="airNationalGuard"` for "Jacksonville IAP (ANG)". Regenerate: `uv run python tests/fixtures/make_hifld_military_samples.py`.

- [ ] **Step 2: Write the tests**

```python
def test_guard_sites_are_medium_confidence(run):
    cands, _ = run
    assert cands["TX:NG CAMP MABRY"].confidence_override == "medium"
    assert cands["MIL-FL-JAX"].confidence_override == "medium"


def test_other_components_keep_the_cell_confidence(run):
    cands, _ = run
    assert cands["MIL-TX-1"].confidence_override is None
    assert cands["MIL-PA-CARE"].confidence_override is None
```

In `tests/sources/test_faa.py` (this one passes from the start and locks the spec's "FAA: no override"):

```python
def test_airports_carry_no_confidence_override(source):
    cands = source.iter_candidates(state_filter={"TX", "FL", "PA"})
    assert all(c.confidence_override is None for c in cands)
```

- [ ] **Step 3: Run the MIRTA tests and see the Guard test fail**

Run: `uv run pytest tests/sources/test_hifld_military.py -q -k confidence`
Expected: FAIL. Mabry's override is `None`.

- [ ] **Step 4: Implement `GUARD_COMPONENTS` and the `confidence_override=` argument**

- [ ] **Step 5: Run both source test files**

Run: `uv run pytest tests/sources/test_hifld_military.py tests/sources/test_faa.py -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources/hifld_military.py importer/tests/fixtures/make_hifld_military_samples.py \
  importer/tests/fixtures/hifld_military_sample.geojson importer/tests/fixtures/hifld_military_points_sample.geojson \
  importer/tests/sources/test_hifld_military.py importer/tests/sources/test_faa.py
git commit -m "feat(importer): National Guard sites get medium confidence"
```

---

### Task 6: Orphan planning keeps records the source could not use

**Files:**
- Modify: `importer/importer/stages/orphans.py`, `importer/importer/stages/apply.py:72-82`
- Test: `importer/tests/stages/test_orphans.py`, `importer/tests/stages/test_apply.py`

**Interfaces:**
- Produces:
  - `plan_orphans(orphans, *, in_scope_count, delete, cap=None, unusable_keys: Collection[str] = frozenset()) -> OrphanPlan`.
  - `OrphanPlan.unusable: list[ExistingPinRow]` (default empty) holds the pins no user corrected whose `source_external_id` is in `unusable_keys`. They are marked, never deleted, and outside the cap.
  - `marked_count` is `keep + mark + unusable`. `actions()` adds `(row, "unusable_kept")`.
  - Partition order: a user-corrected pin goes to `keep` (delete mode) or `mark` (mark mode), as today. Otherwise a key in `unusable_keys` goes to `unusable`. Otherwise the pin goes to `delete` (delete mode) or `mark`.
  - `apply_to_supabase` marks `plan.unusable` along with `keep` and `mark`.

- [ ] **Step 1: Write the failing tests** (append to `tests/stages/test_orphans.py`)

```python
def test_a_saw_but_dropped_record_is_kept_and_marked_never_deleted():
    gone, bad = _pin("gone"), _pin("bad")
    plan = plan_orphans([gone, bad], in_scope_count=10, delete=True, unusable_keys={"E-bad"})
    assert plan.delete == [gone] and plan.unusable == [bad]
    assert plan.marked_count == 1
    assert (bad, "unusable_kept") in plan.actions()


def test_unusable_pins_never_count_toward_the_cap():
    bad = [_pin(f"p{i}") for i in range(60)]
    plan = plan_orphans(bad, in_scope_count=100, delete=True,
                        unusable_keys={p.source_external_id for p in bad})
    assert plan.delete == [] and len(plan.unusable) == 60 and not plan.breached


def test_mark_mode_keeps_unusable_pins_in_their_own_bucket():
    gone, bad = _pin("gone"), _pin("bad")
    plan = plan_orphans([gone, bad], in_scope_count=10, delete=False, unusable_keys={"E-bad"})
    assert plan.mark == [gone] and plan.unusable == [bad] and plan.marked_count == 2


def test_a_user_correction_wins_over_unusable():
    fixed = _pin("fixed", user_modified=True)
    plan = plan_orphans([fixed], in_scope_count=10, delete=True, unusable_keys={"E-fixed"})
    assert plan.keep == [fixed] and plan.unusable == []
```

Append to `tests/stages/test_apply.py`:

```python
def test_unusable_orphans_are_marked_not_deleted():
    bad = _orphan("E-bad", pin_id="bad")
    client = MagicMock()
    apply_to_supabase(_empty_diff(orphans=[bad]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(unusable=[bad]))
    client.delete_pins.assert_not_called()
    client.mark_orphans.assert_called_once_with(["bad"])
```

- [ ] **Step 2: Run them and see them fail**

Run: `uv run pytest tests/stages/test_orphans.py tests/stages/test_apply.py -q`
Expected: FAIL with an unexpected keyword `unusable_keys` and no `unusable` field.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the suite**

Run: `uv run pytest -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add importer/importer/stages/orphans.py importer/importer/stages/apply.py \
  importer/tests/stages/test_orphans.py importer/tests/stages/test_apply.py
git commit -m "feat(importer): keep and mark orphans whose record was seen but unusable"
```

---

### Task 7: Sources report the records they saw but could not use

**Files:**
- Modify: `importer/importer/sources/base.py`, `importer/importer/sources/gsa.py`, `importer/importer/sources/hifld_military.py`, `importer/importer/sources/faa.py`, `importer/tests/fixtures/make_hifld_military_samples.py` and its regenerated boundary `.geojson`
- Test: `importer/tests/sources/test_gsa.py`, `importer/tests/sources/test_hifld_military.py`, `importer/tests/sources/test_faa.py`

**Interfaces:**
- Produces: `Source.last_unusable_keys`, a class-level default of `frozenset()` on the base class, documented as the external ids of records the source saw but dropped for a data problem, valid once the iterator is exhausted, never including deliberate exclusions. Each source below assigns a fresh `set[str]` at the start of `iter_candidates`.
  - **GSA:** the external id of rows skipped as `missing_name`, `missing_address`, `geocode_miss` or `coord_state_mismatch`.
  - **MIRTA:** reorder the per-record checks to closed, then missing name, then missing geometry. Collect `_site_key(props)` for `missing_geometry` (the name is known by then), the real SDSID for `missing_name` when there is one, and the group key for `state_pip_miss`.
  - **FAA:** the location id of rows skipped as `missing_name`, `missing_coords` or `coord_state_mismatch`.

- [ ] **Step 1: Add a closed site with no geometry to the MIRTA fixture**

Append `boundary("MIL-TX-CLOSED-NULL", "Closed Null Depot", "tx", None, status="clsd")` and regenerate. In `test_closed_sites_are_skipped_and_caretaker_sites_stay`, change the expected `closed` count from 1 to 2. `missing_geometry` stays 1 once the checks are reordered.

- [ ] **Step 2: Write the failing tests**

`tests/sources/test_gsa.py`:

```python
def test_unusable_keys_are_the_rows_dropped_for_data_problems(source):
    list(source.iter_candidates(state_filter={"TX"}))
    assert source.last_unusable_keys == {
        K("RPUID-TX-4"), K("RPUID-TX-5"), K("RPUID-TX-NOGEO"), K("RPUID-TX-NONAME"),
    }  # Land, Disposed, no-bureau and use-filtered rows (HOUSING included) are not here
```

`tests/sources/test_hifld_military.py`:

```python
def test_unusable_keys_cover_data_problems_not_closures():
    src = _source()
    list(src.iter_candidates(state_filter=PILOT))
    # MIL-NULL has no geometry; Camp Pendleton is outside the fixture's states.
    # The closed site with no geometry counts as closed, not unusable.
    assert src.last_unusable_keys == {"MIL-NULL", "MIL-CA-1"}
```

`tests/sources/test_faa.py`:

```python
def test_unusable_keys_are_airports_dropped_for_data_problems(source):
    list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert source.last_unusable_keys == {"ABC", "AUS"}  # no NASR row; coordinate in WI
```

- [ ] **Step 3: Run them and see them fail**

Run: `uv run pytest tests/sources -q -k "unusable or closed"`
Expected: FAIL. The attribute doesn't exist, and the closed count is 1 because geometry is checked first.

- [ ] **Step 4: Implement in the base class and the three sources**

- [ ] **Step 5: Run the source tests, then the suite**

Run: `uv run pytest tests/sources -q` and then `uv run pytest -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources importer/tests/fixtures/make_hifld_military_samples.py \
  importer/tests/fixtures/hifld_military_sample.geojson importer/tests/sources
git commit -m "feat(importer): sources report records seen but dropped for data problems"
```

---

### Task 8: Dedup prefers existing keys and carries cluster confidence

**Files:**
- Modify: `importer/importer/stages/dedup.py`
- Test: `importer/tests/stages/test_dedup.py`

**Interfaces:**
- Consumes: `ClassifiedCandidate.confidence` and `CONFIDENCE_RANK` (Task 2).
- Produces: `dedup(classified, *, existing_user_pins, existing_keys: Collection[tuple[str, str]] = frozenset()) -> DedupResult`. A survivor may come back as a copy whose `candidate.confidence_override` reflects its cluster. Cross-source priority is unchanged.

The algorithm the signature does not determine:

```
# Same tier: the key already in the database wins, then today's (source, eid) order.
rank(c) = ((c.source, c.source_external_id) not in existing_keys, c.source, c.source_external_id)
winner = a if rank(a) <= rank(b) else b

# Track absorption transitively in the stage-3 loop.
absorbed = [[] for each candidate]
on every drop: absorbed[winner] += [loser, *absorbed[loser]]

# After the loop, for each survivor s:
members = [s] + [absorbed rows whose source == s.source]
best = min(max(CONFIDENCE_RANK[m.confidence] for m in members),
           CONFIDENCE_RANK[s.cell.confidence])
if best != CONFIDENCE_RANK[s.confidence]:
    s = copy with confidence_override = None if best is the cell's rank, else that rank's name
```

User-pin drops (stage 2) and within-source duplicate ids (stage 1) are not clusters and do not lend confidence.

- [ ] **Step 1: Write the failing tests** (append to `tests/stages/test_dedup.py`)

```python
DFC = "Denver Federal Center"


def _gsa(eid, lat=39.7200, lng=-105.1200, override=None):
    cc = _cc("gsa", eid, DFC, lat, lng)
    return cc.model_copy(update={"candidate": cc.candidate.model_copy(
        update={"confidence_override": override})})


def _eids(result):
    return [s.candidate.source_external_id for s in result.survivors]


def test_an_equal_priority_match_keeps_the_key_already_in_the_database():
    a, b = _gsa("47-00-A"), _gsa("47-00-B", lat=39.7201)
    assert _eids(dedup([a, b], existing_user_pins=[])) == ["47-00-A"]
    assert _eids(dedup([a, b], existing_user_pins=[],
                       existing_keys={("gsa", "47-00-B")})) == ["47-00-B"]


def test_stickiness_never_beats_source_priority():
    faa = _cc("faa", "DEN", DFC, 39.7200, -105.1200, category=RestrictionTag.AIRPORT_SECURE)
    gsa = _gsa("47-00-A", lat=39.7201)
    result = dedup([gsa, faa], existing_user_pins=[], existing_keys={("gsa", "47-00-A")})
    assert [s.candidate.source for s in result.survivors] == ["faa"]


def test_a_cluster_pin_takes_the_highest_confidence_in_either_order():
    office = _gsa("47-00-A", override="medium")   # existing key: survives
    court = _gsa("47-00-B", lat=39.7201)           # high
    for order in ([office, court], [court, office]):
        (pin,) = dedup(order, existing_user_pins=[],
                       existing_keys={("gsa", "47-00-A")}).survivors
        assert pin.candidate.source_external_id == "47-00-A"
        assert pin.confidence == "high"


def test_absorbed_rows_pass_their_confidence_through_a_chain():
    # Three rows about 34 m apart. Whichever pair is compared first, A (lowest
    # key) ends up absorbing B and C, directly or through B.
    a = _gsa("47-00-A", 39.72000, -105.12000, override="medium")
    b = _gsa("47-00-B", 39.72030, -105.12000, override="medium")
    c = _gsa("47-00-C", 39.72015, -105.12035)   # high
    (pin,) = dedup([b, c, a], existing_user_pins=[]).survivors
    assert pin.candidate.source_external_id == "47-00-A"
    assert pin.confidence == "high"


def test_cluster_confidence_ignores_other_sources():
    gsa = _gsa("47-00-A", override="medium")
    mil = _cc("hifld_military", "MIL-1", DFC, 39.7201, -105.1200)   # high, lower priority
    (pin,) = dedup([gsa, mil], existing_user_pins=[]).survivors
    assert (pin.candidate.source, pin.confidence) == ("gsa", "medium")


def test_cluster_confidence_never_exceeds_the_survivors_cell():
    medium_cell = _cell(RestrictionTag.FEDERAL_PROPERTY).model_copy(update={"confidence": "medium"})
    a = _gsa("47-00-A").model_copy(update={"cell": medium_cell})
    b = _gsa("47-00-B", lat=39.7201)   # high cell
    (pin,) = dedup([a, b], existing_user_pins=[]).survivors
    assert (pin.candidate.source_external_id, pin.confidence) == ("47-00-A", "medium")
```

- [ ] **Step 2: Run them and see them fail**

Run: `uv run pytest tests/stages/test_dedup.py -q`
Expected: FAIL with an unexpected keyword `existing_keys`.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the dedup tests, then the suite**

Run: `uv run pytest tests/stages/test_dedup.py -q` and then `uv run pytest -q`
Expected: PASS. The existing tie-break tests still hold with no `existing_keys`.

- [ ] **Step 5: Commit**

```bash
git add importer/importer/stages/dedup.py importer/tests/stages/test_dedup.py
git commit -m "feat(importer): sticky dedup survivors and highest confidence per cluster"
```

---

### Task 9: Pipeline wiring and report

**Files:**
- Modify: `importer/importer/pipeline.py`, `importer/importer/reports/__init__.py`, `importer/importer/reports/markdown.py`, `importer/importer/reports/json_report.py`
- Test: `importer/tests/test_pipeline.py`, `importer/tests/reports/test_markdown.py`, `importer/tests/reports/test_json_report.py`

**Interfaces:**
- Consumes: `plan_orphans(unusable_keys=)` (Task 6), `last_unusable_keys` (Task 7), `dedup(existing_keys=)` (Task 8), `ClassifiedCandidate.confidence` (Task 2), `last_kept_by_use` and `last_unknown_uses` (Task 3).
- Produces:
  - `SourceResult` gains `confidence_counts: dict[str, int]`, counted over the source's post-dedup survivors, plus `kept_by_use: dict[str, int]` and `unknown_uses: dict[str, int]`, all defaulting to empty.
  - The pipeline reads each source's `last_unusable_keys`, `last_kept_by_use` and `last_unknown_uses` with `getattr` defaults, so fakes and other sources work unchanged. It loads every source's system pins once before dedup (`existing_by_source`), passes their `(source, source_external_id)` keys to `dedup`, and reuses the lists in Phase C1.
  - **Markdown** per source:
    - `- Confidence: high **N**, medium **M**`, listing only present values, highest first.
    - `- Kept, unusable record (the source saw it but could not use it): **U**`, only when `U > 0`. The existing orphan lines stay unchanged.
    - `- Kept by use: ` followed by entries like `` `Office` 7 ``, count descending then name, only when non-empty.
    - `- **Unknown uses (skipped; add each to a use list in gsa.py):** ` followed by the same entry format, only when non-empty.
  - **JSON** per source: `counts.orphans_unusable_kept`, plus top-level `confidence_counts`, `kept_by_use` and `unknown_uses`.

- [ ] **Step 1: Let `_FakeSource` carry the new attributes**

In `tests/test_pipeline.py`, give `_FakeSource.__init__` the keyword arguments `unusable=None`, `kept_by_use=None` and `unknown_uses=None`. Set `last_unusable_keys`, `last_kept_by_use` and `last_unknown_uses` only when one is given, so the other tests keep exercising the `getattr` defaults.

- [ ] **Step 2: Write the failing pipeline tests**

```python
def test_existing_keys_make_dedup_sticky_end_to_end():
    a = _cand("gsa", "47-00-A", "Denver Federal Center", 30.2672, -97.7431)
    b = _cand("gsa", "47-00-B", "Denver Federal Center", 30.2673, -97.7431)
    client = _client_with({"gsa": [_pin("pin-b", (30.2673, -97.7431), eid="47-00-B")]})
    diff = _run([_FakeSource("gsa", [a, b])], client, mode="dry-run").sources[0].diff
    assert [cc.candidate.source_external_id for cc in diff.updates] == ["47-00-B"]
    assert diff.inserts == [] and diff.orphans == []


def test_unusable_records_keep_their_pins():
    gone, bad = _pin("gone"), _pin("bad")
    client = _client_with({"gsa": [gone, bad]})
    client.delete_pins.return_value = ["gone"]
    _run([_FakeSource("gsa", [], unusable={"E-bad"})], client, delete_orphans=True)
    client.delete_pins.assert_called_once_with(["gone"])
    client.mark_orphans.assert_called_once_with(["bad"])


def test_confidence_and_use_counts_reach_the_result():
    medium = _cand("gsa", "g1", "Federal Building Austin", 30.2672, -97.7431).model_copy(
        update={"confidence_override": "medium"})
    high = _cand("gsa", "g2", "US Courthouse Austin", 30.2900, -97.7431)
    src = _FakeSource("gsa", [medium, high], kept_by_use={"Office": 1, "Courthouse": 1},
                      unknown_uses={"Spaceport": 1})
    sr = _run([src], _mock_client(), mode="dry-run").sources[0]
    assert sr.confidence_counts == {"medium": 1, "high": 1}
    assert sr.kept_by_use == {"Office": 1, "Courthouse": 1}
    assert sr.unknown_uses == {"Spaceport": 1}


def test_an_illegal_override_fails_before_any_write():
    airport_cell = StateLawCell(
        state="US", category=RestrictionTag.AIRPORT_SECURE, default_status="NO_GUN",
        confidence="medium", conditions=[], citation="49 CFR 1540.111",
        last_verified_date=date(2026, 5, 1),
    )
    table = StateLawTable(rows=[*_table().rows, airport_cell])
    ok = _FakeSource("gsa", [_cand("gsa", "g1", "Federal Building Austin", 30.2672, -97.7431)])
    bad = _FakeSource("faa", [Candidate(
        source="faa", source_external_id="AUS", source_dataset_version="v",
        name="Austin-Bergstrom International", latitude=30.1945, longitude=-97.6699,
        coord_quality=CoordQuality.PRECISE, category=RestrictionTag.AIRPORT_SECURE,
        state="TX", confidence_override="high",
    )])
    client = _mock_client()
    with pytest.raises(ValueError, match="may only lower"):
        run_pipeline(sources=[ok, bad], state_laws=table, client=client, states=["TX"],
                     mode="apply", system_user_id=SYS, state_locator=LOCATOR)
    assert {c[0] for c in client.method_calls} <= {"select_user_pins", "select_system_pins"}
```

- [ ] **Step 3: Write the failing report tests**

`tests/reports/test_markdown.py`, building `bad` as an `ExistingPinRow` the way the file's cleanup tests do:

```python
def test_markdown_shows_confidence_use_counts_and_unusable_orphans():
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[bad])
    s = _source(source="gsa", diff=diff, orphan_plan=OrphanPlan(unusable=[bad]),
                confidence_counts={"medium": 5, "high": 3},
                kept_by_use={"Office": 5, "Courthouse": 3}, unknown_uses={"Spaceport": 1})
    md = render_markdown(PipelineResult(
        mode="dry-run", started_at=datetime(2026, 11, 1, tzinfo=timezone.utc),
        completed_at=None, states=["CO"], sources=[s], dedup=DedupReport()))
    assert "- Confidence: high **3**, medium **5**" in md
    assert "could not use it): **1**" in md
    assert "- Kept by use: `Office` 5, `Courthouse` 3" in md
    assert "Unknown uses" in md and "`Spaceport` 1" in md
    assert "(unusable_kept)" in md
```

`tests/reports/test_json_report.py`: the same source rendered with `render_json` gives `counts["orphans_unusable_kept"] == 1`, `confidence_counts == {"high": 3, "medium": 5}`, the two use maps unchanged, and `orphans[0]["action"] == "unusable_kept"`.

- [ ] **Step 4: Run them and see them fail**

Run: `uv run pytest tests/test_pipeline.py tests/reports -q`
Expected: FAIL. `SourceResult` has no `confidence_counts`, `_FakeSource` keys are ignored, and dedup isn't sticky yet.

- [ ] **Step 5: Implement the pipeline and report changes**

- [ ] **Step 6: Run the suite**

Run: `uv run pytest -q`
Expected: PASS, including `test_cap_breach_stops_the_apply_before_any_write`. The earlier system-pin load is still a read.

- [ ] **Step 7: Commit**

```bash
git add importer/importer/pipeline.py importer/importer/reports importer/tests/test_pipeline.py \
  importer/tests/reports
git commit -m "feat(importer): wire unusable keys, sticky dedup and confidence counts into runs"
```

---

### Task 10: Client writes retry transient failures

**Files:**
- Modify: `importer/importer/supabase_client.py`
- Test: `importer/tests/test_supabase_client.py`

**Interfaces:**
- Produces:
  - `SupabaseClient.__init__(..., sleep: Callable[[float], None] = time.sleep)`.
  - Class constants `_MAX_ATTEMPTS = 3`, `_BACKOFF_BASE_SECONDS = 1.0` and `_RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 504})`.
  - `_send(self, method: str, url: str, **kwargs) -> httpx.Response` retries `httpx.TransportError` and retryable statuses, sleeping `1.0` and then `2.0` seconds. It returns the last response and leaves `raise_for_status` to the caller. It re-raises the transport error on the last attempt.
  - Every POST, PATCH and DELETE in the class goes through `_send`. GETs do not.

- [ ] **Step 1: Make the fixture record sleeps instead of sleeping**

```python
@pytest.fixture()
def sleeps() -> list[float]:
    return []


@pytest.fixture()
def client(sleeps) -> SupabaseClient:
    return SupabaseClient(url="https://example.supabase.co", service_role_key="srk-test",
                          system_user_id=SYS, sleep=sleeps.append)
```

- [ ] **Step 2: Write the failing tests**

```python
def test_a_write_retries_a_503_then_succeeds(client, httpx_mock, sleeps):
    httpx_mock.add_response(method="POST", status_code=503)
    httpx_mock.add_response(method="POST", status_code=201)
    client.upsert_pins([_upsert_row("E1")])
    assert len(httpx_mock.get_requests()) == 2
    assert sleeps == [1.0]


def test_a_write_gives_up_after_three_attempts(client, httpx_mock, sleeps):
    for _ in range(3):
        httpx_mock.add_response(method="POST", status_code=503)
    with pytest.raises(httpx.HTTPStatusError):
        client.upsert_pins([_upsert_row("E1")])
    assert len(httpx_mock.get_requests()) == 3
    assert sleeps == [1.0, 2.0]


def test_a_write_retries_a_dropped_connection(client, httpx_mock):
    httpx_mock.add_exception(httpx.ConnectError("connection reset"))
    httpx_mock.add_response(method="PATCH", json=[{"id": "p1"}])
    client.patch_external_id("p1", "X")
    assert len(httpx_mock.get_requests()) == 2


def test_a_write_retries_429(client, httpx_mock):
    httpx_mock.add_response(method="DELETE", status_code=429)
    httpx_mock.add_response(method="DELETE", json=[{"id": "a"}])
    assert client.delete_pins(["a"]) == ["a"]


def test_a_write_does_not_retry_a_400(client, httpx_mock, sleeps):
    httpx_mock.add_response(method="PATCH", status_code=400)
    with pytest.raises(httpx.HTTPStatusError):
        client.mark_orphans(["p1"])
    assert len(httpx_mock.get_requests()) == 1 and sleeps == []


def test_import_run_writes_retry_too(client, httpx_mock):
    httpx_mock.add_response(method="POST", status_code=502)
    httpx_mock.add_response(method="POST", json=[{"run_id": "r1"}])
    assert client.insert_import_run(mode="dry-run", source_filter="gsa") == "r1"
```

- [ ] **Step 3: Run them and see them fail**

Run: `uv run pytest tests/test_supabase_client.py -q`
Expected: FAIL with an unexpected keyword `sleep`.

- [ ] **Step 4: Implement `_send` and route the write methods through it**

Note in the docstring that `insert_import_run` is not idempotent: a retry after a lost response can leave a second run row, which the health check ignores because it never completes.

- [ ] **Step 5: Run the suite**

Run: `uv run pytest -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add importer/importer/supabase_client.py importer/tests/test_supabase_client.py
git commit -m "feat(importer): retry Supabase writes on transient failures"
```

---

### Task 11: One-time per-source cap override

**Files:**
- Modify: `importer/importer/stages/orphans.py`, `importer/importer/pipeline.py`, `importer/importer/cli.py`, `.github/workflows/importer-apply.yml`
- Test: `importer/tests/stages/test_orphans.py`, `importer/tests/test_pipeline.py`, `importer/tests/test_cli.py`, `importer/tests/test_apply_workflow.py`

**Interfaces:**
- Produces:
  - `cap_for(source: str, override: int | Mapping[str, int] | None) -> int | None` in `importer.stages.orphans`. An int applies to every source, a mapping applies to the sources it names, and `None` means the default cap.
  - `run_pipeline(..., orphan_delete_cap: int | Mapping[str, int] | None = None)` passes `cap=cap_for(name, orphan_delete_cap)` to `plan_orphans`.
  - `cli._orphan_cap(value: str) -> int | dict[str, int]`, the argparse type for `--orphan-delete-cap`. It replaces `_non_negative_int`; delete that if nothing else uses it. A bare non-negative integer stays an int. Otherwise the value is comma-separated `name=N` pairs, with whitespace around names, values and commas ignored. The name must be in `SUPPORTED_SOURCES`, N must be a non-negative int, and names may not repeat. Anything else raises `argparse.ArgumentTypeError`.
  - After parsing, a mapping that names a source missing from `--sources` is a `p.error`.
  - Workflow input `orphan_delete_cap`: a string, default `''`, described as "One-time per-source cap override, e.g. gsa=2700 (needs delete_orphans; use the dry-run's delete count)". The apply step reads it only through `env: ORPHAN_DELETE_CAP`.

- [ ] **Step 1: Write the failing tests**

`tests/stages/test_orphans.py`:

```python
from importer.stages.orphans import cap_for


@pytest.mark.parametrize("override, source, expected", [
    (None, "gsa", None), (7, "gsa", 7), (7, "faa", 7),
    ({"gsa": 2700}, "gsa", 2700), ({"gsa": 2700}, "faa", None),
])
def test_cap_for(override, source, expected):
    assert cap_for(source, override) == expected
```

`tests/test_pipeline.py`:

```python
def test_a_per_source_cap_lifts_only_that_source():
    client, run = _over_cap_run(delete_orphans=True, orphan_delete_cap={"gsa": 100})
    with pytest.raises(OrphanCapExceeded, match="hifld_military"):
        run("apply")
    client, run = _over_cap_run(delete_orphans=True, orphan_delete_cap={"hifld_military": 100})
    client.delete_pins.return_value = [f"m{i}" for i in range(51)]
    run("apply")
    assert len(client.delete_pins.call_args.args[0]) == 51
```

`tests/test_cli.py`:

```python
APPLY_TWO = ["--apply", "--states", "TX", "--sources", "gsa,faa", "--project-ref", "staging",
             "--i-know-this-writes-to-staging", "--delete-orphans"]


def test_cap_accepts_per_source_pairs_with_spaces():
    args = build_parser().parse_args(APPLY_TWO + ["--orphan-delete-cap", " gsa=2700 , faa=10 "])
    assert args.orphan_delete_cap == {"gsa": 2700, "faa": 10}


@pytest.mark.parametrize("value", [
    "gas=2700", "hifld_military=5", "gsa=", "gsa=-1", "=5", "gsa=10,gsa=20", "gsa=2700;faa=10", "",
])
def test_cap_rejects_bad_values(value):
    with pytest.raises(SystemExit):
        build_parser().parse_args(APPLY_TWO + ["--orphan-delete-cap", value])
```

`tests/test_apply_workflow.py`: delete the last assertion and its comment from `test_delete_orphans_is_an_opt_in_checkbox` (`"--orphan-delete-cap" not in raw`). Then add:

```python
def test_orphan_delete_cap_is_a_per_source_override_that_needs_delete_orphans():
    wf = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    inputs = wf[True]["workflow_dispatch"]["inputs"]
    assert (inputs["orphan_delete_cap"]["type"], inputs["orphan_delete_cap"]["default"]) == ("string", "")
    assert inputs["states"]["default"] == "TX,FL,PA"
    step = next(s for s in wf["jobs"]["apply"]["steps"] if "importer.cli" in s.get("run", ""))
    assert step["env"]["ORPHAN_DELETE_CAP"] == "${{ inputs.orphan_delete_cap }}"
    run = step["run"]
    assert '[ -n "$ORPHAN_DELETE_CAP" ]' in run
    assert '[ "$DELETE_ORPHANS" != "true" ]' in run
    assert "orphan_delete_cap needs delete_orphans" in run
    assert '--orphan-delete-cap "$ORPHAN_DELETE_CAP"' in run
    assert "GITHUB_STEP_SUMMARY" in run
    # Operator text reaches the shell only through env, never through ${{ }} in the script.
    assert "inputs.orphan_delete_cap" not in run
```

- [ ] **Step 2: Run them and see them fail**

Run: `uv run pytest tests/stages/test_orphans.py tests/test_pipeline.py tests/test_cli.py tests/test_apply_workflow.py -q`
Expected: FAIL. `cap_for` is missing, a mapping cap is rejected by `_non_negative_int`, and the workflow has no input.

- [ ] **Step 3: Implement `cap_for`, the pipeline argument, `_orphan_cap` and the `parse_args` check**

- [ ] **Step 4: Add the workflow input and the step logic**

Replace the comment "The cap override is deliberately not exposed here…" with one saying the override is for a one-time cleanup whose deletions a dry-run listed first. Add this inside the apply step, after the `DELETE_ORPHANS` line:

```bash
if [ -n "$ORPHAN_DELETE_CAP" ]; then
  if [ "$DELETE_ORPHANS" != "true" ]; then
    echo "::error::orphan_delete_cap needs delete_orphans"
    exit 1
  fi
  orphan_flags+=(--orphan-delete-cap "$ORPHAN_DELETE_CAP")
  echo "**Orphan delete cap override: $ORPHAN_DELETE_CAP**" >> "$GITHUB_STEP_SUMMARY"
fi
```

- [ ] **Step 5: Run the importer suite and the CI suite**

Run: `uv run pytest -q`, then from the repo root `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: PASS for both.

- [ ] **Step 6: Commit**

```bash
git add importer/importer/stages/orphans.py importer/importer/pipeline.py importer/importer/cli.py \
  .github/workflows/importer-apply.yml importer/tests/stages/test_orphans.py \
  importer/tests/test_pipeline.py importer/tests/test_cli.py importer/tests/test_apply_workflow.py
git commit -m "feat(importer): per-source one-time orphan delete cap override"
```

---

### Task 12: Federal property cell and omissions

**Files:**
- Modify: `data/state_laws/states.yaml` (the `US` / `FEDERAL_PROPERTY` row), `docs/importer/OMISSIONS.md`
- Test: `importer/tests/test_state_laws.py`

**Interfaces:**
- Produces: the federal cell keeps `default_status: NO_GUN`, `confidence: high`, its `conditions` and `source_filter: [gsa, hifld_military]`. It gets the new citation, `last_verified_date: 2026-10-25` and new notes.

- [ ] **Step 1: Write the failing test**

```python
def test_federal_property_cell_cites_the_olc_reading():
    cell = load_state_laws(PROD_TABLE).lookup("CO", RestrictionTag.FEDERAL_PROPERTY)
    assert cell is not None and cell.state == "US"
    assert (cell.default_status, cell.confidence) == ("NO_GUN", "high")
    assert cell.citation == (
        "18 USC §930(a); §930(d)(3) as read by OLC, Application of "
        "18 U.S.C. § 930(a) to Post Offices (Aug. 12, 2026)"
    )
    assert cell.last_verified_date == date(2026, 10, 25)
    assert cell.source_filter == ["gsa", "hifld_military"]
    notes = " ".join(cell.notes.split())
    for watched in ("medium", "Zimmerman v. Blanche", "Hornbake v. Blanche",
                    "Fifth Circuit", "OLC opinion", "38 CFR 1.218"):
        assert watched in notes
```

- [ ] **Step 2: Run it and see it fail**

Run: `uv run pytest tests/test_state_laws.py -q -k olc`
Expected: FAIL on the citation.

- [ ] **Step 3: Update the cell**

Quote the citation exactly as in the test. The notes say four things. The cell is federal-uniform and covers buildings where federal employees regularly work. The importer lowers confidence to medium per pin (Phase 8a design §4.3, memo `docs/importer/LEGAL_FEDERAL_CARRY_2026-10.md`) while status stays NO_GUN. The watch list is Zimmerman v. Blanche, Hornbake v. Blanche, any Fifth Circuit ruling on §930(a), withdrawal of the OLC opinion, and VA changes to 38 CFR 1.218.

- [ ] **Step 4: Add the omissions entry**

Add a section to `docs/importer/OMISSIONS.md`, "Federal buildings not pinned (2026-10)". It says that 18 USC §930 covers buildings where federal employees regularly work, so the importer drops these, each with its skip count:
- the five unstaffed uses (`use_unstaffed`);
- Post Office (`use_post_office`): a later round, and UNCERTAIN rather than red after the OLC opinion;
- buildings reporting 0 federal employees (`zero_employees`);
- the five gray uses without a reported count above 0 (`use_unverified`).

It also says a use FRPP adds later is skipped (`use_unknown`) and listed in the dry-run report until someone adds it to a list in `importer/importer/sources/gsa.py`. Point to spec §4.2 and the memo.

- [ ] **Step 5: Run the state-law tests**

Run: `uv run pytest tests/test_state_laws.py -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add data/state_laws/states.yaml docs/importer/OMISSIONS.md importer/tests/test_state_laws.py
git commit -m "feat(state-laws): federal cell cites the 2026 OLC reading of 930(d)(3)"
```

---

### Task 13: Runbook and docs

**Files:**
- Modify: `docs/importer/PROD_APPLY.md`, `docs/importer/SOURCES.md`, `importer/README.md`, `CLAUDE.md`

No code. Each item below is one edit.

- [ ] **Step 1: Add "Phase 8a national federal wave (2026-10)" to `PROD_APPLY.md`**

It carries the spec §5 steps as an operator checklist. It defines the 49-code list for the local PowerShell dry-runs in lines of 70 characters or fewer (the owner's terminal hard-wraps long pastes):

```powershell
$n = "AL,AZ,AR,CA,CO,CT,DE,DC,FL,GA,ID,IL,IN,IA,KS,KY,LA"
$n += ",ME,MD,MA,MI,MN,MS,MO,MT,NE,NV,NH,NJ,NM,NY,NC"
$n += ",ND,OH,OK,OR,PA,RI,SC,SD,TN,TX,UT,VT,VA,WA,WV,WI,WY"
```

The dry-run command mirrors B1, with `--sources gsa,hifld_military,faa --states $n --refetch`. The checklist also says:
- **Why three sources is safe here.** Outside TX/FL/PA no other source has a cell. In the pilot states, a three-source run could re-insert a GSA or FAA pin only where NCES or IPEDS used to win dedup. The 2026-10-19 prod report had none of those wins. Re-check the latest full report's dedup pairs before each run, and run all seven sources if any appear.
- **What to read in the dry-run.** Per-source skip counts, kept-by-use counts and confidence counts. GSA deletes in the pilot states should be about 2,700. Expect no unknown uses and no surprising unusable-kept counts. Compare `coord_state_mismatch` with the pilot's.
- **The apply.** Use the workflow with `delete_orphans` checked and `orphan_delete_cap` set to `gsa=<dry-run GSA delete count, rounded up>`, then run a second dry-run that must be all zeros.
- **Prod.** Wait for the next health check, run the prod dry-run, then the prod apply, then the zero dry-run, then spot-check clusters at zoom 5 over California, Arizona and New Mexico.
- **Close-out.** Update the health-check baseline table, CLAUDE.md's status line and the archived report in `.local/importer-reports/`.
- **Rollback** is unchanged.

In the "Re-applying prod" section, replace "never re-run with a bigger cap from the workflow; if the deletion is intended, raise it in a PR" with: never raise the cap to get past a breach you did not expect, and use the workflow's `orphan_delete_cap` only for a planned cleanup whose deletions a dry-run listed first.

- [ ] **Step 2: Update `importer/README.md`**

- The cap bullet: the `gsa=2700` form, the workflow input and its `delete_orphans` requirement.
- Unusable records: a pin whose record the source saw but dropped for a data problem is kept, marked and reported, never deleted.
- Per-pin confidence and the GSA kept-by-use and unknown-use report lines.
- Add the Phase 8a exception to "Run the full source set" with the reason from Step 1.

- [ ] **Step 3: Update `docs/importer/SOURCES.md`**

Extend the GSA row and notes with the use and employee filter and the confidence rules, citing spec §4.2–4.3. Extend the MIRTA row with the Guard rule.

- [ ] **Step 4: Update `CLAUDE.md`**

Change the importer test count in the "Tests passing" bullet to the final count from `uv run pytest -q`. The status line changes only after the prod rollout (runbook close-out).

- [ ] **Step 5: Commit**

```bash
git add docs/importer/PROD_APPLY.md docs/importer/SOURCES.md importer/README.md CLAUDE.md
git commit -m "docs(importer): Phase 8a runbook, cap override and confidence notes"
```

---

### Task 14: Offline national smoke and PR

**Files:** none committed. The smoke script lives in the session scratchpad.

- [ ] **Step 1: Run both suites**

Run: `uv run pytest -q` from `importer/`, then the CI suite from the repo root.
Expected: all pass. Record the importer count for CLAUDE.md if Task 13 guessed it.

- [ ] **Step 2: Offline national smoke against the cached datasets (no database)**

Write a scratchpad script, run from `importer/` with `uv run python <script>`. It builds `GsaSource` from `data/sources/gsa/frpp.xlsx` with the national locator and a geocoder that returns `{}`, plus `HifldMilitarySource` from `data/sources/hifld_military/`. It runs `iter_candidates` for the 49 codes, `apply_state_law` with the real `states.yaml`, and `dedup` with no user pins. It prints the elapsed time, GSA skip counts, `last_kept_by_use`, `last_unknown_uses`, survivors per source, and survivor confidence counts. Use the existing caches; don't refetch.

Expected, which checks the spec's §3 and §4.7 figures:

| Check | Expected |
|---|---|
| GSA rows kept by the use filter | about 29,000 |
| GSA survivors after dedup | about 13,000–15,000 |
| `use_unknown` | 0 |
| MIRTA medium survivors | about 260 |
| Elapsed | a few minutes at most |

A large miss on any of these is a finding to report before the PR, not something to tune away.

- [ ] **Step 3: Preflight, push and open the PR**

Use the `pr-preflight` skill, then `superpowers:finishing-a-development-branch`. The PR body lists the spec refinements above and the smoke numbers. Check every commit's trailers before pushing.

---

## Rollout (owner-gated, after merge)

Nothing here is automatic, and the implementer does none of it without the owner's go. Follow `docs/importer/PROD_APPLY.md` → "Phase 8a national federal wave (2026-10)":

1. Staging dry-run of the three sources, all 49 codes, with `--refetch`.
2. Staging apply with `delete_orphans` and `orphan_delete_cap=gsa=<count>`, then a dry-run that is all zeros.
3. Next day's health check green.
4. Prod dry-run, local and read-only. Numbers match staging within source churn.
5. Prod apply with the same cap, a zero dry-run, and the zoom-5 cluster spot check.
6. Close-out docs, the archived report, and the CLAUDE.md status line.
