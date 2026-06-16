# Pre-Populate Pins — Phase 6 (OSM long-tail + ODbL dump + title-casing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Overpass-backed OSM source (per-state, state-law-table-driven auto-scope), a real ODbL derived-database dump to public Supabase Storage, and all-caps label title-casing in `normalize` — all importer-only, staging-tested, no app/migration/prod changes.

**Architecture:** The OSM source asks the state-law table which categories have an `osm`-filtered cell *for each requested state* and queries Overpass only for those (pilot → bars in TX/FL, zero queries for PA). Surviving OSM pins flow through the existing normalize → apply_state_law → dedup (OSM already lowest priority) → diff → apply pipeline unchanged. After an apply run that touched OSM, a new pipeline Phase D writes `dump-YYYY-MM-DD.csv.gz` of the OSM-derived columns and uploads it to a public bucket. Title-casing is a guarded transform in `normalize` affecting every source's all-caps labels.

**Tech Stack:** Python 3.12, httpx (0.27.x), pydantic v2, shapely, pytest + pytest-httpx. Overpass API. Supabase Postgrest + Storage REST.

---

## Spec reference

Design: `docs/superpowers/specs/2026-06-16-phase6-osm-longtail-design.md`. Parent: `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` (§4 pipeline, §6 ODbL).

## File map

**Create:**
- `importer/importer/sources/osm.py` — OSM source module.
- `importer/importer/stages/_titlecase.py` — smart title-case helper.
- `importer/tests/sources/test_osm.py` — OSM source tests.
- `importer/tests/stages/test_titlecase.py` — title-case unit tests.
- `importer/tests/stages/test_odbl_dump.py` — dump generator tests (replaces the stub test).
- `importer/tests/fixtures/osm_tx_bars_sample.json` — captured Overpass fixture.

**Modify:**
- `importer/importer/state_laws.py` — add `osm_categories_for_state`.
- `importer/importer/stages/normalize.py` — apply guarded title-casing.
- `importer/importer/supabase_client.py` — Storage methods + `OsmDumpRow` + `select_osm_pins_for_dump`.
- `importer/importer/stages/odbl_dump.py` — replace stub with real generator.
- `importer/importer/pipeline.py` — Phase D (apply-only dump) + `odbl_dump_url`.
- `importer/importer/reports/__init__.py` — `PipelineResult.odbl_dump_url`.
- `importer/importer/reports/markdown.py` — ODbL section.
- `importer/config.yaml` — `sources.osm`.
- `importer/importer/cli.py` — register `osm`; pass `state_laws` + `states` to `_build_source`.
- `importer/tests/test_state_laws.py`, `tests/stages/test_normalize.py`, `tests/stages/test_dedup.py`, `tests/test_supabase_client.py`, `tests/test_cli.py` — extend.
- `docs/importer/SOURCES.md`, `docs/importer/OMISSIONS.md`, `docs/importer/STAGING_REAPPLY.md`, `importer/README.md` — docs.

**Delete:**
- `importer/tests/stages/test_odbl_dump_stub.py` — superseded by `test_odbl_dump.py`.

## Conventions

- Run tests from the `importer/` dir: `cd importer && python -m pytest`.
- Single test: `python -m pytest tests/path::test_name -v`.
- Commit from the repo root; current branch is `feature/pre-populate`. Use the project trailer on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```
- 123 importer tests pass today; each task adds tests and keeps the suite green.

---

### Task 1: `StateLawTable.osm_categories_for_state`

Derives the per-state auto-scope used by the OSM source.

**Files:**
- Modify: `importer/importer/state_laws.py`
- Test: `importer/tests/test_state_laws.py`

- [ ] **Step 1: Write the failing test**

`importer/tests/test_state_laws.py` already imports `RestrictionTag`, `StateLawCell`, `StateLawTable` (top of file). Add `from datetime import date` to its imports, then add these inline-table tests (self-contained — they don't couple to the live `states.yaml`):

```python
def test_osm_categories_for_state_resolves_per_state():
    table = StateLawTable(rows=[
        StateLawCell(state="TX", category=RestrictionTag.BAR_ALCOHOL,
                     default_status="NO_GUN", confidence="medium", conditions=[],
                     citation="x", last_verified_date=date(2026, 5, 31),
                     source_filter=["osm"]),
        StateLawCell(state="TX", category=RestrictionTag.STATE_LOCAL_GOVT,
                     default_status="NO_GUN", confidence="high", conditions=[],
                     citation="y", last_verified_date=date(2026, 5, 31),
                     source_filter=["hifld_courts"]),
    ])
    assert table.osm_categories_for_state("TX") == {RestrictionTag.BAR_ALCOHOL}
    # PA has no bar cell and no US fallback -> empty (documented in OMISSIONS.md).
    assert table.osm_categories_for_state("PA") == set()
    # A non-osm source_filter (hifld_courts) must never appear here.
    assert RestrictionTag.STATE_LOCAL_GOVT not in table.osm_categories_for_state("TX")


def test_osm_categories_for_state_uses_us_fallback():
    table = StateLawTable(rows=[
        StateLawCell(state="US", category=RestrictionTag.BAR_ALCOHOL,
                     default_status="NO_GUN", confidence="medium", conditions=[],
                     citation="x", last_verified_date=date(2026, 5, 31),
                     source_filter=["osm"]),
    ])
    # No state-specific cell -> US fallback applies (matches lookup() semantics).
    assert table.osm_categories_for_state("TX") == {RestrictionTag.BAR_ALCOHOL}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd importer && python -m pytest tests/test_state_laws.py::test_osm_categories_for_state_resolves_per_state -v`
Expected: FAIL with `AttributeError: 'StateLawTable' object has no attribute 'osm_categories_for_state'`.

- [ ] **Step 3: Implement the method**

In `importer/importer/state_laws.py`, add to class `StateLawTable` (after `lookup`):

```python
    def osm_categories_for_state(self, state: str) -> set[RestrictionTag]:
        """Categories whose effective cell for `state` is OSM-filtered.

        Uses the same state->US fallback as lookup(), so a state-specific cell
        shadows the US cell exactly as classification will later resolve it.
        Drives the OSM source's per-state Overpass query plan: we never query a
        (state, category) combination that will not become a pin.
        """
        cats: set[RestrictionTag] = set()
        for category in {row.category for row in self.rows}:
            cell = self.lookup(state, category)
            if cell and cell.source_filter and "osm" in cell.source_filter:
                cats.add(category)
        return cats
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/test_state_laws.py -v`
Expected: PASS (including the existing tests).

- [ ] **Step 5: Commit**

```bash
git add importer/importer/state_laws.py importer/tests/test_state_laws.py
git commit -m "feat(importer): add osm_categories_for_state for OSM auto-scope

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: OSM source module (`sources/osm.py`)

Overpass-backed source with per-state auto-scope. `fetch()` downloads one cached JSON per auto-scoped state; `iter_candidates()` parses cached JSON into `Candidate`s. Mirrors the two-phase shape of `faa.py`.

