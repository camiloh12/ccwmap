# Phase 4 — Federal Floor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GSA FRPP + HIFLD military source modules, a US Census batch geocoder, and a real cross-source dedup, wired into a multi-source importer pipeline that produces the federal-floor pins (FEDERAL_PROPERTY + courthouses) for TX/FL/PA — validated by dry-run/apply against **staging only**.

**Architecture:** Each upstream dataset is a `Source` that yields `Candidate`s. `run_pipeline` now takes a *list* of sources, runs each through normalize → refine(pass-through) → apply-state-law, then a **single** cross-source `dedup` pass (shapely STRtree + rapidfuzz, priority `user > … > gsa > hifld_* > osm`) before diffing/applying per source against Supabase. No Flutter changes, no schema migration — `008` already added every provenance column the floor writes.

**Tech Stack:** Python 3.12, pydantic v2, httpx (0.27.x), shapely 2.0 (STRtree + centroids), rapidfuzz (new), pytest + pytest-httpx. Spec: [`docs/superpowers/specs/2026-06-02-phase4-federal-floor-design.md`](../specs/2026-06-02-phase4-federal-floor-design.md).

---

## File Structure

**New files:**
- `importer/importer/stages/dedup.py` — replaces the pass-through with real cross-source resolution + `DedupResult`. (Helpers `_meters_between`, `_matches`, `SOURCE_PRIORITY` live here.)
- `importer/importer/geo/census_geocode.py` — `CensusGeocoder` client + on-disk cache.
- `importer/importer/sources/hifld_military.py` — polygon-centroid military source.
- `importer/importer/sources/gsa.py` — FRPP CSV source (uses `CensusGeocoder`).
- `importer/tests/stages/test_dedup.py`
- `importer/tests/geo/__init__.py`, `importer/tests/geo/test_census_geocode.py`
- `importer/tests/sources/test_hifld_military.py`, `importer/tests/sources/test_gsa.py`
- `importer/tests/fixtures/hifld_military_sample.geojson`
- `importer/tests/fixtures/gsa_frpp_sample.csv`, `importer/tests/fixtures/census_batch_response.txt`

**Modified files:**
- `importer/pyproject.toml` — add `rapidfuzz`.
- `importer/importer/reports/__init__.py` — restructure `PipelineResult` into per-source `SourceResult` + `DedupReport`.
- `importer/importer/reports/markdown.py`, `importer/importer/reports/json_report.py` — render the multi-source shape.
- `importer/importer/pipeline.py` — `run_pipeline(sources: list[Source], …)`.
- `importer/importer/supabase_client.py` — add `select_user_pins()`.
- `importer/importer/cli.py` — source-factory registry; build a list; one combined report.
- `importer/config.yaml` — add `gsa` + `hifld_military` blocks.
- `importer/tests/test_pipeline.py`, `importer/tests/test_cli.py`, `importer/tests/reports/test_markdown.py`, `importer/tests/reports/test_json_report.py` — update for the new shape.
- `docs/importer/SOURCES.md`, `CLAUDE.md`.

