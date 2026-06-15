# Phase 5 — Schools + Airports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new importer source modules — NCES public K-12 schools, IPEDS colleges, and FAA commercial-service airports — for TX/FL/PA, landing as a staging apply.

**Architecture:** Each source is a self-contained `Source` subclass (mirroring the Phase 4 `gsa.py` / `hifld_military.py` pattern) that reads cached CSV(s) and yields `Candidate`s with native coordinates. They flow through the **unchanged** pipeline (normalize → refine_coords pass-through → apply_state_law → cross-source dedup → diff → apply). No schema migration, no pipeline/dedup changes, no Flutter changes. Only new files + CLI/config wiring + tests + docs.

**Tech Stack:** Python 3.12, pydantic, shapely (already present), stdlib `csv`, httpx; pytest with frozen CSV fixtures.

---

## Context the engineer must know

- **Run all commands from `C:\Users\camil\projects\ccwmap\importer`** (the importer package root). The venv is at `importer/.venv`; activate it or use `importer/.venv/Scripts/python -m pytest`.
- **Branch:** `feature/pre-populate` (Phase 4 work lives here; continue on it).
- **The `Candidate` contract** (`importer/importer/candidate.py`): `source, source_external_id, source_dataset_version, name (min_length 1), latitude, longitude, coord_quality, category, state (^[A-Z]{2}$), extra`. All three sources emit `coord_quality=CoordQuality.PRECISE`.
- **State assignment pattern (the GSA rule):** filter on the source's own state field, then **validate** by point-in-polygon — drop rows whose coordinate does not fall inside the claimed state (`coord_state_mismatch`). This both enforces TX/FL/PA scope and catches corrupt coordinates.
- **`StateLocator.state_for(lat, lng)`** returns the USPS code or `None`. Built from `importer/tests/fixtures/states_sample.geojson` (TX/FL/PA polygons only — a coordinate outside those three returns `None`).
- **`last_skip_counts: Counter`** is a side effect populated during iteration; callers must fully exhaust the iterator (`list(...)`) before reading it.
- **State-law cells already exist** (`data/state_laws/states.yaml`): `SCHOOL_K12` for TX/FL/PA, `COLLEGE_UNIVERSITY` for **FL only**, `AIRPORT_SECURE` federal-uniform `US`. The dedup priority (`nces=1, ipeds=2, faa=3`) and migration `008`'s `source` enum already include all three names.
- **Designed behavior:** IPEDS emits TX and PA colleges, which then **drop at `apply_state_law`** (no cell) and appear in the report's "missing cells" list. This is expected (see `docs/importer/OMISSIONS.md`), not a bug.

---

## File Structure

**Create:**
- `importer/importer/sources/nces.py` — NCES public-school source.
- `importer/importer/sources/ipeds.py` — IPEDS college source.
- `importer/importer/sources/faa.py` — FAA commercial-service airport source.
- `importer/tests/sources/test_nces.py`, `test_ipeds.py`, `test_faa.py`.
- `importer/tests/fixtures/nces_edge_sample.csv`, `nces_ccd_directory_sample.csv`,
  `ipeds_hd_sample.csv`, `faa_commercial_service_sample.csv`, `faa_nasr_apt_sample.csv`.

**Modify:**
- `importer/importer/cli.py` — imports, `SUPPORTED_SOURCES`, `_build_source` factory.
- `importer/config.yaml` — add `nces`, `ipeds`, `faa` source blocks.
- `importer/tests/test_cli.py` — supported-sources + factory coverage.
- `importer/tests/test_pipeline.py` — multi-source run surfacing the IPEDS missing-cell drops.
- `docs/importer/SOURCES.md`, `docs/importer/OMISSIONS.md`, `CLAUDE.md` — docs.

**Unchanged (verify, do not edit):** `pipeline.py`, `stages/dedup.py`, `stages/apply_state_law.py`, `stages/normalize.py`, `stages/diff.py`, `reports/*`, `supabase_client.py`, all migrations.

---

## Task 1: NCES public-school source

NCES public schools come from two CSVs joined on `NCESSCH`: the **EDGE geocode** file (name, state, lat/lon — the driver) and the **CCD directory** file (`SY_STATUS` — operational filter, so closed campuses are not pinned).

**Files:**
- Create: `importer/tests/fixtures/nces_edge_sample.csv`
- Create: `importer/tests/fixtures/nces_ccd_directory_sample.csv`
- Test: `importer/tests/sources/test_nces.py`
- Create: `importer/importer/sources/nces.py`

- [ ] **Step 1: Create the EDGE geocode fixture**

`importer/tests/fixtures/nces_edge_sample.csv`:

```csv
NCESSCH,NAME,STATE,LAT,LON,STREET,CITY,ZIP
480000100001,Austin High School,TX,30.2672,-97.7431,1715 W Cesar Chavez St,Austin,78703
120000200002,Miami Senior High School,FL,25.7617,-80.1918,2450 SW 1st St,Miami,33135
420000300003,Philadelphia Central HS,PA,39.9526,-75.1652,1700 W Olney Ave,Philadelphia,19141
480000400004,Closed Campus TX,TX,29.7604,-95.3698,100 Main St,Houston,77002
480000600006,Mislocated TX School,TX,43.0389,-87.9065,1 Wrong Way,Milwaukee,53202
060000500005,Los Angeles Senior HS,CA,34.0522,-118.2437,4650 W Olympic Blvd,Los Angeles,90019
```

- [ ] **Step 2: Create the CCD directory (status) fixture**