**Files:**
- Create: `importer/importer/sources/osm.py`
- Create: `importer/tests/sources/test_osm.py`
- Create: `importer/tests/fixtures/osm_tx_bars_sample.json`

> The fixture below is a representative, hand-built Overpass response. Task 11 runs a live Overpass query and replaces it with real captured data if the shape differs.

- [ ] **Step 1: Create the test fixture**

Create `importer/tests/fixtures/osm_tx_bars_sample.json`:

```json
{
  "version": 0.6,
  "generator": "Overpass API",
  "elements": [
    {"type": "node", "id": 1001, "lat": 29.7604, "lon": -95.3698,
     "tags": {"amenity": "bar", "name": "The Houston Tap"}},
    {"type": "way", "id": 2002, "center": {"lat": 29.7610, "lon": -95.3700},
     "tags": {"amenity": "pub", "name": "Downtown Pub House"}},
    {"type": "node", "id": 1003, "lat": 29.7000, "lon": -95.4000,
     "tags": {"amenity": "bar"}},
    {"type": "node", "id": 1004, "lat": 34.0522, "lon": -118.2437,
     "tags": {"amenity": "bar", "name": "Out Of State Bar"}}
  ]
}
```

(Node 1001 = clean node bar; way 2002 = polygon centroid pub; node 1003 = no name → skipped; node 1004 = coords in CA but we’ll claim TX → `coord_state_mismatch` skip.)

- [ ] **Step 2: Write the failing tests**

Create `importer/tests/sources/test_osm.py`:

```python
import json
from pathlib import Path

import pytest
from pytest_httpx import HTTPXMock

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.osm import OsmSource
from importer.state_laws import load_state_laws

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"
STATES_YAML = Path(__file__).parents[3] / "data" / "state_laws" / "states.yaml"


def _make_source(tmp_path: Path, states: list[str]) -> OsmSource:
    return OsmSource(
        cache_dir=tmp_path,
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
        state_laws=load_state_laws(STATES_YAML),
        states=states,
        dataset_version="OSM-FIXTURE",
        overpass_url="https://overpass.example/api/interpreter",
        area_selector_template='["ISO3166-2"="US-{state}"]',
        category_tags={"BAR_ALCOHOL": ["amenity=bar", "amenity=pub"]},
    )


def test_source_name_is_stable(tmp_path):
    assert _make_source(tmp_path, ["TX"]).SOURCE_NAME == "osm"


def test_query_plan_is_per_state_autoscoped(tmp_path):
    src = _make_source(tmp_path, ["TX", "FL", "PA"])
    plan = src.build_query_plan(["TX", "FL", "PA"])
    # TX/FL have a BAR_ALCOHOL osm cell; PA does not -> no PA query at all.
    assert set(plan) == {"TX", "FL"}
    assert plan["TX"] == ["amenity=bar", "amenity=pub"]


def test_fetch_posts_overpass_query_and_caches(tmp_path, httpx_mock: HTTPXMock):
    httpx_mock.add_response(
        method="POST",
        url="https://overpass.example/api/interpreter",
        json={"elements": []},
    )
    src = _make_source(tmp_path, ["TX"])
    src.fetch()
    assert (tmp_path / "TX.json").exists()
    req = httpx_mock.get_requests()[0]
    body = req.content.decode()
    assert '["ISO3166-2"="US-TX"]' in body
    assert 'nwr["amenity"="bar"]' in body
    assert 'nwr["amenity"="pub"]' in body


def test_iter_candidates_parses_nodes_and_way_centers(tmp_path):
    (tmp_path / "TX.json").write_bytes(
        (FIXTURE_DIR / "osm_tx_bars_sample.json").read_bytes()
    )
    src = _make_source(tmp_path, ["TX"])
    cands = {c.source_external_id: c for c in src.iter_candidates(state_filter={"TX"})}

    assert set(cands) == {"node/1001", "way/2002"}
    assert cands["node/1001"].coord_quality is CoordQuality.PRECISE
    assert cands["way/2002"].coord_quality is CoordQuality.BUILDING_POLYGON
    assert all(c.category is RestrictionTag.BAR_ALCOHOL for c in cands.values())
    assert all(c.state == "TX" for c in cands.values())
    assert src.last_skip_counts["missing_name"] >= 1          # node/1003
    assert src.last_skip_counts["coord_state_mismatch"] >= 1  # node/1004


def test_iter_candidates_skips_states_with_no_plan(tmp_path):
    src = _make_source(tmp_path, ["PA"])
    assert list(src.iter_candidates(state_filter={"PA"})) == []
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd importer && python -m pytest tests/sources/test_osm.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.sources.osm'`.

- [ ] **Step 4: Implement `sources/osm.py`**

Create `importer/importer/sources/osm.py`:

```python
"""OpenStreetMap venues via the Overpass API -> Candidate stream.

Per-state auto-scope: the source asks the state-law table which categories have
an `osm`-filtered cell for each requested state and queries Overpass only for
those. For the pilot (TX/FL/PA) that resolves to BAR_ALCOHOL in TX and FL; PA
generates no query at all. This keeps load off the free, shared Overpass API and
matches OMISSIONS.md (worship/sports/healthcare have no categorical prohibition
in the pilot states, so they are never queried).

License: ODbL (share-alike) — the only pilot source so licensed. The ODbL dump
(stages/odbl_dump.py) publishes the derived columns of source='osm' rows.
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source
from importer.state_laws import StateLawTable


class OsmSource(Source):
    SOURCE_NAME: ClassVar[str] = "osm"

    def __init__(
        self,
        *,
        cache_dir: Path,
        state_locator: StateLocator,
        state_laws: StateLawTable,
        states: list[str],
        dataset_version: str,
        area_selector_template: str,
        category_tags: dict[str, list[str]],
        overpass_url: str = "",
        timeout: float = 240.0,
    ) -> None:
        self._cache_dir = cache_dir
        self._locator = state_locator
        self._state_laws = state_laws
        self._states = list(states)
        self._version = dataset_version
        self._area_template = area_selector_template
        self._category_tags = category_tags
        self._overpass_url = overpass_url
        self._timeout = timeout
        self.last_skip_counts: Counter[str] = Counter()
        # Reverse map "amenity=bar" -> BAR_ALCOHOL for classifying returned elements.
        self._tag_to_category: dict[str, RestrictionTag] = {}
        for cat_name, tags in category_tags.items():
            cat = RestrictionTag(cat_name)
            for tag in tags:
                self._tag_to_category[tag] = cat

    def build_query_plan(self, states: list[str]) -> dict[str, list[str]]:
        """state -> ordered union of OSM tag filters to query for that state.

        States with no auto-scoped category (e.g. PA) are omitted entirely.
        """
        plan: dict[str, list[str]] = {}
        for state in states:
            tags: list[str] = []
            for category in sorted(
                self._state_laws.osm_categories_for_state(state), key=lambda c: c.value
            ):
                cat_tags = self._category_tags.get(category.value)
                if not cat_tags:
                    # Auto-scope picked a category we have no Overpass tags for.
                    # Surface it; never silently default.
                    self.last_skip_counts[f"no_tag_map:{category.value}"] += 1
                    continue
                tags.extend(cat_tags)
            if tags:
                plan[state] = tags
        return plan

    def _build_query(self, state: str, tags: list[str]) -> str:
        area = self._area_template.format(state=state)
        clauses = []
        for tag in tags:
            key, _, value = tag.partition("=")
            clauses.append(f'  nwr["{key}"="{value}"](area.a);')
        body = "\n".join(clauses)
        return (
            "[out:json][timeout:180];\n"
            f"area{area}->.a;\n"
            "(\n"
            f"{body}\n"
            ");\n"
            "out center tags;\n"
        )

    def fetch(self, *, refetch: bool = False) -> None:
        plan = self.build_query_plan(self._states)
        if plan and not self._overpass_url:
            raise RuntimeError(
                "osm overpass_url not configured; set sources.osm.overpass_url in config.yaml"
            )
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=self._timeout, follow_redirects=True) as client:
            for state, tags in plan.items():
                dest = self._cache_dir / f"{state}.json"
                if dest.exists() and not refetch:
                    continue
                query = self._build_query(state, tags)
                r = client.post(self._overpass_url, content=query.encode("utf-8"))
                r.raise_for_status()
                dest.write_bytes(r.content)

    def _element_coords(self, el: dict) -> tuple[float, float] | None:
        if "lat" in el and "lon" in el:
            return float(el["lat"]), float(el["lon"])
        center = el.get("center")
        if center and "lat" in center and "lon" in center:
            return float(center["lat"]), float(center["lon"])
        return None

    def _category_for(self, tags: dict) -> RestrictionTag | None:
        for key, value in tags.items():
            cat = self._tag_to_category.get(f"{key}={value}")
            if cat is not None:
                return cat
        return None

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        states = sorted(state_filter) if state_filter else list(self._states)
        plan = self.build_query_plan(states)
        for state in plan:
            path = self._cache_dir / f"{state}.json"
            if not path.exists():
                self.last_skip_counts["missing_cache"] += 1
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            for el in data.get("elements", []):
                el_type = el.get("type")
                el_id = el.get("id")
                if el_type not in ("node", "way", "relation") or el_id is None:
                    self.last_skip_counts["malformed_element"] += 1
                    continue
                tags = el.get("tags") or {}
                name = (tags.get("name") or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                category = self._category_for(tags)
                if category is None:
                    self.last_skip_counts["no_category_tag"] += 1
                    continue
                coords = self._element_coords(el)
                if coords is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                lat, lng = coords
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                quality = (
                    CoordQuality.PRECISE
                    if el_type == "node"
                    else CoordQuality.BUILDING_POLYGON
                )
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=f"{el_type}/{el_id}",
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=quality,
                    category=category,
                    state=state,
                    extra={},
                )
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/sources/test_osm.py -v`
Expected: PASS (all 5).

- [ ] **Step 6: Commit**

```bash
git add importer/importer/sources/osm.py importer/tests/sources/test_osm.py importer/tests/fixtures/osm_tx_bars_sample.json
git commit -m "feat(importer): add Overpass OSM source with per-state auto-scope

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Config + CLI wiring for `osm`

Register the source so `--sources osm` works, injecting the state-law table and the requested states.

**Files:**
- Modify: `importer/config.yaml`
- Modify: `importer/importer/cli.py`
- Test: `importer/tests/test_cli.py`

- [ ] **Step 1: Add config**

Append to `importer/config.yaml` under `sources:`:

```yaml
  osm:
    # OpenStreetMap venues via Overpass. ODbL (share-alike); the ODbL dump
    # (stages/odbl_dump.py) republishes derived columns after each apply.
    # Per-state auto-scope means only categories with an osm-filtered state-law
    # cell are queried (pilot: BAR_ALCOHOL in TX/FL; PA generates no query).
    cache_dir: "data/sources/osm"
    dataset_version: "OSM-2026-06"
    overpass_url: "https://overpass-api.de/api/interpreter"
    area_selector_template: '["ISO3166-2"="US-{state}"]'
    categories:
      BAR_ALCOHOL:
        tags: ["amenity=bar", "amenity=pub"]
```

- [ ] **Step 2: Write the failing test**

Inspect `importer/tests/test_cli.py` for how it invokes `_build_source` or `build_parser`. Add a test that `osm` is accepted and builds. If the file builds sources via `_build_source`, mirror its style; otherwise assert parser acceptance:

```python
def test_osm_is_a_supported_source():
    from importer.cli import SUPPORTED_SOURCES
    assert "osm" in SUPPORTED_SOURCES


def test_build_source_constructs_osm(tmp_path):
    import yaml
    from pathlib import Path
    from importer.cli import _build_source, CONFIG_PATH, STATES_BOUNDARY_FIXTURE, STATES_YAML
    from importer.geo.states import load_state_locator
    from importer.state_laws import load_state_laws
    from importer.sources.osm import OsmSource

    config = yaml.safe_load(Path(CONFIG_PATH).read_text(encoding="utf-8"))
    locator = load_state_locator(STATES_BOUNDARY_FIXTURE)
    laws = load_state_laws(STATES_YAML)
    src = _build_source(
        "osm", config=config, locator=locator, repo_root=tmp_path,
        state_laws=laws, states=["TX", "FL", "PA"],
    )
    assert isinstance(src, OsmSource)
    assert src.SOURCE_NAME == "osm"
```

> If `test_cli.py` already imports these constants under different names, match them. `STATES_BOUNDARY_FIXTURE` / `STATES_YAML` / `CONFIG_PATH` are module-level in `cli.py`.

- [ ] **Step 3: Run test to verify it fails**

Run: `cd importer && python -m pytest tests/test_cli.py::test_osm_is_a_supported_source -v`
Expected: FAIL — `"osm"` not in `SUPPORTED_SOURCES`.

- [ ] **Step 4: Wire the CLI**

In `importer/importer/cli.py`:

1. Add the import near the other source imports:
```python
from importer.sources.osm import OsmSource
```

2. Add `"osm"` to `SUPPORTED_SOURCES`:
```python
SUPPORTED_SOURCES = ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa", "osm")
```

3. Change `_build_source` to accept `state_laws` and `states`, and add the `osm` branch. Replace the signature and add the branch:
```python
def _build_source(name, *, config, locator, repo_root, state_laws, states):
    cfg = config["sources"][name]
    cache_dir = Path(repo_root) / cfg["cache_dir"]
    version = cfg["dataset_version"]
    url = cfg.get("url", "")
    if name == "osm":
        return OsmSource(
            cache_dir=cache_dir,
            state_locator=locator,
            state_laws=state_laws,
            states=states,
            dataset_version=version,
            area_selector_template=cfg["area_selector_template"],
            category_tags={k: v["tags"] for k, v in cfg["categories"].items()},
            overpass_url=cfg.get("overpass_url", ""),
        )
    # ... existing branches unchanged ...