**Test command (run from `importer/`):** `python -m pytest -q` (the repo venv is `importer/.venv`; use `importer/.venv/Scripts/python.exe -m pytest -q` on Windows if the bare `python` isn't the venv).

---

## Task 1: Add rapidfuzz + dedup primitives

**Files:**
- Modify: `importer/pyproject.toml`
- Create: `importer/importer/stages/dedup.py` (overwrites the pass-through)
- Test: `importer/tests/stages/test_dedup.py`

- [ ] **Step 1: Add the dependency**

In `importer/pyproject.toml`, add `rapidfuzz` to `dependencies` (keep alphabetical-ish, after `pyyaml`):

```toml
dependencies = [
    # Pinned to 0.27.x for pytest-httpx 0.30.x compat — revisit when pytest-httpx supports httpx 0.28.
    "httpx >= 0.27,< 0.28",
    "pydantic >= 2.7,< 3",
    "pyyaml >= 6.0,< 7",
    "rapidfuzz >= 3.9,< 4",
    "shapely >= 2.0,< 3",
]
```

- [ ] **Step 2: Install it into the venv**

Run (from `importer/`): `python -m pip install -e ".[dev]"`
Expected: `Successfully installed ... rapidfuzz-3.x`

- [ ] **Step 3: Write the failing test for the distance + match helpers**

Create `importer/tests/stages/test_dedup.py`:

```python
from importer.stages.dedup import _matches, _meters_between


def test_meters_between_is_zero_for_same_point():
    assert _meters_between(30.0, -97.0, 30.0, -97.0) == 0.0


def test_meters_between_approximates_one_degree_lat():
    # ~111 km per degree latitude.
    m = _meters_between(30.0, -97.0, 31.0, -97.0)
    assert 110_000 < m < 112_000


def test_matches_true_when_close_and_similar_name():
    assert _matches("Travis County Courthouse", 30.2672, -97.7431,
                    "Travis County Court House", 30.2673, -97.7432) is True


def test_matches_false_when_far_apart():
    assert _matches("Travis County Courthouse", 30.2672, -97.7431,
                    "Travis County Courthouse", 31.0, -97.7431) is False


def test_matches_false_when_names_differ():
    assert _matches("Federal Building", 30.2672, -97.7431,
                    "City Animal Shelter", 30.2673, -97.7432) is False
```

- [ ] **Step 4: Run it — expect failure**

Run: `python -m pytest tests/stages/test_dedup.py -q`
Expected: FAIL — `ModuleNotFoundError`/`ImportError: cannot import name '_matches'`.

- [ ] **Step 5: Write `dedup.py` with the primitives (full real dedup added in Task 2)**

Overwrite `importer/importer/stages/dedup.py`:

```python
"""Cross-source + within-source dedup (spec §4 step 4).

Two records match when they are within MATCH_RADIUS_M AND
rapidfuzz.token_set_ratio(name_a, name_b) >= NAME_RATIO_THRESHOLD. On a match the
lower-priority record is dropped. user-created pins are highest priority and are
never dropped; a candidate matching a user pin is dropped.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from rapidfuzz import fuzz
from shapely.geometry import Point
from shapely.strtree import STRtree

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.supabase_client import ExistingPinRow

# Highest priority = lowest number = wins a match. HIFLD sub-sources share a tier.
SOURCE_PRIORITY: dict[str, int] = {
    "user": 0,
    "nces": 1,
    "ipeds": 2,
    "faa": 3,
    "gsa": 4,
    "hifld_courts": 5,
    "hifld_hospitals": 5,
    "hifld_military": 5,
    "osm": 6,
}

MATCH_RADIUS_M = 100.0
NAME_RATIO_THRESHOLD = 70.0
_DEG_LAT_M = 111_320.0  # meters per degree of latitude


def _priority(source: str) -> int:
    return SOURCE_PRIORITY.get(source, 99)


def _meters_between(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Equirectangular approximation — adequate at the 100 m scale in CONUS."""
    mean_lat = math.radians((lat1 + lat2) / 2.0)
    dx = (lng2 - lng1) * _DEG_LAT_M * math.cos(mean_lat)
    dy = (lat2 - lat1) * _DEG_LAT_M
    return math.hypot(dx, dy)


def _matches(
    name_a: str, lat_a: float, lng_a: float,
    name_b: str, lat_b: float, lng_b: float,
) -> bool:
    if _meters_between(lat_a, lng_a, lat_b, lng_b) > MATCH_RADIUS_M:
        return False
    return fuzz.token_set_ratio(name_a, name_b) >= NAME_RATIO_THRESHOLD


@dataclass
class DedupResult:
    survivors: list[ClassifiedCandidate]
    dropped_total: int = 0
    within_source_dups: int = 0
    # (winner_source, loser_source) -> count
    drops_by_pair: dict[tuple[str, str], int] = field(default_factory=dict)


def _record_drop(result: DedupResult, winner: str, loser: str) -> None:
    result.dropped_total += 1
    key = (winner, loser)
    result.drops_by_pair[key] = result.drops_by_pair.get(key, 0) + 1
```

- [ ] **Step 6: Run the test — expect pass**

Run: `python -m pytest tests/stages/test_dedup.py -q`
Expected: PASS (5 passed).

- [ ] **Step 7: Commit**

```bash
git add importer/pyproject.toml importer/importer/stages/dedup.py importer/tests/stages/test_dedup.py
git commit -m "feat(importer): add rapidfuzz + dedup distance/match primitives"
```

---

## Task 2: Real cross-source dedup resolution

**Files:**
- Modify: `importer/importer/stages/dedup.py` (add `dedup()`)
- Test: `importer/tests/stages/test_dedup.py` (append)

- [ ] **Step 1: Write failing tests for `dedup()`**

Append to `importer/tests/stages/test_dedup.py`:

```python
from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.dedup import dedup
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow
from datetime import date


def _cell(category: RestrictionTag) -> StateLawCell:
    return StateLawCell(
        state="TX", category=category, default_status="NO_GUN",
        confidence="high", citation="x", last_verified_date=date(2026, 5, 31),
    )


def _cc(source: str, eid: str, name: str, lat: float, lng: float,
        category: RestrictionTag = RestrictionTag.FEDERAL_PROPERTY) -> ClassifiedCandidate:
    return ClassifiedCandidate(
        candidate=Candidate(
            source=source, source_external_id=eid, source_dataset_version="v",
            name=name, latitude=lat, longitude=lng,
            coord_quality=CoordQuality.PRECISE, category=category, state="TX",
        ),
        cell=_cell(category),
    )


def test_dedup_keeps_higher_priority_source():
    gsa = _cc("gsa", "g1", "US Courthouse Austin", 30.2672, -97.7431)
    courts = _cc("hifld_courts", "c1", "US Court House Austin", 30.2673, -97.7432,
                 category=RestrictionTag.STATE_LOCAL_GOVT)
    result = dedup([courts, gsa], existing_user_pins=[])
    assert [cc.candidate.source for cc in result.survivors] == ["gsa"]
    assert result.drops_by_pair[("gsa", "hifld_courts")] == 1


def test_dedup_keeps_both_when_far_apart():
    a = _cc("gsa", "g1", "Federal Building", 30.2672, -97.7431)
    b = _cc("hifld_military", "m1", "Fort Hood", 31.13, -97.78)
    result = dedup([a, b], existing_user_pins=[])
    assert len(result.survivors) == 2
    assert result.dropped_total == 0


def test_dedup_drops_candidate_matching_user_pin():
    cand = _cc("gsa", "g1", "Travis County Courthouse", 30.2672, -97.7431)
    user = ExistingPinRow(
        id="u1", source="user", source_external_id=None,
        name="Travis County Courthouse", latitude=30.2673, longitude=-97.7432,
        status=2, restriction_tag="STATE_LOCAL_GOVT", user_modified=True,
        source_dataset_version=None,
    )
    result = dedup([cand], existing_user_pins=[user])
    assert result.survivors == []
    assert result.drops_by_pair[("user", "gsa")] == 1


def test_dedup_drops_within_source_duplicate_external_id():
    a = _cc("gsa", "dup", "Federal Building", 30.2672, -97.7431)
    b = _cc("gsa", "dup", "Federal Building", 40.0, -100.0)
    result = dedup([a, b], existing_user_pins=[])
    assert len(result.survivors) == 1
    assert result.within_source_dups == 1


def test_dedup_equal_tier_tiebreak_is_deterministic():
    # courts vs military share tier 5; keep the lexicographically-smaller key.
    courts = _cc("hifld_courts", "c1", "Joint Base Courthouse", 30.2672, -97.7431,
                 category=RestrictionTag.STATE_LOCAL_GOVT)
    military = _cc("hifld_military", "m1", "Joint Base Court House", 30.2673, -97.7432)
    survivors_a = {cc.candidate.source for cc in dedup([courts, military], existing_user_pins=[]).survivors}
    survivors_b = {cc.candidate.source for cc in dedup([military, courts], existing_user_pins=[]).survivors}
    assert survivors_a == survivors_b
    assert len(survivors_a) == 1
```

- [ ] **Step 2: Run — expect failure**

Run: `python -m pytest tests/stages/test_dedup.py -q`
Expected: FAIL — `ImportError: cannot import name 'dedup'`.

- [ ] **Step 3: Implement `dedup()`**

Append to `importer/importer/stages/dedup.py`:

```python
def dedup(
    classified: list[ClassifiedCandidate],
    *,
    existing_user_pins: list[ExistingPinRow],
) -> DedupResult:
    result = DedupResult(survivors=[])

    # 1. Within-source dedup on (source, external_id). First occurrence wins.
    seen_keys: set[tuple[str, str]] = set()
    unique: list[ClassifiedCandidate] = []
    for cc in classified:
        key = (cc.candidate.source, cc.candidate.source_external_id)
        if key in seen_keys:
            result.within_source_dups += 1
            continue
        seen_keys.add(key)
        unique.append(cc)

    if not unique:
        return result

    # 2. Suppress candidates that collide with an existing user pin.
    survivors_stage2: list[ClassifiedCandidate] = []
    if existing_user_pins:
        user_geoms = [Point(p.longitude, p.latitude) for p in existing_user_pins]
        user_tree = STRtree(user_geoms)
        radius_deg = (MATCH_RADIUS_M / _DEG_LAT_M) * 1.5  # generous bbox pre-filter
        for cc in unique:
            cand = cc.candidate
            cg = Point(cand.longitude, cand.latitude)
            hit = False
            for j in user_tree.query(cg.buffer(radius_deg)):
                up = existing_user_pins[int(j)]
                if _matches(cand.name, cand.latitude, cand.longitude,
                            up.name, up.latitude, up.longitude):
                    _record_drop(result, "user", cand.source)
                    hit = True
                    break
            if not hit:
                survivors_stage2.append(cc)
    else:
        survivors_stage2 = unique

    if not survivors_stage2:
        return result

    # 3. Cross-candidate resolution via one STRtree over all remaining points.
    geoms = [Point(cc.candidate.longitude, cc.candidate.latitude) for cc in survivors_stage2]
    tree = STRtree(geoms)
    radius_deg = (MATCH_RADIUS_M / _DEG_LAT_M) * 1.5
    dropped = [False] * len(survivors_stage2)

    for i, cc in enumerate(survivors_stage2):
        if dropped[i]:
            continue
        a = cc.candidate
        for j_raw in tree.query(geoms[i].buffer(radius_deg)):
            j = int(j_raw)
            if j == i or dropped[j]:
                continue
            b = survivors_stage2[j].candidate
            if not _matches(a.name, a.latitude, a.longitude, b.name, b.latitude, b.longitude):
                continue
            pi, pj = _priority(a.source), _priority(b.source)
            if pi < pj:        # a wins
                dropped[j] = True
                _record_drop(result, a.source, b.source)
            elif pj < pi:      # b wins
                dropped[i] = True
                _record_drop(result, b.source, a.source)
                break
            else:              # same tier — deterministic tiebreak on (source, eid)
                key_a = (a.source, a.source_external_id)
                key_b = (b.source, b.source_external_id)
                if key_a <= key_b:
                    dropped[j] = True
                    _record_drop(result, a.source, b.source)
                else:
                    dropped[i] = True
                    _record_drop(result, b.source, a.source)
                    break

    result.survivors = [cc for k, cc in enumerate(survivors_stage2) if not dropped[k]]
    return result
```

- [ ] **Step 4: Run — expect pass**

Run: `python -m pytest tests/stages/test_dedup.py -q`
Expected: PASS (10 passed).

- [ ] **Step 5: Commit**

```bash
git add importer/importer/stages/dedup.py importer/tests/stages/test_dedup.py
git commit -m "feat(importer): implement cross-source dedup with priority + user-pin protection"
```

---

## Task 3: US Census batch geocoder

**Files:**
- Create: `importer/importer/geo/census_geocode.py`
- Create: `importer/tests/geo/__init__.py`, `importer/tests/geo/test_census_geocode.py`
- Create: `importer/tests/fixtures/census_batch_response.txt`

The Census batch API (`/geocoder/locations/addressbatch`) accepts a CSV upload
(`id,street,city,state,zip`) and returns CSV rows of the form:
`id,"input address","Match"/"No_Match",match_type,"matched address","lng,lat",tigerlineid,side`.

- [ ] **Step 1: Create the fixture response**

Create `importer/tests/fixtures/census_batch_response.txt` (note: coords are `lng,lat`):

```
"1","100 Main St, Austin, TX, 78701","Match","Exact","100 MAIN ST, AUSTIN, TX, 78701","-97.7431,30.2672","12345","L"
"2","999 Nowhere Rd, Austin, TX, 78701","No_Match"
```

- [ ] **Step 2: Write the failing test**

Create `importer/tests/geo/__init__.py` (empty) and `importer/tests/geo/test_census_geocode.py`:

```python
from pathlib import Path

import httpx
import pytest

from importer.geo.census_geocode import AddressRecord, CensusGeocoder

FIXTURE = Path(__file__).parent.parent / "fixtures" / "census_batch_response.txt"


def test_geocode_parses_match_and_skips_no_match(httpx_mock, tmp_path):
    httpx_mock.add_response(text=FIXTURE.read_text(encoding="utf-8"))
    geocoder = CensusGeocoder(cache_path=tmp_path / "geocoded.json")
    records = [
        AddressRecord(id="1", street="100 Main St", city="Austin", state="TX", zip="78701"),
        AddressRecord(id="2", street="999 Nowhere Rd", city="Austin", state="TX", zip="78701"),
    ]
    out = geocoder.geocode(records)
    assert out["1"] == pytest.approx((30.2672, -97.7431))
    assert "2" not in out


def test_geocode_uses_cache_on_second_call(httpx_mock, tmp_path):
    httpx_mock.add_response(text=FIXTURE.read_text(encoding="utf-8"))
    cache = tmp_path / "geocoded.json"
    rec = [AddressRecord(id="1", street="100 Main St", city="Austin", state="TX", zip="78701")]
    first = CensusGeocoder(cache_path=cache)
    first.geocode(rec)
    # Second geocoder, no new HTTP response registered — must hit cache or it errors.
    second = CensusGeocoder(cache_path=cache)
    out = second.geocode(rec)
    assert out["1"] == pytest.approx((30.2672, -97.7431))
```

- [ ] **Step 3: Run — expect failure**

Run: `python -m pytest tests/geo/test_census_geocode.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.geo.census_geocode'`.

- [ ] **Step 4: Implement the geocoder**

Create `importer/importer/geo/census_geocode.py`:

```python
"""US Census batch geocoder (public domain, no API key, US-only).

Endpoint: POST /geocoder/locations/addressbatch with an uploaded CSV of
id,street,city,state,zip. Returns CSV rows; matched rows carry "lng,lat".
Successful matches are cached to disk keyed by a hash of the normalized address
so re-runs skip already-geocoded rows.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
from dataclasses import dataclass
from pathlib import Path

import httpx

CENSUS_BATCH_URL = "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
_BENCHMARK = "Public_AR_Current"


@dataclass(frozen=True)
class AddressRecord:
    id: str
    street: str
    city: str
    state: str
    zip: str

    def cache_key(self) -> str:
        norm = f"{self.street}|{self.city}|{self.state}|{self.zip}".upper().strip()
        return hashlib.sha1(norm.encode("utf-8")).hexdigest()


class CensusGeocoder:
    def __init__(self, *, cache_path: Path, timeout: float = 120.0) -> None:
        self._cache_path = cache_path
        self._timeout = timeout
        self._cache: dict[str, list[float]] = {}
        if cache_path.exists():
            self._cache = json.loads(cache_path.read_text(encoding="utf-8"))

    def geocode(self, records: list[AddressRecord]) -> dict[str, tuple[float, float]]:
        """Return {record.id: (lat, lng)} for matched records only."""
        out: dict[str, tuple[float, float]] = {}
        uncached: list[AddressRecord] = []
        for rec in records:
            cached = self._cache.get(rec.cache_key())
            if cached is not None:
                out[rec.id] = (cached[0], cached[1])
            else:
                uncached.append(rec)

        if uncached:
            fetched = self._fetch_batch(uncached)
            by_key = {rec.id: rec.cache_key() for rec in uncached}
            for rid, (lat, lng) in fetched.items():
                out[rid] = (lat, lng)
                self._cache[by_key[rid]] = [lat, lng]
            self._flush_cache()
        return out

    def _fetch_batch(self, records: list[AddressRecord]) -> dict[str, tuple[float, float]]:
        buf = io.StringIO()
        writer = csv.writer(buf)
        for rec in records:
            writer.writerow([rec.id, rec.street, rec.city, rec.state, rec.zip])
        files = {"addressFile": ("addresses.csv", buf.getvalue(), "text/csv")}
        data = {"benchmark": _BENCHMARK}
        with httpx.Client(timeout=self._timeout) as client:
            r = client.post(CENSUS_BATCH_URL, data=data, files=files)
            r.raise_for_status()
            return self._parse(r.text)

    @staticmethod
    def _parse(text: str) -> dict[str, tuple[float, float]]:
        out: dict[str, tuple[float, float]] = {}
        for row in csv.reader(io.StringIO(text)):
            if len(row) < 6 or row[2] != "Match":
                continue
            rid = row[0]
            lng_str, lat_str = row[5].split(",")
            out[rid] = (float(lat_str), float(lng_str))
        return out

    def _flush_cache(self) -> None:
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        self._cache_path.write_text(json.dumps(self._cache), encoding="utf-8")
```

- [ ] **Step 5: Run — expect pass**

Run: `python -m pytest tests/geo/test_census_geocode.py -q`
Expected: PASS (2 passed).

- [ ] **Step 6: Commit**

```bash
git add importer/importer/geo/census_geocode.py importer/tests/geo/ importer/tests/fixtures/census_batch_response.txt
git commit -m "feat(importer): add US Census batch geocoder with disk cache"
```

---

## Task 4: HIFLD military installations source

**Files:**
- Create: `importer/importer/sources/hifld_military.py`
- Create: `importer/tests/fixtures/hifld_military_sample.geojson`
- Create: `importer/tests/sources/test_hifld_military.py`

> **Implementation pre-flight (do once, document in the module docstring like `hifld_courts.py` did):** confirm the live HIFLD Military Installations ArcGIS Hub item id + layer and the GUID field name, and refresh the fixture in the same step. The code below assumes Polygon/MultiPolygon features with `GLOBALID`/`OBJECTID` + `siteName`/`NAME`.

- [ ] **Step 1: Create the polygon fixture**

Create `importer/tests/fixtures/hifld_military_sample.geojson` — three pilot-state polygons (one MultiPolygon), one out-of-state, one null-geometry:

```json
{
  "type": "FeatureCollection",
  "features": [
    {"type": "Feature", "properties": {"GLOBALID": "MIL-TX-1", "siteName": "Fort Cavazos"},
     "geometry": {"type": "Polygon", "coordinates": [[[-97.79,31.13],[-97.77,31.13],[-97.77,31.15],[-97.79,31.15],[-97.79,31.13]]]}},
    {"type": "Feature", "properties": {"GLOBALID": "MIL-FL-1", "siteName": "NAS Jacksonville"},
     "geometry": {"type": "MultiPolygon", "coordinates": [[[[-81.68,30.22],[-81.66,30.22],[-81.66,30.24],[-81.68,30.24],[-81.68,30.22]]]]}},
    {"type": "Feature", "properties": {"GLOBALID": "MIL-PA-1", "siteName": "Carlisle Barracks"},
     "geometry": {"type": "Polygon", "coordinates": [[[-77.19,40.20],[-77.17,40.20],[-77.17,40.22],[-77.19,40.22],[-77.19,40.20]]]}},
    {"type": "Feature", "properties": {"GLOBALID": "MIL-CA-1", "siteName": "Camp Pendleton"},
     "geometry": {"type": "Polygon", "coordinates": [[[-117.40,33.30],[-117.38,33.30],[-117.38,33.32],[-117.40,33.32],[-117.40,33.30]]]}},
    {"type": "Feature", "properties": {"GLOBALID": "MIL-NULL", "siteName": "No Geometry Base"},
     "geometry": null}
  ]
}
```

- [ ] **Step 2: Write the failing test**

Create `importer/tests/sources/test_hifld_military.py`:

```python
from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.hifld_military import HifldMilitarySource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


@pytest.fixture(scope="module")
def source() -> HifldMilitarySource:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    return HifldMilitarySource(
        cache_path=FIXTURE_DIR / "hifld_military_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-MIL-FIXTURE",
    )


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "hifld_military"


def test_yields_three_pilot_states_from_polygon_centroids(source):
    cands = list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert {c.state for c in cands} == {"TX", "FL", "PA"}
    assert all(c.category is RestrictionTag.FEDERAL_PROPERTY for c in cands)
    assert all(c.coord_quality is CoordQuality.BUILDING_POLYGON for c in cands)


def test_centroid_is_inside_the_polygon_bbox(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX"})}
    tx = cands["MIL-TX-1"]
    assert -97.79 < tx.longitude < -97.77
    assert 31.13 < tx.latitude < 31.15


def test_skips_null_geometry_and_out_of_state(source):
    list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert source.last_skip_counts["missing_geometry"] >= 1
    assert source.last_skip_counts["state_pip_miss"] >= 1
```

- [ ] **Step 3: Run — expect failure**

Run: `python -m pytest tests/sources/test_hifld_military.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.sources.hifld_military'`.

- [ ] **Step 4: Implement the source**

Create `importer/importer/sources/hifld_military.py`:

```python
"""HIFLD Military Installations -> Candidate stream.

Source: Military Installations boundary dataset on the HIFLD/GeoPlatform ArcGIS
Hub. Format: GeoJSON, Polygon/MultiPolygon features (installation boundaries).
License: Public domain (DHS HIFLD Open).

Unlike hifld_courts (Point features), installations are areas: we emit the
shapely centroid with coord_quality=BUILDING_POLYGON. Category is
FEDERAL_PROPERTY (18 USC 930 via the US FEDERAL_PROPERTY state-law cell, whose
source_filter includes hifld_military).

Pre-flight: confirm the live Hub item/layer + GUID field and refresh the fixture
in the same PR. The signed blob URL expires (~1h) and must never be hard-pinned —
only the stable hub URL belongs in config.yaml.
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx
from shapely.geometry import shape

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


class HifldMilitarySource(Source):
    SOURCE_NAME: ClassVar[str] = "hifld_military"

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
            raise RuntimeError("hifld_military url not configured; set sources.hifld_military.url in config.yaml")
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        raw = json.loads(self._cache_path.read_text(encoding="utf-8"))
        for feature in raw.get("features", []):
            geom = feature.get("geometry")
            props = feature.get("properties") or {}
            if not geom or geom.get("type") not in ("Polygon", "MultiPolygon"):
                self.last_skip_counts["missing_geometry"] += 1
                continue
            centroid = shape(geom).centroid
            lat, lng = float(centroid.y), float(centroid.x)

            state = self._locator.state_for(lat, lng)
            if state is None:
                self.last_skip_counts["state_pip_miss"] += 1
                continue
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue

            external_id = self._external_id(props)
            if external_id is None:
                self.last_skip_counts["missing_external_id"] += 1
                continue
            name = (props.get("siteName") or props.get("NAME") or props.get("name") or "").strip()
            if not name:
                self.last_skip_counts["missing_name"] += 1
                continue

            yield Candidate(
                source=self.SOURCE_NAME,
                source_external_id=external_id,
                source_dataset_version=self._version,
                name=name,
                latitude=lat,
                longitude=lng,
                coord_quality=CoordQuality.BUILDING_POLYGON,
                category=RestrictionTag.FEDERAL_PROPERTY,
                state=state,
                extra={"component": props.get("component")},
            )

    @staticmethod
    def _external_id(props: dict) -> str | None:
        for key in ("GLOBALID", "OBJECTID", "FID"):
            v = props.get(key)
            if v not in (None, ""):
                return str(v)
        return None
```

- [ ] **Step 5: Run — expect pass**

Run: `python -m pytest tests/sources/test_hifld_military.py -q`
Expected: PASS (4 passed).

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources/hifld_military.py importer/tests/sources/test_hifld_military.py importer/tests/fixtures/hifld_military_sample.geojson
git commit -m "feat(importer): add HIFLD military installations source (polygon centroids)"
```

---

## Task 5: GSA FRPP source (geocoded)

**Files:**
- Create: `importer/importer/sources/gsa.py`
- Create: `importer/tests/fixtures/gsa_frpp_sample.csv`
- Create: `importer/tests/sources/test_gsa.py`

> **Implementation pre-flight:** confirm the live GSA FRPP public CSV download URL + exact column headers; refresh the fixture + the `_COL_*` constants below in the same PR. The code assumes the headered columns named in `_COL_*`. The federal-facility predicate (exclude `Land`) and owned-or-leased inclusion are documented, tunable choices — the dry-run report's counts validate them.

- [ ] **Step 1: Create the FRPP fixture**

Create `importer/tests/fixtures/gsa_frpp_sample.csv` — a TX row with coords, a TX row needing geocoding, an out-of-state row, a `Land` row (excluded), and a no-address row:

```csv
Real Property Unique Identifier,Real Property Type,Real Property Use,Street Address,City,State,Zip Code,Latitude,Longitude,Real Property Asset Name
RPUID-TX-1,Building,Office,100 Main St,Austin,TX,78701,30.2672,-97.7431,Federal Office Building
RPUID-TX-2,Building,Courthouse,200 Geocode Ave,Houston,TX,77002,,,US Courthouse Houston
RPUID-CA-1,Building,Office,1 Bay St,San Francisco,CA,94105,37.79,-122.40,SF Federal Building
RPUID-TX-3,Land,Vacant,Rural Rd,Marfa,TX,79843,,,Vacant Federal Land
RPUID-TX-4,Building,Office,,Dallas,TX,75201,,,No Address Building
```

- [ ] **Step 2: Write the failing test**

Create `importer/tests/sources/test_gsa.py`:

```python
from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.sources.gsa import GsaSource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


class _FakeGeocoder:
    """Returns a coord for the one row that lacks lat/lng; misses nothing else."""
    def __init__(self):
        self.calls = []

    def geocode(self, records):
        self.calls.append([r.id for r in records])
        return {"RPUID-TX-2": (29.7604, -95.3698)}


@pytest.fixture
def source(tmp_path):
    return GsaSource(
        cache_path=FIXTURE_DIR / "gsa_frpp_sample.csv",
        dataset_version="FRPP-FIXTURE",
        geocoder=_FakeGeocoder(),
    )


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "gsa"


def test_uses_existing_coords_and_geocodes_missing(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX"})}
    assert cands["RPUID-TX-1"].coord_quality is CoordQuality.PRECISE
    assert cands["RPUID-TX-2"].coord_quality is CoordQuality.ADDRESS_CENTROID
    assert cands["RPUID-TX-2"].latitude == pytest.approx(29.7604)
    assert all(c.category is RestrictionTag.FEDERAL_PROPERTY for c in cands.values())


def test_filters_state_before_geocoding(source):
    list(source.iter_candidates(state_filter={"TX"}))
    # The fake geocoder must only ever be asked about the TX row that lacked coords.
    assert source._geocoder.calls == [["RPUID-TX-2"]]


def test_excludes_land_and_no_address(source):
    cands = {c.source_external_id for c in source.iter_candidates(state_filter={"TX"})}
    assert "RPUID-TX-3" not in cands  # Land
    assert "RPUID-TX-4" not in cands  # no street address
    assert source.last_skip_counts["not_federal_facility"] >= 1
    assert source.last_skip_counts["missing_address"] >= 1
```

- [ ] **Step 3: Run — expect failure**

Run: `python -m pytest tests/sources/test_gsa.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.sources.gsa'`.

- [ ] **Step 4: Implement the source**

Create `importer/importer/sources/gsa.py`:

```python
"""GSA FRPP (Federal Real Property Profile) -> Candidate stream.

Source: GSA FRPP public dataset (CSV). Federal owned/leased real property.
License: Public domain (US Gov). Category: FEDERAL_PROPERTY (18 USC 930 via the
US FEDERAL_PROPERTY state-law cell, source_filter includes gsa).

Coordinates: rows may carry Latitude/Longitude; when present we trust them
(coord_quality=PRECISE), otherwise we geocode the street address via the US
Census batch geocoder (coord_quality=ADDRESS_CENTROID). State filtering happens
on the dataset's own State column BEFORE geocoding so only pilot rows hit the API.

Pre-flight: confirm the live CSV URL + column headers; refresh _COL_* + fixture
in the same PR.
"""

from __future__ import annotations

import csv
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar, Protocol

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.census_geocode import AddressRecord
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source

_COL_ID = "Real Property Unique Identifier"
_COL_TYPE = "Real Property Type"
_COL_STREET = "Street Address"
_COL_CITY = "City"
_COL_STATE = "State"
_COL_ZIP = "Zip Code"
_COL_LAT = "Latitude"
_COL_LNG = "Longitude"
_COL_NAME = "Real Property Asset Name"

# 18 USC 930 attaches to federal *facilities* (buildings/structures), not land.
_EXCLUDED_TYPES = {"land"}


class _Geocoder(Protocol):
    def geocode(self, records: list[AddressRecord]) -> dict[str, tuple[float, float]]: ...


class GsaSource(Source):
    SOURCE_NAME: ClassVar[str] = "gsa"

    def __init__(
        self,
        *,
        cache_path: Path,
        dataset_version: str,
        geocoder: _Geocoder,
        url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._version = dataset_version
        self._geocoder = geocoder
        self._url = url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        if self._cache_path.exists() and not refetch:
            return
        if not self._url:
            raise RuntimeError("gsa url not configured; set sources.gsa.url in config.yaml")
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        rows = list(csv.DictReader(self._cache_path.read_text(encoding="utf-8").splitlines()))

        kept: list[dict] = []
        to_geocode: list[AddressRecord] = []
        for row in rows:
            state = (row.get(_COL_STATE) or "").strip().upper()
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue
            if (row.get(_COL_TYPE) or "").strip().lower() in _EXCLUDED_TYPES:
                self.last_skip_counts["not_federal_facility"] += 1
                continue
            eid = (row.get(_COL_ID) or "").strip()
            if not eid:
                self.last_skip_counts["missing_external_id"] += 1
                continue
            name = (row.get(_COL_NAME) or "").strip()
            if not name:
                self.last_skip_counts["missing_name"] += 1
                continue
            street = (row.get(_COL_STREET) or "").strip()
            lat, lng = self._existing_coords(row)
            if lat is None and not street:
                self.last_skip_counts["missing_address"] += 1
                continue
            row["_state"] = state
            row["_eid"] = eid
            row["_name"] = name
            row["_lat"] = lat
            row["_lng"] = lng
            kept.append(row)
            if lat is None:
                to_geocode.append(AddressRecord(
                    id=eid, street=street,
                    city=(row.get(_COL_CITY) or "").strip(),
                    state=state, zip=(row.get(_COL_ZIP) or "").strip(),
                ))

        geocoded = self._geocoder.geocode(to_geocode) if to_geocode else {}

        for row in kept:
            lat, lng = row["_lat"], row["_lng"]
            quality = CoordQuality.PRECISE
            if lat is None:
                hit = geocoded.get(row["_eid"])
                if hit is None:
                    self.last_skip_counts["geocode_miss"] += 1
                    continue
                lat, lng = hit
                quality = CoordQuality.ADDRESS_CENTROID
            yield Candidate(
                source=self.SOURCE_NAME,
                source_external_id=row["_eid"],
                source_dataset_version=self._version,
                name=row["_name"],
                latitude=lat,
                longitude=lng,
                coord_quality=quality,
                category=RestrictionTag.FEDERAL_PROPERTY,
                state=row["_state"],
                extra={},
            )

    @staticmethod
    def _existing_coords(row: dict) -> tuple[float | None, float | None]:
        lat_s, lng_s = (row.get(_COL_LAT) or "").strip(), (row.get(_COL_LNG) or "").strip()
        if not lat_s or not lng_s:
            return None, None
        try:
            return float(lat_s), float(lng_s)
        except ValueError:
            return None, None
```

- [ ] **Step 5: Run — expect pass**

Run: `python -m pytest tests/sources/test_gsa.py -q`
Expected: PASS (4 passed).

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources/gsa.py importer/tests/sources/test_gsa.py importer/tests/fixtures/gsa_frpp_sample.csv
git commit -m "feat(importer): add GSA FRPP source with Census geocoding fallback"
```

---

## Task 6: Multi-source pipeline + report restructure

This is the coupled refactor: `PipelineResult` becomes per-source, `run_pipeline`
takes a list and runs one dedup pass, the renderers and their tests update
together so the suite stays green at the task boundary.

**Files:**
- Modify: `importer/importer/reports/__init__.py`, `reports/markdown.py`, `reports/json_report.py`
- Modify: `importer/importer/supabase_client.py` (add `select_user_pins`)
- Modify: `importer/importer/pipeline.py`
- Modify: `importer/tests/reports/test_markdown.py`, `test_json_report.py`, `importer/tests/test_pipeline.py`, `importer/tests/test_supabase_client.py`

- [ ] **Step 1: Restructure `PipelineResult`**

Overwrite `importer/importer/reports/__init__.py`:

```python
"""Report generation for dry-run and apply modes."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from importer.stages.diff import DiffResult


@dataclass
class SourceResult:
    """Per-source counts. `classified` is pre-dedup; diff buckets are post-dedup."""

    source: str
    candidates_fetched: int
    candidates_after_state_filter: int
    classified: int
    dropped_no_cell: int
    missing_cells: list[tuple[str, str]]
    name_truncations: int
    diff: DiffResult
    geocode_matched: int | None = None
    geocode_missed: int | None = None


@dataclass
class DedupReport:
    dropped_total: int = 0
    within_source_dups: int = 0
    drops_by_pair: dict[tuple[str, str], int] = field(default_factory=dict)


@dataclass
class PipelineResult:
    mode: str  # 'dry-run' or 'apply'
    started_at: datetime
    completed_at: datetime | None
    states: list[str]
    sources: list[SourceResult]
    dedup: DedupReport
    errors: list[str] = field(default_factory=list)
```

- [ ] **Step 2: Add `select_user_pins` to the Supabase client**

In `importer/importer/supabase_client.py`, add this method after `select_pins_by_keys`:

```python
    def select_user_pins(self) -> list[ExistingPinRow]:
        """All user-created pins — dedup must never clobber these."""
        params = {"select": self.SELECT_COLUMNS, "source": "eq.user"}
        r = self._client.get(f"{self._base}/pins", headers=self._headers, params=params)
        r.raise_for_status()
        return [ExistingPinRow.model_validate(row) for row in r.json()]
```

- [ ] **Step 3: Add the failing test for `select_user_pins`**

In `importer/tests/test_supabase_client.py`, add a test mirroring the existing
`select_pins_by_keys` test pattern (check the file for its `httpx_mock` style first):

```python
def test_select_user_pins_filters_source_user(httpx_mock):
    httpx_mock.add_response(json=[{
        "id": "u1", "source": "user", "source_external_id": None,
        "name": "My Pin", "latitude": 30.0, "longitude": -97.0,
        "status": 2, "restriction_tag": "FEDERAL_PROPERTY",
        "user_modified": True, "source_dataset_version": None,
    }])
    with SupabaseClient(url="https://x.supabase.co", service_role_key="k", system_user_id="sys") as c:
        rows = c.select_user_pins()
    assert rows[0].source == "user"
    req = httpx_mock.get_requests()[0]
    assert "source=eq.user" in str(req.url)
```

- [ ] **Step 4: Rewrite `run_pipeline` for multiple sources**

Overwrite `importer/importer/pipeline.py`:

```python
"""End-to-end orchestration of all pipeline stages, across multiple sources."""

from __future__ import annotations

from datetime import datetime, timezone

from importer.reports import DedupReport, PipelineResult, SourceResult
from importer.sources.base import Source
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
from importer.stages.dedup import dedup
from importer.stages.diff import DiffStats, diff_candidates
from importer.stages.normalize import NormalizeStats, normalize
from importer.stages.refine_coords import refine_coords
from importer.state_laws import StateLawTable
from importer.supabase_client import SupabaseClient


def run_pipeline(
    *,
    sources: list[Source],
    state_laws: StateLawTable,
    client: SupabaseClient,
    states: list[str],
    mode: str,
    system_user_id: str,
    refetch: bool = False,
) -> PipelineResult:
    started_at = datetime.now(timezone.utc)
    state_set = set(states) if states else None

    # Phase A: per-source fetch → normalize → refine → classify. Accumulate all
    # ClassifiedCandidates plus per-source pre-dedup bookkeeping.
    per_source: list[dict] = []
    all_classified = []
    for source in sources:
        source.fetch(refetch=refetch)
        raw = list(source.iter_candidates(state_filter=state_set))
        norm_stats = NormalizeStats()
        normalized = list(normalize(raw, stats=norm_stats))
        refined = list(refine_coords(normalized))
        asl_stats = ApplyStateLawStats()
        classified = list(apply_state_law(refined, table=state_laws, stats=asl_stats))
        all_classified.extend(classified)
        skip = getattr(source, "last_skip_counts", {})
        per_source.append({
            "source": source.SOURCE_NAME,
            "fetched": len(raw),
            "classified_objs": classified,
            "asl": asl_stats,
            "norm": norm_stats,
            "geocode_miss": int(skip.get("geocode_miss", 0)) if source.SOURCE_NAME == "gsa" else None,
        })

    # Phase B: one cross-source dedup pass against all user pins.
    existing_user_pins = client.select_user_pins()
    dedup_out = dedup(all_classified, existing_user_pins=existing_user_pins)
    survivors_by_source: dict[str, list] = {}
    for cc in dedup_out.survivors:
        survivors_by_source.setdefault(cc.candidate.source, []).append(cc)

    # Phase C: per-source diff + apply on the survivors.
    source_results: list[SourceResult] = []
    for ps in per_source:
        name = ps["source"]
        survivors = survivors_by_source.get(name, [])
        diff_stats = DiffStats()
        eids = [cc.candidate.source_external_id for cc in survivors]
        existing = client.select_pins_by_keys(name, eids)
        diff_result = diff_candidates(survivors, existing=existing, stats=diff_stats)
        if mode == "apply":
            apply_to_supabase(diff_result, client=client, system_user_id=system_user_id, source=name)
        asl: ApplyStateLawStats = ps["asl"]
        geocode_matched = None
        if name == "gsa":
            geocode_matched = sum(
                1 for cc in survivors
                if cc.candidate.coord_quality.value == "address_centroid"
            )
        source_results.append(SourceResult(
            source=name,
            candidates_fetched=ps["fetched"],
            candidates_after_state_filter=ps["fetched"],
            classified=asl.classified,
            dropped_no_cell=asl.dropped_no_cell,
            missing_cells=sorted(asl.missing_cells),
            name_truncations=ps["norm"].truncations,
            diff=diff_result,
            geocode_matched=geocode_matched,
            geocode_missed=ps["geocode_miss"],
        ))

    return PipelineResult(
        mode=mode,
        started_at=started_at,
        completed_at=datetime.now(timezone.utc),
        states=sorted(state_set) if state_set else [],
        sources=source_results,
        dedup=DedupReport(
            dropped_total=dedup_out.dropped_total,
            within_source_dups=dedup_out.within_source_dups,
            drops_by_pair=dedup_out.drops_by_pair,
        ),
    )
```

- [ ] **Step 5: Rewrite the markdown renderer**

Overwrite `importer/importer/reports/markdown.py`:

```python
"""Render a PipelineResult as a human-readable Markdown report."""

from __future__ import annotations

from importer.reports import PipelineResult, SourceResult


def _source_block(s: SourceResult) -> list[str]:
    lines = [f"### Source: `{s.source}`", ""]
    lines.append(f"- Candidates fetched: **{s.candidates_fetched}**")
    lines.append(f"- Classified by state-law table: **{s.classified}**")
    lines.append(f"- Dropped (no state-law cell): **{s.dropped_no_cell}**")
    lines.append(f"- Name truncations: **{s.name_truncations}**")
    if s.geocode_matched is not None or s.geocode_missed is not None:
        lines.append(f"- Geocoded (address centroid): **{s.geocode_matched or 0}**")
        lines.append(f"- Geocode misses (dropped): **{s.geocode_missed or 0}**")
    lines.append(f"- INSERT: **{len(s.diff.inserts)}**")
    lines.append(f"- UPDATE: **{len(s.diff.updates)}**")
    lines.append(f"- SKIP (user-modified): **{len(s.diff.skips)}**")
    lines.append(f"- Orphan: **{len(s.diff.orphans)}**")
    lines.append("")
    if s.missing_cells:
        lines.append("**Needs research** (no `states.yaml` cell, dropped):")
        for state, category in sorted(s.missing_cells):
            lines.append(f"- ({state}, {category})")
        lines.append("")
    if s.diff.orphans:
        lines.append("**Orphans** (in DB, not in upstream; NOT auto-deleted):")
        for row in s.diff.orphans[:50]:
            lines.append(f"- `{row.source_external_id}` — {row.name}")
        if len(s.diff.orphans) > 50:
            lines.append(f"- … and {len(s.diff.orphans) - 50} more.")
        lines.append("")
    return lines


def render_markdown(r: PipelineResult) -> str:
    title = "dry-run report" if r.mode == "dry-run" else "apply report"
    lines = [f"# Importer {title}", ""]
    lines.append(f"- Sources: **{', '.join(s.source for s in r.sources)}**")
    lines.append(f"- States: **{', '.join(r.states)}**")
    lines.append(f"- Started: {r.started_at.isoformat()}")
    if r.completed_at is not None:
        lines.append(f"- Completed: {r.completed_at.isoformat()}")
    lines.append("")

    lines.append("## Cross-source dedup")
    lines.append("")
    lines.append(f"- Dropped (cross-source): **{r.dedup.dropped_total}**")
    lines.append(f"- Within-source duplicate ids dropped: **{r.dedup.within_source_dups}**")
    for (winner, loser), n in sorted(r.dedup.drops_by_pair.items()):
        lines.append(f"- `{loser}` dropped in favor of `{winner}`: **{n}**")
    lines.append("")

    for s in r.sources:
        lines.append("## " + s.source)
        lines.append("")
        lines.extend(_source_block(s))

    if r.errors:
        lines.append("## Errors")
        lines.append("")
        for err in r.errors:
            lines.append(f"- {err}")
        lines.append("")
    return "\n".join(lines)
```

- [ ] **Step 6: Rewrite the JSON renderer**

Overwrite `importer/importer/reports/json_report.py`:

```python
"""Render a PipelineResult as a JSON sidecar."""

from __future__ import annotations

import json

from importer.reports import PipelineResult


def render_json(r: PipelineResult) -> str:
    payload = {
        "mode": r.mode,
        "states": r.states,
        "started_at": r.started_at.isoformat(),
        "completed_at": r.completed_at.isoformat() if r.completed_at else None,
        "dedup": {
            "dropped_total": r.dedup.dropped_total,
            "within_source_dups": r.dedup.within_source_dups,
            "drops_by_pair": [
                {"winner": w, "loser": l, "count": n}
                for (w, l), n in sorted(r.dedup.drops_by_pair.items())
            ],
        },
        "sources": [
            {
                "source": s.source,
                "counts": {
                    "candidates_fetched": s.candidates_fetched,
                    "classified": s.classified,
                    "dropped_no_cell": s.dropped_no_cell,
                    "name_truncations": s.name_truncations,
                    "geocode_matched": s.geocode_matched,
                    "geocode_missed": s.geocode_missed,
                    "inserts": len(s.diff.inserts),
                    "updates": len(s.diff.updates),
                    "skips": len(s.diff.skips),
                    "orphans": len(s.diff.orphans),
                },
                "missing_cells": [list(p) for p in s.missing_cells],
                "orphans": [
                    {"source_external_id": row.source_external_id, "name": row.name}
                    for row in s.diff.orphans
                ],
            }
            for s in r.sources
        ],
        "errors": r.errors,
    }
    return json.dumps(payload, indent=2, sort_keys=True)
```

- [ ] **Step 7: Update the report + pipeline tests**

Read `importer/tests/reports/test_markdown.py` and `test_json_report.py` — they
construct a `PipelineResult` with the old flat shape. Rewrite each construction
to the new shape (wrap the single source's fields in a `SourceResult`, add an
empty `DedupReport()`, drop the top-level `source=`). Assert on the new strings,
e.g. markdown contains `"## Cross-source dedup"` and `"### Source:"`; JSON has
`payload["sources"][0]["counts"]`.

Rewrite `importer/tests/test_pipeline.py` to call `run_pipeline(sources=[fake1, fake2], …)`
with two fake `Source`s (small in-memory candidate lists, a fake `SupabaseClient`
whose `select_user_pins()` returns `[]` and `select_pins_by_keys()` returns `[]`),
and assert: combined `result.sources` has both, and a deliberately-overlapping
pair across the two sources shows up in `result.dedup.drops_by_pair`.

- [ ] **Step 8: Run the full suite — expect pass**

Run (from `importer/`): `python -m pytest -q`
Expected: PASS (all green; failures here mean a missed call-site of the old `PipelineResult` shape — fix and re-run).

- [ ] **Step 9: Commit**

```bash
git add importer/importer/reports/ importer/importer/pipeline.py importer/importer/supabase_client.py importer/tests/
git commit -m "refactor(importer): multi-source pipeline with combined dedup + per-source reports"
```

---

## Task 7: CLI source registry + config

**Files:**
- Modify: `importer/importer/cli.py`
- Modify: `importer/config.yaml`
- Modify: `importer/tests/test_cli.py`

- [ ] **Step 1: Add config blocks**

In `importer/config.yaml`, under `sources:`, add (URLs pinned at implementation pre-flight; leave the placeholders for now and fill before any real fetch):

```yaml
  gsa:
    cache_dir: "data/sources/gsa"
    dataset_version: "FRPP-2026"
    url: "PIN-AT-PREFLIGHT-gsa-frpp-public-csv-url"
  hifld_military:
    cache_dir: "data/sources/hifld_military"
    dataset_version: "HIFLD-MIL-2026-05"
    url: "PIN-AT-PREFLIGHT-hifld-military-arcgis-hub-geojson-url"
```

- [ ] **Step 2: Write/extend the failing CLI test**

In `importer/tests/test_cli.py`, add a test asserting the new sources parse and
the dry-run path builds them (follow the file's existing harness for stubbing the
service-role env var + a fake client; check the file first):

```python
def test_supported_sources_includes_gsa_and_military():
    from importer.cli import SUPPORTED_SOURCES
    assert "gsa" in SUPPORTED_SOURCES
    assert "hifld_military" in SUPPORTED_SOURCES


def test_build_source_factory_constructs_each(monkeypatch, tmp_path):
    from importer.cli import _build_source
    from importer.geo.states import load_state_locator
    from pathlib import Path
    fixtures = Path(__file__).parent / "fixtures"
    locator = load_state_locator(fixtures / "states_sample.geojson")
    config = {
        "sources": {
            "hifld_courts": {"cache_dir": "data/sources/hifld_courts", "dataset_version": "v", "url": "u"},
            "gsa": {"cache_dir": "data/sources/gsa", "dataset_version": "v", "url": "u"},
            "hifld_military": {"cache_dir": "data/sources/hifld_military", "dataset_version": "v", "url": "u"},
        }
    }
    for name in ("hifld_courts", "gsa", "hifld_military"):
        src = _build_source(name, config=config, locator=locator, repo_root=tmp_path)
        assert src.SOURCE_NAME == name
```

- [ ] **Step 3: Run — expect failure**

Run: `python -m pytest tests/test_cli.py -q`
Expected: FAIL — `ImportError: cannot import name '_build_source'` / `gsa` not in `SUPPORTED_SOURCES`.

- [ ] **Step 4: Implement the registry in `cli.py`**

In `importer/importer/cli.py`:

1. Update imports + supported list:

```python
from importer.geo.census_geocode import CensusGeocoder
from importer.sources.gsa import GsaSource
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.sources.hifld_military import HifldMilitarySource
```

```python
SUPPORTED_SOURCES = ("hifld_courts", "gsa", "hifld_military")
```

2. Add a `_build_source` factory (place above `main`):

```python
def _build_source(name, *, config, locator, repo_root):
    cfg = config["sources"][name]
    cache_dir = Path(repo_root) / cfg["cache_dir"]
    version = cfg["dataset_version"]
    url = cfg.get("url", "")
    if name == "hifld_courts":
        return HifldCourthousesSource(
            cache_path=cache_dir / "courthouses.geojson",
            state_locator=locator, dataset_version=version,
            **({"url": url} if url else {}),
        )
    if name == "hifld_military":
        return HifldMilitarySource(
            cache_path=cache_dir / "military.geojson",
            state_locator=locator, dataset_version=version, url=url,
        )
    if name == "gsa":
        return GsaSource(
            cache_path=cache_dir / "frpp.csv",
            dataset_version=version, url=url,
            geocoder=CensusGeocoder(cache_path=cache_dir / "geocoded.json"),
        )
    raise NotImplementedError(name)
```

3. Replace the per-source loop body in `main` so it builds the list and calls `run_pipeline` once:

```python
            sources = [
                _build_source(name, config=config, locator=locator, repo_root=REPO_ROOT)
                for name in args.sources
            ]
            result = run_pipeline(
                sources=sources,
                state_laws=state_laws,
                client=client,
                states=args.states,
                mode=mode,
                system_user_id=system_user_id,
                refetch=args.refetch,
            )

            report_md = render_markdown(result)
            report_json = render_json(result)
            report_path = args.report_out or Path.cwd() / f"report-{run_id}.md"
            json_path = report_path.with_suffix(".json")
            report_path.write_text(report_md, encoding="utf-8")
            json_path.write_text(report_json, encoding="utf-8")
            sys.stdout.write(report_md)

            client.update_import_run(
                run_id=run_id,
                candidates_processed=sum(s.candidates_fetched for s in result.sources),
                inserts=sum(len(s.diff.inserts) for s in result.sources),
                updates=sum(len(s.diff.updates) for s in result.sources),
                skips=sum(len(s.diff.skips) for s in result.sources),
                orphans_marked=sum(len(s.diff.orphans) for s in result.sources),
                errors_json=None,
                report_artifact_url=None,
            )
```

Also update the `--sources` help text to drop "Phase 2" and remove the now-dead
`if source_name != "hifld_courts": raise NotImplementedError` block.

- [ ] **Step 5: Run the full suite — expect pass**

Run (from `importer/`): `python -m pytest -q`
Expected: PASS (all green).

- [ ] **Step 6: Commit**

```bash
git add importer/importer/cli.py importer/config.yaml importer/tests/test_cli.py
git commit -m "feat(importer): CLI source registry for gsa + hifld_military; single combined report"
```

---

## Task 8: Docs, status, and full-suite verification

**Files:**
- Modify: `docs/importer/SOURCES.md`, `CLAUDE.md`

- [ ] **Step 1: Update SOURCES.md**

In `docs/importer/SOURCES.md`: change the GSA FRPP and HIFLD Military rows'
Status to `Phase 4 (built; staging)`, change the GSA Module/HIFLD Military Module
cells to their real paths, and **correct the stale `NCES K-12 … Phase 4` row to
`Phase 5`** (NCES is Wave 2, not the federal floor). Add a sentence under
"License notes" that GSA addresses are geocoded via the US Census batch geocoder
(public domain, no key).

- [ ] **Step 2: Bump CLAUDE.md status**

In `CLAUDE.md`, update the "Current Status" line and the
"What's Implemented" list to note Phase 4 federal-floor sources (GSA FRPP +
HIFLD military) and real cross-source dedup are built; staging apply pending
operator run; ODbL UI + prod apply still deferred.

- [ ] **Step 3: Run the entire importer suite + a format/lint sanity check**

Run (from `importer/`): `python -m pytest -q`
Expected: PASS — full green suite.

Confirm no `flutter` side was touched (this phase is importer-only): `git status`
should show only `importer/**`, `data/**` (none expected), `docs/**`, `CLAUDE.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/importer/SOURCES.md CLAUDE.md
git commit -m "docs: mark Phase 4 federal-floor sources built; staging apply pending"
```

---

## Post-implementation: operator-run staging validation (NOT an agent step)

After the code lands and URLs are pinned in `config.yaml`, the **operator** runs
(with `IMPORTER_SUPABASE_SERVICE_ROLE_KEY` set to the **staging** key):

```bash
# Dry-run first — review the report together before applying.
python -m importer.cli --dry-run --states TX,FL,PA \
  --sources hifld_courts,gsa,hifld_military --project-ref staging

# Apply to STAGING only (never prod from a dev machine, per spec §7).
python -m importer.cli --apply --states TX,FL,PA \
  --sources hifld_courts,gsa,hifld_military \
  --project-ref staging --i-know-this-writes-to-staging
```

Review gates before declaring Phase 4 done:
- GSA geocode-miss rate acceptable (report's "Geocode misses"); if GSA coverage
  is poor, drop GSA from `--sources` and ship courts+military, filing GSA as a
  follow-up (spec §5 risk).
- Cross-source dedup `drops_by_pair` shows GSA winning federal-courthouse
  overlaps; total cross-source dup rate `<1%`.
- A second apply run is all-SKIP (idempotency).

---

## Self-review notes (author check)

- **Spec coverage:** §1 sources → Tasks 4–5; Census geocoder → Task 3; §2 dedup →
  Tasks 1–2; §3 pipeline/CLI/config/reports → Tasks 6–7; §4 tests → every task;
  docs → Task 8; staging-run guard → Post-implementation section. ODbL UI / prod
  apply / migration 009 correctly absent (out of scope).
- **Type consistency:** `dedup()` returns `DedupResult` (stages) which the
  pipeline copies into the report `DedupReport`; `SourceResult.diff` is the
  existing `DiffResult`; `CoordQuality.ADDRESS_CENTROID.value == "address_centroid"`
  is what the GSA geocode-matched count keys on. `_build_source` signature matches
  its Task 7 test.