`importer/tests/fixtures/nces_ccd_directory_sample.csv` — `SY_STATUS`: `1`=Open, `2`=Closed:

```csv
NCESSCH,SY_STATUS,SCH_NAME,LSTATE
480000100001,1,Austin High School,TX
120000200002,1,Miami Senior High School,FL
420000300003,1,Philadelphia Central HS,PA
480000400004,2,Closed Campus TX,TX
480000600006,1,Mislocated TX School,TX
060000500005,1,Los Angeles Senior HS,CA
```

- [ ] **Step 3: Write the failing test**

`importer/tests/sources/test_nces.py`:

```python
from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.nces import NcesSource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


@pytest.fixture
def source():
    return NcesSource(
        cache_path=FIXTURE_DIR / "nces_edge_sample.csv",
        directory_path=FIXTURE_DIR / "nces_ccd_directory_sample.csv",
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
        dataset_version="NCES-FIXTURE",
    )


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "nces"


def test_emits_open_pilot_state_schools(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX", "FL", "PA"})}
    assert set(cands) == {"480000100001", "120000200002", "420000300003"}
    assert {c.state for c in cands.values()} == {"TX", "FL", "PA"}
    assert all(c.category is RestrictionTag.SCHOOL_K12 for c in cands.values())
    assert all(c.coord_quality is CoordQuality.PRECISE for c in cands.values())


def test_drops_closed_school(source):
    cands = {c.source_external_id for c in source.iter_candidates(state_filter={"TX", "FL", "PA"})}
    assert "480000400004" not in cands
    assert source.last_skip_counts["not_operational"] >= 1


def test_drops_mislocated_school_and_filters_out_of_region(source):
    list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert source.last_skip_counts["coord_state_mismatch"] >= 1  # 480000600006 claims TX, coords WI
    assert source.last_skip_counts["filtered_out"] >= 1          # CA school
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `.venv/Scripts/python -m pytest tests/sources/test_nces.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.sources.nces'`.

- [ ] **Step 5: Implement the source**

`importer/importer/sources/nces.py`:

```python
"""NCES public K-12 schools -> Candidate stream.

Two companion CSVs joined on NCESSCH:
  - EDGE public-school geocode file (NCESSCH, NAME, STATE, LAT, LON, address) —
    the coordinate-bearing driver. https://nces.ed.gov/programs/edge/
  - CCD directory file (NCESSCH, SY_STATUS) — operational-status lookup so closed
    campuses are not pinned. https://nces.ed.gov/ccd/
License: public domain (US Gov / NCES). Category: SCHOOL_K12 (cells exist for
TX/FL/PA). Native coordinates, so every Candidate is PRECISE.

Column names below were verified at pre-flight against the live release (Task 6);
if NCES renames a column, update the constant AND the frozen fixture together.
"""

from __future__ import annotations

import csv
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


class NcesSource(Source):
    SOURCE_NAME: ClassVar[str] = "nces"

    # EDGE geocode columns.
    _COL_ID = "NCESSCH"
    _COL_NAME = "NAME"
    _COL_STATE = "STATE"  # 2-letter USPS
    _COL_LAT = "LAT"
    _COL_LON = "LON"
    # CCD directory columns.
    _DIR_COL_ID = "NCESSCH"
    _DIR_COL_STATUS = "SY_STATUS"
    # CCD status codes that mean operating: 1=Open, 3=New, 8=Reopened.
    _OPERATIONAL_STATUSES: ClassVar[frozenset[str]] = frozenset({"1", "3", "8"})

    def __init__(
        self,
        *,
        cache_path: Path,
        directory_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
        directory_url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._directory_path = directory_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self._directory_url = directory_url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        for path, src_url in (
            (self._cache_path, self._url),
            (self._directory_path, self._directory_url),
        ):
            if path.exists() and not refetch:
                continue
            if not src_url:
                raise RuntimeError(
                    "nces url(s) not configured; set sources.nces.url and "
                    "sources.nces.directory_url in config.yaml"
                )
            path.parent.mkdir(parents=True, exist_ok=True)
            with httpx.Client(timeout=120.0, follow_redirects=True) as client:
                r = client.get(src_url)
                r.raise_for_status()
                path.write_bytes(r.content)

    def _load_status_map(self) -> dict[str, str]:
        out: dict[str, str] = {}
        with open(self._directory_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                eid = (row.get(self._DIR_COL_ID) or "").strip()
                if eid:
                    out[eid] = (row.get(self._DIR_COL_STATUS) or "").strip()
        return out

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        status_map = self._load_status_map()
        with open(self._cache_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                eid = (row.get(self._COL_ID) or "").strip()
                if not eid:
                    self.last_skip_counts["missing_external_id"] += 1
                    continue
                name = (row.get(self._COL_NAME) or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                state = (row.get(self._COL_STATE) or "").strip().upper()
                if state_filter is not None and state not in state_filter:
                    self.last_skip_counts["filtered_out"] += 1
                    continue
                lat, lng = self._coords(row)
                if lat is None or lng is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                status = status_map.get(eid)
                if status is not None and status not in self._OPERATIONAL_STATUSES:
                    self.last_skip_counts["not_operational"] += 1
                    continue
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=eid,
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=CoordQuality.PRECISE,
                    category=RestrictionTag.SCHOOL_K12,
                    state=state,
                    extra={},
                )

    @staticmethod
    def _coords(row: dict) -> tuple[float | None, float | None]:
        lat_s = (row.get(NcesSource._COL_LAT) or "").strip()
        lng_s = (row.get(NcesSource._COL_LON) or "").strip()
        if not lat_s or not lng_s:
            return None, None
        try:
            return float(lat_s), float(lng_s)
        except ValueError:
            return None, None
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `.venv/Scripts/python -m pytest tests/sources/test_nces.py -v`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add importer/importer/sources/nces.py importer/tests/sources/test_nces.py importer/tests/fixtures/nces_edge_sample.csv importer/tests/fixtures/nces_ccd_directory_sample.csv
git commit -m "feat(importer): add NCES public-school source (SCHOOL_K12)"
```