```

4. Update the call site in `main()` (currently builds the list comprehension) to pass the new kwargs:
```python
            sources = [
                _build_source(
                    name, config=config, locator=locator, repo_root=REPO_ROOT,
                    state_laws=state_laws, states=args.states,
                )
                for name in args.sources
            ]
```

(`state_laws` and `args.states` are already in scope in `main()`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/test_cli.py -v`
Expected: PASS (existing CLI tests still green — they call `_build_source` only via `main()`, which now passes the new kwargs).

- [ ] **Step 6: Commit**

```bash
git add importer/config.yaml importer/importer/cli.py importer/tests/test_cli.py
git commit -m "feat(importer): register osm source in config + CLI

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Smart title-case helper (`stages/_titlecase.py`)

Pure function, no I/O. Resolves the deferred all-caps-label feedback.

**Files:**
- Create: `importer/importer/stages/_titlecase.py`
- Create: `importer/tests/stages/test_titlecase.py`

- [ ] **Step 1: Write the failing tests**

Create `importer/tests/stages/test_titlecase.py`:

```python
from importer.stages._titlecase import smart_title_case


def test_basic_all_caps_to_title():
    assert smart_title_case("UNITED STATES COURTHOUSE") == "United States Courthouse"


def test_preserves_trailing_state_code():
    assert smart_title_case("OFFICE BUILDING TAMPA FL") == "Office Building Tampa FL"


def test_preserves_federal_acronyms():
    assert smart_title_case("US ARMY CORPS USACE DEPOT") == "US Army Corps USACE Depot"


def test_ambiguous_state_codes_are_not_uppercase_preserved():
    # IN/OR are also English words; title-case them rather than shouting them.
    assert smart_title_case("BUILDING IN TAMPA") == "Building In Tampa"
    assert smart_title_case("PARK OR LOT") == "Park Or Lot"


def test_mc_and_apostrophe_names():
    assert smart_title_case("MCDONALD HALL") == "McDonald Hall"
    assert smart_title_case("O'BRIEN CENTER") == "O'Brien Center"


def test_hyphen_and_roman_numerals():
    assert smart_title_case("WINSTON-SALEM CENTER III") == "Winston-Salem Center III"


def test_ordinals_lowercased():
    assert smart_title_case("1ST AVENUE BUILDING") == "1st Avenue Building"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd importer && python -m pytest tests/stages/test_titlecase.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'importer.stages._titlecase'`.

- [ ] **Step 3: Implement `_titlecase.py`**

Create `importer/importer/stages/_titlecase.py`:

```python
"""Smart title-casing for all-caps source labels (importer-feedback issue 5).

Only the normalize stage calls this, and only for names with no lowercase letter
(see normalize.py) — already-mixed-case names are assumed well-cased and left
untouched. The preserve-list is curated and maintained: add acronyms as new
sources surface them.
"""

from __future__ import annotations

import re

# 2-letter USPS codes that are ALSO common English words: title-case them
# normally (Building In Tampa) rather than shouting them (Building IN Tampa).
_AMBIGUOUS_STATE_CODES = {"IN", "OR", "OK", "ME", "HI", "OH", "ID"}

_STATE_CODES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "IA", "IL",
    "KS", "KY", "LA", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV",
    "NH", "NJ", "NM", "NY", "NC", "ND", "PA", "RI", "SC", "SD", "TN", "TX",
    "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC",
} - _AMBIGUOUS_STATE_CODES

# Federal agencies / common government acronyms seen in GSA/HIFLD/FAA labels.
_FEDERAL_ACRONYMS = {
    "US", "USA", "VA", "SBA", "FBI", "IRS", "FAA", "GSA", "DOD", "USACE",
    "NFH", "USCG", "TSA", "DHS", "FEMA", "ATF", "DEA", "EPA", "NOAA", "NASA",
    "USDA", "DOI", "DOJ", "DOT", "HHS", "HUD", "NPS", "USFS", "BLM", "USGS",
    "NIH", "CDC", "FDA", "SSA", "USPS", "NWS", "USAF", "USMC",
}

_PRESERVE: frozenset[str] = frozenset(_STATE_CODES | _FEDERAL_ACRONYMS)

_ROMAN_RE = re.compile(r"^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$")
_ORDINAL_RE = re.compile(r"^\d+(ST|ND|RD|TH)$", re.IGNORECASE)


def _capitalize(word: str) -> str:
    return word[:1].upper() + word[1:].lower() if word else word


def _case_token(token: str) -> str:
    if not token:
        return token
    upper = token.upper()
    if upper in _PRESERVE:
        return upper
    if len(token) > 1 and _ROMAN_RE.match(upper):
        return upper
    if _ORDINAL_RE.match(token):
        return token.lower()
    if "-" in token:
        return "-".join(_case_token(p) for p in token.split("-"))
    if "'" in token:
        return "'".join(_capitalize(p) for p in token.split("'"))
    if upper.startswith("MC") and len(token) > 2:
        return "Mc" + _capitalize(token[2:])
    return _capitalize(token)


def smart_title_case(name: str) -> str:
    return " ".join(_case_token(tok) for tok in name.split(" "))
```

> Note: `_ROMAN_RE` matches the empty string, hence the `len(token) > 1` guard and the explicit `_PRESERVE`/ordinal checks first so short tokens like "DC" or "1ST" are handled before the roman test.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/stages/test_titlecase.py -v`
Expected: PASS (all 8).

- [ ] **Step 5: Commit**

```bash
git add importer/importer/stages/_titlecase.py importer/tests/stages/test_titlecase.py
git commit -m "feat(importer): add smart title-case helper for all-caps labels

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Apply title-casing in `normalize` (all-caps guard)

**Files:**
- Modify: `importer/importer/stages/normalize.py`
- Test: `importer/tests/stages/test_normalize.py`

- [ ] **Step 1: Write the failing tests**

`importer/tests/stages/test_normalize.py` already has a `_c(name)` helper that builds a `Candidate` and imports `NormalizeStats`, `normalize`. Add these tests using `_c`:

```python
def test_normalize_titlecases_all_caps_names():
    out = list(normalize([_c("UNITED STATES COURTHOUSE")], stats=NormalizeStats()))
    assert out[0].name == "United States Courthouse"


def test_normalize_leaves_mixed_case_untouched():
    out = list(normalize([_c("The Ginger Man")], stats=NormalizeStats()))
    assert out[0].name == "The Ginger Man"


def test_normalize_titlecase_preserves_trailing_state_and_acronyms():
    out = list(normalize([_c("USACE DEPOT TAMPA FL")], stats=NormalizeStats()))
    assert out[0].name == "USACE Depot Tampa FL"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd importer && python -m pytest tests/stages/test_normalize.py::test_normalize_titlecases_all_caps_names -v`
Expected: FAIL — name is still `"UNITED STATES COURTHOUSE"`.

- [ ] **Step 3: Implement the guard in `normalize.py`**

Edit `importer/importer/stages/normalize.py`. Add the import and the guard:

```python
from importer.stages._titlecase import smart_title_case
```

In the loop, after `new_name = c.name.strip()` and before the truncation block, insert:

```python
        # Re-case only all-caps source labels (no lowercase letter present);
        # already-mixed-case names (OSM, HIFLD, recomposed GSA) are left as-is.
        if new_name and not any(ch.islower() for ch in new_name):
            new_name = smart_title_case(new_name)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/stages/test_normalize.py -v`
Expected: PASS (existing truncation tests still green — title-casing preserves length).

- [ ] **Step 5: Commit**

```bash
git add importer/importer/stages/normalize.py importer/tests/stages/test_normalize.py
git commit -m "feat(importer): title-case all-caps labels in normalize stage

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: SupabaseClient Storage methods + OSM dump reader

