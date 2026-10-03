# Importer Identity and Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the importer safe to run nationally: one pin per source record with a stable id, military pins inside their base, records the source dropped leave the map (opt-in and capped), and no courthouse cites 18 USC 930.

**Architecture:** Sources emit new keys (GSA agency-bureau-property, MIRTA SDSID or state+name) plus *legacy identity hints* (old id, old position). The diff stage re-keys an existing pin in place when a legacy hint lands within 50 m of it, so pin UUIDs and user corrections survive. Orphans are a source's system pins inside the run's states that no record claimed. They are planned per source (mark, delete, or keep if user-corrected) and checked against a delete cap for **every** source before anything is written. The daily health check stops counting deletions made inside an importer apply window.

**Tech Stack:** Python 3.12 importer (pydantic 2, shapely 2, httpx 0.27, openpyxl, pytest, pytest-httpx 0.30), Supabase Postgrest with the service-role key, GitHub Actions, PostgreSQL (health-check SQL).

**Spec:** `docs/superpowers/specs/2026-09-29-importer-identity-and-cleanup-design.md`. Read it first; this plan argues from it.

## Global Constraints

- **No migration, no schema change.** `import_runs.orphans_marked` keeps its meaning: orphans marked, not deleted.
- **System user:** `81775f8b-1a6a-47d6-b793-e9ab7e38634e` (`config.yaml` `system_user_id`). Deletes only ever touch pins with `created_by` = this UUID **and** `user_modified = false`.
- **Re-key threshold:** 50 m between the candidate's `legacy_point` and the pin. **Site-point threshold:** ~50 m between the MIRTA site point and the (merged) boundary.
- **Delete cap:** `max(50, 5% of the source's in-scope pins)` (integer floor). `--orphan-delete-cap N` overrides it in a local run; `importer-apply.yml` must not expose it.
- **`--delete-orphans` is apply-only.** The CLI rejects it with `--dry-run`. A dry-run instead plans orphans the way `--delete-orphans` would.
- **Key formats:** GSA `"{Reporting Agency Code}-{Reporting Bureau Code}-{Real Property Unique Identifier}"` (e.g. `13-14-14000592`). Military: `SDSID` when it is a real GUID (not blank, not all zeros), else `"{STATE}:{SITENAME}"` with the state upper-cased and the name upper-cased and whitespace-collapsed (e.g. `TX:NG CAMP MABRY`).
- **Filters:** FRPP skips only `Asset Status == Disposed` (skip count `disposed`). MIRTA skips only `SITEOPERATIONALSTATUS == 'clsd'` (skip count `closed`); `act`, `care`, `excs`, `semi` stay.
- **Prod is never written in this plan.** Staging is written only by `importer-apply.yml`, and only after the owner says go. The Supabase MCP is bound to staging.
- **Health check:** a deletion inside an `import_runs` row with `mode = 'apply'` (between `started_at` and `completed_at`) is excluded from rules 4 and 5 and counted in `importer_deleted_24h`, which has no rule. A run with no `completed_at` covers nothing.
- **Commands:** importer commands run from `importer/` (`uv run pytest …`). The ci tests run from the repo root: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`. Git commands run from the repo root. Baseline before Task 1: **159** importer tests, **143** ci tests, all passing.
- **Test snippets that are "appended"** sometimes start with imports or constants. Put those imports at the top of the file with the existing ones.
- **Commits:** the commit commands below show the subject line only. End every commit message with the attribution trailers from your session's system reminder, and check them before pushing (a Haiku git subagent has rewritten them before).

## Spec refinements (decided while planning; flag any you disagree with)

These keep the spec's outcomes but change how they are reached. Each is in the task named.

1. **One fetch per source (Task 9).** The pipeline fetches all of a source's system pins once with `select_system_pins(source)` and uses that list both to match candidates (new ids and legacy ids) and, filtered by state, to find orphans. The spec described a separate id-list lookup for matching. Matching against every system pin gives the same matches, uses fewer requests (≈5 pages for pilot GSA instead of ≈50 id-list chunks), and avoids putting keys like `' '` or `TX:NG MARSEILLES (MTA TNG AREA)` inside a Postgrest `in.(…)` list. `select_pins_by_keys` loses its last caller and is removed.
2. **Pass 2 matches by distance, not by yield order (Task 6).** Within a legacy id, the closest candidate–pin pair is re-keyed first. The spec's wording (each candidate in order takes its nearest pin) gives the same result when the record the old code kept comes first. It doesn't always: a base whose old centroid fell outside every state can now enter the run earlier in file order, take the `' '` pin's slot, count as `rekey_too_far`, and push the right record to an insert. `rekey_too_far` counts **legacy pins** that had candidates but none within 50 m. Those pins are the ones left as orphans.
3. **Upserts clear `source_orphaned_at` (Task 5).** Today `upsert_pins` dumps rows with `exclude_none=True`, which drops the field, so an orphan-marked pin whose record comes back would stay marked forever. Harmless until now, because orphans never fired.
4. **`mark_orphans` takes pin ids (Task 5).** The spec reuses today's `mark_orphans`. It now keys on pin UUIDs instead of `(source, source_external_id)`, for the same quoting reason as #1.
5. **Empty layers are errors (Task 3).** A MIRTA cache with no `features` (ArcGIS returns HTTP 200 with an `{"error": …}` body) raises instead of yielding nothing. An empty boundary layer would orphan every military pin, and an empty points layer would silently move them all.
6. **`import_runs.updates` includes re-keys (Task 11).** There is no re-key column, and a re-key is an update of an existing row.

## Review Focus

These are inputs and conditions the spec implies but doesn't test, and the ones most likely to bite. Each has a test in the owning task.

1. **An apply that crashes after some re-key PATCHes, then is re-run.** Expected: the re-keyed pins match by new id (update), the rest re-key, with no inserts and no orphans. Covered by Task 6, `test_partial_apply_rerun_resolves_without_duplicates`.
2. **A record that was orphan-marked comes back in a later run.** Expected: its pin is un-marked. Covered by Task 5, `test_upsert_pins_clears_the_orphan_mark`.
3. **A user corrects a pin between the diff and the delete.** Expected: the delete skips it (`user_modified = false` filter) and the apply marks it instead, so it is neither lost nor left unmarked. Covered by Task 8, `test_pin_corrected_after_the_diff_is_marked_not_deleted`.
4. **An ArcGIS error body or empty layer saved as the MIRTA cache.** Expected: a hard error, not zero candidates (which would orphan every military pin) and not a silent fallback (which would move every pin). Covered by Task 3, `test_an_arcgis_error_body_is_an_error_not_an_empty_layer`.
5. **A pin whose coordinate is outside every state polygon, in a state-filtered run.** Expected: never in scope, so never marked or deleted. Covered by Task 7, `test_pin_outside_every_state_is_never_in_scope`.

Also covered, though not in the top five: two FRPP rows that share a property id and both need geocoding each get their own coordinate (Task 2). The old code keyed geocoder results by the bare id, so one row silently took the other's coordinate.

## File map

| File | Change | Responsibility |
|---|---|---|
| `importer/importer/geo/distance.py` | create | `meters_between`, `DEG_LAT_M` (shared by dedup, diff, military) |
| `importer/importer/candidate.py` | modify | `legacy_external_id`, `legacy_point` |
| `importer/importer/stages/dedup.py` | modify | import the shared distance helper |
| `importer/importer/sources/gsa.py` | modify | composite key, Disposed filter, legacy identity |
| `importer/importer/sources/hifld_military.py` | rewrite | site keys, merge, site points, closed filter, legacy identity |
| `importer/importer/stages/diff.py` | rewrite | two-pass match, `Rekey`, orphans from `in_scope` |
| `importer/importer/stages/orphans.py` | create | `scope_to_states`, `OrphanPlan`, `plan_orphans`, cap, `OrphanCapExceeded` |
| `importer/importer/stages/apply.py` | modify | re-key PATCHes, upsert, orphan plan |
| `importer/importer/supabase_client.py` | modify | `select_system_pins`, `patch_external_id`, `delete_pins`, `mark_orphans(ids)`, upsert clears the orphan mark; `select_pins_by_keys` removed |
| `importer/importer/pipeline.py` | rewrite | diff all sources → check caps → apply all |
| `importer/importer/reports/__init__.py`, `markdown.py`, `json_report.py` | modify | re-keys, orphan split, cap, skip counts |
| `importer/importer/cli.py` | modify | `--delete-orphans`, `--orphan-delete-cap`, wiring, import_runs counts, military points |
| `importer/config.yaml` | modify | `sources.hifld_military.points_url` |
| `data/state_laws/states.yaml` (+ `README.md`, `docs/importer/OMISSIONS.md`) | modify | drop the `US / STATE_LOCAL_GOVT` cell |
| `.github/workflows/importer-apply.yml` | modify | `delete_orphans` checkbox |
| `ci/health_check.sql`, `ci/health_check.py` | modify | importer-window exclusion, `importer_deleted_24h` |
| tests + fixtures under `importer/tests/`, `ci/tests/test_health_check.py` | modify/create | as each task lists |
| docs (`importer/README.md`, `docs/importer/*.md`, `CLAUDE.md`) | modify | Tasks 13–14 |

---

### Task 1: Legacy identity on `Candidate` and a shared distance helper

**Files:**
- Create: `importer/importer/geo/distance.py`
- Modify: `importer/importer/candidate.py`
- Modify: `importer/importer/stages/dedup.py:11,34-48`
- Test: `importer/tests/geo/test_distance.py` (create), `importer/tests/test_candidate.py`

**Interfaces:**
- Produces: `importer.geo.distance.meters_between(lat1: float, lng1: float, lat2: float, lng2: float) -> float`, `importer.geo.distance.DEG_LAT_M: float`; `Candidate.legacy_external_id: str | None = None`, `Candidate.legacy_point: tuple[float, float] | None = None` (lat, lng).

- [ ] **Step 1: Write the failing tests**

Create `importer/tests/geo/test_distance.py`:

```python
import pytest

from importer.geo.distance import DEG_LAT_M, meters_between


def test_same_point_is_zero() -> None:
    assert meters_between(30.0, -97.0, 30.0, -97.0) == 0.0


def test_one_degree_of_latitude() -> None:
    assert meters_between(30.0, -97.0, 31.0, -97.0) == pytest.approx(DEG_LAT_M)


def test_longitude_degrees_shrink_with_latitude() -> None:
    # 0.00031 deg of longitude at 30.23 N: the NAS Jacksonville site-point fixture.
    assert meters_between(30.23, -81.66, 30.23, -81.65969) == pytest.approx(29.8, abs=0.2)
```

Append to `importer/tests/test_candidate.py`:

```python
def _military(**kw) -> Candidate:
    fields = dict(
        source="hifld_military",
        source_external_id="TX:NG CAMP MABRY",
        source_dataset_version="v1",
        name="NG Camp Mabry",
        latitude=30.325,
        longitude=-97.755,
        coord_quality=CoordQuality.BUILDING_POLYGON,
        category=RestrictionTag.FEDERAL_PROPERTY,
        state="TX",
    )
    fields.update(kw)
    return Candidate(**fields)


def test_legacy_identity_defaults_to_none() -> None:
    c = _military()
    assert c.legacy_external_id is None
    assert c.legacy_point is None


def test_normalize_keeps_legacy_identity() -> None:
    from importer.stages.normalize import NormalizeStats, normalize

    c = _military(legacy_external_id=" ", legacy_point=(30.32, -97.76))
    out = next(normalize([c], stats=NormalizeStats()))
    assert out.legacy_external_id == " "
    assert out.legacy_point == (30.32, -97.76)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/geo/test_distance.py tests/test_candidate.py -v`
Expected: `ModuleNotFoundError: No module named 'importer.geo.distance'`, plus `AttributeError: 'Candidate' object has no attribute 'legacy_external_id'`. Pydantic ignores the unknown keyword, so the failure shows up on attribute access, not at construction.

- [ ] **Step 3: Implement**

Create `importer/importer/geo/distance.py`:

```python
"""Short-range distances in metres, for the importer's CONUS-scale checks
(dedup matching, re-key matching, MIRTA site points)."""

from __future__ import annotations

import math

DEG_LAT_M = 111_320.0  # metres per degree of latitude


def meters_between(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Equirectangular approximation: well under 1% error at the sub-kilometre
    distances the importer compares."""
    mean_lat = math.radians((lat1 + lat2) / 2.0)
    dx = (lng2 - lng1) * DEG_LAT_M * math.cos(mean_lat)
    dy = (lat2 - lat1) * DEG_LAT_M
    return math.hypot(dx, dy)
```

In `importer/importer/candidate.py`, add after `extra: dict = Field(default_factory=dict)`:

```python
    # Identity hints for the diff stage, set only by sources whose id scheme
    # changed and only when the old id differs from the new one. Never written
    # to the database. legacy_point is the (lat, lng) the old code wrote.
    legacy_external_id: str | None = None
    legacy_point: tuple[float, float] | None = None
```

In `importer/importer/stages/dedup.py`: delete `import math` (line 11), the `_DEG_LAT_M = 111_320.0 …` line, and the whole `_meters_between` function. Put these imports with the other `importer.` imports:

```python
from importer.geo.distance import DEG_LAT_M as _DEG_LAT_M
from importer.geo.distance import meters_between as _meters_between
```

(The aliases keep `tests/stages/test_dedup.py`'s `from importer.stages.dedup import _meters_between` working.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/geo/test_distance.py tests/test_candidate.py tests/stages/test_dedup.py -v`
Expected: all PASS.

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/geo/distance.py importer/importer/candidate.py importer/importer/stages/dedup.py importer/tests/geo/test_distance.py importer/tests/test_candidate.py
git commit -m "feat(importer): legacy identity on Candidate; shared meters_between"
```

---

### Task 2: GSA composite key, Disposed filter, legacy identity

**Files:**
- Create: `importer/tests/fixtures/make_gsa_frpp_sample.py`
- Regenerate: `importer/tests/fixtures/gsa_frpp_sample.xlsx`
- Modify: `importer/importer/sources/gsa.py`
- Test: `importer/tests/sources/test_gsa.py` (rewrite)

**Interfaces:**
- Consumes: `Candidate.legacy_external_id`, `Candidate.legacy_point` (Task 1).
- Produces: GSA candidates with `source_external_id = "{agency}-{bureau}-{rpuid}"`, `legacy_external_id = rpuid`, `legacy_point = (latitude, longitude)` (always set); `last_skip_counts["disposed"]`; `last_skip_counts["missing_external_id"]` now also counts a blank agency or bureau code. The geocoder is asked with `AddressRecord.id` = the composite key.

- [ ] **Step 1: Write the fixture generator and regenerate the fixture**

Create `importer/tests/fixtures/make_gsa_frpp_sample.py`:

```python
"""Regenerate gsa_frpp_sample.xlsx. Run from importer/:

    uv run python tests/fixtures/make_gsa_frpp_sample.py

The real FRPP file has 117 columns; the fixture carries only the ones
GsaSource reads. Agency and bureau codes are strings, as in the real file.
"""

from pathlib import Path

import openpyxl

HEADER = (
    "Real Property Unique Identifier", "Real Property Type", "Real Property Use",
    "Street Address", "City Name", "State Name", "Zip Code", "Latitude", "Longitude",
    "Installation Name", "Reporting Agency Code", "Reporting Bureau Code", "Asset Status",
)

OK = "Current Mission Need"

ROWS = [
    ("RPUID-TX-1", "Building", "Office", "100 Main St", "Austin", "TEXAS", "78701", 30.2672, -97.7431, "Federal Office Building", "47", "00", OK),
    ("RPUID-TX-2", "Building", "Courthouse", "200 Geocode Ave", "Houston", "TEXAS", "77002", None, None, "US Courthouse Houston", "47", "00", OK),
    ("RPUID-CA-1", "Building", "Office", "1 Bay St", "San Francisco", "CALIFORNIA", "94105", 37.79, -122.4, "SF Federal Building", "47", "00", OK),
    ("RPUID-TX-3", "Land", "Vacant", "Rural Rd", "Marfa", "TEXAS", "79843", None, None, "Vacant Federal Land", "47", "00", OK),
    ("RPUID-TX-4", "Building", "Office", None, "Dallas", "TEXAS", "75201", None, None, "No Address Building", "47", "00", OK),
    ("RPUID-TX-5", "Building", "Office", "1 Bad Coord Rd", "Portland Mills", "TEXAS", "75001", 43.0392538, -87.9031992, "Mislocated Federal Building", "47", "00", OK),
    ("RPUID-TX-6", "Building", "Office", "500 Commerce St", "Dallas", "TEXAS", "75201", 32.7767, -96.797, "DALLAS, TX", "47", "00", OK),
    ("RPUID-TX-7", "Building", "Warehouses", "1234 Main Street", "Austin", "TEXAS", "78704", 30.25, -97.75, "1234 Main Street", "47", "00", OK),
    # One property id under two agencies: two buildings, two pins.
    ("RPUID-TX-DUP", "Building", "Office", "10 Alamo Plaza", "San Antonio", "TEXAS", "78205", 29.4241, -98.4936, "San Antonio Federal Center", "13", "14", OK),
    ("RPUID-TX-DUP", "Building", "Office", "20 Broadway", "Lubbock", "TEXAS", "79401", 33.5779, -101.8552, "Lubbock Federal Building", "14", "10", "Determination to Dispose"),
    # No longer federal property.
    ("RPUID-TX-GONE", "Building", "Office", "30 Austin Ave", "Waco", "TEXAS", "76701", 31.5493, -97.1467, "Former Federal Building", "47", "00", "Disposed"),
    # Blank bureau code: no stable identity.
    ("RPUID-TX-NOBUREAU", "Building", "Office", "40 Broadway", "Tyler", "TEXAS", "75701", 32.3513, -95.3011, "Tyler Federal Building", "47", None, OK),
    # One property id, no coordinates: each row must get its own geocode.
    ("RPUID-TX-GEO", "Building", "Office", "50 Smith St", "Houston", "TEXAS", "77002", None, None, "Houston Annex A", "13", "14", OK),
    ("RPUID-TX-GEO", "Building", "Office", "60 Fannin St", "Houston", "TEXAS", "77002", None, None, "Houston Annex B", "14", "10", OK),
]


def main() -> None:
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(HEADER)
    for row in ROWS:
        ws.append(row)
    wb.save(Path(__file__).with_name("gsa_frpp_sample.xlsx"))


if __name__ == "__main__":
    main()
```

Run: `uv run python tests/fixtures/make_gsa_frpp_sample.py`
Expected: no output; `tests/fixtures/gsa_frpp_sample.xlsx` is rewritten. The `.py` name doesn't match `test_*.py`, so pytest won't collect it.

- [ ] **Step 2: Rewrite the GSA tests**

Replace `importer/tests/sources/test_gsa.py` with:

```python
from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.gsa import GsaSource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"

# Rows: tests/fixtures/make_gsa_frpp_sample.py
GEOCODED = {
    "47-00-RPUID-TX-2": (29.7604, -95.3698),
    "13-14-RPUID-TX-GEO": (29.7590, -95.3650),
    "14-10-RPUID-TX-GEO": (29.7550, -95.3620),
}


def K(rpuid: str) -> str:
    """External id of a fixture row reported by agency 47, bureau 00."""
    return f"47-00-{rpuid}"


class _FakeGeocoder:
    """Geocodes the fixture rows that lack lat/lng, keyed by external id."""

    def __init__(self):
        self.calls = []

    def geocode(self, records):
        self.calls.append([r.id for r in records])
        return {r.id: GEOCODED[r.id] for r in records if r.id in GEOCODED}


@pytest.fixture
def source():
    return GsaSource(
        cache_path=FIXTURE_DIR / "gsa_frpp_sample.xlsx",
        dataset_version="FRPP-FIXTURE",
        geocoder=_FakeGeocoder(),
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
    )


def _by_id(source):
    return {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX"})}


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "gsa"


def test_uses_existing_coords_and_geocodes_missing(source):
    cands = _by_id(source)
    assert cands[K("RPUID-TX-1")].coord_quality is CoordQuality.PRECISE
    assert cands[K("RPUID-TX-2")].coord_quality is CoordQuality.ADDRESS_CENTROID
    assert cands[K("RPUID-TX-2")].latitude == pytest.approx(29.7604)
    assert all(c.category is RestrictionTag.FEDERAL_PROPERTY for c in cands.values())


def test_filters_state_before_geocoding(source):
    list(source.iter_candidates(state_filter={"TX"}))
    # Only TX rows that lack coords are geocoded, each under its composite id.
    assert source._geocoder.calls == [[K("RPUID-TX-2"), "13-14-RPUID-TX-GEO", "14-10-RPUID-TX-GEO"]]


def test_excludes_land_and_no_address(source):
    cands = _by_id(source)
    assert K("RPUID-TX-3") not in cands  # Land
    assert K("RPUID-TX-4") not in cands  # no street address
    assert source.last_skip_counts["not_federal_facility"] >= 1
    assert source.last_skip_counts["missing_address"] >= 1


def test_drops_row_whose_coord_is_outside_claimed_state(source):
    # RPUID-TX-5 claims TEXAS but its lat/lng is in Milwaukee, WI (the real
    # ALLEGHENY-NATIONAL-FOREST-in-Milwaukee bug). The point-in-polygon check
    # must catch the disagreement and drop it.
    cands = _by_id(source)
    assert K("RPUID-TX-5") not in cands
    assert source.last_skip_counts["coord_state_mismatch"] >= 1
    assert K("RPUID-TX-1") in cands


def test_composes_label_for_city_and_address_names(source):
    cands = _by_id(source)
    assert cands[K("RPUID-TX-6")].name == "Office — Dallas, TX"
    assert cands[K("RPUID-TX-7")].name == "Warehouses — Austin, TX"
    assert cands[K("RPUID-TX-1")].name == "Federal Office Building"


def test_external_id_is_agency_bureau_and_property_id(source):
    cands = _by_id(source)
    assert "13-14-RPUID-TX-DUP" in cands
    assert K("RPUID-TX-1") in cands


def test_same_property_id_under_two_agencies_yields_two_candidates(source):
    dup = [c for c in _by_id(source).values() if c.source_external_id.endswith("-RPUID-TX-DUP")]
    assert sorted(c.source_external_id for c in dup) == ["13-14-RPUID-TX-DUP", "14-10-RPUID-TX-DUP"]
    assert {c.name for c in dup} == {"San Antonio Federal Center", "Lubbock Federal Building"}


def test_disposed_rows_are_skipped(source):
    assert K("RPUID-TX-GONE") not in _by_id(source)
    assert source.last_skip_counts["disposed"] == 1


def test_other_disposal_statuses_stay(source):
    # "Determination to Dispose" is still federal property.
    assert "14-10-RPUID-TX-DUP" in _by_id(source)


def test_row_missing_a_code_is_skipped(source):
    assert not any("RPUID-TX-NOBUREAU" in eid for eid in _by_id(source))
    assert source.last_skip_counts["missing_external_id"] == 1


def test_legacy_identity_is_the_bare_property_id_at_its_own_coordinate(source):
    cands = _by_id(source)
    sa = cands["13-14-RPUID-TX-DUP"]
    assert sa.legacy_external_id == "RPUID-TX-DUP"
    assert sa.legacy_point == (29.4241, -98.4936)
    geo = cands[K("RPUID-TX-2")]
    assert geo.legacy_external_id == "RPUID-TX-2"
    assert geo.legacy_point == (geo.latitude, geo.longitude)


def test_rows_sharing_a_property_id_each_get_their_own_geocode(source):
    cands = _by_id(source)
    a, b = cands["13-14-RPUID-TX-GEO"], cands["14-10-RPUID-TX-GEO"]
    assert (a.latitude, a.longitude) == (29.7590, -95.3650)
    assert (b.latitude, b.longitude) == (29.7550, -95.3620)
```

- [ ] **Step 3: Run them to verify they fail**

Run: `uv run pytest tests/sources/test_gsa.py -v`
Expected: FAIL. `KeyError: '47-00-RPUID-TX-1'` and similar, because the source still emits bare ids.

- [ ] **Step 4: Implement in `importer/importer/sources/gsa.py`**

Add to the module docstring, after the `Latitude`/`Longitude` bullet:

```
Identity (2026-10): `Real Property Unique Identifier` is unique only within a
reporting agency and bureau (it repeats across agencies), so a building's
external id is "{Reporting Agency Code}-{Reporting Bureau Code}-{Real Property
Unique Identifier}". Candidates also carry the bare id and their own coordinate
as legacy identity, so the diff stage re-keys pins written under the old id.
`Asset Status == Disposed` rows are no longer federal property and are skipped.
```

Add the column constants after `_COL_USE = "Real Property Use"`:

```python
_COL_AGENCY = "Reporting Agency Code"
_COL_BUREAU = "Reporting Bureau Code"
_COL_STATUS = "Asset Status"
```

Extend `_NEEDED_COLS`:

```python
_NEEDED_COLS = (
    _COL_ID, _COL_TYPE, _COL_STREET, _COL_CITY, _COL_STATE, _COL_ZIP,
    _COL_LAT, _COL_LNG, _COL_NAME, _COL_USE, _COL_AGENCY, _COL_BUREAU, _COL_STATUS,
)
```

In `iter_candidates`, replace the block from `eid = (row.get(_COL_ID) or "").strip()` through `continue` (the `missing_external_id` check) with:

```python
            rpuid = (row.get(_COL_ID) or "").strip()
            agency = (row.get(_COL_AGENCY) or "").strip()
            bureau = (row.get(_COL_BUREAU) or "").strip()
            if not (rpuid and agency and bureau):
                self.last_skip_counts["missing_external_id"] += 1
                continue
            if (row.get(_COL_STATUS) or "").strip().lower() == "disposed":
                # No longer federal property: no legal basis for a pin.
                self.last_skip_counts["disposed"] += 1
                continue
            eid = f"{agency}-{bureau}-{rpuid}"
```

After `row["_eid"] = eid`, add `row["_rpuid"] = rpuid`. In the final `yield Candidate(...)`, add these arguments after `extra={},`:

```python
                # Before 2026-10 the id was the bare property id, which repeats
                # across agencies; the diff stage re-keys those pins by position.
                legacy_external_id=row["_rpuid"],
                legacy_point=(lat, lng),
```

(`AddressRecord(id=eid, …)` already passes `eid`, which is now the composite key. That is the geocode fix.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run pytest tests/sources/test_gsa.py -v`
Expected: 14 PASS.

- [ ] **Step 6: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/sources/gsa.py importer/tests/sources/test_gsa.py importer/tests/fixtures/make_gsa_frpp_sample.py importer/tests/fixtures/gsa_frpp_sample.xlsx
git commit -m "feat(importer): GSA agency-bureau-property key, skip Disposed, legacy identity"
```

---

### Task 3: MIRTA military source: site keys, merged records, site points, closed sites

**Files:**
- Create: `importer/tests/fixtures/make_hifld_military_samples.py`
- Regenerate: `importer/tests/fixtures/hifld_military_sample.geojson`; create `importer/tests/fixtures/hifld_military_points_sample.geojson`
- Rewrite: `importer/importer/sources/hifld_military.py`
- Modify: `importer/config.yaml` (`sources.hifld_military`), `importer/importer/cli.py` (`_build_source`)
- Test: `importer/tests/sources/test_hifld_military.py` (rewrite), `importer/tests/test_cli.py`

**Interfaces:**
- Consumes: `meters_between` (Task 1); `Candidate.legacy_*` (Task 1).
- Produces: `HifldMilitarySource(*, cache_path: Path, points_cache_path: Path, state_locator: StateLocator, dataset_version: str, url: str = "", points_url: str = "")`; module constant `SITE_POINT_MAX_M = 50.0`; skip counts `missing_geometry`, `closed`, `missing_name`, `state_pip_miss`, `filtered_out`, and `merged_records` (records folded into another record of the same site); `config.yaml` key `sources.hifld_military.points_url`.

- [ ] **Step 1: Write the fixture generator and generate both fixtures**

Create `importer/tests/fixtures/make_hifld_military_samples.py`:

```python
"""Regenerate the MIRTA fixtures. Run from importer/:

    uv run python tests/fixtures/make_hifld_military_samples.py

Writes hifld_military_sample.geojson (layer 1, boundaries) and
hifld_military_points_sample.geojson (layer 0, DoD site points). Field names
and value shapes match the live service: lower-case state codes on most
records, SDSID null on 202 boundaries, MIRTALOCATIONSIDPK a single space.
"""

import json
from pathlib import Path

HERE = Path(__file__).parent
ZERO = "00000000-0000-0000-0000-000000000000"


def square(w, s, e, n):
    return [[[w, s], [e, s], [e, n], [w, n], [w, s]]]


def polygon(w, s, e, n):
    return {"type": "Polygon", "coordinates": square(w, s, e, n)}


def multipolygon(*boxes):
    return {"type": "MultiPolygon", "coordinates": [square(*b) for b in boxes]}


def boundary(sdsid, name, state, geometry, status="act"):
    return {
        "type": "Feature",
        "properties": {
            "SDSID": sdsid,
            "SITENAME": name,
            "STATENAMECODE": state,
            "SITEOPERATIONALSTATUS": status,
            "SITEREPORTINGCOMPONENT": "usa",
            "MIRTALOCATIONSIDPK": " ",
        },
        "geometry": geometry,
    }


def site(sdsid, name, state, lng, lat):
    return {
        "type": "Feature",
        "properties": {"SDSID": sdsid, "SITENAME": name, "STATENAMECODE": state},
        "geometry": {"type": "Point", "coordinates": [lng, lat]},
    }


BOUNDARIES = [
    boundary("MIL-TX-1", "Fort Cavazos", "tx", polygon(-97.79, 31.13, -97.77, 31.15)),
    boundary("MIL-FL-1", "NAS Jacksonville", "fl", multipolygon((-81.68, 30.22, -81.66, 30.24))),
    boundary("MIL-PA-1", "Carlisle Barracks", "pa", polygon(-77.19, 40.20, -77.17, 40.22)),
    boundary("MIL-CA-1", "Camp Pendleton", "ca", polygon(-117.40, 33.30, -117.38, 33.32)),
    boundary("MIL-NULL", "No Geometry Base", "tx", None),
    # No SDSID: keyed by state + name. The old code gave all of these the id " ".
    boundary(None, "NG Camp Mabry", "tx", polygon(-97.77, 30.31, -97.75, 30.33)),
    # All-zero SDSID: also keyed by state + name.
    boundary(ZERO, "Camp Blanding", "fl", polygon(-81.99, 29.95, -81.97, 29.97)),
    # One installation split across two records: merged into one candidate.
    boundary(None, "NG Camp Swift", "tx", polygon(-97.30, 30.27, -97.28, 30.29)),
    boundary(None, "NG Camp Swift", "tx", polygon(-97.26, 30.25, -97.25, 30.26)),
    # Multi-part base whose DoD point is on the small part (JBSA: Lackland, not Camp Bullis).
    boundary("MIL-TX-JBSA", "Joint Base San Antonio", "tx",
             multipolygon((-98.60, 29.65, -98.50, 29.75), (-98.63, 29.37, -98.61, 29.39))),
    # Multi-part base whose point is ~8 km off and whose area centroid misses both parts.
    boundary("MIL-FL-JAX", "Jacksonville IAP (ANG)", "fl",
             multipolygon((-81.70, 30.48, -81.68, 30.50), (-81.50, 30.48, -81.49, 30.49))),
    boundary("MIL-TX-CLOSED", "Closed Depot", "tx", polygon(-97.10, 31.50, -97.08, 31.52), status="clsd"),
    boundary("MIL-PA-CARE", "Caretaker Depot", "pa", polygon(-76.90, 40.27, -76.88, 40.29), status="care"),
]

POINTS = [
    site("MIL-TX-1", "Fort Cavazos", "tx", -97.775, 31.145),             # on the base
    site("MIL-FL-1", "NAS Jacksonville", "fl", -81.65969, 30.23),         # ~30 m east of the boundary
    site(None, "NG  Camp Mabry", "TX", -97.755, 30.325),                   # state + name match
    site("MIL-TX-JBSA", "Joint Base San Antonio", "tx", -98.62, 29.38),   # on the small part
    site("MIL-FL-JAX", "Jacksonville IAP (ANG)", "fl", -81.60, 30.49),    # off the base
    site("MIL-CA-9", "Unrelated Site", "ca", -117.0, 33.0),
]


def _write(name, features):
    (HERE / name).write_text(
        json.dumps({"type": "FeatureCollection", "features": features}, indent=1) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    _write("hifld_military_sample.geojson", BOUNDARIES)
    _write("hifld_military_points_sample.geojson", POINTS)
```

Run: `uv run python tests/fixtures/make_hifld_military_samples.py`
Expected: both files written, no output.

(This was prototyped against `states_sample.geojson` while planning. Every pilot fixture position resolves to its state; Camp Pendleton resolves to none.)

- [ ] **Step 2: Rewrite the military tests**

Replace `importer/tests/sources/test_hifld_military.py` with:

```python
import json
from pathlib import Path

import pytest
from shapely.geometry import Point, shape

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.hifld_military import HifldMilitarySource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"
BOUNDARIES = FIXTURE_DIR / "hifld_military_sample.geojson"
POINTS = FIXTURE_DIR / "hifld_military_points_sample.geojson"
LOCATOR = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
PILOT = {"TX", "FL", "PA"}
ZERO = "00000000-0000-0000-0000-000000000000"


def _source(cache_path=BOUNDARIES, points_cache_path=POINTS, **kw):
    return HifldMilitarySource(
        cache_path=cache_path,
        points_cache_path=points_cache_path,
        state_locator=LOCATOR,
        dataset_version="HIFLD-MIL-FIXTURE",
        **kw,
    )


@pytest.fixture(scope="module")
def run():
    """(candidates by external id, skip counts) for one pass over the pilot states."""
    src = _source()
    cands = {c.source_external_id: c for c in src.iter_candidates(state_filter=PILOT)}
    return cands, src.last_skip_counts


def _parts(name):
    """Polygon parts of every fixture boundary record with this SITENAME."""
    raw = json.loads(BOUNDARIES.read_text(encoding="utf-8"))
    out = []
    for f in raw["features"]:
        if f["properties"]["SITENAME"] == name and f["geometry"]:
            g = shape(f["geometry"])
            out.extend(getattr(g, "geoms", [g]))
    return out


def _at(c):
    return Point(c.longitude, c.latitude)


def test_source_name_is_stable():
    assert HifldMilitarySource.SOURCE_NAME == "hifld_military"


def test_yields_pilot_states_as_federal_property(run):
    cands, _ = run
    assert {c.state for c in cands.values()} == PILOT
    assert all(c.category is RestrictionTag.FEDERAL_PROPERTY for c in cands.values())
    assert all(c.coord_quality is CoordQuality.BUILDING_POLYGON for c in cands.values())


def test_real_sdsid_is_the_key(run):
    cands, _ = run
    assert {"MIL-TX-1", "MIL-FL-1", "MIL-PA-1", "MIL-TX-JBSA", "MIL-FL-JAX"} <= cands.keys()


def test_blank_and_all_zero_sdsids_key_on_state_and_name(run):
    cands, _ = run
    assert "TX:NG CAMP MABRY" in cands
    assert "FL:CAMP BLANDING" in cands
    assert " " not in cands and ZERO not in cands


def test_records_sharing_a_key_merge_into_one_candidate(run):
    cands, skips = run
    swift = [c for c in cands.values() if c.name == "NG Camp Swift"]
    assert [c.source_external_id for c in swift] == ["TX:NG CAMP SWIFT"]
    assert skips["merged_records"] == 1
    largest = max(_parts("NG Camp Swift"), key=lambda g: g.area)
    assert largest.covers(_at(swift[0]))  # no site point: inside the largest part


def test_site_point_on_the_base_is_used(run):
    cands, _ = run
    assert (cands["MIL-TX-1"].latitude, cands["MIL-TX-1"].longitude) == (31.145, -97.775)


def test_site_point_within_50_m_of_the_boundary_is_used(run):
    cands, _ = run
    assert cands["MIL-FL-1"].longitude == -81.65969  # ~30 m east of the boundary


def test_site_point_on_a_small_part_beats_the_largest_part(run):
    cands, _ = run
    assert (cands["MIL-TX-JBSA"].latitude, cands["MIL-TX-JBSA"].longitude) == (29.38, -98.62)


def test_site_point_matches_on_state_and_name_ignoring_case_and_spacing(run):
    cands, _ = run
    mabry = cands["TX:NG CAMP MABRY"]
    assert (mabry.latitude, mabry.longitude) == (30.325, -97.755)


def test_far_site_point_falls_back_inside_the_largest_part(run):
    cands, _ = run
    largest = max(_parts("Jacksonville IAP (ANG)"), key=lambda g: g.area)
    assert largest.covers(_at(cands["MIL-FL-JAX"]))


def test_without_a_site_point_the_pin_is_inside_the_boundary(run):
    cands, _ = run
    (carlisle,) = _parts("Carlisle Barracks")
    assert carlisle.covers(_at(cands["MIL-PA-1"]))


def test_closed_sites_are_skipped_and_caretaker_sites_stay(run):
    cands, skips = run
    assert "MIL-TX-CLOSED" not in cands
    assert skips["closed"] == 1
    assert "MIL-PA-CARE" in cands


def test_legacy_identity_only_when_the_id_changed(run):
    cands, _ = run
    mabry = cands["TX:NG CAMP MABRY"]
    assert mabry.legacy_external_id == " "  # the old MIRTALOCATIONSIDPK fallback
    assert mabry.legacy_point == pytest.approx((30.32, -97.76))  # old centroid, not the site point
    assert cands["FL:CAMP BLANDING"].legacy_external_id == ZERO
    assert cands["MIL-TX-1"].legacy_external_id is None
    assert cands["MIL-TX-1"].legacy_point is None


def test_merged_site_takes_its_legacy_identity_from_the_first_record(run):
    cands, _ = run
    swift = cands["TX:NG CAMP SWIFT"]
    assert swift.legacy_external_id == " "
    assert swift.legacy_point == pytest.approx((30.28, -97.29))


def test_skips_null_geometry_and_out_of_state(run):
    _, skips = run
    assert skips["missing_geometry"] == 1
    assert skips["state_pip_miss"] == 1  # Camp Pendleton, CA


def test_missing_points_file_is_an_error(tmp_path):
    src = _source(points_cache_path=tmp_path / "absent.geojson")
    with pytest.raises(RuntimeError, match="site-points file missing"):
        list(src.iter_candidates(state_filter=PILOT))


@pytest.mark.parametrize("which", ["boundary", "site-points"])
def test_an_arcgis_error_body_is_an_error_not_an_empty_layer(tmp_path, which):
    bad = tmp_path / "bad.geojson"
    bad.write_text('{"error": {"code": 400, "message": "Invalid query"}}', encoding="utf-8")
    src = _source(cache_path=bad) if which == "boundary" else _source(points_cache_path=bad)
    with pytest.raises(RuntimeError, match=f"{which} file has no features"):
        list(src.iter_candidates(state_filter=PILOT))


def test_fetch_downloads_both_layers(tmp_path, httpx_mock):
    httpx_mock.add_response(url="https://example.test/boundaries", content=b'{"features": [1]}')
    httpx_mock.add_response(url="https://example.test/points", content=b'{"features": [2]}')
    src = _source(
        cache_path=tmp_path / "military.geojson",
        points_cache_path=tmp_path / "military_points.geojson",
        url="https://example.test/boundaries",
        points_url="https://example.test/points",
    )
    src.fetch()
    assert (tmp_path / "military.geojson").read_bytes() == b'{"features": [1]}'
    assert (tmp_path / "military_points.geojson").read_bytes() == b'{"features": [2]}'


def test_fetch_requires_a_points_url(tmp_path):
    src = _source(
        cache_path=tmp_path / "military.geojson",
        points_cache_path=tmp_path / "military_points.geojson",
        url="https://example.test/boundaries",
    )
    with pytest.raises(RuntimeError, match="points_url"):
        src.fetch()
```

Add to `importer/tests/test_cli.py`:

```python
def test_build_source_wires_military_site_points(tmp_path):
    from pathlib import Path
    from importer.cli import _build_source
    from importer.geo.states import load_state_locator

    locator = load_state_locator(Path(__file__).parent / "fixtures" / "states_sample.geojson")
    config = {"sources": {"hifld_military": {
        "cache_dir": "data/sources/hifld_military", "dataset_version": "v",
        "url": "u", "points_url": "p",
    }}}
    src = _build_source("hifld_military", config=config, locator=locator, repo_root=tmp_path)
    assert src._points_url == "p"
    assert src._points_cache_path == tmp_path / "data/sources/hifld_military" / "military_points.geojson"


def test_config_pins_the_mirta_site_points_layer():
    import yaml
    from pathlib import Path
    from importer.cli import CONFIG_PATH

    cfg = yaml.safe_load(Path(CONFIG_PATH).read_text(encoding="utf-8"))["sources"]["hifld_military"]
    assert cfg["points_url"].endswith(
        "/mirta/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson"
    )
```

- [ ] **Step 3: Run them to verify they fail**

Run: `uv run pytest tests/sources/test_hifld_military.py tests/test_cli.py -v`
Expected: FAIL, with `TypeError: HifldMilitarySource.__init__() got an unexpected keyword argument 'points_cache_path'` and `KeyError: 'points_url'`.

- [ ] **Step 4: Rewrite `importer/importer/sources/hifld_military.py`**

```python
"""HIFLD Military Installations (MIRTA) -> Candidate stream.

Source: Military Installations, Ranges, and Training Areas (MIRTA) DoD Sites,
from the USACE-owned MIRTA feature service (item owner `usace_crrel_als`); the
legacy HIFLD Open hub was deactivated 2025-08-26. License: public domain (US
Gov / DoD DISDI). Two layers, each fetched with one GeoJSON GET
(maxRecordCount 1000 exceeds both counts: 825 boundaries, 737 points, 2026-09):
  - layer 1, "DoD Sites - Boundaries" (`url`): a Polygon/MultiPolygon per record.
  - layer 0, "DoD Sites - Point" (`points_url`): one DoD-placed point per site.

Identity. A site's key is its `SDSID` when that is a real GUID (not blank, not
all zeros). 202 boundaries have no SDSID and 3 share the all-zero one; those
are keyed "{STATE}:{SITENAME}" (upper-cased, whitespace collapsed). Records
that share a key are one installation split across records; their geometries
are merged into one candidate.

Position. The pin goes on the site's DoD point (matched by SDSID, else by
state + name) when that point lies within SITE_POINT_MAX_M of the boundary;
otherwise on a point inside the boundary's largest part. The area-weighted
centroid used before 2026-10 fell outside the base for 77 multi-part sites.

Closed sites (SITEOPERATIONALSTATUS 'clsd') are skipped. Caretaker, excess
and semi-active sites stay: DoD still holds them.

Legacy identity. Before 2026-10 the id fell back to MIRTALOCATIONSIDPK, which
is a single space on every record, so all blank-SDSID sites collapsed into one
pin. A candidate whose key differs from that old id carries the old id and the
old centroid (of its first record in file order, which the old code kept), so
the diff stage can re-key that pin instead of replacing it.

Category is FEDERAL_PROPERTY (18 USC 930 via the US FEDERAL_PROPERTY
state-law cell, whose source_filter includes hifld_military).
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx
from shapely.geometry import Point, shape
from shapely.ops import nearest_points, unary_union

from importer.candidate import Candidate, CoordQuality
from importer.geo.distance import meters_between
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source

# A DoD site point this close to the boundary counts as on the base: boundary
# digitizing and the point's placement disagree by a few metres at the edge.
SITE_POINT_MAX_M = 50.0

_CLOSED = "clsd"


def _real_sdsid(props: dict) -> str | None:
    """The SDSID when it is a real GUID: not blank and not all zeros."""
    v = str(props.get("SDSID") or "").strip()
    if not v or set(v) <= set("{}-0"):
        return None
    return v


def _site_name(props: dict) -> str:
    return str(
        props.get("SITENAME")
        or props.get("siteName")
        or props.get("NAME")
        or props.get("name")
        or ""
    ).strip()


def _name_key(props: dict) -> str:
    state = str(props.get("STATENAMECODE") or "").strip().upper()
    return f"{state}:{' '.join(_site_name(props).upper().split())}"


def _site_key(props: dict) -> str:
    return _real_sdsid(props) or _name_key(props)


def _legacy_external_id(props: dict) -> str | None:
    """The id the pre-2026-10 code used, kept verbatim for re-keying."""
    for key in ("SDSID", "MIRTALOCATIONSIDPK", "GLOBALID", "OBJECTID", "FID"):
        v = props.get(key)
        if v not in (None, ""):
            return str(v)
    return None


def _load_features(path: Path, what: str) -> list[dict]:
    """Features of a cached layer. A missing file, an ArcGIS error body or an
    empty layer is an error: an empty boundary layer would orphan every
    military pin, and an empty points layer would silently move them all."""
    if not path.exists():
        raise RuntimeError(f"hifld_military {what} file missing: {path}; run fetch()")
    raw = json.loads(path.read_text(encoding="utf-8"))
    features = raw.get("features") if isinstance(raw, dict) else None
    if not features:
        raise RuntimeError(f"hifld_military {what} file has no features: {path}")
    return features


class _SitePoints:
    """DoD site points, looked up by real SDSID, else by state + name."""

    def __init__(self, features: list[dict]) -> None:
        self._by_sdsid: dict[str, Point] = {}
        self._by_name: dict[str, Point] = {}
        for f in features:
            geom = f.get("geometry") or {}
            if geom.get("type") != "Point":
                continue
            props = f.get("properties") or {}
            pt = shape(geom)
            sdsid = _real_sdsid(props)
            if sdsid:
                self._by_sdsid.setdefault(sdsid, pt)
            self._by_name.setdefault(_name_key(props), pt)

    def match(self, props: dict) -> Point | None:
        sdsid = _real_sdsid(props)
        if sdsid and sdsid in self._by_sdsid:
            return self._by_sdsid[sdsid]
        return self._by_name.get(_name_key(props))


def _meters_outside(area, pt: Point) -> float:
    if area.covers(pt):
        return 0.0
    near = nearest_points(area, pt)[0]
    return meters_between(near.y, near.x, pt.y, pt.x)


def _position(area, site_point: Point | None) -> Point:
    """The site point when it is on the base, else a point inside the largest part."""
    if site_point is not None and _meters_outside(area, site_point) <= SITE_POINT_MAX_M:
        return site_point
    parts = [g for g in getattr(area, "geoms", [area]) if g.geom_type == "Polygon"]
    return max(parts, key=lambda g: g.area).representative_point()


class HifldMilitarySource(Source):
    SOURCE_NAME: ClassVar[str] = "hifld_military"

    def __init__(
        self,
        *,
        cache_path: Path,
        points_cache_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
        points_url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._points_cache_path = points_cache_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self._points_url = points_url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        layers = (
            ("url", self._url, self._cache_path),
            ("points_url", self._points_url, self._points_cache_path),
        )
        todo = [(key, url, path) for key, url, path in layers if refetch or not path.exists()]
        for key, url, _ in todo:
            if not url:
                raise RuntimeError(
                    f"hifld_military {key} not configured; set sources.hifld_military.{key} in config.yaml"
                )
        if not todo:
            return
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            for _, url, path in todo:
                r = client.get(url)
                r.raise_for_status()
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        """One Candidate per installation; respect state_filter when set.

        Side effect: resets and populates `self.last_skip_counts`. Callers must
        fully exhaust the iterator (e.g. via `list(...)`) before reading them.
        """
        self.last_skip_counts = Counter()
        features = _load_features(self._cache_path, "boundary")
        points = _SitePoints(_load_features(self._points_cache_path, "site-points"))

        # Insertion order is the file order of each key's first record.
        groups: dict[str, list[dict]] = {}
        for feature in features:
            geom = feature.get("geometry")
            props = feature.get("properties") or {}
            if not geom or geom.get("type") not in ("Polygon", "MultiPolygon"):
                self.last_skip_counts["missing_geometry"] += 1
                continue
            if str(props.get("SITEOPERATIONALSTATUS") or "").strip().lower() == _CLOSED:
                self.last_skip_counts["closed"] += 1
                continue
            if not _site_name(props):
                self.last_skip_counts["missing_name"] += 1
                continue
            groups.setdefault(_site_key(props), []).append(feature)

        for key, members in groups.items():
            first = members[0].get("properties") or {}
            shapes = [shape(m["geometry"]) for m in members]
            pos = _position(unary_union(shapes), points.match(first))
            lat, lng = float(pos.y), float(pos.x)

            state = self._locator.state_for(lat, lng)
            if state is None:
                self.last_skip_counts["state_pip_miss"] += 1
                continue
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue
            if len(members) > 1:
                self.last_skip_counts["merged_records"] += len(members) - 1

            legacy: dict = {}
            old_id = _legacy_external_id(first)
            if old_id is not None and old_id != key:
                old = shapes[0].centroid
                legacy = {
                    "legacy_external_id": old_id,
                    "legacy_point": (float(old.y), float(old.x)),
                }
            yield Candidate(
                source=self.SOURCE_NAME,
                source_external_id=key,
                source_dataset_version=self._version,
                name=_site_name(first),
                latitude=lat,
                longitude=lng,
                coord_quality=CoordQuality.BUILDING_POLYGON,
                category=RestrictionTag.FEDERAL_PROPERTY,
                state=state,
                extra={"component": first.get("SITEREPORTINGCOMPONENT") or first.get("component")},
                **legacy,
            )
```

In `importer/config.yaml`, replace the `hifld_military:` block with:

```yaml
  hifld_military:
    # MIRTA DoD Sites, USACE-owned feature service (owner usace_crrel_als); the
    # legacy HIFLD Open hub was deactivated 2025-08-26. Each /query endpoint
    # returns GeoJSON in one GET (maxRecordCount 1000 > 825 boundaries / 737 points).
    #   url        = layer 1, "DoD Sites - Boundaries" (polygons)
    #   points_url = layer 0, "DoD Sites - Point" (the DoD-placed point per site;
    #                the pin goes there when it lies on the base)
    cache_dir: "data/sources/hifld_military"
    dataset_version: "MIRTA-2026-06"
    url: "https://services7.arcgis.com/n1YM8pTrFmm7L4hs/arcgis/rest/services/mirta/FeatureServer/1/query?where=1%3D1&outFields=*&outSR=4326&f=geojson"
    points_url: "https://services7.arcgis.com/n1YM8pTrFmm7L4hs/arcgis/rest/services/mirta/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson"
```

In `importer/importer/cli.py` `_build_source`, replace the `hifld_military` branch with:

```python
    if name == "hifld_military":
        return HifldMilitarySource(
            cache_path=cache_dir / "military.geojson",
            points_cache_path=cache_dir / "military_points.geojson",
            state_locator=locator, dataset_version=version,
            url=url, points_url=cfg.get("points_url", ""),
        )
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run pytest tests/sources/test_hifld_military.py tests/test_cli.py -v`
Expected: all PASS.

- [ ] **Step 6: Check it against the real layers**

`fetch()` downloads only the missing points layer (a read-only public GET). Run from `importer/`:

```bash
uv run python -c "
from importer.cli import REPO_ROOT, STATES_BOUNDARY_FIXTURE, _build_source, _load_config
from importer.geo.states import load_state_locator
src = _build_source('hifld_military', config=_load_config(), locator=load_state_locator(STATES_BOUNDARY_FIXTURE), repo_root=REPO_ROOT)
src.fetch()
cands = list(src.iter_candidates(state_filter={'TX', 'FL', 'PA'}))
print(len(cands), 'candidates;', sum(c.legacy_external_id is not None for c in cands), 'with legacy ids;', dict(src.last_skip_counts))
"
```

Expected: about 102 candidates, about 25 with legacy ids, and `closed` among the skip counts. (`data/sources/` is git-ignored; this only refreshes the local cache.)

- [ ] **Step 7: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/sources/hifld_military.py importer/importer/cli.py importer/config.yaml importer/tests/sources/test_hifld_military.py importer/tests/test_cli.py importer/tests/fixtures/make_hifld_military_samples.py importer/tests/fixtures/hifld_military_sample.geojson importer/tests/fixtures/hifld_military_points_sample.geojson
git commit -m "feat(importer): MIRTA site keys, merged records, DoD site points, skip closed sites"
```

---

### Task 4: Drop the federal courthouse fallback cell

**Files:**
- Modify: `data/state_laws/states.yaml:41-54`, `data/state_laws/README.md`, `docs/importer/OMISSIONS.md`
- Test: `importer/tests/test_state_laws.py`

**Interfaces:**
- Produces: no `state: US` cell whose `source_filter` contains `hifld_courts`. `hifld_courts` candidates outside TX/FL/PA drop at `apply_state_law` and appear in `missing_cells`.

- [ ] **Step 1: Write the failing tests**

Append to `importer/tests/test_state_laws.py`:

```python
def test_no_us_cell_claims_courthouses():
    # HIFLD courthouses are state and county courts (4 federal-looking names in
    # 3,713). 18 USC 930 covers federal courthouses, which come from GSA. Each
    # state needs its own court cell; there is no federal fallback.
    table = load_state_laws(PROD_TABLE)
    for row in table.rows:
        if row.state == "US":
            assert "hifld_courts" not in (row.source_filter or []), row


def test_tx_courthouse_resolves_to_the_tx_cell():
    stats = ApplyStateLawStats()
    out = list(apply_state_law(
        [_candidate("hifld_courts", "TX", RestrictionTag.STATE_LOCAL_GOVT)],
        table=load_state_laws(PROD_TABLE), stats=stats,
    ))
    assert len(out) == 1
    assert out[0].cell.state == "TX"
    assert out[0].cell.citation == "TX Penal Code §46.03(a)(3)"


def test_courthouse_in_a_state_without_a_cell_drops_and_is_reported():
    stats = ApplyStateLawStats()
    out = list(apply_state_law(
        [_candidate("hifld_courts", "GA", RestrictionTag.STATE_LOCAL_GOVT)],
        table=load_state_laws(PROD_TABLE), stats=stats,
    ))
    assert out == []
    assert stats.dropped_no_cell == 1
    assert ("GA", "STATE_LOCAL_GOVT") in stats.missing_cells
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_state_laws.py -v`
Expected: `test_no_us_cell_claims_courthouses` and `test_courthouse_in_a_state_without_a_cell_drops_and_is_reported` FAIL (GA resolves to the US cell). The TX test passes.

- [ ] **Step 3: Delete the cell and document why**

In `data/state_laws/states.yaml`, delete the whole `- state: US` / `category: STATE_LOCAL_GOVT` cell (the 14 lines from `- state: US` above `category: STATE_LOCAL_GOVT` through its `take precedence via lookup ordering.` notes line). Then add this comment at the end of the federal-uniform section, just before `# ── Texas`:

```yaml
# No US STATE_LOCAL_GOVT cell (removed 2026-10). HIFLD courthouses are state
# and county courts; 18 USC §930 covers only federal courthouses, which come
# from GSA. A courthouse in a state without its own STATE_LOCAL_GOVT cell drops
# and is listed under "needs research". See docs/importer/OMISSIONS.md.
```

In `data/state_laws/README.md`, replace the Phase 2 coverage row's cell text with `` `(US, STATE_LOCAL_GOVT)` only — proves the loader and one HIFLD source end-to-end. Removed 2026-10: there is no federal courthouse fallback (see `docs/importer/OMISSIONS.md`). ``

Append to `docs/importer/OMISSIONS.md`:

```markdown
## No federal courthouse fallback (2026-10)

There is no `state: US` `STATE_LOCAL_GOVT` cell. It used to cite 18 USC §930
for every `hifld_courts` courthouse in a state without its own cell, but HIFLD
Courthouses lists state and county courts: only 4 of 3,713 names look federal,
and 3 of those are in territories. Federal courthouses already come from GSA
(`FEDERAL_PROPERTY`). Outside TX/FL/PA, courthouse candidates drop at
`apply_state_law` and appear in the dry-run "needs research" list until that
state gets its own court cell. That list entry is expected, not a gap.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/test_state_laws.py tests/sources/test_osm.py -v`
Expected: all PASS. (`test_osm.py` loads the real table; the OSM scope doesn't use this cell.)

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add data/state_laws/states.yaml data/state_laws/README.md docs/importer/OMISSIONS.md importer/tests/test_state_laws.py
git commit -m "fix(state-laws): drop the federal courthouse fallback cell"
```

---

### Task 5: Supabase client: system-pin paging, re-key, delete, mark by id, un-mark on upsert

**Files:**
- Modify: `importer/importer/supabase_client.py`
- Modify: `importer/importer/stages/apply.py:63-69` (mark by id)
- Test: `importer/tests/test_supabase_client.py`, `importer/tests/stages/test_apply.py`

**Interfaces:**
- Produces on `SupabaseClient`:
  - `select_system_pins(source: str) -> list[ExistingPinRow]`: every pin with `source = source` and `created_by = system user`, ordered by id, paged 1,000 at a time with a `Range` header.
  - `patch_external_id(pin_id: str, new_external_id: str) -> None`: sets `source_external_id` and clears `source_orphaned_at`. Raises `RuntimeError` if no row changed.
  - `delete_pins(pin_ids: list[str]) -> list[str]`: deletes only system-owned, `user_modified = false` pins with those ids, and returns the ids actually deleted.
  - `mark_orphans(pin_ids: list[str]) -> None`: **signature changed** from `(source, external_ids)`.
  - `upsert_pins(rows)` now always sends `"source_orphaned_at": null`.
  - Constants `UUID_CHUNK_SIZE = 100`, `PAGE_SIZE = 1000`.
- `apply_to_supabase` keeps its signature for now and marks orphans by `row.id`.

- [ ] **Step 1: Write the failing tests**

In `importer/tests/test_supabase_client.py`, add `import json` at the top. Replace `test_mark_orphans_chunks_large_id_lists` with the mark test below, and append the rest:

```python
SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"


def _pin_json(i: int, **kw) -> dict:
    row = {
        "id": f"00000000-0000-0000-0000-{i:012d}", "source": "gsa",
        "source_external_id": f"E{i}", "name": f"P{i}", "latitude": 30.0,
        "longitude": -97.0, "status": 2, "restriction_tag": "FEDERAL_PROPERTY",
        "user_modified": False, "source_dataset_version": "v",
    }
    row.update(kw)
    return row


def _upsert_row(eid: str) -> SupabaseUpsertRow:
    return SupabaseUpsertRow(
        source="gsa", source_external_id=eid, source_dataset_version="v",
        name="P", latitude=30.0, longitude=-97.0, status=2,
        restriction_tag="FEDERAL_PROPERTY", has_security_screening=False,
        has_posted_signage=False, created_by=SYS, confidence="high",
        legal_citation="18 USC §930(a)", legal_citation_verified_date="2026-05-31",
    )


def test_select_system_pins_pages_until_a_short_page(client, httpx_mock):
    httpx_mock.add_response(method="GET", match_headers={"Range": "0-999"},
                            json=[_pin_json(i) for i in range(1000)])
    httpx_mock.add_response(method="GET", match_headers={"Range": "1000-1999"},
                            json=[_pin_json(1000 + i) for i in range(5)])
    rows = client.select_system_pins("gsa")
    assert len(rows) == 1005
    url = str(httpx_mock.get_requests()[0].url)
    assert "source=eq.gsa" in url
    assert f"created_by=eq.{SYS}" in url
    assert "order=id" in url


def test_patch_external_id_rekeys_one_pin_and_clears_the_orphan_mark(client, httpx_mock):
    httpx_mock.add_response(method="PATCH", json=[{"id": "p1"}])
    client.patch_external_id("p1", "13-14-14000592")
    req = httpx_mock.get_requests()[0]
    assert "id=eq.p1" in str(req.url)
    assert json.loads(req.content) == {
        "source_external_id": "13-14-14000592", "source_orphaned_at": None,
    }


def test_patch_external_id_fails_loudly_when_no_row_changed(client, httpx_mock):
    httpx_mock.add_response(method="PATCH", json=[])
    with pytest.raises(RuntimeError, match="p1"):
        client.patch_external_id("p1", "X")


def test_delete_pins_only_deletes_uncorrected_system_pins(client, httpx_mock):
    httpx_mock.add_response(method="DELETE", json=[{"id": "a"}])
    assert client.delete_pins(["a", "b"]) == ["a"]
    url = str(httpx_mock.get_requests()[0].url)
    assert "id=in.%28a%2Cb%29" in url
    assert "user_modified=eq.false" in url
    assert f"created_by=eq.{SYS}" in url


def test_delete_pins_chunks_and_skips_empty(client, httpx_mock):
    assert client.delete_pins([]) == []
    httpx_mock.add_response(method="DELETE", json=[])
    client.delete_pins([f"00000000-0000-0000-0000-{i:012d}" for i in range(250)])
    reqs = httpx_mock.get_requests()
    assert len(reqs) == 3
    assert all(len(str(r.url)) < 8000 for r in reqs)


def test_mark_orphans_marks_by_pin_id_in_chunks(client, httpx_mock):
    httpx_mock.add_response(method="PATCH", status_code=204)
    client.mark_orphans([f"00000000-0000-0000-0000-{i:012d}" for i in range(250)])
    reqs = httpx_mock.get_requests()
    assert len(reqs) == 3
    assert all(len(str(r.url)) < 8000 for r in reqs)
    assert "id=in.%2800000000-0000-0000-0000-000000000000%2C" in str(reqs[0].url)
    assert json.loads(reqs[0].content) == {"source_orphaned_at": "now()"}


def test_upsert_pins_clears_the_orphan_mark(client, httpx_mock):
    # A record marked orphaned in an earlier run that reappears must be un-marked.
    httpx_mock.add_response(method="POST", status_code=201, json=[])
    client.upsert_pins([_upsert_row("E1")])
    body = json.loads(httpx_mock.get_requests()[0].content)
    assert body[0]["source_orphaned_at"] is None
    assert "imported_at" not in body[0]  # server default on insert, untouched on update
```

In `importer/tests/stages/test_apply.py`, change the mark assertion in `test_apply_writes_inserts_and_updates_and_marks_orphans` to:

```python
    # Orphan-marking by pin id.
    client.mark_orphans.assert_called_once_with(["00000000-0000-0000-0000-000000000099"])
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_supabase_client.py tests/stages/test_apply.py -v`
Expected: FAIL. `AttributeError: 'SupabaseClient' object has no attribute 'select_system_pins'` (and `patch_external_id`, `delete_pins`); the mark tests fail on the old signature; the upsert test fails with `KeyError: 'source_orphaned_at'`.

- [ ] **Step 3: Implement in `importer/importer/supabase_client.py`**

Under `ID_CHUNK_SIZE = 200`, add:

```python
    # Pin UUIDs per `in.(...)` request: 36 chars plus an encoded comma each,
    # so 100 ids keep a URL near 4 KB.
    UUID_CHUNK_SIZE = 100
    PAGE_SIZE = 1000
```

Change the comment on `SupabaseUpsertRow.source_orphaned_at` to `# sent as null on every upsert (see upsert_pins)`. In `upsert_pins`, replace the `batch = …` line with:

```python
            # exclude_none drops imported_at (server default on insert) but would
            # also drop source_orphaned_at; send it explicitly so a record that
            # comes back is no longer marked orphaned.
            batch = [
                {**r.model_dump(mode="json", exclude_none=True), "source_orphaned_at": None}
                for r in rows[i : i + batch_size]
            ]
```

Replace `mark_orphans` with:

```python
    def mark_orphans(self, pin_ids: list[str]) -> None:
        """Set source_orphaned_at = now() on these pins."""
        headers = dict(self._headers)
        headers["Prefer"] = "return=minimal"
        for i in range(0, len(pin_ids), self.UUID_CHUNK_SIZE):
            chunk = pin_ids[i : i + self.UUID_CHUNK_SIZE]
            r = self._client.patch(
                f"{self._base}/pins",
                headers=headers,
                params={"id": f"in.({','.join(chunk)})"},
                json={"source_orphaned_at": "now()"},
            )
            r.raise_for_status()
```

Add after `select_user_pins`:

```python
    def select_system_pins(self, source: str) -> list[ExistingPinRow]:
        """Every pin of `source` owned by the system user, i.e. every pin the
        importer wrote for it. Paged with a Range header; ordered by id so
        pages don't shift between requests."""
        out: list[ExistingPinRow] = []
        offset = 0
        while True:
            headers = dict(self._headers)
            headers["Range-Unit"] = "items"
            headers["Range"] = f"{offset}-{offset + self.PAGE_SIZE - 1}"
            params = {
                "select": self.SELECT_COLUMNS,
                "source": f"eq.{source}",
                "created_by": f"eq.{self._system_user_id}",
                "order": "id",
            }
            r = self._client.get(f"{self._base}/pins", headers=headers, params=params)
            r.raise_for_status()
            rows = r.json()
            out.extend(ExistingPinRow.model_validate(row) for row in rows)
            if len(rows) < self.PAGE_SIZE:
                return out
            offset += self.PAGE_SIZE

    def patch_external_id(self, pin_id: str, new_external_id: str) -> None:
        """Re-key one pin in place: its UUID and any user edits survive. A
        service-role write never sets user_modified (013)."""
        r = self._client.patch(
            f"{self._base}/pins",
            headers=self._headers,  # return=representation: count the rows changed
            params={"id": f"eq.{pin_id}", "select": "id"},
            json={"source_external_id": new_external_id, "source_orphaned_at": None},
        )
        r.raise_for_status()
        if not r.json():
            raise RuntimeError(f"re-key of pin {pin_id} changed no row; was it deleted mid-run?")

    def delete_pins(self, pin_ids: list[str]) -> list[str]:
        """Delete system-owned pins no user corrected; return the ids deleted.

        A pin a user corrected after the diff is left alone (the caller marks
        it instead). The record_pin_deletion trigger writes the tombstones; the
        delete rate limit skips service_role (008 §6c).
        """
        deleted: list[str] = []
        for i in range(0, len(pin_ids), self.UUID_CHUNK_SIZE):
            chunk = pin_ids[i : i + self.UUID_CHUNK_SIZE]
            r = self._client.delete(
                f"{self._base}/pins",
                headers=self._headers,  # return=representation: the ids deleted
                params={
                    "id": f"in.({','.join(chunk)})",
                    "user_modified": "eq.false",
                    "created_by": f"eq.{self._system_user_id}",
                    "select": "id",
                },
            )
            r.raise_for_status()
            deleted.extend(row["id"] for row in r.json())
        return deleted
```

In `importer/importer/stages/apply.py`, replace the orphan block at the end of `apply_to_supabase` with:

```python
    orphan_ids = [row.id for row in diff.orphans]
    if orphan_ids:
        client.mark_orphans(orphan_ids)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/test_supabase_client.py tests/stages/test_apply.py -v`
Expected: all PASS.

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/supabase_client.py importer/importer/stages/apply.py importer/tests/test_supabase_client.py importer/tests/stages/test_apply.py
git commit -m "feat(importer): client paging of system pins, re-key, delete and id-based orphan marking"
```

---

### Task 6: Diff stage: re-key by legacy id, orphans from the in-scope pins

**Files:**
- Rewrite: `importer/importer/stages/diff.py`
- Test: `importer/tests/stages/test_diff.py`

**Interfaces:**
- Consumes: `Candidate.legacy_external_id`, `Candidate.legacy_point` (Task 1); `meters_between` (Task 1).
- Produces:
  - `REKEY_MAX_M = 50.0`
  - `class Rekey(BaseModel)`: `pin_id: str`, `old_external_id: str`, `new_external_id: str`, `user_modified: bool`, `classified: ClassifiedCandidate`.
  - `DiffResult` gains `rekeys: list[Rekey] = []` and `rekey_too_far: int = 0`.
  - `DiffStats` gains `rekeys: int = 0` and `rekey_too_far: int = 0`.
  - `diff_candidates(classified, *, existing: list[ExistingPinRow], stats: DiffStats, in_scope: list[ExistingPinRow] | None = None) -> DiffResult`. `existing` is every system pin of the source; `in_scope` is the subset this run may orphan (default: all of `existing`).

- [ ] **Step 1: Write the failing tests**

Append to `importer/tests/stages/test_diff.py`:

```python
from importer.stages.diff import REKEY_MAX_M

FED = StateLawCell(
    state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
    confidence="high", conditions=[], citation="18 USC §930(a)",
    last_verified_date=date(2026, 5, 31),
)
SA = (29.4241, -98.4936)
LUBBOCK = (33.5779, -101.8552)


def _gsa(eid, legacy=None, legacy_point=SA):
    lat, lng = legacy_point
    return ClassifiedCandidate(
        candidate=Candidate(
            source="gsa", source_external_id=eid, source_dataset_version="FRPP-FY24",
            name=f"Building {eid}", latitude=lat, longitude=lng,
            coord_quality=CoordQuality.PRECISE, category=RestrictionTag.FEDERAL_PROPERTY,
            state="TX", legacy_external_id=legacy,
            legacy_point=legacy_point if legacy is not None else None,
        ),
        cell=FED,
    )


def _pin(eid, at=SA, *, pin_id=None, user_modified=False):
    return ExistingPinRow(
        id=pin_id or f"pin-{eid}", source="gsa", source_external_id=eid,
        name=f"Pin {eid}", latitude=at[0], longitude=at[1], status=2,
        restriction_tag="FEDERAL_PROPERTY", user_modified=user_modified,
        source_dataset_version="FRPP-FY24",
    )


def test_legacy_match_is_a_rekey() -> None:
    stats = DiffStats()
    result = diff_candidates([_gsa("13-14-140", legacy="140")], existing=[_pin("140")], stats=stats)
    assert [(r.pin_id, r.old_external_id, r.new_external_id) for r in result.rekeys] == [
        ("pin-140", "140", "13-14-140")
    ]
    assert result.inserts == [] and result.orphans == []
    assert stats.rekeys == 1


def test_colliding_legacy_ids_go_to_the_nearest_candidate() -> None:
    # Two agencies reported property id 140; the pin was the San Antonio one.
    # The Lubbock building comes first in file order and must not steal it.
    lubbock = _gsa("14-10-140", legacy="140", legacy_point=LUBBOCK)
    san_antonio = _gsa("13-14-140", legacy="140", legacy_point=SA)
    stats = DiffStats()
    result = diff_candidates([lubbock, san_antonio], existing=[_pin("140", SA)], stats=stats)
    assert [r.new_external_id for r in result.rekeys] == ["13-14-140"]
    assert [cc.candidate.source_external_id for cc in result.inserts] == ["14-10-140"]
    assert result.rekey_too_far == 0 and stats.rekey_too_far == 0


def test_legacy_pin_too_far_is_an_insert_an_orphan_and_counted() -> None:
    far = (SA[0] + (REKEY_MAX_M + 30) / 111_320.0, SA[1])  # 80 m north
    stats = DiffStats()
    result = diff_candidates([_gsa("13-14-140", legacy="140", legacy_point=far)],
                             existing=[_pin("140", SA)], stats=stats)
    assert result.rekeys == []
    assert [cc.candidate.source_external_id for cc in result.inserts] == ["13-14-140"]
    assert [row.source_external_id for row in result.orphans] == ["140"]
    assert result.rekey_too_far == 1 and stats.rekey_too_far == 1


def test_user_corrected_pin_is_rekeyed_and_flagged() -> None:
    result = diff_candidates([_gsa("13-14-140", legacy="140")],
                             existing=[_pin("140", user_modified=True)], stats=DiffStats())
    assert [r.user_modified for r in result.rekeys] == [True]
    assert result.skips == [] and result.updates == []


def test_a_new_id_match_wins_over_a_legacy_match() -> None:
    existing = [_pin("13-14-140", pin_id="already-rekeyed"), _pin("140", pin_id="legacy")]
    result = diff_candidates([_gsa("13-14-140", legacy="140")], existing=existing, stats=DiffStats())
    assert [cc.candidate.source_external_id for cc in result.updates] == ["13-14-140"]
    assert result.rekeys == []
    assert [row.id for row in result.orphans] == ["legacy"]


def test_a_second_run_is_update_only() -> None:
    cands = [_gsa("13-14-140", legacy="140"), _gsa("47-00-200", legacy="200", legacy_point=LUBBOCK)]
    first = diff_candidates(cands, existing=[_pin("140", SA), _pin("200", LUBBOCK)], stats=DiffStats())
    assert len(first.rekeys) == 2
    rekeyed = [_pin(r.new_external_id, pin_id=r.pin_id,
                    at=(r.classified.candidate.latitude, r.classified.candidate.longitude))
               for r in first.rekeys]
    second = diff_candidates(cands, existing=rekeyed, stats=DiffStats())
    assert len(second.updates) == 2
    assert second.rekeys == [] and second.inserts == [] and second.orphans == []


def test_partial_apply_rerun_resolves_without_duplicates() -> None:
    # The apply crashed after re-keying 140 but before 200: one pin carries its
    # new id, the other still its legacy id.
    cands = [_gsa("13-14-140", legacy="140"), _gsa("47-00-200", legacy="200", legacy_point=LUBBOCK)]
    existing = [_pin("13-14-140", SA, pin_id="pin-140"), _pin("200", LUBBOCK)]
    result = diff_candidates(cands, existing=existing, stats=DiffStats())
    assert [cc.candidate.source_external_id for cc in result.updates] == ["13-14-140"]
    assert [r.new_external_id for r in result.rekeys] == ["47-00-200"]
    assert result.inserts == [] and result.orphans == []


def test_orphans_come_only_from_in_scope_pins() -> None:
    tx, fl = _pin("TX-GONE"), _pin("FL-GONE", (25.77, -80.19))
    result = diff_candidates([], existing=[tx, fl], in_scope=[tx], stats=DiffStats())
    assert [row.source_external_id for row in result.orphans] == ["TX-GONE"]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/stages/test_diff.py -v`
Expected: `ImportError: cannot import name 'REKEY_MAX_M'`.

- [ ] **Step 3: Rewrite `importer/importer/stages/diff.py`**

```python
"""Classify each ClassifiedCandidate against the source's existing pins.

Pass 1 matches a candidate to the pin carrying its own source_external_id:
an update, or a skip when a user corrected that pin. Pass 2 re-keys pins
whose id scheme changed: a candidate carrying a legacy id takes over the pin
with that id when the pin sits within REKEY_MAX_M of where the old code put
the record. Closest pairs go first, so the order a source yields records in
doesn't decide which record inherits a shared old id. Every other candidate
is an insert. In-scope pins neither pass claimed are orphans: their record
is gone, or lost cross-source dedup.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from pydantic import BaseModel, ConfigDict, Field

from importer.geo.distance import meters_between
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.supabase_client import ExistingPinRow

# A legacy pin is re-keyed only this close to the record's old position;
# farther means the old id now belongs to a different record.
REKEY_MAX_M = 50.0


class Rekey(BaseModel):
    """An existing pin taking a new source_external_id; its UUID survives."""

    model_config = ConfigDict(frozen=True)

    pin_id: str
    old_external_id: str
    new_external_id: str
    user_modified: bool
    classified: ClassifiedCandidate


class DiffResult(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True, frozen=True)

    inserts: list[ClassifiedCandidate]
    updates: list[ClassifiedCandidate]
    skips: list[ClassifiedCandidate]   # user_modified rows we leave alone
    orphans: list[ExistingPinRow]      # in scope, claimed by no candidate
    rekeys: list[Rekey] = Field(default_factory=list)
    # Legacy pins that had candidates but none within REKEY_MAX_M. Those
    # candidates were inserted, and the old pin is left as an orphan.
    rekey_too_far: int = 0


@dataclass
class DiffStats:
    inserts: int = 0
    updates: int = 0
    skips: int = 0
    orphans: int = 0
    rekeys: int = 0
    rekey_too_far: int = 0


def diff_candidates(
    classified: Iterable[ClassifiedCandidate],
    *,
    existing: list[ExistingPinRow],
    stats: DiffStats,
    in_scope: list[ExistingPinRow] | None = None,
) -> DiffResult:
    """`existing`: every pin of the source. `in_scope`: the pins this run may
    orphan (default: all of `existing`)."""
    by_eid = {row.source_external_id: row for row in existing if row.source_external_id}
    claimed: set[str] = set()
    updates: list[ClassifiedCandidate] = []
    skips: list[ClassifiedCandidate] = []
    pending: list[ClassifiedCandidate] = []

    # Pass 1: the candidate's own id.
    for cc in classified:
        row = by_eid.get(cc.candidate.source_external_id)
        if row is None or row.id in claimed:
            pending.append(cc)
            continue
        claimed.add(row.id)
        (skips if row.user_modified else updates).append(cc)

    # Pass 2: legacy ids, closest candidate-pin pairs first.
    pairs: list[tuple[float, int, ExistingPinRow]] = []
    for i, cc in enumerate(pending):
        c = cc.candidate
        if c.legacy_external_id is None or c.legacy_point is None:
            continue
        row = by_eid.get(c.legacy_external_id)
        if row is None or row.id in claimed:
            continue
        lat, lng = c.legacy_point
        pairs.append((meters_between(lat, lng, row.latitude, row.longitude), i, row))

    matched: dict[int, Rekey] = {}
    for dist, i, row in sorted(pairs, key=lambda p: (p[0], p[1])):
        if dist > REKEY_MAX_M or i in matched or row.id in claimed:
            continue
        claimed.add(row.id)
        cc = pending[i]
        matched[i] = Rekey(
            pin_id=row.id,
            old_external_id=row.source_external_id,
            new_external_id=cc.candidate.source_external_id,
            user_modified=row.user_modified,
            classified=cc,
        )
    too_far = {row.id for _, _, row in pairs if row.id not in claimed}

    rekeys = [matched[i] for i in sorted(matched)]
    inserts = [cc for i, cc in enumerate(pending) if i not in matched]
    scope = existing if in_scope is None else in_scope
    orphans = [row for row in scope if row.id not in claimed]

    stats.inserts = len(inserts)
    stats.updates = len(updates)
    stats.skips = len(skips)
    stats.orphans = len(orphans)
    stats.rekeys = len(rekeys)
    stats.rekey_too_far = len(too_far)
    return DiffResult(
        inserts=inserts, updates=updates, skips=skips, orphans=orphans,
        rekeys=rekeys, rekey_too_far=len(too_far),
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/stages/test_diff.py -v`
Expected: all PASS, including the four original tests.

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/stages/diff.py importer/tests/stages/test_diff.py
git commit -m "feat(importer): diff re-keys pins by legacy id; orphans from in-scope pins"
```

---

### Task 7: Orphan planning: state scope, delete/keep/mark, the cap

**Files:**
- Create: `importer/importer/stages/orphans.py`
- Test: `importer/tests/stages/test_orphans.py` (create)

**Interfaces:**
- Consumes: `ExistingPinRow`; `StateLocator.state_for(lat, lng) -> str | None`.
- Produces:
  - `MIN_DELETE_CAP = 50`, `DELETE_CAP_PCT = 5`
  - `class OrphanCapExceeded(RuntimeError)`
  - `default_cap(in_scope_count: int) -> int`
  - `scope_to_states(rows: Iterable[ExistingPinRow], *, states: set[str] | None, locator: StateLocator | None) -> list[ExistingPinRow]`
  - `@dataclass(frozen=True) class OrphanPlan`: `delete`, `keep`, `mark` (each `list[ExistingPinRow]`), `cap: int = MIN_DELETE_CAP`; properties `breached: bool` (`len(delete) > cap`) and `marked_count: int` (`len(keep) + len(mark)`); method `actions() -> list[tuple[ExistingPinRow, str]]` with actions `"delete"`, `"keep"`, `"mark"`.
  - `plan_orphans(orphans: Iterable[ExistingPinRow], *, in_scope_count: int, delete: bool, cap: int | None = None) -> OrphanPlan`

- [ ] **Step 1: Write the failing tests**

Create `importer/tests/stages/test_orphans.py`:

```python
from pathlib import Path

import pytest

from importer.geo.states import load_state_locator
from importer.stages.orphans import (
    OrphanPlan,
    default_cap,
    plan_orphans,
    scope_to_states,
)
from importer.supabase_client import ExistingPinRow

LOCATOR = load_state_locator(Path(__file__).parents[1] / "fixtures" / "states_sample.geojson")
AUSTIN, MIAMI, NULL_ISLAND = (30.27, -97.74), (25.77, -80.19), (0.5, 0.5)


def _pin(pid, at=AUSTIN, *, user_modified=False):
    return ExistingPinRow(
        id=pid, source="gsa", source_external_id=f"E-{pid}", name=pid,
        latitude=at[0], longitude=at[1], status=2, restriction_tag="FEDERAL_PROPERTY",
        user_modified=user_modified, source_dataset_version="v",
    )


@pytest.mark.parametrize("in_scope, cap", [(0, 50), (1000, 50), (1019, 50), (4221, 211), (20000, 1000)])
def test_default_cap_is_50_or_5_percent(in_scope, cap):
    assert default_cap(in_scope) == cap


def test_mark_mode_marks_every_orphan_and_never_breaches():
    orphans = [_pin(f"p{i}") for i in range(500)]
    plan = plan_orphans(orphans, in_scope_count=500, delete=False)
    assert plan.mark == orphans and plan.delete == [] and plan.keep == []
    assert not plan.breached
    assert plan.marked_count == 500


def test_delete_mode_keeps_user_corrected_pins():
    gone, fixed = _pin("gone"), _pin("fixed", user_modified=True)
    plan = plan_orphans([gone, fixed], in_scope_count=10, delete=True)
    assert plan.delete == [gone] and plan.keep == [fixed] and plan.mark == []
    assert plan.marked_count == 1
    assert plan.actions() == [(gone, "delete"), (fixed, "keep")]


def test_cap_breaches_only_past_the_cap():
    at_cap = plan_orphans([_pin(f"p{i}") for i in range(50)], in_scope_count=100, delete=True)
    assert at_cap.cap == 50 and not at_cap.breached
    over = plan_orphans([_pin(f"p{i}") for i in range(51)], in_scope_count=100, delete=True)
    assert over.breached


def test_cap_override_replaces_the_default():
    plan = plan_orphans([_pin(f"p{i}") for i in range(51)], in_scope_count=100, delete=True, cap=100)
    assert plan.cap == 100 and not plan.breached


def test_empty_plan_is_the_default():
    assert OrphanPlan().marked_count == 0 and not OrphanPlan().breached


def test_scope_keeps_only_pins_in_the_run_states():
    tx, fl = _pin("tx", AUSTIN), _pin("fl", MIAMI)
    assert scope_to_states([tx, fl], states={"TX"}, locator=LOCATOR) == [tx]
    assert scope_to_states([tx, fl], states=None, locator=None) == [tx, fl]


def test_pin_outside_every_state_is_never_in_scope():
    stray = _pin("stray", NULL_ISLAND)
    assert scope_to_states([stray], states={"TX", "FL", "PA"}, locator=LOCATOR) == []


def test_scoping_by_state_needs_a_locator():
    assert scope_to_states([], states={"TX"}, locator=None) == []
    with pytest.raises(ValueError, match="state_locator"):
        scope_to_states([_pin("tx")], states={"TX"}, locator=None)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/stages/test_orphans.py -v`
Expected: `ModuleNotFoundError: No module named 'importer.stages.orphans'`.

- [ ] **Step 3: Implement `importer/importer/stages/orphans.py`**

```python
"""Which orphans an apply deletes, keeps or marks, and the per-source cap.

An orphan is a system pin, inside the run's states, that no record claimed:
the record left the dataset, or lost cross-source dedup. A plain apply marks
orphans (source_orphaned_at). With --delete-orphans it deletes them, except
pins a user corrected, which are kept and marked. Deletions per source are
capped so a truncated download can't wipe a layer.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field

from importer.geo.states import StateLocator
from importer.supabase_client import ExistingPinRow

MIN_DELETE_CAP = 50
DELETE_CAP_PCT = 5


class OrphanCapExceeded(RuntimeError):
    """A source would delete more orphans than its cap; nothing was written."""


def default_cap(in_scope_count: int) -> int:
    """max(50, 5% of the source's in-scope pins)."""
    return max(MIN_DELETE_CAP, in_scope_count * DELETE_CAP_PCT // 100)


def scope_to_states(
    rows: Iterable[ExistingPinRow],
    *,
    states: set[str] | None,
    locator: StateLocator | None,
) -> list[ExistingPinRow]:
    """The pins a run may orphan: those inside its states. Pins have no state
    column, so the polygons the sources use decide. A pin outside every
    polygon is never in scope for a state-filtered run."""
    rows = list(rows)
    if states is None or not rows:
        return rows
    if locator is None:
        raise ValueError("a state_locator is required to scope orphans to states")
    return [r for r in rows if locator.state_for(r.latitude, r.longitude) in states]


@dataclass(frozen=True)
class OrphanPlan:
    delete: list[ExistingPinRow] = field(default_factory=list)
    keep: list[ExistingPinRow] = field(default_factory=list)  # user-corrected: marked, never deleted
    mark: list[ExistingPinRow] = field(default_factory=list)
    cap: int = MIN_DELETE_CAP

    @property
    def breached(self) -> bool:
        return len(self.delete) > self.cap

    @property
    def marked_count(self) -> int:
        """Pins whose source_orphaned_at the apply sets (import_runs.orphans_marked)."""
        return len(self.keep) + len(self.mark)

    def actions(self) -> list[tuple[ExistingPinRow, str]]:
        return (
            [(r, "delete") for r in self.delete]
            + [(r, "keep") for r in self.keep]
            + [(r, "mark") for r in self.mark]
        )


def plan_orphans(
    orphans: Iterable[ExistingPinRow],
    *,
    in_scope_count: int,
    delete: bool,
    cap: int | None = None,
) -> OrphanPlan:
    """`delete=False`: mark every orphan. `delete=True`: delete the ones no
    user corrected and keep (mark) the rest. `cap` overrides default_cap()."""
    orphans = list(orphans)
    limit = default_cap(in_scope_count) if cap is None else cap
    if not delete:
        return OrphanPlan(mark=orphans, cap=limit)
    return OrphanPlan(
        delete=[o for o in orphans if not o.user_modified],
        keep=[o for o in orphans if o.user_modified],
        cap=limit,
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/stages/test_orphans.py -v`
Expected: all PASS.

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/stages/orphans.py importer/tests/stages/test_orphans.py
git commit -m "feat(importer): orphan plan with state scope and per-source delete cap"
```

---

### Task 8: Apply stage: re-keys first, then upsert, then the orphan plan

**Files:**
- Modify: `importer/importer/stages/apply.py`
- Modify: `importer/importer/pipeline.py:72` (drop `source=name` from the call)
- Test: `importer/tests/stages/test_apply.py`

**Interfaces:**
- Consumes: `DiffResult.rekeys`, `Rekey` (Task 6); `OrphanPlan`, `plan_orphans` (Task 7); `client.patch_external_id`, `client.delete_pins`, `client.mark_orphans(ids)`, `client.upsert_pins` (Task 5).
- Produces: `apply_to_supabase(diff: DiffResult, *, client: SupabaseClient, system_user_id: str, orphan_plan: OrphanPlan | None = None) -> None`. **The `source` parameter is removed.** `orphan_plan=None` means "mark every orphan".

- [ ] **Step 1: Write the failing tests**

In `importer/tests/stages/test_apply.py`: remove `source="hifld_courts",` from the three existing `apply_to_supabase(...)` calls, **replace** the existing `_orphan` helper with the one below (existing `_orphan("Z")` calls keep working), and append the rest:

```python
from importer.stages.diff import Rekey
from importer.stages.orphans import OrphanPlan

SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"


def _orphan(eid: str, *, pin_id: str = "00000000-0000-0000-0000-000000000099",
            user_modified: bool = False) -> ExistingPinRow:
    return ExistingPinRow(
        id=pin_id, source="hifld_courts", source_external_id=eid, name="X",
        latitude=0.0, longitude=0.0, status=2, restriction_tag="STATE_LOCAL_GOVT",
        user_modified=user_modified, source_dataset_version="old",
    )


def _rekey(new: str, *, user_modified: bool) -> Rekey:
    return Rekey(pin_id=f"pin-{new}", old_external_id=" ", new_external_id=new,
                 user_modified=user_modified, classified=_classified(new))


def _empty_diff(**kw) -> DiffResult:
    return DiffResult(**{"inserts": [], "updates": [], "skips": [], "orphans": [], **kw})


def test_rekeys_are_patched_before_the_upsert_and_refreshed_unless_corrected() -> None:
    client = MagicMock()
    diff = _empty_diff(inserts=[_classified("A")],
                       rekeys=[_rekey("R1", user_modified=False), _rekey("R2", user_modified=True)])
    apply_to_supabase(diff, client=client, system_user_id=SYS)
    assert [c[0] for c in client.mock_calls][:3] == ["patch_external_id", "patch_external_id", "upsert_pins"]
    client.patch_external_id.assert_any_call("pin-R1", "R1")
    client.patch_external_id.assert_any_call("pin-R2", "R2")
    rows = client.upsert_pins.call_args.args[0]
    # The corrected pin keeps its edits: re-keyed, but not refreshed.
    assert {r.source_external_id for r in rows} == {"A", "R1"}


def test_delete_plan_deletes_and_marks_the_user_corrected() -> None:
    client = MagicMock()
    gone, fixed = _orphan("G", pin_id="g"), _orphan("F", pin_id="f", user_modified=True)
    client.delete_pins.return_value = ["g"]
    apply_to_supabase(_empty_diff(orphans=[gone, fixed]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(delete=[gone], keep=[fixed]))
    client.delete_pins.assert_called_once_with(["g"])
    client.mark_orphans.assert_called_once_with(["f"])


def test_pin_corrected_after_the_diff_is_marked_not_deleted() -> None:
    # The DELETE filters on user_modified = false, so a pin corrected between
    # the diff and the apply survives the delete; it must still be marked.
    client = MagicMock()
    a, b = _orphan("A", pin_id="a"), _orphan("B", pin_id="b")
    client.delete_pins.return_value = ["a"]
    apply_to_supabase(_empty_diff(orphans=[a, b]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(delete=[a, b]))
    client.mark_orphans.assert_called_once_with(["b"])


def test_mark_plan_never_deletes() -> None:
    client = MagicMock()
    o = _orphan("Z", pin_id="z")
    apply_to_supabase(_empty_diff(orphans=[o]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(mark=[o]))
    client.delete_pins.assert_not_called()
    client.mark_orphans.assert_called_once_with(["z"])
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/stages/test_apply.py -v`
Expected: FAIL. `TypeError: apply_to_supabase() missing 1 required keyword-only argument: 'source'` on the edited calls, and `unexpected keyword argument 'orphan_plan'`.

- [ ] **Step 3: Implement in `importer/importer/stages/apply.py`**

Add the import `from importer.stages.orphans import OrphanPlan, plan_orphans`, and replace `apply_to_supabase` with:

```python
def apply_to_supabase(
    diff: DiffResult,
    *,
    client: SupabaseClient,
    system_user_id: str,
    orphan_plan: OrphanPlan | None = None,
) -> None:
    """Write one source's diff.

    Re-keys go first, so the upsert (keyed on source + source_external_id)
    refreshes re-keyed pins instead of inserting duplicates. A user-corrected
    pin is re-keyed but not refreshed: its edits stay. Orphans follow
    `orphan_plan` (default: mark them all).
    """
    for rk in diff.rekeys:
        client.patch_external_id(rk.pin_id, rk.new_external_id)

    refreshed = diff.inserts + diff.updates + [
        rk.classified for rk in diff.rekeys if not rk.user_modified
    ]
    rows = [_to_upsert_row(cc, system_user_id=system_user_id) for cc in refreshed]
    if rows:
        client.upsert_pins(rows)

    plan = orphan_plan or plan_orphans(diff.orphans, in_scope_count=0, delete=False)
    to_mark = [row.id for row in plan.keep + plan.mark]
    if plan.delete:
        wanted = [row.id for row in plan.delete]
        deleted = set(client.delete_pins(wanted))
        # Corrected by a user after the diff, so the delete skipped it: mark it.
        to_mark += [pid for pid in wanted if pid not in deleted]
    if to_mark:
        client.mark_orphans(to_mark)
```

In `importer/importer/pipeline.py`, change the call to `apply_to_supabase(diff_result, client=client, system_user_id=system_user_id)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/stages/test_apply.py tests/test_pipeline.py -v`
Expected: all PASS.

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/stages/apply.py importer/importer/pipeline.py importer/tests/stages/test_apply.py
git commit -m "feat(importer): apply re-keys before upsert and follows the orphan plan"
```

---

### Task 9: Pipeline: diff every source, check every cap, then write

**Files:**
- Rewrite: `importer/importer/pipeline.py`
- Modify: `importer/importer/reports/__init__.py` (`SourceResult` fields)
- Modify: `importer/importer/supabase_client.py` (remove `select_pins_by_keys` and `ID_CHUNK_SIZE`)
- Test: `importer/tests/test_pipeline.py`, `importer/tests/test_supabase_client.py`

**Interfaces:**
- Consumes: `client.select_system_pins` (Task 5); `diff_candidates(..., in_scope=...)` (Task 6); `scope_to_states`, `plan_orphans`, `OrphanCapExceeded` (Task 7); `apply_to_supabase(..., orphan_plan=...)` (Task 8).
- Produces:
  - `run_pipeline(*, sources, state_laws, client, states, mode, system_user_id, refetch=False, state_locator: StateLocator | None = None, delete_orphans: bool = False, orphan_delete_cap: int | None = None) -> PipelineResult`. It raises `ValueError` when `delete_orphans` is set outside apply mode, and `OrphanCapExceeded` (before any write) when an apply with `delete_orphans` breaches a cap. A dry-run plans deletes and lists breaches in `PipelineResult.errors`.
  - `SourceResult.orphan_plan: OrphanPlan = field(default_factory=OrphanPlan)`, `SourceResult.skip_counts: dict[str, int] = field(default_factory=dict)`.

- [ ] **Step 1: Write the failing tests**

In `importer/tests/test_pipeline.py`, change `_mock_client` to:

```python
def _mock_client():
    client = MagicMock()
    client.select_system_pins.return_value = []
    client.select_user_pins.return_value = []
    return client
```

Change `_FakeSource.__init__` to take `skips=None` and set `self.last_skip_counts = dict(skips or {})`. Then append:

```python
import pytest

from importer.stages.orphans import OrphanCapExceeded
from importer.supabase_client import ExistingPinRow

LOCATOR = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"
AUSTIN, MIAMI = (30.27, -97.74), (25.77, -80.19)


def _pin(pid, at=AUSTIN, *, source="gsa", eid=None, user_modified=False):
    return ExistingPinRow(
        id=pid, source=source, source_external_id=eid or f"E-{pid}", name=f"Pin {pid}",
        latitude=at[0], longitude=at[1], status=2, restriction_tag="FEDERAL_PROPERTY",
        user_modified=user_modified, source_dataset_version="v",
    )


def _client_with(pins_by_source):
    client = _mock_client()
    client.select_system_pins.side_effect = lambda name: pins_by_source.get(name, [])
    return client


def _run(sources, client, *, mode="apply", states=("TX",), **kw):
    return run_pipeline(
        sources=sources, state_laws=_table(), client=client, states=list(states),
        mode=mode, system_user_id=SYS, state_locator=LOCATOR, **kw,
    )


def test_orphans_are_scoped_to_the_run_states():
    tx, fl = _pin("tx", AUSTIN), _pin("fl", MIAMI)
    result = _run([_FakeSource("gsa", [])], _client_with({"gsa": [tx, fl]}), mode="dry-run")
    assert result.sources[0].diff.orphans == [tx]


def test_default_apply_marks_orphans_and_deletes_nothing():
    client = _client_with({"gsa": [_pin("tx")]})
    _run([_FakeSource("gsa", [])], client)
    client.mark_orphans.assert_called_once_with(["tx"])
    client.delete_pins.assert_not_called()


def test_delete_orphans_deletes_uncorrected_and_marks_corrected():
    gone, fixed = _pin("gone"), _pin("fixed", user_modified=True)
    client = _client_with({"gsa": [gone, fixed]})
    client.delete_pins.return_value = ["gone"]
    _run([_FakeSource("gsa", [])], client, delete_orphans=True)
    client.delete_pins.assert_called_once_with(["gone"])
    client.mark_orphans.assert_called_once_with(["fixed"])


def _over_cap_run(**kw):
    # gsa would insert one pin; military would delete 51 of its 51 in-scope pins (cap 50).
    gsa = _FakeSource("gsa", [_cand("gsa", "g1", "Federal Building Austin", 30.2672, -97.7431)])
    mil = _FakeSource("hifld_military", [])
    client = _client_with({"hifld_military": [_pin(f"m{i}", source="hifld_military") for i in range(51)]})
    return client, (lambda mode: _run([gsa, mil], client, mode=mode, **kw))


def test_cap_breach_stops_the_apply_before_any_write():
    client, run = _over_cap_run(delete_orphans=True)
    with pytest.raises(OrphanCapExceeded, match="hifld_military: 51 orphan deletions exceed the cap of 50"):
        run("apply")
    for write in ("upsert_pins", "patch_external_id", "delete_pins", "mark_orphans"):
        getattr(client, write).assert_not_called()


def test_dry_run_reports_a_cap_breach_as_an_error():
    client, run = _over_cap_run()
    result = run("dry-run")
    assert any("hifld_military: 51 orphan deletions exceed the cap of 50" in e for e in result.errors)
    client.delete_pins.assert_not_called()


def test_cap_override_lets_a_large_deletion_through():
    client, run = _over_cap_run(delete_orphans=True, orphan_delete_cap=100)
    client.delete_pins.return_value = [f"m{i}" for i in range(51)]
    run("apply")
    assert len(client.delete_pins.call_args.args[0]) == 51


def test_rekey_flows_from_source_to_writes():
    cand = Candidate(
        source="gsa", source_external_id="13-14-140", source_dataset_version="v",
        name="San Antonio Federal Center", latitude=29.4241, longitude=-98.4936,
        coord_quality=CoordQuality.PRECISE, category=RestrictionTag.FEDERAL_PROPERTY,
        state="TX", legacy_external_id="140", legacy_point=(29.4241, -98.4936),
    )
    client = _client_with({"gsa": [_pin("pin-140", (29.4241, -98.4936), eid="140")]})
    result = _run([_FakeSource("gsa", [cand])], client)
    assert [r.pin_id for r in result.sources[0].diff.rekeys] == ["pin-140"]
    client.patch_external_id.assert_called_once_with("pin-140", "13-14-140")
    assert [r.source_external_id for r in client.upsert_pins.call_args.args[0]] == ["13-14-140"]
    client.mark_orphans.assert_not_called()


def test_delete_orphans_is_rejected_outside_apply():
    with pytest.raises(ValueError, match="apply-only"):
        _run([_FakeSource("gsa", [])], _mock_client(), mode="dry-run", delete_orphans=True)


def test_skip_counts_reach_the_result():
    result = _run([_FakeSource("gsa", [], skips={"disposed": 3})], _mock_client(), mode="dry-run")
    assert result.sources[0].skip_counts == {"disposed": 3}
```

In `importer/tests/test_supabase_client.py`, delete `test_select_pins_by_keys_returns_parsed_rows` and `test_select_pins_by_keys_chunks_large_id_lists`.

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_pipeline.py -v`
Expected: the new tests FAIL with `TypeError: run_pipeline() got an unexpected keyword argument 'state_locator'`.

- [ ] **Step 3: Add the `SourceResult` fields**

In `importer/importer/reports/__init__.py`, add `from importer.stages.orphans import OrphanPlan` and append to `SourceResult`:

```python
    # How this run treats the source's orphans (a dry-run plans deletes the
    # way --delete-orphans would), and its skip counts by reason.
    orphan_plan: OrphanPlan = field(default_factory=OrphanPlan)
    skip_counts: dict[str, int] = field(default_factory=dict)
```

- [ ] **Step 4: Rewrite `importer/importer/pipeline.py`**

```python
"""End-to-end orchestration of all pipeline stages, across multiple sources."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from importer.geo.states import StateLocator
from importer.reports import DedupReport, PipelineResult, SourceResult
from importer.sources.base import Source
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
from importer.stages.dedup import dedup
from importer.stages.diff import DiffStats, diff_candidates
from importer.stages.normalize import NormalizeStats, normalize
from importer.stages.odbl_dump import generate_and_upload
from importer.stages.orphans import OrphanCapExceeded, plan_orphans, scope_to_states
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
    state_locator: StateLocator | None = None,
    delete_orphans: bool = False,
    orphan_delete_cap: int | None = None,
) -> PipelineResult:
    """Fetch, classify and dedup every source, diff each against its system
    pins, then (apply mode) write.

    Orphans are a source's system pins inside the run's states (located with
    `state_locator`) that no candidate claimed. An apply marks them; with
    `delete_orphans` it deletes the ones no user corrected. A dry-run plans
    them the way `delete_orphans` would. Every source's delete cap is checked
    before anything is written, so one breach stops the whole apply.
    """
    if delete_orphans and mode != "apply":
        raise ValueError("delete_orphans is apply-only")
    started_at = datetime.now(timezone.utc)
    state_set = set(states) if states else None

    # Phase A: per-source fetch -> normalize -> refine -> classify.
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
            "asl": asl_stats,
            "norm": norm_stats,
            "skips": dict(skip),
            "geocode_miss": int(skip.get("geocode_miss", 0)) if source.SOURCE_NAME == "gsa" else None,
        })

    # Phase B: one cross-source dedup pass against all user pins.
    existing_user_pins = client.select_user_pins()
    dedup_out = dedup(all_classified, existing_user_pins=existing_user_pins)
    survivors_by_source: dict[str, list] = {}
    for cc in dedup_out.survivors:
        survivors_by_source.setdefault(cc.candidate.source, []).append(cc)

    # Phase C1: diff every source and plan its orphans. Nothing is written yet.
    plan_deletes = mode == "dry-run" or delete_orphans
    source_results: list[SourceResult] = []
    for ps in per_source:
        name = ps["source"]
        survivors = survivors_by_source.get(name, [])
        existing = client.select_system_pins(name)
        in_scope = scope_to_states(existing, states=state_set, locator=state_locator)
        diff_result = diff_candidates(
            survivors, existing=existing, in_scope=in_scope, stats=DiffStats()
        )
        orphan_plan = plan_orphans(
            diff_result.orphans, in_scope_count=len(in_scope),
            delete=plan_deletes, cap=orphan_delete_cap,
        )
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
            orphan_plan=orphan_plan,
            skip_counts=ps["skips"],
        ))

    # Phase C2: delete caps, for every source before any write: a truncated
    # download must not wipe a layer.
    breaches = [
        f"{sr.source}: {len(sr.orphan_plan.delete)} orphan deletions exceed "
        f"the cap of {sr.orphan_plan.cap}"
        for sr in source_results
        if sr.orphan_plan.breached
    ]
    if breaches and mode == "apply":
        raise OrphanCapExceeded("; ".join(breaches) + "; nothing was written")
    errors = [f"{b}; an apply with --delete-orphans would stop" for b in breaches]

    # Phase C3: writes.
    if mode == "apply":
        for sr in source_results:
            apply_to_supabase(
                sr.diff, client=client, system_user_id=system_user_id,
                orphan_plan=sr.orphan_plan,
            )

    # Phase D: ODbL dump (apply mode only, and only when OSM rows actually landed).
    odbl_dump_url = None
    if mode == "apply":
        osm_applied = sum(
            len(sr.diff.inserts) + len(sr.diff.updates)
            for sr in source_results
            if sr.source == "osm"
        )
        if osm_applied > 0:
            odbl_dump_url = generate_and_upload(client=client, out_dir=Path.cwd())

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
        errors=errors,
        odbl_dump_url=odbl_dump_url,
    )
```

In `importer/importer/supabase_client.py`, delete `select_pins_by_keys` and the `ID_CHUNK_SIZE` constant with its comment (nothing else uses them now).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run pytest tests/test_pipeline.py tests/test_supabase_client.py -v`
Expected: all PASS.

- [ ] **Step 6: Full suite, then commit**

Run: `uv run pytest -q` and `grep -rn "select_pins_by_keys\|ID_CHUNK_SIZE" importer tests` (from `importer/`; expect no matches). Then:

```bash
git add importer/importer/pipeline.py importer/importer/reports/__init__.py importer/importer/supabase_client.py importer/tests/test_pipeline.py importer/tests/test_supabase_client.py
git commit -m "feat(importer): diff every source and check delete caps before writing"
```

---

### Task 10: Reports: re-keys, orphan split, cap line, skip counts

**Files:**
- Modify: `importer/importer/reports/markdown.py`, `importer/importer/reports/json_report.py`
- Test: `importer/tests/reports/test_markdown.py`, `importer/tests/reports/test_json_report.py`

**Interfaces:**
- Consumes: `SourceResult.orphan_plan`, `SourceResult.skip_counts` (Task 9); `DiffResult.rekeys`, `DiffResult.rekey_too_far`, `Rekey` (Task 6); `OrphanPlan.actions()`, `.breached`, `.cap` (Task 7).
- Produces: in JSON `sources[].counts`, the new keys `rekeys`, `rekey_too_far`, `orphans_deleted`, `orphans_kept_user_corrected`, `orphans_marked`, `orphan_delete_cap`, `orphan_cap_breached`. Also `sources[].skip_counts`, `sources[].rekeys[]` (`pin_id`, `old_external_id`, `new_external_id`, `user_modified`), and `sources[].orphans[]` with `id`, `source_external_id`, `name`, `action`. Task 14's verify script reads these names.

- [ ] **Step 1: Write the failing tests**

Append to `importer/tests/reports/test_markdown.py`:

```python
from datetime import date

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import Rekey
from importer.stages.orphans import OrphanPlan
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow

CELL = StateLawCell(state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
                    confidence="high", conditions=[], citation="18 USC §930(a)",
                    last_verified_date=date(2026, 5, 31))


def _row(pid, eid, *, user_modified=False):
    return ExistingPinRow(id=pid, source="gsa", source_external_id=eid, name=f"Pin {eid}",
                          latitude=30.0, longitude=-97.0, status=2, restriction_tag="FEDERAL_PROPERTY",
                          user_modified=user_modified, source_dataset_version="v")


def _rekey(new):
    cc = ClassifiedCandidate(candidate=Candidate(
        source="gsa", source_external_id=new, source_dataset_version="v", name="B",
        latitude=30.0, longitude=-97.0, coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.FEDERAL_PROPERTY, state="TX"), cell=CELL)
    return Rekey(pin_id=f"pin-{new}", old_external_id="140", new_external_id=new,
                 user_modified=False, classified=cc)


def _cleanup_result(mode, *, too_far=0, plan=None):
    a, b, c = _row("a", "GONE-A"), _row("b", "GONE-B"), _row("c", "FIXED", user_modified=True)
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[a, b, c],
                      rekeys=[_rekey("13-14-140")], rekey_too_far=too_far)
    return PipelineResult(
        mode=mode, started_at=datetime(2026, 10, 2, tzinfo=timezone.utc), completed_at=None,
        states=["TX"], dedup=DedupReport(),
        sources=[_source(diff=diff, orphan_plan=plan or OrphanPlan(delete=[a, b], keep=[c]),
                         skip_counts={"disposed": 103, "filtered_out": 7})],
    )


def test_markdown_apply_shows_rekeys_and_the_orphan_split() -> None:
    md = render_markdown(_cleanup_result("apply"))
    assert "Re-key: **1**" in md
    assert "Orphan: **3** (deleted **2**, kept, user-corrected **1**, marked **0**)" in md
    assert "- `GONE-A` — Pin GONE-A (delete)" in md
    assert "- `FIXED` — Pin FIXED (keep)" in md
    assert "too far" not in md


def test_markdown_dry_run_previews_what_delete_orphans_would_do() -> None:
    md = render_markdown(_cleanup_result("dry-run"))
    assert "an apply with `--delete-orphans` would delete **2** and keep **1** user-corrected" in md


def test_markdown_shows_rekey_too_far_and_a_cap_breach() -> None:
    a = _row("a", "GONE-A")
    md = render_markdown(_cleanup_result("dry-run", too_far=2, plan=OrphanPlan(delete=[a], cap=0)))
    assert "Re-key too far (inserted; old pin left as an orphan): **2**" in md
    assert "Orphan delete cap breached: 1 deletions > cap 0" in md


def test_markdown_lists_skip_counts() -> None:
    md = render_markdown(_cleanup_result("apply"))
    assert "Skipped at source: `disposed` 103, `filtered_out` 7" in md
```

Append to `importer/tests/reports/test_json_report.py`:

```python
def test_json_report_has_rekeys_the_orphan_split_and_skips() -> None:
    from datetime import date

    from importer.candidate import Candidate, CoordQuality
    from importer.restriction_tag import RestrictionTag
    from importer.stages.apply_state_law import ClassifiedCandidate
    from importer.stages.diff import Rekey
    from importer.stages.orphans import OrphanPlan
    from importer.state_laws import StateLawCell
    from importer.supabase_client import ExistingPinRow

    cell = StateLawCell(state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
                        confidence="high", conditions=[], citation="x", last_verified_date=date(2026, 5, 31))
    cc = ClassifiedCandidate(candidate=Candidate(
        source="gsa", source_external_id="13-14-140", source_dataset_version="v", name="B",
        latitude=30.0, longitude=-97.0, coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.FEDERAL_PROPERTY, state="TX"), cell=cell)
    gone = ExistingPinRow(id="g", source="gsa", source_external_id="OLD", name="Old", latitude=30.0,
                          longitude=-97.0, status=2, restriction_tag="FEDERAL_PROPERTY",
                          user_modified=False, source_dataset_version="v")
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[gone],
                      rekeys=[Rekey(pin_id="p", old_external_id="140", new_external_id="13-14-140",
                                    user_modified=False, classified=cc)])
    result = PipelineResult(
        mode="apply", started_at=datetime(2026, 10, 2, tzinfo=timezone.utc), completed_at=None,
        states=["TX"], dedup=DedupReport(),
        sources=[SourceResult(source="gsa", candidates_fetched=1, candidates_after_state_filter=1,
                              classified=1, dropped_no_cell=0, missing_cells=[], name_truncations=0,
                              diff=diff, orphan_plan=OrphanPlan(delete=[gone], cap=50),
                              skip_counts={"disposed": 103})],
    )
    src = json.loads(render_json(result))["sources"][0]
    assert src["counts"]["rekeys"] == 1
    assert src["counts"]["rekey_too_far"] == 0
    assert src["counts"]["orphans_deleted"] == 1
    assert src["counts"]["orphans_kept_user_corrected"] == 0
    assert src["counts"]["orphans_marked"] == 0
    assert src["counts"]["orphan_delete_cap"] == 50
    assert src["counts"]["orphan_cap_breached"] is False
    assert src["skip_counts"] == {"disposed": 103}
    assert src["rekeys"] == [{"pin_id": "p", "old_external_id": "140",
                              "new_external_id": "13-14-140", "user_modified": False}]
    assert src["orphans"] == [{"id": "g", "source_external_id": "OLD", "name": "Old", "action": "delete"}]
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/reports -v`
Expected: the new tests FAIL (`AssertionError` on missing lines, `KeyError: 'rekeys'`).

- [ ] **Step 3: Implement**

In `importer/importer/reports/markdown.py`, change `_source_block(s)` to `_source_block(s: SourceResult, *, dry_run: bool)` and call it as `_source_block(s, dry_run=r.mode == "dry-run")`. Replace everything from the `INSERT` line through the end of the orphans listing with:

```python
    plan = s.orphan_plan
    lines.append(f"- INSERT: **{len(s.diff.inserts)}**")
    lines.append(f"- UPDATE: **{len(s.diff.updates)}**")
    lines.append(f"- Re-key: **{len(s.diff.rekeys)}**")
    if s.diff.rekey_too_far:
        lines.append(
            f"- Re-key too far (inserted; old pin left as an orphan): **{s.diff.rekey_too_far}**"
        )
    lines.append(f"- SKIP (user-modified): **{len(s.diff.skips)}**")
    if dry_run:
        lines.append(
            f"- Orphan: **{len(s.diff.orphans)}**: an apply with `--delete-orphans` would "
            f"delete **{len(plan.delete)}** and keep **{len(plan.keep)}** user-corrected "
            f"(a plain apply marks all of them)"
        )
    else:
        lines.append(
            f"- Orphan: **{len(s.diff.orphans)}** (deleted **{len(plan.delete)}**, "
            f"kept, user-corrected **{len(plan.keep)}**, marked **{len(plan.mark)}**)"
        )
    if plan.breached:
        lines.append(
            f"- **Orphan delete cap breached: {len(plan.delete)} deletions > cap {plan.cap}**"
        )
    if s.skip_counts:
        skipped = ", ".join(f"`{k}` {v}" for k, v in sorted(s.skip_counts.items()))
        lines.append(f"- Skipped at source: {skipped}")
    lines.append("")
    if s.missing_cells:
        lines.append("**Needs research** (no `states.yaml` cell, dropped):")
        for state, category in sorted(s.missing_cells):
            lines.append(f"- ({state}, {category})")
        lines.append("")
    if s.diff.orphans:
        actions = {row.id: action for row, action in plan.actions()}
        lines.append("**Orphans** (system pins in scope that no record claimed):")
        for row in s.diff.orphans[:50]:
            suffix = f" ({actions[row.id]})" if row.id in actions else ""
            lines.append(f"- `{row.source_external_id}` — {row.name}{suffix}")
        if len(s.diff.orphans) > 50:
            lines.append(f"- … and {len(s.diff.orphans) - 50} more (full list in the JSON report).")
        lines.append("")
    return lines
```

In `importer/importer/reports/json_report.py`, replace the per-source dict comprehension with a helper:

```python
def _source(s) -> dict:
    plan = s.orphan_plan
    actions = {row.id: action for row, action in plan.actions()}
    return {
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
            "rekeys": len(s.diff.rekeys),
            "rekey_too_far": s.diff.rekey_too_far,
            "orphans": len(s.diff.orphans),
            "orphans_deleted": len(plan.delete),
            "orphans_kept_user_corrected": len(plan.keep),
            "orphans_marked": len(plan.mark),
            "orphan_delete_cap": plan.cap,
            "orphan_cap_breached": plan.breached,
        },
        "skip_counts": dict(sorted(s.skip_counts.items())),
        "missing_cells": [list(p) for p in s.missing_cells],
        "rekeys": [
            {
                "pin_id": rk.pin_id,
                "old_external_id": rk.old_external_id,
                "new_external_id": rk.new_external_id,
                "user_modified": rk.user_modified,
            }
            for rk in s.diff.rekeys
        ],
        # Every orphan with what the run did (or, in a dry-run, would do) to it:
        # the audit trail for deletions, which can't be undone.
        "orphans": [
            {
                "id": row.id,
                "source_external_id": row.source_external_id,
                "name": row.name,
                "action": actions.get(row.id),
            }
            for row in s.diff.orphans
        ],
    }
```

and use `"sources": [_source(s) for s in r.sources],` in `render_json`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run pytest tests/reports -v`
Expected: all PASS.

- [ ] **Step 5: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/reports/markdown.py importer/importer/reports/json_report.py importer/tests/reports/test_markdown.py importer/tests/reports/test_json_report.py
git commit -m "feat(importer): report re-keys, the orphan split, cap breaches and skip counts"
```

---

### Task 11: CLI flags, import_runs counts, and the workflow checkbox

**Files:**
- Modify: `importer/importer/cli.py`
- Modify: `.github/workflows/importer-apply.yml`
- Test: `importer/tests/test_cli.py`, `importer/tests/test_apply_workflow.py`

**Interfaces:**
- Consumes: `run_pipeline(..., state_locator, delete_orphans, orphan_delete_cap)` (Task 9); `OrphanPlan.marked_count` (Task 7).
- Produces: CLI flags `--delete-orphans` and `--orphan-delete-cap N` (N ≥ 0). `import_runs.updates` = updates + re-keys; `import_runs.orphans_marked` = Σ `orphan_plan.marked_count`. Workflow input `delete_orphans` (boolean, default false).

- [ ] **Step 1: Write the failing tests**

Append to `importer/tests/test_cli.py`:

```python
APPLY_STAGING = ["--apply", "--states", "TX", "--sources", "gsa",
                 "--project-ref", "staging", "--i-know-this-writes-to-staging"]


def test_parser_accepts_orphan_flags_with_apply() -> None:
    args = build_parser().parse_args(APPLY_STAGING + ["--delete-orphans", "--orphan-delete-cap", "7"])
    assert args.delete_orphans is True
    assert args.orphan_delete_cap == 7


def test_parser_rejects_delete_orphans_with_dry_run() -> None:
    with pytest.raises(SystemExit):
        build_parser().parse_args([
            "--dry-run", "--states", "TX", "--sources", "gsa",
            "--project-ref", "staging", "--delete-orphans",
        ])


def test_parser_rejects_a_negative_cap() -> None:
    with pytest.raises(SystemExit):
        build_parser().parse_args(APPLY_STAGING + ["--orphan-delete-cap", "-1"])


class _FakeClient:
    def __init__(self):
        self.updates = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return None

    def insert_import_run(self, **kw):
        return "run-1"

    def update_import_run(self, **kw):
        self.updates.append(kw)


def _fake_main(monkeypatch, run_pipeline):
    import importer.cli as cli

    monkeypatch.setenv("IMPORTER_SUPABASE_SERVICE_ROLE_KEY", "dummy")
    fake = _FakeClient()
    monkeypatch.setattr(cli, "SupabaseClient", lambda **kw: fake)
    monkeypatch.setattr(cli, "_build_source", lambda name, **kw: object())
    monkeypatch.setattr(cli, "run_pipeline", run_pipeline)
    return cli, fake


def test_main_passes_orphan_flags_and_records_counts(monkeypatch, tmp_path) -> None:
    from datetime import datetime, timezone
    from importer.reports import DedupReport, PipelineResult, SourceResult
    from importer.stages.diff import DiffResult
    from importer.stages.orphans import OrphanPlan
    from importer.supabase_client import ExistingPinRow

    kept = ExistingPinRow(id="k", source="gsa", source_external_id="E", name="N", latitude=30.0,
                          longitude=-97.0, status=2, restriction_tag="FEDERAL_PROPERTY",
                          user_modified=True, source_dataset_version="v")
    captured = {}

    def fake_run(**kw):
        captured.update(kw)
        return PipelineResult(
            mode="apply", started_at=datetime.now(timezone.utc), completed_at=None,
            states=["TX"], dedup=DedupReport(),
            sources=[SourceResult(source="gsa", candidates_fetched=1, candidates_after_state_filter=1,
                                  classified=1, dropped_no_cell=0, missing_cells=[], name_truncations=0,
                                  diff=DiffResult(inserts=[], updates=[], skips=[], orphans=[kept]),
                                  orphan_plan=OrphanPlan(keep=[kept]))],
        )

    cli, fake = _fake_main(monkeypatch, fake_run)
    rc = cli.main(APPLY_STAGING + ["--delete-orphans", "--orphan-delete-cap", "7",
                                   "--report-out", str(tmp_path / "r.md")])
    assert rc == 0
    assert captured["delete_orphans"] is True
    assert captured["orphan_delete_cap"] == 7
    assert captured["state_locator"] is not None
    assert fake.updates[-1]["orphans_marked"] == 1


def test_main_exits_1_and_records_a_cap_breach(monkeypatch, tmp_path) -> None:
    from importer.stages.orphans import OrphanCapExceeded

    def breach(**kw):
        raise OrphanCapExceeded("gsa: 300 orphan deletions exceed the cap of 211; nothing was written")

    cli, fake = _fake_main(monkeypatch, breach)
    rc = cli.main(APPLY_STAGING + ["--delete-orphans", "--report-out", str(tmp_path / "r.md")])
    assert rc == 1
    assert "exceed the cap" in fake.updates[-1]["errors_json"]["message"]
```

Append to `importer/tests/test_apply_workflow.py`:

```python
def test_delete_orphans_is_an_opt_in_checkbox():
    raw = WORKFLOW.read_text(encoding="utf-8")
    wf = yaml.safe_load(raw)
    inputs = wf[True]["workflow_dispatch"]["inputs"]  # PyYAML reads the `on:` key as True
    assert inputs["delete_orphans"]["type"] == "boolean"
    assert inputs["delete_orphans"]["default"] is False
    step = next(s for s in wf["jobs"]["apply"]["steps"] if "importer.cli" in s.get("run", ""))
    assert step["env"]["DELETE_ORPHANS"] == "${{ inputs.delete_orphans }}"
    assert '[ "$DELETE_ORPHANS" = "true" ]' in step["run"]
    assert "--delete-orphans" in step["run"]
    # The cap override stays local-only: a prod breach means stop and investigate.
    assert "--orphan-delete-cap" not in raw
```

- [ ] **Step 2: Run them to verify they fail**

Run: `uv run pytest tests/test_cli.py tests/test_apply_workflow.py -v`
Expected: FAIL, with `error: unrecognized arguments: --delete-orphans` (SystemExit) and `KeyError: 'delete_orphans'`.

- [ ] **Step 3: Implement the CLI**

In `importer/importer/cli.py`, add above `build_parser`:

```python
def _non_negative_int(value: str) -> int:
    n = int(value)
    if n < 0:
        raise argparse.ArgumentTypeError("must be >= 0")
    return n
```

Add to `build_parser`, after `--refetch`:

```python
    p.add_argument(
        "--delete-orphans",
        action="store_true",
        help="Apply only: delete system pins whose source record is gone (capped "
             "per source; user-corrected pins are marked instead). A dry-run "
             "already reports what this would do.",
    )
    p.add_argument(
        "--orphan-delete-cap",
        type=_non_negative_int,
        default=None,
        metavar="N",
        help="Override the per-source orphan delete cap "
             "(default: max(50, 5%% of the source's in-scope pins)). Local runs only.",
    )
```

In `_parse_args`, before `return args`:

```python
        if args.delete_orphans and args.dry_run:
            p.error("--delete-orphans is apply-only; a dry-run already reports what it would delete")
```

In `main`, pass the new arguments to `run_pipeline`:

```python
                refetch=args.refetch,
                state_locator=locator,
                delete_orphans=args.delete_orphans,
                orphan_delete_cap=args.orphan_delete_cap,
```

and change two arguments of the success-path `update_import_run`:

```python
                # A re-key is an update of an existing row (no column of its own).
                updates=sum(len(s.diff.updates) + len(s.diff.rekeys) for s in result.sources),
                orphans_marked=sum(s.orphan_plan.marked_count for s in result.sources),
```

- [ ] **Step 4: Implement the workflow checkbox**

In `.github/workflows/importer-apply.yml`, add after the `states` input:

```yaml
      delete_orphans:
        description: 'Delete pins whose source record is gone (capped per source; user-corrected pins are kept)'
        required: false
        type: boolean
        default: false
```

Replace the `Apply to ${{ inputs.target }}` step with:

```yaml
      - name: Apply to ${{ inputs.target }}
        env:
          DELETE_ORPHANS: ${{ inputs.delete_orphans }}
        run: |
          # --delete-orphans is opt-in. The cap override is deliberately not
          # exposed here: a breach means stop and investigate.
          orphan_flags=()
          if [ "$DELETE_ORPHANS" = "true" ]; then orphan_flags+=(--delete-orphans); fi
          uv run --no-sync python -m importer.cli \
            --apply \
            --states "${{ inputs.states }}" \
            --sources "${{ inputs.sources }}" \
            --project-ref ${{ inputs.target }} \
            --i-know-this-writes-to-${{ inputs.target }} \
            "${orphan_flags[@]}" \
            --report-out "$GITHUB_WORKSPACE/importer-report.md"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run pytest tests/test_cli.py tests/test_apply_workflow.py -v`
Expected: all PASS.

- [ ] **Step 6: Full suite, then commit**

Run: `uv run pytest -q`, expecting all pass. Then:

```bash
git add importer/importer/cli.py importer/tests/test_cli.py importer/tests/test_apply_workflow.py .github/workflows/importer-apply.yml
git commit -m "feat(importer): --delete-orphans / --orphan-delete-cap and the workflow checkbox"
```

---

### Task 12: Health check: don't alert on importer deletions

**Files:**
- Modify: `ci/health_check.sql`, `ci/health_check.py`
- Test: `ci/tests/test_health_check.py`

**Interfaces:**
- Produces: a new metric key `importer_deleted_24h` (in `METRIC_KEYS`, no rule). Rules 4 and 5 now count only deletions outside importer apply windows. The digest line is `Pins deleted during importer applies, last 24 h (not judged): N`.

- [ ] **Step 1: Write the failing tests**

In `ci/tests/test_health_check.py`: add `"importer_deleted_24h": 0,` to `HEALTHY` (after `"deletions_24h": 3,`). Change the digest assertion in `test_digest_flags_breached_rules` to `assert "| 5 | Pin deletions outside importer applies, last 24 h | 51 | > 50 | 🔴 alert |" in d`. Then append:

```python
def test_deletion_rules_skip_importer_apply_windows():
    code = _sql_code()
    cte = re.search(r"recent_deletions AS \((.*?)\n\),", code, re.S).group(1)
    assert "r.mode = 'apply'" in cte
    assert "d.deleted_at BETWEEN r.started_at AND r.completed_at" in cte
    for key in ("imported_deleted_24h", "deletions_24h"):
        expr = re.search(rf"'{key}',\s*\((.*?)\),\n", code, re.S).group(1)
        assert "NOT by_importer" in expr, key
    expr = re.search(r"'importer_deleted_24h',\s*\((.*?)\),\n", code, re.S).group(1)
    assert "by_importer" in expr and "NOT" not in expr


def test_importer_deletions_are_shown_but_never_judged():
    m = metrics(importer_deleted_24h=4321)
    assert evaluate("prod", m, REST_OK) == []
    assert "Pins deleted during importer applies, last 24 h (not judged): 4,321" in hc.render_digest("prod", m, REST_OK, [])
```

- [ ] **Step 2: Run them to verify they fail**

Run (repo root): `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: FAIL. `test_sql_returns_exactly_the_metric_keys` fails (the key is not in the SQL yet), the new tests fail, and the digest test fails on the label.

- [ ] **Step 3: Implement the SQL**

In `ci/health_check.sql`, insert this CTE between `imported AS (…),` and the `flipped` comment. It must come before `flipped`, because `test_statutory_flip_rule_does_not_depend_on_who_wrote_it` expects `flipped` to be the last CTE:

```sql
-- Pin deletions in the last 24 h. by_importer: made while an importer apply
-- ran (between its started_at and completed_at), e.g. by --delete-orphans.
-- Rules 4 and 5 skip those; importer_deleted_24h counts them. A run that
-- never recorded completed_at (killed mid-run) covers nothing, so its
-- deletions still alert.
recent_deletions AS (
  SELECT d.original_created_by,
         EXISTS (SELECT 1 FROM import_runs r
                 WHERE r.mode = 'apply'
                   AND d.deleted_at BETWEEN r.started_at AND r.completed_at) AS by_importer
  FROM pin_deletions d
  WHERE d.deleted_at > now() - interval '24 hours'
),
```

Replace the `imported_deleted_24h` and `deletions_24h` entries with:

```sql
  'imported_deleted_24h', (SELECT count(*) FROM recent_deletions d, sys
                           WHERE d.original_created_by = sys.id
                             AND NOT by_importer),
  'deletions_24h', (SELECT count(*) FROM recent_deletions WHERE NOT by_importer),
  'importer_deleted_24h', (SELECT count(*) FROM recent_deletions WHERE by_importer),
```

- [ ] **Step 4: Implement the script**

In `ci/health_check.py`, change rules 4 and 5:

```python
    Rule(
        4, "imported_deleted_24h", "Imported pins deleted outside importer applies, last 24 h", "> 0",
        lambda n: n > 0,
        lambda n, m: (
            f"{n} imported pin(s) deleted in the last 24 h outside an importer apply; users can't "
            "delete them (012), so this is an admin error, a leaked key or a policy regression"
        ),
    ),
    Rule(
        5, "deletions_24h", "Pin deletions outside importer applies, last 24 h", f"> {MAX_DELETIONS_24H}",
        lambda n: n > MAX_DELETIONS_24H,
        lambda n, m: (
            f"{n} pin deletions in the last 24 h outside importer applies "
            f"(threshold {MAX_DELETIONS_24H}): possible scripted mass delete"
        ),
    ),
```

Add `"importer_deleted_24h",` to the extra keys in `METRIC_KEYS`. In `render_digest`, add as the first item of the counts list (before `- User pins:`):

```python
            f"- Pins deleted during importer applies, last 24 h (not judged): {metrics['importer_deleted_24h']:,}",
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: all pass (143 + 2).

- [ ] **Step 6: Probe the new SQL on staging (rolled back by design)**

Check the windows are clear. Run with the Supabase MCP `execute_sql`:

```sql
SELECT count(*) FROM import_runs WHERE started_at > now() - interval '6 hours';
```

Expect `0`. If it isn't, wait until it is: real runs would overlap the probe's windows.

Write this generator to your scratchpad as `make_probe.py`, run it from the repo root with `uv run --no-project python <scratchpad>/make_probe.py <scratchpad>/probe.sql`, and send the contents of `probe.sql` to MCP `execute_sql`:

```python
"""Build a self-rolling-back staging probe of ci/health_check.sql's deletion metrics."""
import sys
from pathlib import Path

sql = Path("ci/health_check.sql").read_text(encoding="utf-8").strip()
assert sql.endswith(";") and "$q$" not in sql
body = sql[:-1]
SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"
probe = f"""DO $probe$
DECLARE b json; a json;
BEGIN
  EXECUTE $q${body}$q$ INTO b;
  INSERT INTO import_runs (mode, source_filter, started_at, completed_at) VALUES
    ('apply',   'probe-done', now() - interval '2 hours',    now() - interval '1 hour'),
    ('apply',   'probe-open', now() - interval '20 minutes', NULL),
    ('dry-run', 'probe-dry',  now() - interval '5 hours',    now() - interval '4 hours');
  INSERT INTO pin_deletions (pin_id, deleted_at, original_created_by) VALUES
    (gen_random_uuid(), now() - interval '90 minutes',  '{SYS}'),  -- inside the done apply
    (gen_random_uuid(), now() - interval '3 hours',     '{SYS}'),  -- outside every run
    (gen_random_uuid(), now() - interval '10 minutes',  '{SYS}'),  -- inside the run with no completed_at
    (gen_random_uuid(), now() - interval '270 minutes', '{SYS}');  -- inside a dry-run
  EXECUTE $q${body}$q$ INTO a;
  RAISE EXCEPTION 'PROBE (rolled back) imported_deleted_24h %->%, deletions_24h %->%, importer_deleted_24h %->%',
    b->'imported_deleted_24h', a->'imported_deleted_24h',
    b->'deletions_24h', a->'deletions_24h',
    b->'importer_deleted_24h', a->'importer_deleted_24h';
END $probe$;"""
Path(sys.argv[1]).write_text(probe, encoding="utf-8")
```

Expected: the call **fails by design** with `PROBE (rolled back) …`, which rolls everything back. Relative to the "before" values: `imported_deleted_24h` +3, `deletions_24h` +3, `importer_deleted_24h` +1. Re-run the window-count query and expect `0` again, which confirms the rollback. If MCP refuses the write (read-only session), say so in the task report and rely on the structural tests plus Task 14 step 9.

- [ ] **Step 7: Commit**

```bash
git add ci/health_check.sql ci/health_check.py ci/tests/test_health_check.py
git commit -m "fix(health-check): don't count importer apply deletions in rules 4 and 5"
```

---

### Task 13: Operator docs

**Files:**
- Modify: `importer/README.md`, `docs/importer/SOURCES.md`, `docs/importer/STAGING_REAPPLY.md`, `docs/importer/PROD_APPLY.md`, `docs/importer/PROD_HEALTH_CHECK.md`

No code or tests. Each step below gives the exact text.

- [ ] **Step 1: `importer/README.md`**

Insert after the "Apply mode (`--apply`) …" paragraph:

```markdown
## Re-keys and orphans

- **Stable ids.** A pin is identified by `(source, source_external_id)`. GSA
  uses `{Reporting Agency Code}-{Reporting Bureau Code}-{Real Property Unique
  Identifier}`; military uses the MIRTA `SDSID`, or `{STATE}:{SITENAME}` when
  the SDSID is blank or all zeros. When a source's id scheme changes, its
  candidates carry the old id and old position, and the diff **re-keys** the
  existing pin in place (UUID and any user correction survive) if it is within
  50 m of where the old code put the record. The report shows `Re-key: N`, and
  `Re-key too far` when an old pin was more than 50 m away (that pin is
  reported as an orphan instead).
- **Orphans** are a source's system pins inside the run's `--states` that no
  record claimed: the record left the dataset (a Disposed building, a closed
  base) or lost cross-source dedup. A plain `--apply` marks them
  (`source_orphaned_at`). `--apply --delete-orphans` deletes them, except pins
  a user corrected, which are marked and listed as "kept, user-corrected".
  Deletions are permanent; the JSON report lists every one.
- **Delete cap.** Before anything is written, each source's deletions are
  checked against `max(50, 5% of its in-scope pins)`. One breach stops the
  whole apply with nothing written. A dry-run plans orphans the way
  `--delete-orphans` would and lists a breach under **Errors**.
  `--orphan-delete-cap N` overrides the cap for a local run; the Actions
  workflow doesn't expose it. `--delete-orphans` is rejected with `--dry-run`.
- **Run the full source set** (the workflow default). Dedup decides between
  sources, so a partial run can re-insert a pin another source won.
```

- [ ] **Step 2: `docs/importer/SOURCES.md`**

Change the GSA row's Coverage to `Federal owned/leased buildings (\`Real Property Type == Building\`, not Disposed)` and the military row's Coverage to `Military installations (not closed); pin on the DoD site point when it is on the base, else inside the largest part`. Then append to the License notes list:

```markdown
- **GSA FRPP identity and status (2026-10).** `Real Property Unique Identifier` repeats across reporting agencies (4,243 ids nationally) and, within Interior, across bureaus, so the external id is `{Reporting Agency Code}-{Reporting Bureau Code}-{Real Property Unique Identifier}`, which is unique across all 113,015 buildings. Rows with `Asset Status = Disposed` are skipped (no longer federal property); "Determination to Dispose", "Report of Excess", "Surplus" and "Cannot Currently be Disposed" stay.
- **MIRTA identity, position and status (2026-10).** A site's key is its `SDSID` when that is a real GUID; otherwise `{STATE}:{SITENAME}` (202 boundaries have no SDSID, 3 share the all-zero one). Records sharing a key are one installation split across records and are merged. The pin goes on the DoD site point from layer 0 ("DoD Sites – Point", config `points_url`, cached as `military_points.geojson`) when it lies within ~50 m of the boundary; otherwise inside the boundary's largest part. The area-weighted centroid used before fell outside the base for 77 multi-part sites. `SITEOPERATIONALSTATUS = clsd` sites are skipped; caretaker, excess and semi-active sites stay. A missing or empty points file is an error, not a silent fallback.
```

- [ ] **Step 3: `docs/importer/STAGING_REAPPLY.md`**

Append:

```markdown
## 8. Re-keys and orphan deletion (2026-10)

The clear-and-reinsert flow above is no longer needed when only ids or
positions changed: the diff re-keys existing pins in place, and orphans can be
deleted by the importer itself.

1. **Dry-run** (Step 1, with all 7 sources and `--refetch` so it sees what the
   workflow will fetch). Read per source:
   - `Re-key: N`: pins that will take a new id. `Re-key too far` should be 0;
     anything else means an old pin is more than 50 m from every new record
     carrying its old id. Investigate before applying.
   - `Orphan: N`: an apply with `--delete-orphans` would delete D and keep K
     user-corrected. A breach shows as **Orphan delete cap breached** and under
     **Errors**; an apply with deletion would stop.
   - `Skipped at source`: e.g. `disposed` (GSA), `closed` (military).
2. **Apply** through Actions → *Importer Apply (manual)* → `target: staging`,
   confirm phrase, and check **delete_orphans** to remove orphans (leave it
   unchecked to only mark them). Re-keys are one PATCH per pin: ≈4,200 GSA
   re-keys take a few minutes.
3. **Dry-run again:** expect 0 inserts, 0 re-keys and 0 orphans (everything
   UPDATE or SKIP).
4. Rules 4 and 5 of the daily health check ignore deletions made during an
   apply; they show up as "Pins deleted during importer applies".
```

- [ ] **Step 4: `docs/importer/PROD_APPLY.md`**

In B2's input list, after the `states` bullet, add `` - `delete_orphans`: unchecked for a plain re-apply (orphans are only marked); checked to remove orphans. See "Re-applying prod" below. `` Then append:

```markdown
---

## Re-applying prod (after the 2026-10 identity changes)

Prod's GSA and military pins were written under the old ids. The next prod
apply re-keys them in place (same UUIDs) instead of duplicating them.

1. **B1 dry-run** against prod. Per source, check: `Re-key` ≈ the staging
   numbers; `Re-key too far` = 0; no **Orphan delete cap breached** and no
   **Errors**; orphan counts close to staging's (mostly Disposed buildings,
   closed bases, and pins displaced by a higher-priority source).
2. **B2** with `delete_orphans` checked. A cap breach stops the run before any
   write. That means stop and investigate (a truncated download, an upstream
   change), never re-run with a bigger cap from the workflow; if the deletion
   is intended, raise it in a PR.
3. **B3:** the second dry-run shows 0 inserts / 0 re-keys / 0 orphans.
   `SELECT source, source_external_id, count(*) FROM pins GROUP BY 1, 2 HAVING count(*) > 1;`
   returns no rows.
4. **Deletions are permanent.** `importer-report.json` (90-day artifact) lists
   every deleted pin (`orphans[]` with `action: "delete"`). B4's rollback
   doesn't bring them back; if a deletion was wrong, fix the cause and re-apply,
   and the record returns as a new pin.
5. The health check's rules 4 and 5 skip deletions inside the apply's
   `import_runs` window; the digest shows them as "Pins deleted during importer
   applies".
```

- [ ] **Step 5: `docs/importer/PROD_HEALTH_CHECK.md`**

Replace rows 4 and 5 of the findings table with:

```markdown
| 4 | imported pins deleted outside an importer apply | users can't delete them (012), so: an admin delete, a leaked service key, or an RLS regression. Deletions while an importer apply ran (inside its `import_runs` window) don't count; the digest shows them as "Pins deleted during importer applies" | `pin_deletions.deleted_by` for rows whose `original_created_by` is the system user says who |
| 5 | more than 50 deletions in 24 h outside importer applies | a scripted mass delete | `pin_deletions.deleted_by`; Postgres logs show `P0001` if the rate limit fired |
```

Then add after the table:

```markdown
An importer apply with `--delete-orphans` deletes pins on purpose. Rules 4 and
5 skip any deletion made between an `apply` run's `started_at` and
`completed_at`. An apply killed before it recorded `completed_at` covers
nothing, so its deletions still alert.
```

- [ ] **Step 6: Commit**

```bash
git add importer/README.md docs/importer/SOURCES.md docs/importer/STAGING_REAPPLY.md docs/importer/PROD_APPLY.md docs/importer/PROD_HEALTH_CHECK.md
git commit -m "docs(importer): re-keys, orphan deletion, the cap and the health-check exclusion"
```

---

### Task 14: Staging verification (pilot TX/FL/PA)

Spec "Staging verification" steps 1–7. **Writes to staging happen only in step 6, after the owner says go.** Prod is not touched. Results go into CLAUDE.md and memory at the end.

**Files:**
- Modify: `CLAUDE.md` (Current Status, test counts), memory (`project_pilot_closeout.md`)
- Scratch only: `snapshot_system_pins.py`, `verify_reapply.py`, reports, snapshots (scratchpad; not committed)

- [ ] **Step 1: Get the staging key without pasting it**

Ask the owner to save the staging `service_role` key as one line in `.local/staging_service_role_key` (git-ignored; Supabase dashboard → ccwmap-staging → Project Settings → API). Every local importer command below sets it inline from that file and never prints it:

```powershell
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = (Get-Content ..\.local\staging_service_role_key -Raw).Trim(); <command>
```

Also confirm the full suites are green: `uv run pytest -q` (importer) and the ci suite.

- [ ] **Step 2: Resume staging, then snapshot every system pin**

Run `select count(*) from pins where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';` via MCP. If it errors, staging is paused: ask the owner to resume it.

Save to your scratchpad as `snapshot_system_pins.py`:

```python
"""Snapshot every system pin on staging. Run from importer/: uv run python <this> <out.json>"""
import json
import os
import sys

import yaml

from importer.cli import CONFIG_PATH
from importer.supabase_client import SupabaseClient

SOURCES = ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa", "osm")
cfg = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
with SupabaseClient(url=cfg["projects"]["staging"]["url"],
                    service_role_key=os.environ["IMPORTER_SUPABASE_SERVICE_ROLE_KEY"],
                    system_user_id=cfg["system_user_id"]) as c:
    rows = [{"id": r.id, "source": r.source, "eid": r.source_external_id,
             "lat": r.latitude, "lng": r.longitude}
            for s in SOURCES for r in c.select_system_pins(s)]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(rows, f)
print(len(rows), "system pins")
```

Run it to `<scratchpad>/before.json`. Expected: ≈23,827 rows (staging on 2026-10-02: gsa 4221, military 77, courts 472, nces 15432, osm 3275, ipeds 290, faa 60).

- [ ] **Step 3: Dry-run with fresh sources**

```powershell
uv run python -m importer.cli --dry-run --states TX,FL,PA `
  --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm `
  --project-ref staging --refetch --report-out <scratchpad>\dryrun1.md
```

(`--refetch` makes the local data match what the workflow will download. The FRPP and OSM downloads take a few minutes.) Expected, roughly:
- **gsa:** Re-key ≈ 4.2k, INSERT ≈ +290 (less dedup), `disposed` ≈ 103.
- **hifld_military:** INSERT ≈ +23, Re-key 1–2 (the `' '` and all-zero pins), `closed` in skip counts.
- **Orphans:** ≈ 100 (mostly Disposed), plus pins displaced in dedup.
- **No cap breach, no Errors section; `Re-key too far` absent (0) everywhere.**
- `hifld_courts`: unchanged (TX/FL/PA have their own cells).

Investigate any large deviation **before** going on. Show the owner the per-source block.

- [ ] **Step 4: Spot-check military positions**

From `importer/`:

```bash
uv run python -c "
from importer.cli import REPO_ROOT, STATES_BOUNDARY_FIXTURE, _build_source, _load_config
from importer.geo.states import load_state_locator
src = _build_source('hifld_military', config=_load_config(), locator=load_state_locator(STATES_BOUNDARY_FIXTURE), repo_root=REPO_ROOT)
for c in src.iter_candidates(state_filter={'TX', 'FL', 'PA'}):
    if any(k in c.name.upper() for k in ('SAN ANTONIO', 'JACKSONVILLE', 'INDIANTOWN', 'MABRY', 'ELLINGTON', 'SWIFT')):
        print(f'{c.name:45} {c.latitude:.5f},{c.longitude:.5f}  {c.source_external_id}')
"
```

Expected: JBSA near Lackland (≈29.38, −98.62), not Camp Bullis (≈29.7, −98.55). Jacksonville IAP on its base (≈30.49, −81.69). Fort Indiantown Gap, Camp Mabry, Camp Swift and Ellington Field present. Give the owner the coordinates to paste into a map.

- [ ] **Step 5: Push the branch (owner go-ahead)**

Ask the owner before pushing: the push is outward-facing, and the next step writes to staging. Then: `git push -u origin fix/importer-identity-and-cleanup`.

- [ ] **Step 6: Apply to staging through the workflow (owner go-ahead)**

With the owner's explicit go:

```bash
gh workflow run importer-apply.yml --ref fix/importer-identity-and-cleanup \
  -f target=staging -f confirm=I-KNOW-THIS-WRITES-TO-STAGING -f delete_orphans=true
gh run list --workflow importer-apply.yml --limit 1     # note the run id
gh run watch <run-id>
gh run download <run-id> -n importer-apply-staging-<run-id> -D <scratchpad>/apply
```

Expected: success. The report matches step 3 (Re-key / INSERT / Orphan deleted counts), and nothing is under Errors. (A workflow dispatched from a branch uses that branch's workflow file, so the `delete_orphans` input exists.)

- [ ] **Step 7: Dry-run again, without refetch**

Same command as step 3 but without `--refetch`, to `<scratchpad>\dryrun2.md`. Expected per source: INSERT 0, Re-key 0, Orphan 0 (everything UPDATE or SKIP). A handful of inserts or orphans can come from upstream drift between the local fetch and the workflow's fetch. Explain any before calling it done.

- [ ] **Step 8: Check identity against the snapshot**

Snapshot again to `<scratchpad>/after.json` (step 2's script). Save as `verify_reapply.py` in the scratchpad and run `uv run python <scratchpad>/verify_reapply.py <scratchpad>/before.json <scratchpad>/after.json <scratchpad>/apply/importer-report.json`:

```python
"""Check a staging apply against the pre-apply snapshot and the apply report."""
import json
import sys
from collections import Counter

before = {r["id"]: r for r in json.load(open(sys.argv[1], encoding="utf-8"))}
after = {r["id"]: r for r in json.load(open(sys.argv[2], encoding="utf-8"))}
report = json.load(open(sys.argv[3], encoding="utf-8"))
rekeys = {rk["pin_id"]: rk for s in report["sources"] for rk in s["rekeys"]}
deleted = {o["id"] for s in report["sources"] for o in s["orphans"] if o["action"] == "delete"}
inserts = sum(s["counts"]["inserts"] for s in report["sources"])
problems = []
for pid, rk in rekeys.items():
    a = after.get(pid)
    if a is None:
        problems.append(f"re-keyed pin {pid} is gone")
    elif a["eid"] != rk["new_external_id"]:
        problems.append(f"{pid}: id {a['eid']!r}, expected {rk['new_external_id']!r}")
problems += [f"deleted orphan {pid} still present" for pid in deleted if pid in after]
vanished = set(before) - set(after)
if vanished - deleted:
    problems.append(f"{len(vanished - deleted)} pins vanished without a planned delete")
changed = [p for p in set(before) & set(after) if before[p]["eid"] != after[p]["eid"] and p not in rekeys]
if changed:
    problems.append(f"{len(changed)} pins changed id outside the re-key list")
dups = [k for k, n in Counter((r["source"], r["eid"]) for r in after.values()).items() if n > 1]
if dups:
    problems.append(f"duplicate (source, id): {dups[:5]}")
new = set(after) - set(before)
if len(new) != inserts:
    problems.append(f"{len(new)} new pins, report says {inserts} inserts")
print(f"re-keys {len(rekeys)}  deleted {len(deleted)}  new {len(new)}  total {len(after)}")
print("\n".join(problems) or "OK")
sys.exit(1 if problems else 0)
```

Expected: `OK`. Every re-keyed pin kept its UUID with the new id, only planned deletes vanished, and there are no duplicate keys.

- [ ] **Step 9: SQL checks and health metrics on staging (MCP)**

```sql
SELECT source, source_external_id, count(*) FROM pins
GROUP BY 1, 2 HAVING count(*) > 1;                                   -- expect no rows

SELECT source, count(*) FROM pins
WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
GROUP BY source ORDER BY source;                                     -- matches after.json

SELECT source_external_id, name FROM pins
WHERE source = 'gsa' ORDER BY random() LIMIT 5;                      -- e.g. 47-00-…, 13-14-…
```

Then run `ci/health_check.sql`'s full text through MCP `execute_sql` (it is one read-only statement). Expected: `importer_deleted_24h` equals the number of pins the apply deleted, and `imported_deleted_24h` = 0. Don't dispatch `health-check.yml` from the branch: its `prod` job's `production-plan` environment is master-only, so the job would fail and the `alert` job would open an issue. The workflow itself is checked by the first scheduled run after merge.

- [ ] **Step 10: Record the results**

Update `CLAUDE.md`: in "Current Status", add a sentence saying that importer identity & cleanup is staging-verified on `fix/importer-identity-and-cleanup`, with the re-key/insert/delete counts from step 6 and "prod re-apply pending (owner-approved run, likely with Phase 8a)". Update the importer test count in the "What's Implemented" bullet (`152 at Phase 6` → the new `uv run pytest` total). Update memory `project_pilot_closeout.md` the same way. Then:

```bash
git add CLAUDE.md
git commit -m "docs: importer identity and cleanup staging-verified"
```

Then hand off to superpowers:finishing-a-development-branch (PR to master). The prod re-apply stays out of scope.