---

## Task 2: IPEDS college source

Single IPEDS **HD** ("directory information") CSV: `UNITID`, `INSTNM`, `STABBR`, `LATITUDE`, `LONGITUD`, `CYACTIVE` (1 = active). Emits `COLLEGE_UNIVERSITY` for all pilot states; TX/PA drop downstream at `apply_state_law`.

**Files:**
- Create: `importer/tests/fixtures/ipeds_hd_sample.csv`
- Test: `importer/tests/sources/test_ipeds.py`
- Create: `importer/importer/sources/ipeds.py`

- [ ] **Step 1: Create the HD fixture**

`importer/tests/fixtures/ipeds_hd_sample.csv`:

```csv
UNITID,INSTNM,STABBR,LATITUDE,LONGITUD,CYACTIVE
130001,University of Florida-Test,FL,29.6436,-82.3549,1
130002,University of Texas-Test,TX,30.2849,-97.7341,1
130003,Penn State-Test,PA,40.7982,-77.8599,1
130004,Closed College FL,FL,28.5383,-81.3792,2
130005,UCLA-Test,CA,34.0689,-118.4452,1
```

- [ ] **Step 2: Write the failing test**

`importer/tests/sources/test_ipeds.py`:

```python
from datetime import date
from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.ipeds import IpedsSource
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
from importer.state_laws import StateLawCell, StateLawTable

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


@pytest.fixture
def source():
    return IpedsSource(
        cache_path=FIXTURE_DIR / "ipeds_hd_sample.csv",
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
        dataset_version="IPEDS-FIXTURE",
    )


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "ipeds"


def test_emits_active_colleges_in_all_pilot_states(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX", "FL", "PA"})}
    assert set(cands) == {"130001", "130002", "130003"}
    assert {c.state for c in cands.values()} == {"FL", "TX", "PA"}
    assert all(c.category is RestrictionTag.COLLEGE_UNIVERSITY for c in cands.values())
    assert all(c.coord_quality is CoordQuality.PRECISE for c in cands.values())


def test_drops_closed_and_out_of_region(source):
    list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert source.last_skip_counts["not_operating"] >= 1  # closed FL
    assert source.last_skip_counts["filtered_out"] >= 1   # CA


def test_only_florida_colleges_classify_others_drop_as_missing_cell(source):
    # Only FL has a COLLEGE_UNIVERSITY cell; TX & PA must drop at apply_state_law
    # and surface as missing cells (designed behavior — see OMISSIONS.md).
    table = StateLawTable(rows=[
        StateLawCell(
            state="FL", category=RestrictionTag.COLLEGE_UNIVERSITY,
            default_status="NO_GUN", confidence="high", conditions=[],
            citation="Fla. Stat. 790.06(12)(a)(13)",
            last_verified_date=date(2026, 5, 31), source_filter=["ipeds"],
        ),
    ])
    cands = list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    stats = ApplyStateLawStats()
    classified = list(apply_state_law(cands, table=table, stats=stats))
    assert {cc.candidate.state for cc in classified} == {"FL"}
    assert ("TX", "COLLEGE_UNIVERSITY") in stats.missing_cells
    assert ("PA", "COLLEGE_UNIVERSITY") in stats.missing_cells
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `.venv/Scripts/python -m pytest tests/sources/test_ipeds.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.sources.ipeds'`.

- [ ] **Step 4: Implement the source**

`importer/importer/sources/ipeds.py`:

```python
"""IPEDS colleges/universities -> Candidate stream.

Source: IPEDS HD ("Directory information") CSV — one per survey year with UNITID
(stable id), INSTNM, STABBR (state), LATITUDE/LONGITUD, CYACTIVE (1 = active).
https://nces.ed.gov/ipeds/ — License: public domain (US Gov / NCES).
Category: COLLEGE_UNIVERSITY. Native coordinates, so every Candidate is PRECISE.

Only FL has a COLLEGE_UNIVERSITY state-law cell; TX and PA college candidates are
emitted here and then dropped downstream by apply_state_law (no matching cell),
surfacing as expected "missing cell" report noise — see docs/importer/OMISSIONS.md
(TX campus-carry; PA institution-policy).
"""

from __future__ import annotations

import csv
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


class IpedsSource(Source):
    SOURCE_NAME: ClassVar[str] = "ipeds"

    _COL_ID = "UNITID"
    _COL_NAME = "INSTNM"
    _COL_STATE = "STABBR"  # 2-letter USPS
    _COL_LAT = "LATITUDE"
    _COL_LON = "LONGITUD"
    _COL_ACTIVE = "CYACTIVE"  # 1 = active in current year

    def __init__(
        self,
        *,
        cache_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        if self._cache_path.exists() and not refetch:
            return
        if not self._url:
            raise RuntimeError("ipeds url not configured; set sources.ipeds.url in config.yaml")
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        with open(self._cache_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                eid = (row.get(self._COL_ID) or "").strip()
                if not eid:
                    self.last_skip_counts["missing_external_id"] += 1
                    continue
                name = (row.get(self._COL_NAME) or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                state = (row.get(self._COL_STATE) or "").strip().upper()
                if state_filter is not None and state not in state_filter:
                    self.last_skip_counts["filtered_out"] += 1
                    continue
                if (row.get(self._COL_ACTIVE) or "").strip() != "1":
                    self.last_skip_counts["not_operating"] += 1
                    continue
                lat, lng = self._coords(row)
                if lat is None or lng is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=eid,
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=CoordQuality.PRECISE,
                    category=RestrictionTag.COLLEGE_UNIVERSITY,
                    state=state,
                    extra={},
                )

    @staticmethod
    def _coords(row: dict) -> tuple[float | None, float | None]:
        lat_s = (row.get(IpedsSource._COL_LAT) or "").strip()
        lng_s = (row.get(IpedsSource._COL_LON) or "").strip()
        if not lat_s or not lng_s:
            return None, None
        try:
            return float(lat_s), float(lng_s)
        except ValueError:
            return None, None
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `.venv/Scripts/python -m pytest tests/sources/test_ipeds.py -v`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources/ipeds.py importer/tests/sources/test_ipeds.py importer/tests/fixtures/ipeds_hd_sample.csv
git commit -m "feat(importer): add IPEDS college source (COLLEGE_UNIVERSITY)"
```