**Files:**
- Modify: `importer/importer/supabase_client.py`
- Test: `importer/tests/test_supabase_client.py`

- [ ] **Step 1: Write the failing tests**

Add to `importer/tests/test_supabase_client.py`:

```python
from importer.supabase_client import OsmDumpRow


def test_select_osm_pins_for_dump_parses(client, httpx_mock):
    httpx_mock.add_response(
        method="GET",
        json=[
            {"source_external_id": "node/1001", "name": "The Houston Tap",
             "latitude": 29.76, "longitude": -95.37},
        ],
    )
    rows = client.select_osm_pins_for_dump()
    assert rows == [OsmDumpRow(source_external_id="node/1001",
                               name="The Houston Tap", latitude=29.76, longitude=-95.37)]
    assert "source=eq.osm" in str(httpx_mock.get_requests()[0].url)


def test_ensure_public_bucket_treats_existing_as_success(client, httpx_mock):
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/storage/v1/bucket",
        status_code=409,
        json={"error": "Duplicate", "message": "already exists"},
    )
    client.ensure_public_bucket("odbl-dumps")  # must not raise


def test_upload_object_posts_with_upsert(client, httpx_mock):
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/storage/v1/object/odbl-dumps/dump-2026-06-16.csv.gz",
        status_code=200,
        json={"Key": "odbl-dumps/dump-2026-06-16.csv.gz"},
    )
    client.upload_object(
        bucket="odbl-dumps", path="dump-2026-06-16.csv.gz",
        data=b"\x1f\x8b", content_type="application/gzip",
    )
    req = httpx_mock.get_requests()[0]
    assert req.headers.get("x-upsert") == "true"
    assert req.content == b"\x1f\x8b"


def test_public_object_url():
    from importer.supabase_client import SupabaseClient
    c = SupabaseClient(url="https://example.supabase.co", service_role_key="k",
                       system_user_id="u")
    assert c.public_object_url("odbl-dumps", "dump-2026-06-16.csv.gz") == (
        "https://example.supabase.co/storage/v1/object/public/odbl-dumps/dump-2026-06-16.csv.gz"
    )


def test_delete_objects_sends_prefixes(client, httpx_mock):
    httpx_mock.add_response(
        method="DELETE",
        url="https://example.supabase.co/storage/v1/object/odbl-dumps",
        status_code=200, json=[],
    )
    client.delete_objects("odbl-dumps", ["dump-2026-01-01.csv.gz"])
    req = httpx_mock.get_requests()[0]
    assert b"dump-2026-01-01.csv.gz" in req.content
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd importer && python -m pytest tests/test_supabase_client.py::test_select_osm_pins_for_dump_parses -v`
Expected: FAIL — `ImportError: cannot import name 'OsmDumpRow'`.

- [ ] **Step 3: Implement the Storage methods**

In `importer/importer/supabase_client.py`:

1. Add the model near `ExistingPinRow`:
```python
class OsmDumpRow(BaseModel):
    model_config = ConfigDict(frozen=True)

    source_external_id: str
    name: str
    latitude: float
    longitude: float
```

2. In `__init__`, after `self._base = ...`, add the storage/project bases:
```python
        self._project_url = url.rstrip("/")
        self._storage_base = self._project_url + "/storage/v1"
```

3. Add methods to `SupabaseClient`:
```python
    def select_osm_pins_for_dump(self) -> list["OsmDumpRow"]:
        """All source='osm' rows, derived columns only (for the ODbL dump)."""
        out: list[OsmDumpRow] = []
        offset = 0
        page = 1000
        while True:
            headers = dict(self._headers)
            headers["Range-Unit"] = "items"
            headers["Range"] = f"{offset}-{offset + page - 1}"
            params = {
                "select": "source_external_id,name,latitude,longitude",
                "source": "eq.osm",
            }
            r = self._client.get(f"{self._base}/pins", headers=headers, params=params)
            r.raise_for_status()
            rows = r.json()
            out.extend(OsmDumpRow.model_validate(row) for row in rows)
            if len(rows) < page:
                break
            offset += page
        return out

    def public_object_url(self, bucket: str, path: str) -> str:
        return f"{self._storage_base}/object/public/{bucket}/{path}"

    def ensure_public_bucket(self, bucket: str) -> None:
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": "application/json",
        }
        r = self._client.post(
            f"{self._storage_base}/bucket",
            headers=headers,
            json={"id": bucket, "name": bucket, "public": True},
        )
        # 200/201 = created; 409 (or 400 "already exists") = idempotent success.
        if r.status_code in (200, 201, 409):
            return
        if r.status_code == 400 and "exist" in r.text.lower():
            return
        r.raise_for_status()

    def upload_object(
        self, *, bucket: str, path: str, data: bytes, content_type: str
    ) -> None:
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": content_type,
            "x-upsert": "true",
        }
        r = self._client.post(
            f"{self._storage_base}/object/{bucket}/{path}",
            headers=headers,
            content=data,
        )
        r.raise_for_status()

    def list_object_names(self, bucket: str) -> list[str]:
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": "application/json",
        }
        r = self._client.post(
            f"{self._storage_base}/object/list/{bucket}",
            headers=headers,
            json={"prefix": "", "limit": 1000, "offset": 0},
        )
        r.raise_for_status()
        return [obj["name"] for obj in r.json()]

    def delete_objects(self, bucket: str, paths: list[str]) -> None:
        if not paths:
            return
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": "application/json",
        }
        r = self._client.request(
            "DELETE",
            f"{self._storage_base}/object/{bucket}",
            headers=headers,
            json={"prefixes": paths},
        )
        r.raise_for_status()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/test_supabase_client.py -v`
Expected: PASS (existing tests still green).

- [ ] **Step 5: Commit**

```bash
git add importer/importer/supabase_client.py importer/tests/test_supabase_client.py
git commit -m "feat(importer): add Supabase Storage methods + OSM dump reader

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: ODbL dump generator (replace the stub)

**Files:**
- Modify: `importer/importer/stages/odbl_dump.py`
- Create: `importer/tests/stages/test_odbl_dump.py`
- Delete: `importer/tests/stages/test_odbl_dump_stub.py`

- [ ] **Step 1: Delete the stub test and write the new tests**

Delete `importer/tests/stages/test_odbl_dump_stub.py`. Create `importer/tests/stages/test_odbl_dump.py`:

```python
import gzip
from datetime import date
from pathlib import Path

from importer.stages.odbl_dump import generate_and_upload
from importer.supabase_client import OsmDumpRow


class FakeClient:
    def __init__(self, rows, existing_objects=None):
        self._rows = rows
        self._objects = existing_objects or []
        self.uploaded = []
        self.deleted = []
        self.ensured = []

    def select_osm_pins_for_dump(self):
        return self._rows

    def ensure_public_bucket(self, bucket):
        self.ensured.append(bucket)

    def upload_object(self, *, bucket, path, data, content_type):
        self.uploaded.append((bucket, path, data, content_type))

    def list_object_names(self, bucket):
        return list(self._objects)

    def delete_objects(self, bucket, paths):
        self.deleted.extend(paths)

    def public_object_url(self, bucket, path):
        return f"https://example.supabase.co/storage/v1/object/public/{bucket}/{path}"


def test_returns_none_when_no_osm_rows(tmp_path):
    client = FakeClient(rows=[])
    assert generate_and_upload(client=client, out_dir=tmp_path) is None
    assert client.uploaded == []


def test_writes_gz_with_header_and_uploads(tmp_path):
    rows = [
        OsmDumpRow(source_external_id="node/1001", name="The Houston Tap",
                   latitude=29.76, longitude=-95.37),
        OsmDumpRow(source_external_id="way/2002", name="Downtown Pub House",
                   latitude=29.761, longitude=-95.37),
    ]
    client = FakeClient(rows=rows)
    url = generate_and_upload(client=client, out_dir=tmp_path, today=date(2026, 6, 16))

    expected_name = "dump-2026-06-16.csv.gz"
    assert url.endswith(expected_name)
    written = tmp_path / expected_name
    text = gzip.decompress(written.read_bytes()).decode("utf-8")
    assert text.startswith("#")                       # ODbL license header
    assert "Open Database License" in text
    assert "osm_type,osm_id,name,latitude,longitude" in text
    assert "node,1001,The Houston Tap,29.76,-95.37" in text
    assert "way,2002,Downtown Pub House,29.761,-95.37" in text

    assert client.ensured == ["odbl-dumps"]
    bucket, path, data, ctype = client.uploaded[0]
    assert (bucket, path, ctype) == ("odbl-dumps", expected_name, "application/gzip")
    assert data == written.read_bytes()


def test_prunes_dumps_older_than_90_days(tmp_path):
    rows = [OsmDumpRow(source_external_id="node/1", name="A", latitude=29.0, longitude=-95.0)]
    client = FakeClient(
        rows=rows,
        existing_objects=[
            "dump-2026-01-01.csv.gz",   # >90 days before 2026-06-16 -> pruned
            "dump-2026-06-10.csv.gz",   # within 90 days -> kept
            "not-a-dump.txt",           # ignored
        ],
    )
    generate_and_upload(client=client, out_dir=tmp_path, today=date(2026, 6, 16))
    assert client.deleted == ["dump-2026-01-01.csv.gz"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd importer && python -m pytest tests/stages/test_odbl_dump.py -v`
Expected: FAIL — `ImportError: cannot import name 'generate_and_upload'`.

- [ ] **Step 3: Replace `odbl_dump.py`**

Overwrite `importer/importer/stages/odbl_dump.py`:

```python
"""ODbL share-alike dump for OSM-sourced pins (spec §6.3-6.5).

Publishes the *derived database* — the OSM-derived columns of source='osm' rows
(osm_type, osm_id, name, latitude, longitude). It deliberately EXCLUDES our work
product (status, restriction tag, citation, confidence), which is not OSM-derived.
Anyone can re-derive our classification from these ids against OpenStreetMap.

Wired into pipeline Phase D (apply mode only). Generates a dated, gzip'd CSV,
uploads it to a public Supabase Storage bucket, and prunes dumps > 90 days old.
"""

from __future__ import annotations

import csv
import gzip
import io
import logging
import re
from datetime import date, timedelta
from pathlib import Path
from typing import Protocol

logger = logging.getLogger(__name__)

_PRUNE_AFTER_DAYS = 90
_DUMP_RE = re.compile(r"^dump-(\d{4})-(\d{2})-(\d{2})\.csv\.gz$")

_LICENSE_HEADER = (
    "# CCW Map — OpenStreetMap-derived venue database (ODbL share-alike).\n"
    "# Source: OpenStreetMap contributors. License: Open Database License (ODbL) v1.0.\n"
    "# https://opendatacommons.org/licenses/odbl/1-0/\n"
    "# Contains only OSM-derived columns; legal classifications are excluded.\n"
)


class _DumpClient(Protocol):
    def select_osm_pins_for_dump(self) -> list: ...
    def ensure_public_bucket(self, bucket: str) -> None: ...
    def upload_object(self, *, bucket: str, path: str, data: bytes, content_type: str) -> None: ...
    def list_object_names(self, bucket: str) -> list[str]: ...
    def delete_objects(self, bucket: str, paths: list[str]) -> None: ...
    def public_object_url(self, bucket: str, path: str) -> str: ...


def generate_and_upload(
    *,
    client: _DumpClient,
    out_dir: Path,
    bucket: str = "odbl-dumps",
    today: date | None = None,
) -> str | None:
    """Build + upload the dated ODbL dump. Returns its public URL, or None if no
    OSM rows exist."""
    rows = client.select_osm_pins_for_dump()
    if not rows:
        logger.info("odbl_dump: no OSM rows; nothing to dump.")
        return None

    today = today or date.today()
    filename = f"dump-{today.isoformat()}.csv.gz"

    buf = io.StringIO()
    buf.write(_LICENSE_HEADER)
    writer = csv.writer(buf)
    writer.writerow(["osm_type", "osm_id", "name", "latitude", "longitude"])
    for row in rows:
        osm_type, _, osm_id = row.source_external_id.partition("/")
        writer.writerow([osm_type, osm_id, row.name, row.latitude, row.longitude])
    data = gzip.compress(buf.getvalue().encode("utf-8"))

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / filename).write_bytes(data)

    client.ensure_public_bucket(bucket)
    client.upload_object(bucket=bucket, path=filename, data=data, content_type="application/gzip")
    _prune(client, bucket, today)

    url = client.public_object_url(bucket, filename)
    logger.info("odbl_dump: uploaded %d OSM rows to %s", len(rows), url)
    return url


def _prune(client: _DumpClient, bucket: str, today: date) -> None:
    cutoff = today - timedelta(days=_PRUNE_AFTER_DAYS)
    stale: list[str] = []
    for name in client.list_object_names(bucket):
        m = _DUMP_RE.match(name)
        if not m:
            continue
        dumped = date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if dumped < cutoff:
            stale.append(name)
    if stale:
        client.delete_objects(bucket, stale)
        logger.info("odbl_dump: pruned %d dumps older than %d days", len(stale), _PRUNE_AFTER_DAYS)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/stages/test_odbl_dump.py -v`
Expected: PASS (all 3).

- [ ] **Step 5: Commit**

```bash
git add importer/importer/stages/odbl_dump.py importer/tests/stages/test_odbl_dump.py
git rm importer/tests/stages/test_odbl_dump_stub.py
git commit -m "feat(importer): real ODbL dump generator + public Storage upload

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Pipeline Phase D + report surfacing