---

## Task 3: FAA commercial-service airport source

Two CSVs joined on the airport location id: a **commercial-service list** (`LOCID`, `STATE`, `AIRPORT_NAME`, `SERVICE_LEVEL`) and **NASR APT** coordinates (`ARPT_ID`, `LAT_DECIMAL`, `LONG_DECIMAL`). Only commercial-service entries (which have TSA screening) are emitted. Name comes from the mixed-case commercial-service list; coordinates from NASR.

**Files:**
- Create: `importer/tests/fixtures/faa_commercial_service_sample.csv`
- Create: `importer/tests/fixtures/faa_nasr_apt_sample.csv`
- Test: `importer/tests/sources/test_faa.py`
- Create: `importer/importer/sources/faa.py`

- [ ] **Step 1: Create the commercial-service list fixture**

`importer/tests/fixtures/faa_commercial_service_sample.csv`:

```csv
LOCID,STATE,AIRPORT_NAME,SERVICE_LEVEL
DFW,TX,Dallas Fort Worth International,Primary
MIA,FL,Miami International,Primary
PHL,PA,Philadelphia International,Primary
T74,TX,Taylor Municipal,General Aviation
LAX,CA,Los Angeles International,Primary
AUS,TX,Austin Bergstrom International,Primary
ABC,TX,Phantom Field,Primary
```

- [ ] **Step 2: Create the NASR coordinates fixture**

`importer/tests/fixtures/faa_nasr_apt_sample.csv` — note `AUS` coords are deliberately Milwaukee (mismatch test); `ABC` is absent (missing-coords test):

```csv
ARPT_ID,ARPT_NAME,STATE_CODE,LAT_DECIMAL,LONG_DECIMAL
DFW,DALLAS FORT WORTH INTL,TX,32.8998,-97.0403
MIA,MIAMI INTL,FL,25.7959,-80.2870
PHL,PHILADELPHIA INTL,PA,39.8744,-75.2424
T74,TAYLOR MUNI,TX,30.5744,-97.4438
LAX,LOS ANGELES INTL,CA,33.9416,-118.4085
AUS,AUSTIN BERGSTROM INTL,TX,43.0389,-87.9065
```

- [ ] **Step 3: Write the failing test**

`importer/tests/sources/test_faa.py`:

```python
from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.faa import FaaSource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


@pytest.fixture
def source():
    return FaaSource(
        cache_path=FIXTURE_DIR / "faa_commercial_service_sample.csv",
        nasr_path=FIXTURE_DIR / "faa_nasr_apt_sample.csv",
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
        dataset_version="FAA-FIXTURE",
    )


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "faa"


def test_emits_only_commercial_service_in_pilot_states(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX", "FL", "PA"})}
    assert set(cands) == {"DFW", "MIA", "PHL"}
    assert all(c.category is RestrictionTag.AIRPORT_SECURE for c in cands.values())
    assert all(c.coord_quality is CoordQuality.PRECISE for c in cands.values())
    assert cands["DFW"].latitude == pytest.approx(32.8998)
    assert cands["DFW"].name == "Dallas Fort Worth International"  # mixed-case from CS list


def test_excludes_general_aviation_and_out_of_state(source):
    list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert source.last_skip_counts["not_commercial_service"] >= 1  # T74 (General Aviation)
    assert source.last_skip_counts["filtered_out"] >= 1            # LAX (CA)


def test_drops_missing_and_mislocated_coords(source):
    cands = {c.source_external_id for c in source.iter_candidates(state_filter={"TX", "FL", "PA"})}
    assert "ABC" not in cands  # no NASR row
    assert "AUS" not in cands  # NASR coords in WI, claims TX
    assert source.last_skip_counts["missing_coords"] >= 1
    assert source.last_skip_counts["coord_state_mismatch"] >= 1
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `.venv/Scripts/python -m pytest tests/sources/test_faa.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.sources.faa'`.

- [ ] **Step 5: Implement the source**

`importer/importer/sources/faa.py`:

```python
"""FAA commercial-service airports -> Candidate stream.

The AIRPORT_SECURE prohibition attaches to the TSA sterile/secured area past a
screening checkpoint, which exists only at airports with passenger screening. This
source emits the COMMERCIAL-SERVICE subset only, not all NPIAS.

Two companion CSVs (both public domain, US Gov), joined on the airport location id:
  - Commercial-service list: LOCID, STATE, AIRPORT_NAME, SERVICE_LEVEL — the
    authoritative set of commercial-service airports.
    https://www.faa.gov/airports/planning_capacity/npias/
  - FAA NASR APT data: ARPT_ID, LAT_DECIMAL, LONG_DECIMAL — coordinate source
    (airport reference point).
    https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/

Category: AIRPORT_SECURE (federal-uniform US cell). The pin name uses the
mixed-case commercial-service list; coordinates use the NASR ARP. PRECISE.
"""

from __future__ import annotations

import csv
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


class FaaSource(Source):
    SOURCE_NAME: ClassVar[str] = "faa"

    # Commercial-service list columns.
    _CS_COL_ID = "LOCID"
    _CS_COL_STATE = "STATE"
    _CS_COL_NAME = "AIRPORT_NAME"
    _CS_COL_SERVICE = "SERVICE_LEVEL"
    # Service levels with scheduled passenger service (hence TSA screening).
    # Compared case-insensitively.
    _COMMERCIAL_SERVICE: ClassVar[frozenset[str]] = frozenset({
        "primary",
        "nonprimary commercial service",
        "commercial service",
    })
    # NASR APT columns.
    _APT_COL_ID = "ARPT_ID"
    _APT_COL_LAT = "LAT_DECIMAL"
    _APT_COL_LON = "LONG_DECIMAL"

    def __init__(
        self,
        *,
        cache_path: Path,
        nasr_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
        nasr_url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._nasr_path = nasr_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self._nasr_url = nasr_url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        for path, src_url in (
            (self._cache_path, self._url),
            (self._nasr_path, self._nasr_url),
        ):
            if path.exists() and not refetch:
                continue
            if not src_url:
                raise RuntimeError(
                    "faa url(s) not configured; set sources.faa.url and "
                    "sources.faa.nasr_url in config.yaml"
                )
            path.parent.mkdir(parents=True, exist_ok=True)
            with httpx.Client(timeout=120.0, follow_redirects=True) as client:
                r = client.get(src_url)
                r.raise_for_status()
                path.write_bytes(r.content)

    def _load_nasr_coords(self) -> dict[str, tuple[float, float]]:
        out: dict[str, tuple[float, float]] = {}
        with open(self._nasr_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                locid = (row.get(self._APT_COL_ID) or "").strip().upper()
                lat_s = (row.get(self._APT_COL_LAT) or "").strip()
                lng_s = (row.get(self._APT_COL_LON) or "").strip()
                if not locid or not lat_s or not lng_s:
                    continue
                try:
                    out[locid] = (float(lat_s), float(lng_s))
                except ValueError:
                    continue
        return out

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        coords = self._load_nasr_coords()
        with open(self._cache_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                service = (row.get(self._CS_COL_SERVICE) or "").strip().lower()
                if service not in self._COMMERCIAL_SERVICE:
                    self.last_skip_counts["not_commercial_service"] += 1
                    continue
                state = (row.get(self._CS_COL_STATE) or "").strip().upper()
                if state_filter is not None and state not in state_filter:
                    self.last_skip_counts["filtered_out"] += 1
                    continue
                locid = (row.get(self._CS_COL_ID) or "").strip().upper()
                if not locid:
                    self.last_skip_counts["missing_external_id"] += 1
                    continue
                name = (row.get(self._CS_COL_NAME) or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                hit = coords.get(locid)
                if hit is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                lat, lng = hit
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=locid,
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=CoordQuality.PRECISE,
                    category=RestrictionTag.AIRPORT_SECURE,
                    state=state,
                    extra={},
                )
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `.venv/Scripts/python -m pytest tests/sources/test_faa.py -v`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add importer/importer/sources/faa.py importer/tests/sources/test_faa.py importer/tests/fixtures/faa_commercial_service_sample.csv importer/tests/fixtures/faa_nasr_apt_sample.csv
git commit -m "feat(importer): add FAA commercial-service airport source (AIRPORT_SECURE)"
```

---

## Task 4: Wire the three sources into the CLI + config

**Files:**
- Modify: `importer/importer/cli.py`
- Modify: `importer/config.yaml`
- Test: `importer/tests/test_cli.py`

- [ ] **Step 1: Extend the CLI test (failing)**

In `importer/tests/test_cli.py`, **replace** `test_supported_sources_includes_gsa_and_military` with the expanded version and **replace** `test_build_source_factory_constructs_each` with the six-source version:

```python
def test_supported_sources_includes_all_phase4_and_phase5():
    from importer.cli import SUPPORTED_SOURCES
    for name in ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa"):
        assert name in SUPPORTED_SOURCES


def test_build_source_factory_constructs_each(tmp_path):
    from pathlib import Path
    from importer.cli import _build_source
    from importer.geo.states import load_state_locator
    fixtures = Path(__file__).parent / "fixtures"
    locator = load_state_locator(fixtures / "states_sample.geojson")
    config = {
        "sources": {
            "hifld_courts": {"cache_dir": "data/sources/hifld_courts", "dataset_version": "v", "url": "u"},
            "gsa": {"cache_dir": "data/sources/gsa", "dataset_version": "v", "url": "u"},
            "hifld_military": {"cache_dir": "data/sources/hifld_military", "dataset_version": "v", "url": "u"},
            "nces": {"cache_dir": "data/sources/nces", "dataset_version": "v", "url": "u", "directory_url": "d"},
            "ipeds": {"cache_dir": "data/sources/ipeds", "dataset_version": "v", "url": "u"},
            "faa": {"cache_dir": "data/sources/faa", "dataset_version": "v", "url": "u", "nasr_url": "n"},
        }
    }
    for name in ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa"):
        src = _build_source(name, config=config, locator=locator, repo_root=tmp_path)
        assert src.SOURCE_NAME == name
```

- [ ] **Step 2: Run to verify it fails**

Run: `.venv/Scripts/python -m pytest tests/test_cli.py -v`
Expected: FAIL — `nces`/`ipeds`/`faa` not in `SUPPORTED_SOURCES`; `_build_source` raises `NotImplementedError`.

- [ ] **Step 3: Update `cli.py` imports**

In `importer/importer/cli.py`, add to the source imports (after the existing `from importer.sources.hifld_military import HifldMilitarySource`):

```python
from importer.sources.faa import FaaSource
from importer.sources.ipeds import IpedsSource
from importer.sources.nces import NcesSource
```

- [ ] **Step 4: Expand `SUPPORTED_SOURCES`**

Replace:

```python
SUPPORTED_SOURCES = ("hifld_courts", "gsa", "hifld_military")
```

with:

```python
SUPPORTED_SOURCES = ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa")
```

- [ ] **Step 5: Add the factory branches**

In `_build_source`, before the final `raise NotImplementedError(name)`, add:

```python
    if name == "nces":
        return NcesSource(
            cache_path=cache_dir / "edge_geocode.csv",
            directory_path=cache_dir / "ccd_directory.csv",
            state_locator=locator, dataset_version=version,
            url=url, directory_url=cfg.get("directory_url", ""),
        )
    if name == "ipeds":
        return IpedsSource(
            cache_path=cache_dir / "hd.csv",
            state_locator=locator, dataset_version=version, url=url,
        )
    if name == "faa":
        return FaaSource(
            cache_path=cache_dir / "commercial_service.csv",
            nasr_path=cache_dir / "nasr_apt.csv",
            state_locator=locator, dataset_version=version,
            url=url, nasr_url=cfg.get("nasr_url", ""),
        )
```

- [ ] **Step 6: Add the config blocks**

In `importer/config.yaml`, under `sources:`, append (URLs and `dataset_version` are **pinned at pre-flight in Task 6** — leave `url` values empty for now; `fetch()` raises a clear error if used before they are set, and tests never call `fetch()`):

```yaml
  nces:
    # NCES public K-12. Two files joined on NCESSCH: EDGE geocode (coords) +
    # CCD directory (SY_STATUS operational filter). URLs pinned in Task 6.
    cache_dir: "data/sources/nces"
    dataset_version: "NCES-PREFLIGHT"
    url: ""            # EDGE public-school geocode CSV
    directory_url: ""  # CCD directory CSV (status)
  ipeds:
    # IPEDS HD directory CSV (UNITID, INSTNM, STABBR, LATITUDE, LONGITUD, CYACTIVE).
    cache_dir: "data/sources/ipeds"
    dataset_version: "IPEDS-PREFLIGHT"
    url: ""
  faa:
    # FAA commercial-service airports. Two files joined on LOCID/ARPT_ID:
    # commercial-service list (service level) + NASR APT (coords). URLs pinned in Task 6.
    cache_dir: "data/sources/faa"
    dataset_version: "FAA-PREFLIGHT"
    url: ""       # commercial-service list CSV
    nasr_url: ""  # NASR APT CSV
```

- [ ] **Step 7: Run the CLI tests**

Run: `.venv/Scripts/python -m pytest tests/test_cli.py -v`
Expected: PASS (all tests, including the two updated ones).

- [ ] **Step 8: Commit**

```bash
git add importer/importer/cli.py importer/config.yaml importer/tests/test_cli.py
git commit -m "feat(importer): register nces/ipeds/faa sources in CLI + config"
```

---

## Task 5: Multi-source pipeline test (IPEDS missing-cell surfacing)

Verify the pipeline carries the IPEDS TX/PA "missing cell" drops into the per-source report. `pipeline.py` needs **no change** — this is a regression test of existing behavior with the new source shape.

**Files:**
- Test: `importer/tests/test_pipeline.py`

- [ ] **Step 1: Add the failing test**

Append to `importer/tests/test_pipeline.py` (the `_FakeSource` and `_mock_client` helpers already exist in that file; reuse them):

```python
def test_pipeline_surfaces_ipeds_missing_cells() -> None:
    from datetime import date as _date
    from importer.state_laws import StateLawCell

    def _college(eid, state, lat, lng):
        return Candidate(
            source="ipeds", source_external_id=eid, source_dataset_version="v",
            name=f"College {eid}", latitude=lat, longitude=lng,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.COLLEGE_UNIVERSITY, state=state,
        )

    ipeds = _FakeSource("ipeds", [
        _college("u-fl", "FL", 29.6436, -82.3549),
        _college("u-tx", "TX", 30.2849, -97.7341),
        _college("u-pa", "PA", 40.7982, -77.8599),
    ])
    table = StateLawTable(rows=[
        StateLawCell(
            state="FL", category=RestrictionTag.COLLEGE_UNIVERSITY,
            default_status="NO_GUN", confidence="high", conditions=[],
            citation="Fla. Stat. 790.06(12)(a)(13)",
            last_verified_date=_date(2026, 5, 31), source_filter=["ipeds"],
        ),
    ])
    client = _mock_client()
    result = run_pipeline(
        sources=[ipeds],
        state_laws=table,
        client=client,
        states=["TX", "FL", "PA"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    src = next(s for s in result.sources if s.source == "ipeds")
    assert src.classified == 1            # only FL
    assert src.dropped_no_cell == 2       # TX + PA
    assert ("TX", "COLLEGE_UNIVERSITY") in src.missing_cells
    assert ("PA", "COLLEGE_UNIVERSITY") in src.missing_cells
    assert len(src.diff.inserts) == 1     # only the FL college is written
```