Run the dump after an apply that touched OSM; surface the URL in the report.

**Files:**
- Modify: `importer/importer/reports/__init__.py`
- Modify: `importer/importer/pipeline.py`
- Modify: `importer/importer/reports/markdown.py`
- Test: `importer/tests/test_pipeline.py`, `importer/tests/reports/test_markdown.py`

- [ ] **Step 1: Write the failing tests**

`importer/tests/reports/test_markdown.py` already imports `DedupReport`, `PipelineResult`, `render_markdown`, and `datetime`/`timezone` at the top. Add:

```python
def test_markdown_renders_odbl_dump_url() -> None:
    result = PipelineResult(
        mode="apply",
        started_at=datetime(2026, 6, 16, tzinfo=timezone.utc),
        completed_at=datetime(2026, 6, 16, tzinfo=timezone.utc),
        states=["TX", "FL"],
        sources=[],
        dedup=DedupReport(),
        odbl_dump_url="https://example.supabase.co/storage/v1/object/public/odbl-dumps/dump-2026-06-16.csv.gz",
    )
    md = render_markdown(result)
    assert "## ODbL dump" in md
    assert "dump-2026-06-16.csv.gz" in md
```

`importer/tests/test_pipeline.py` already has `_FakeSource(name, candidates)` and `_mock_client()` (a `MagicMock` whose `select_pins_by_keys`/`select_user_pins` return `[]`), and imports `Candidate`, `CoordQuality`, `RestrictionTag`, `StateLawCell`, `StateLawTable`, `run_pipeline`, and `date`. Add:

```python
def _osm_bar_table() -> StateLawTable:
    return StateLawTable(rows=[
        StateLawCell(
            state="TX", category=RestrictionTag.BAR_ALCOHOL,
            default_status="NO_GUN", confidence="medium", conditions=[],
            citation="TX Penal Code 46.03(a)(7)",
            last_verified_date=date(2026, 5, 31), source_filter=["osm"],
        ),
    ])


def _osm_bar() -> Candidate:
    return Candidate(
        source="osm", source_external_id="node/1", source_dataset_version="v",
        name="The Houston Tap", latitude=29.7604, longitude=-95.3698,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.BAR_ALCOHOL, state="TX",
    )


def test_apply_generates_odbl_dump_when_osm_inserts(monkeypatch) -> None:
    import importer.pipeline as pipeline_mod
    calls = {}

    def fake_generate(*, client, out_dir, **kwargs):
        calls["called"] = True
        return "https://example/storage/v1/object/public/odbl-dumps/dump-2026-06-16.csv.gz"

    monkeypatch.setattr(pipeline_mod, "generate_and_upload", fake_generate)

    result = run_pipeline(
        sources=[_FakeSource("osm", [_osm_bar()])],
        state_laws=_osm_bar_table(),
        client=_mock_client(),
        states=["TX"],
        mode="apply",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert calls.get("called") is True
    assert result.odbl_dump_url.endswith("dump-2026-06-16.csv.gz")


def test_dry_run_does_not_generate_odbl_dump(monkeypatch) -> None:
    import importer.pipeline as pipeline_mod
    calls = {}
    monkeypatch.setattr(
        pipeline_mod, "generate_and_upload",
        lambda **kw: calls.setdefault("called", True),
    )
    result = run_pipeline(
        sources=[_FakeSource("osm", [_osm_bar()])],
        state_laws=_osm_bar_table(),
        client=_mock_client(),
        states=["TX"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert "called" not in calls
    assert result.odbl_dump_url is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd importer && python -m pytest tests/reports/test_markdown.py::test_markdown_renders_odbl_dump_url -v`
Expected: FAIL — `PipelineResult` has no `odbl_dump_url`.

- [ ] **Step 3: Add the field**

In `importer/importer/reports/__init__.py`, add to `PipelineResult`:

```python
    odbl_dump_url: str | None = None
```

- [ ] **Step 4: Render it in markdown**

In `importer/importer/reports/markdown.py`, before the `if r.errors:` block in `render_markdown`, add:

```python
    if r.odbl_dump_url:
        lines.append("## ODbL dump")
        lines.append("")
        lines.append(f"- OpenStreetMap-derived database published: {r.odbl_dump_url}")
        lines.append("")
```

- [ ] **Step 5: Wire Phase D in the pipeline**

In `importer/importer/pipeline.py`:

1. Add imports at the top:
```python
from pathlib import Path

from importer.stages.odbl_dump import generate_and_upload
```

2. After the per-source `for ps in per_source:` loop completes (i.e. after `source_results` is fully built) and before the `return PipelineResult(...)`, add Phase D:
```python
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
```

3. Pass it into the result:
```python
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
        odbl_dump_url=odbl_dump_url,
    )
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd importer && python -m pytest tests/test_pipeline.py tests/reports/test_markdown.py -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add importer/importer/pipeline.py importer/importer/reports/__init__.py importer/importer/reports/markdown.py importer/tests/test_pipeline.py importer/tests/reports/test_markdown.py
git commit -m "feat(importer): pipeline Phase D runs ODbL dump after OSM apply

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Dedup test — OSM is lowest priority (no code change)

Locks the exit criterion "dedup against waves 1–2 working correctly."

**Files:**
- Test: `importer/tests/stages/test_dedup.py`

- [ ] **Step 1: Write the test**

`importer/tests/stages/test_dedup.py` already has a `_cc(source, eid, name, lat, lng, category=...)` helper and imports `dedup`. Add a test that an OSM candidate colliding with a higher-priority candidate is the one dropped:

```python
def test_dedup_osm_loses_to_higher_priority_source():
    # Same point + matching names; gsa (priority 4) outranks osm (priority 6).
    gsa = _cc("gsa", "g1", "Veterans Hall", 30.2672, -97.7431)
    osm = _cc("osm", "node/9", "Veterans Hall", 30.2673, -97.7432)
    result = dedup([gsa, osm], existing_user_pins=[])
    assert [cc.candidate.source for cc in result.survivors] == ["gsa"]
    assert result.drops_by_pair[("gsa", "osm")] == 1
```

- [ ] **Step 2: Run the test to verify it passes immediately**

Run: `cd importer && python -m pytest tests/stages/test_dedup.py::test_dedup_osm_loses_to_higher_priority_source -v`
Expected: PASS (OSM is already priority 6 in `SOURCE_PRIORITY`). If it FAILS, the helper signature is wrong — fix the test, not the source.

- [ ] **Step 3: Commit**

```bash
git add importer/tests/stages/test_dedup.py
git commit -m "test(importer): assert OSM loses cross-source dedup ties

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Documentation

**Files:**
- Modify: `docs/importer/SOURCES.md`
- Modify: `docs/importer/OMISSIONS.md`
- Modify: `docs/importer/STAGING_REAPPLY.md`
- Modify: `importer/README.md`