- [ ] **Step 2: Run to verify it passes (behavior already supported)**

Run: `.venv/Scripts/python -m pytest tests/test_pipeline.py -v`
Expected: PASS. If it fails, do **not** edit `pipeline.py` to special-case IPEDS — investigate why `apply_state_law`/report wiring isn't surfacing `missing_cells` (the existing `SourceResult.missing_cells` field is populated from `asl_stats.missing_cells` in `pipeline.py`).

- [ ] **Step 3: Run the full importer suite**

Run: `.venv/Scripts/python -m pytest -q`
Expected: PASS — the prior count (110 at Phase 4) plus the new tests, all green.

- [ ] **Step 4: Commit**

```bash
git add importer/tests/test_pipeline.py
git commit -m "test(importer): assert pipeline surfaces IPEDS missing-cell drops"
```

---

## Task 6: Pre-flight — capture real datasets, pin URLs, realize fixtures

This is the network/research step that converts the plan's synthetic fixtures into **real captured rows** and pins the live URLs. Requires internet. The agent can do this if it has network access; otherwise it is operator-run. Do this **per source**.

> Important: if a live column name differs from a `_COL_*` constant, update the **constant in the source module AND the fixture header together**, then re-run that source's tests. The tests are the contract.

- [ ] **Step 1: NCES — download + inspect**

  - Find the current **EDGE public-school geocode** file (CSV) and the **CCD directory** file at https://nces.ed.gov/programs/edge/Geographic/SchoolLocations and https://nces.ed.gov/ccd/files.asp. If EDGE ships as `.xlsx` inside a `.zip`, extract and convert the sheet to CSV at the cache path (or adjust `NcesSource` to read xlsx via `openpyxl`, already a dependency — mirror `gsa.py:_read_rows`).
  - Print headers to confirm the constants:
    `python -c "import csv;print(next(csv.reader(open('PATH', encoding='utf-8-sig'))))"`
    Confirm `NCESSCH, NAME, STATE, LAT, LON` (EDGE) and `NCESSCH, SY_STATUS` (CCD). Note: some CCD releases name status `SY_STATUS_TEXT` (values like `Open`/`Closed`) — if so, change `_DIR_COL_STATUS` and `_OPERATIONAL_STATUSES` to match the text values.
  - Replace fixture rows with ~6–8 **real** TX/FL/PA rows (keep one closed and one deliberately out-of-region row for the skip-counter tests). Re-run `tests/sources/test_nces.py`, adjusting expected IDs/coords to the real rows.
  - Set `sources.nces.url`, `sources.nces.directory_url`, `sources.nces.dataset_version` (e.g. `NCES-2023-24`) in `config.yaml`.

- [ ] **Step 2: IPEDS — download + inspect**

  - Download the current **HD** ("Directory information") CSV from the IPEDS data center (https://nces.ed.gov/ipeds/datacenter/) — typically `hdYYYY.csv` inside a zip. IPEDS CSVs are often `latin-1`/`cp1252`; if `utf-8-sig` raises a decode error on the live file, change the `open(...)` encoding in `ipeds.py` to `"latin-1"` (and note it in the module docstring).
  - Confirm headers `UNITID, INSTNM, STABBR, LATITUDE, LONGITUD, CYACTIVE`.
  - Replace fixture rows with ~5 real rows (FL active, TX active, PA active, a closed FL, an out-of-region active). Re-run `tests/sources/test_ipeds.py`.
  - Set `sources.ipeds.url`, `sources.ipeds.dataset_version` (e.g. `IPEDS-HD2023`).

- [ ] **Step 3: FAA — download + inspect**

  - Get the authoritative **commercial-service airport list** (FAA NPIAS report appendix or the FAA "Passenger Boarding (Enplanement)" / commercial-service spreadsheet) and the **NASR APT** data (https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/). Export both to CSV at the cache paths.
  - Confirm the commercial-service list's id/state/name/service-level columns and adjust `_CS_COL_*` + `_COMMERCIAL_SERVICE` to the real values (e.g. the list may use a hub column `S`/`L`/`M`/`N` rather than a `SERVICE_LEVEL` string — if so, set `_CS_COL_SERVICE` to that column and `_COMMERCIAL_SERVICE` to the codes that imply scheduled service). Confirm NASR `ARPT_ID, LAT_DECIMAL, LONG_DECIMAL`.
  - Replace fixtures with ~7 real rows preserving the GA-excluded, out-of-state, missing-coords, and mislocated cases. Re-run `tests/sources/test_faa.py`.
  - Set `sources.faa.url`, `sources.faa.nasr_url`, `sources.faa.dataset_version` (e.g. `FAA-2024`).

- [ ] **Step 4: Full suite green on real fixtures**

Run: `.venv/Scripts/python -m pytest -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add importer/importer/sources/ importer/tests/sources/ importer/tests/fixtures/ importer/config.yaml
git commit -m "chore(importer): pin Phase 5 dataset URLs + real frozen fixtures"
```

---

## Task 7: Documentation

**Files:**
- Modify: `docs/importer/SOURCES.md`
- Modify: `docs/importer/OMISSIONS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update `docs/importer/SOURCES.md`**

Mark NCES (public K-12), IPEDS, FAA (commercial-service) as **Phase 5 (built)**. Record, for each: the dataset files used, the two-file join key (NCES `NCESSCH`, FAA `LOCID`/`ARPT_ID`), the commercial-service rationale for FAA, and that all three carry native coordinates (no geocoding/refinement). Correct any stale "NCES = Phase 4" row.

- [ ] **Step 2: Update `docs/importer/OMISSIONS.md`**

Add a one-line note under the TX/PA `COLLEGE_UNIVERSITY` rows: "As of Phase 5, the `ipeds` source actively emits these candidates; they drop at `apply_state_law` and appear in the dry-run 'missing cells' list — expected, not a gap."

- [ ] **Step 3: Update `CLAUDE.md` status line**

In the **Current Status** paragraph, note Phase 5 (schools + airports) sources built: NCES public K-12 (EDGE geocode + CCD status), IPEDS colleges (FL classified; TX/PA expected missing-cell drops), FAA commercial-service airports (NASR coords); no new migration; staging apply pending. Update the importer test count.

- [ ] **Step 4: Commit**

```bash
git add docs/importer/SOURCES.md docs/importer/OMISSIONS.md CLAUDE.md
git commit -m "docs(importer): document Phase 5 schools+airports sources"
```

---

## Task 8: Staging dry-run + apply (operator/agent verification)

The Supabase MCP is now bound to staging, so post-apply verification can run over MCP. The importer's `fetch`/`apply` still needs the **staging** service-role key in `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`.

- [ ] **Step 1: Combined dry-run (all six sources) against staging**

Run (from `importer/`, with the staging key exported):

```bash
python -m importer.cli --dry-run --states TX,FL,PA \
  --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa \
  --project-ref staging
```

Review the report together: per-source candidate counts (~16k NCES, hundreds IPEDS-FL, ~50 FAA), the IPEDS TX/PA missing-cell drops in the "missing cells" section, and the **dedup drops-by-pair** — confirm no spurious collapses between FAA airports and Phase 4 federal pins, and between NCES/IPEDS.

- [ ] **Step 2: Apply to staging**

```bash
python -m importer.cli --apply --states TX,FL,PA \
  --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa \
  --project-ref staging --i-know-this-writes-to-staging
```

- [ ] **Step 3: Verify over MCP (staging)**

Use `mcp__supabase__execute_sql` against staging:
- `select source, restriction_tag, count(*) from pins group by 1,2 order by 1,2;` — confirm `nces`/`SCHOOL_K12`, `ipeds`/`COLLEGE_UNIVERSITY` (FL only), `faa`/`AIRPORT_SECURE` rows exist with expected magnitudes.
- Confirm no `ipeds` rows for TX/PA: `select count(*) from pins where source='ipeds' and latitude between <PA/TX bbox>` (or join state via a spot check).
- Run `mcp__supabase__get_advisors` (type `security` and `performance`) — confirm no new warnings.

- [ ] **Step 4: Idempotency — re-run apply, expect all-SKIP**

Re-run the Step 2 command. Confirm the report shows ~0 inserts/updates (all SKIP) and staging row counts are unchanged over MCP.

- [ ] **Step 5: Clustering eyeball**

Point a local app build at staging (staging `SUPABASE_URL` + anon key in `.env`) and pan to **Houston, Miami, Philadelphia** at regional and neighborhood zoom. Confirm clusters render and expand sensibly with the new pin volume (parent spec §8 Phase 5 exit criterion). No commit — this is observation; capture findings in the PR description.

---

## Self-Review

**Spec coverage:**
- §1 NCES source → Task 1 + Task 6 Step 1. ✓
- §1 IPEDS source (FL-only classify; TX/PA missing-cell) → Task 2 + Task 5 + Task 6 Step 2. ✓
- §1 FAA commercial-service source → Task 3 + Task 6 Step 3. ✓
- §2 dedup interaction (no code change) → verified-unchanged; exercised in Task 8 Step 1 drops-by-pair review. ✓
- §3 CLI/config/registry → Task 4. ✓
- §3 reports (missing-cells rendering) → Task 5 (no code change needed; existing `SourceResult.missing_cells`). ✓
- §4 tests/docs/deps → Tasks 1–5 (tests), Task 7 (docs); no new deps. ✓
- §4 operator/agent run split → Task 8. ✓
- Success criteria (combined dry-run, idempotent apply, <1% dupes, user-pin safety, clustering) → Task 8 Steps 1–5. ✓
- No migration / no Flutter / ODbL deferred → honored (no such tasks). ✓

**Placeholder scan:** The only intentionally-empty values are the `config.yaml` `url`/`dataset_version` fields, which are explicitly pinned in Task 6 (a real task with concrete commands), mirroring how Phase 4 captured the FRPP/MIRTA URLs. `fetch()` raises a clear error if used before they are set; unit tests never call `fetch()`. Not a vague TODO.

**Type consistency:** `Candidate`, `CoordQuality.PRECISE`, `RestrictionTag.{SCHOOL_K12,COLLEGE_UNIVERSITY,AIRPORT_SECURE}`, `StateLocator.state_for`, `StateLawCell(... source_filter=[...])`, `ApplyStateLawStats.missing_cells`, `SourceResult.{classified,dropped_no_cell,missing_cells,diff}`, `_build_source(name, *, config, locator, repo_root)` — all checked against the live modules read during planning. Source constructor signatures (`NcesSource`, `IpedsSource`, `FaaSource`) match their `_build_source` call sites and their test fixtures.