- [ ] **Step 1: SOURCES.md — add the OSM row**

Read `docs/importer/SOURCES.md` and add an OSM entry consistent with the existing source entries, covering: Overpass API endpoint, ODbL license, per-state auto-scope (only categories with an `osm` state-law cell are queried; pilot = bars TX/FL), `ISO3166-2` area selector, `out center tags`, external-id format `node/way/relation`, and that the ODbL dump republishes derived columns.

- [ ] **Step 2: OMISSIONS.md — note the auto-scope behavior**

In `docs/importer/OMISSIONS.md`, add a paragraph (after the table) noting:

```markdown
**OSM auto-scope behavior (Phase 6):** the `osm` source queries Overpass only for
categories with an `osm`-filtered cell **for each requested state** (per-state
auto-scope). Consequently worship/sports/healthcare are **never queried** in the
pilot states and will **not** appear in the dry-run "needs research / missing cells"
list (unlike IPEDS TX/PA colleges, which are emitted-then-dropped). PA bars are
likewise never generated, because PA has no `BAR_ALCOHOL` cell. When a future state
with a categorical worship/sports/healthcare prohibition is added to `states.yaml`,
that category is auto-queried with no importer code change — add its Overpass tag
map under `sources.osm.categories` in `config.yaml`.
```

- [ ] **Step 3: STAGING_REAPPLY.md — public bucket + title-case re-apply note**

In `docs/importer/STAGING_REAPPLY.md`, add notes that: (a) the `odbl-dumps` public bucket is created idempotently by the importer on first OSM apply (no manual step), and (b) the first full re-apply after Phase 6 produces a one-time wave of `UPDATE`s across **all** sources as all-caps labels are title-cased — expected, not a regression; the second apply is INSERT-0/UPDATE-0.

- [ ] **Step 4: importer/README.md — Data Sources & Licenses**

In `importer/README.md`, add a "Data Sources & Licenses" section listing each source and its license (NCES/IPEDS/FAA/GSA/HIFLD = US Gov public domain; OSM = ODbL share-alike) and the compliance posture (ODbL dump published to public Storage; in-app attribution deferred to Phase 7 pilot ship). Also add `osm` to any source list in the README.

- [ ] **Step 5: Commit**

```bash
git add docs/importer/SOURCES.md docs/importer/OMISSIONS.md docs/importer/STAGING_REAPPLY.md importer/README.md
git commit -m "docs(importer): document OSM source, auto-scope, and ODbL dump

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Live Overpass pre-flight + staging apply + idempotency (operator)

**Not TDD — operator-run on the Windows machine, which holds the staging service-role key.** Mirrors the Phase 5 staging-apply task. Run the full suite first.

- [ ] **Step 1: Full importer suite green**

Run: `cd importer && python -m pytest`
Expected: all tests pass (123 prior + the new Phase 6 tests).

- [ ] **Step 2: Live Overpass pre-flight (validate query + refresh fixture)**

Run a real Overpass query for TX bars to confirm the endpoint, `ISO3166-2` area selector, and `out center tags` behave as coded, e.g.:

```bash
cd importer && python -c "
import httpx
q='[out:json][timeout:120];area[\"ISO3166-2\"=\"US-TX\"]->.a;(nwr[\"amenity\"=\"bar\"](area.a);nwr[\"amenity\"=\"pub\"](area.a););out center tags;'
r=httpx.post('https://overpass-api.de/api/interpreter', content=q.encode(), timeout=180)
r.raise_for_status()
els=r.json()['elements']
print('elements:', len(els))
print('sample:', next((e for e in els if e.get('tags',{}).get('name')), None))
"
```

Confirm a non-trivial element count and that elements carry `tags.name` plus `lat/lon` (nodes) or `center` (ways/relations). If the real shape differs from the Task 2 fixture, update `importer/tests/fixtures/osm_tx_bars_sample.json` with real captured rows and re-run `pytest tests/sources/test_osm.py`.

- [ ] **Step 3: Dry-run against staging**

```bash
cd importer
export IMPORTER_SUPABASE_SERVICE_ROLE_KEY=<staging service-role key>
python -m importer.cli --dry-run --states TX,FL,PA --sources osm --project-ref staging
```

Expected: report shows bars classified for TX and FL, **zero** for PA (no PA query), coherent dedup section, no crash.

- [ ] **Step 4: Apply OSM to staging**

```bash
python -m importer.cli --apply --states TX,FL,PA --sources osm \
  --project-ref staging --i-know-this-writes-to-staging
```

Expected: INSERTs for TX/FL bars only; report's "## ODbL dump" section prints a public URL. Fetch it (`curl -fSL <url> -o /tmp/dump.csv.gz && gunzip -t /tmp/dump.csv.gz`) and confirm it downloads and the header + columns are present.

- [ ] **Step 5: Full re-apply (lands title-casing across all sources)**

```bash
python -m importer.cli --apply --states TX,FL,PA \
  --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm \
  --project-ref staging --i-know-this-writes-to-staging
```

Expected: a one-time wave of UPDATEs as previously all-caps labels are title-cased (INSERT-0 for already-present rows). Spot-check a few previously all-caps pins in the staging DB now read title-cased.

- [ ] **Step 6: Idempotency re-run**

Re-run Step 5 verbatim. Expected: INSERT-0 / UPDATE-0 across every source (title-casing is now stable).

- [ ] **Step 7: Advisors + clustering eyeball**

Check Supabase advisors (`get_advisors` security + performance) — expect no new findings. Eyeball clustering around Houston/Miami for the new bar pins. Confirm staging total pin count increased only by the new TX/FL bars.

- [ ] **Step 8: Update status + memory, then push the branch**

Update `CLAUDE.md` Current Status to mark Phase 6 staging-complete, and `memory/project_pre_populate_roadmap.md` accordingly. Commit. Then push `feature/pre-populate` and open the Phase 6 PR to master (run the `pr-preflight` skill first).

```bash
git add CLAUDE.md
git commit -m "docs: mark pre-populate Phase 6 OSM+ODbL staging-complete

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-review notes (for the implementer)

- **Spec coverage:** §2 OSM source → Tasks 1–3; §3 dedup → Task 9; §4 ODbL dump + Storage → Tasks 6–8; §5 title-casing → Tasks 4–5; §6 config/CLI → Task 3; §7 tests → every task; §8 staging apply → Task 11; §9 docs → Task 10.
- **No new migration / no Flutter / no prod write** — confirm none crept in. All app-side ODbL UI is Phase 7.
- **Type consistency:** `OsmDumpRow` (Task 6) is consumed by `generate_and_upload` (Task 7) via `.source_external_id/.name/.latitude/.longitude`; `generate_and_upload` (Task 7) is called by the pipeline (Task 8) with `client=` + `out_dir=`. `build_query_plan` is the public method name used in both `osm.py` and `test_osm.py`. `smart_title_case` is the name shared by `_titlecase.py`, `normalize.py`, and both test files.
- If any existing test helper/constant name in a test file differs from what a step assumes, match the file — the production code names above are authoritative.
```
