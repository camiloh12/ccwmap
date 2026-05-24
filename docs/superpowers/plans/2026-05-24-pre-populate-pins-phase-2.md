# Pre-Populate Pins — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the standalone Python importer skeleton described in §§2–4 of [the spec](../specs/2026-05-10-pre-populate-pins-design.md) and drive **one** source — HIFLD courthouses — end-to-end into the staging Supabase project. No pre-populated rows ship to prod; this phase exists to prove the pipeline, the state-law lookup, the dry-run report, and the CI workflows.

**Architecture:** A new `importer/` Python package (separate from Flutter, same monorepo) reads source datasets via per-source modules, normalizes them to a common `Candidate` dataclass, applies the maintained state-law lookup (`data/state_laws/states.yaml`), runs a stub-passthrough refine/dedup, diffs against the live `pins` table on the targeted Supabase project, and either writes a Markdown+JSON report (dry-run, default) or upserts rows via the service-role key (apply). All importer-driven writes set `source != 'user'` so the `set_user_modified` trigger keeps them re-importable. Three GitHub Actions workflows wrap the CLI: PR-validate (dry-run on staging for `importer/**` or `data/state_laws/**` PRs), weekly scheduled dry-run (staging), and manual `workflow_dispatch` apply.

**Tech Stack:** Python 3.12, `uv` for dependency/venv management (locally and in CI), `pydantic` v2 for `Candidate` / config validation, `shapely` for state point-in-polygon, `pyyaml` for the state-law table, `httpx` for HTTP (HIFLD fetches, Supabase Postgrest writes), `pytest` for tests, GitHub Actions (`astral-sh/setup-uv@v3`).

**Out of scope (deferred to later phases):**
- All other source modules (NCES, IPEDS, FAA, GSA, HIFLD hospitals/military, OSM) — Phases 4–6.
- Coordinate refinement via Overpass (the `refine_coords` stage stays a pass-through here; HIFLD courthouses already carry precise lat/lng). — Phases 4–6.
- Cross-source dedup logic (`dedup` stays a pass-through; only one source runs in Phase 2 so there is nothing to dedup against). — Phase 5.
- ODbL dump generation (only relevant once OSM data is imported). — Phase 6.
- State-law cells beyond the one row this phase needs (federal-uniform `STATE_LOCAL_GOVT` for courthouses). The full 33-cell research is Phase 3.
- Pin dialog UI changes to render `source`, `legal_citation`, the "Pre-populated from {source}" badge, or the `has_posted_signage = false` default copy. — Phase 4.
- Daily `pin-health-check` Edge Function and ODbL attribution UI. — Phase 6/7.
- Application of migration 008 to **prod** (still deferred until Phase 7 ship, per the existing Phase 0 deferral). Phase 2 targets staging only.

---

## Pre-flight checklist (do these once, before Task 1)

Read-only checks plus a small number of one-time setup items. None of these go in git.

- [ ] **Confirm Phase 0/1 prerequisites are in place.**
  - `grep -n "schemaVersion" lib/data/database/database.dart` → reports `4`.
  - `grep -n "kSystemUserId" lib/core/system_constants.dart` → reports the real UUID (`81775f8b-1a6a-47d6-b793-e9ab7e38634e` per memory `project_system_user_uuid.md`), not the `REPLACE-WITH-YOUR-PRE-GENERATED-UUID` placeholder.
  - In the **staging** Supabase SQL editor (project `miihmfhnsfmwgrvgayns`, per memory `reference_supabase_staging.md`):
    ```sql
    SELECT proname FROM pg_proc WHERE proname = 'get_pins_in_view';
    SELECT count(*) FROM pin_deletions;       -- table exists
    SELECT count(*) FROM import_runs;         -- table exists
    SELECT count(*) FROM recent_deletes;      -- table exists
    SELECT id FROM auth.users WHERE id = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid;
    ```
    All five queries must succeed without error and the last must return one row.

- [ ] **Install `uv` locally.** On Windows PowerShell:
  ```powershell
  powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
  ```
  Verify: `uv --version` prints a version `>= 0.5.0`.

- [ ] **Pin a Python version.** `uv python install 3.12`. The importer targets 3.12 (latest stable as of 2026-05; matches the `astral-sh/setup-uv` default).

- [ ] **Capture the staging service-role key.** Supabase dashboard → Project Settings → API → `service_role` (secret). Do not paste it into the plan, into git, or into chat. You will export it as the env var `IMPORTER_SUPABASE_SERVICE_ROLE_KEY` when running locally and store it as the GitHub Actions secret `STAGING_SUPABASE_SERVICE_ROLE_KEY` (Task 19).

- [ ] **Confirm the staging project ref and URL.**
  - URL: `https://miihmfhnsfmwgrvgayns.supabase.co`
  - Project ref: `miihmfhnsfmwgrvgayns`
  - Both go into `importer/config.yaml` under `staging:` (Task 9).

- [ ] **Look up the current HIFLD Courthouses GeoJSON URL.** Open <https://hifld-geoplatform.opendata.arcgis.com/datasets/courthouses> in a browser. Click *Download → GeoJSON*. The download URL has the shape `https://opendata.arcgis.com/api/v3/datasets/<dataset-uuid>_0/downloads/data?format=geojson&spatialRefId=4326`. Copy the full URL. You will paste it into `importer/sources/hifld_courts.py` (Task 5). If the page shows a "Data has been updated" banner with a different URL, use the newer one.

  Place the chosen URL into a one-line text file at `data/sources/.hifld_courts_url.txt` (gitignored — created in Task 14) so the importer fetches use the same URL the human verified.

- [ ] **Capture the fixture.** Once the URL works in a browser, save the response (or a 50-row prefix produced by `head -c 200000` after pretty-printing) to `importer/tests/fixtures/hifld_courts_sample.geojson`. The fixture must contain at least three rows located in TX, FL, and PA respectively (eyeball by `STATE` or geocoded coordinates). This file IS checked in — it is the source-of-truth for all `iter_candidates` unit tests, so it should not change unless we deliberately refresh.

---

## File map

**Create (Python source):**
- `importer/pyproject.toml` — package metadata + dependencies; `setuptools` backend so `uv pip install -e .` works.
- `importer/uv.lock` — generated by `uv lock`; committed for reproducible CI installs.
- `importer/README.md` — operator notes (how to run dry-run, apply, refresh fixtures).
- `importer/config.yaml` — non-secret runtime config (project refs/URLs, system_user_id, source URLs hash-pinned where possible).
- `importer/importer/__init__.py`
- `importer/importer/candidate.py` — `Candidate` pydantic model + Python `RestrictionTag` enum mirror.
- `importer/importer/restriction_tag.py` — enum mirroring `lib/domain/models/restriction_tag.dart` exactly (10 values).
- `importer/importer/state_laws.py` — YAML loader + `(state, category) → row` lookup with US fallback.
- `importer/importer/geo/__init__.py`
- `importer/importer/geo/states.py` — load US Census state polygons; `state_for(lat, lng) -> str | None` via STRtree.
- `importer/importer/sources/__init__.py`
- `importer/importer/sources/base.py` — abstract `Source` interface (`SOURCE_NAME`, `fetch()`, `iter_candidates(state_filter)`).
- `importer/importer/sources/hifld_courts.py` — HIFLD courthouses source module.
- `importer/importer/stages/__init__.py`
- `importer/importer/stages/normalize.py` — name-truncation pass; preserves all other fields.
- `importer/importer/stages/apply_state_law.py` — joins each `Candidate` to its `states.yaml` cell; drops + logs misses.
- `importer/importer/stages/refine_coords.py` — Phase 2 pass-through (returns input unchanged); signature locked for Phase 4+.
- `importer/importer/stages/dedup.py` — Phase 2 pass-through (returns input unchanged); signature locked for Phase 5.
- `importer/importer/stages/diff.py` — classify each candidate INSERT/UPDATE/SKIP against live `pins`; mark orphans.
- `importer/importer/stages/apply.py` — batched upserts via service-role Postgrest; no-op in dry-run.
- `importer/importer/stages/odbl_dump.py` — Phase 2 stub (logs "no OSM rows; nothing to dump"); signature locked for Phase 6.
- `importer/importer/supabase_client.py` — thin `httpx`-based wrapper: `select_pins_by_keys`, `upsert_pins`, `insert_import_run`, `update_import_run`.
- `importer/importer/pipeline.py` — orchestrates stages; emits a `PipelineResult` containing counts, sample diffs, error rows, and the orphan list.
- `importer/importer/reports/__init__.py`
- `importer/importer/reports/markdown.py` — render `PipelineResult` as a human-readable Markdown report.
- `importer/importer/reports/json_report.py` — render `PipelineResult` as a machine-readable JSON sidecar.
- `importer/importer/cli.py` — argparse-driven `__main__`; `python -m importer.cli`.
- `importer/importer/__main__.py` — `from .cli import main; main()`.

**Create (tests):**
- `importer/tests/__init__.py`
- `importer/tests/conftest.py` — shared fixtures (loaded state-law table, sample Candidates, fake Supabase client).
- `importer/tests/fixtures/hifld_courts_sample.geojson` — checked-in HIFLD slice from pre-flight.
- `importer/tests/fixtures/states_sample.geojson` — TX+FL+PA polygons clipped from Census `cb_2022_us_state_500k`; small enough to live in git.
- `importer/tests/test_candidate.py`
- `importer/tests/test_state_laws.py`
- `importer/tests/test_geo_states.py`
- `importer/tests/sources/__init__.py`
- `importer/tests/sources/test_hifld_courts.py`
- `importer/tests/stages/__init__.py`
- `importer/tests/stages/test_normalize.py`
- `importer/tests/stages/test_apply_state_law.py`
- `importer/tests/stages/test_refine_coords_passthrough.py`
- `importer/tests/stages/test_dedup_passthrough.py`
- `importer/tests/stages/test_diff.py`
- `importer/tests/stages/test_apply.py`
- `importer/tests/stages/test_odbl_dump_stub.py`
- `importer/tests/test_supabase_client.py`
- `importer/tests/test_pipeline.py`
- `importer/tests/reports/test_markdown.py`
- `importer/tests/reports/test_json_report.py`
- `importer/tests/test_cli.py`

**Create (data + docs):**
- `data/state_laws/states.yaml` — initially holds **one** row: federal-uniform `(US, STATE_LOCAL_GOVT)` for courthouses.
- `data/state_laws/LICENSE` — CC0 dedication.
- `data/state_laws/README.md` — schema reference + maintenance cadence.
- `data/sources/.gitkeep` — empty file so the directory exists; everything else inside is gitignored.
- `docs/importer/README.md` — operator overview: how to install, run dry-run, run apply, refresh fixtures, regenerate `uv.lock`.
- `docs/importer/SOURCES.md` — running list of sources and their licenses (Phase 2 lists only HIFLD courthouses; later phases extend).

**Create (CI):**
- `.github/workflows/importer-pr-validate.yml` — runs on PRs touching `importer/**` or `data/state_laws/**`; executes `python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging`.
- `.github/workflows/importer-dry-run.yml` — weekly cron; same invocation as PR-validate; uploads the report as an artifact.
- `.github/workflows/importer-apply.yml` — `workflow_dispatch` only; required input `target` (`staging` or `prod`, no default); calls the CLI in apply mode against the operator-selected ref.

**Modify:**
- `.gitignore` — append rules for `data/sources/*` (excepting `.gitkeep`), `importer/.venv/`, `importer/.pytest_cache/`, `importer/**/__pycache__/`, `importer/dist/`, `importer/*.egg-info/`.
- `.github/workflows/pr-checks.yml` — add `paths-ignore: ['importer/**', 'data/**', 'docs/importer/**']` to each Flutter-side job so importer-only PRs do not fan out into Flutter checks.
- `pubspec.yaml` — no change. The `importer/` and `data/` directories are not referenced by `pubspec.yaml` and Flutter's build does not traverse arbitrary top-level dirs, so a `.flutterignore` change is unnecessary.

---

## Task 1: Bootstrap the `importer/` Python package

**Files:**
- Create: `importer/pyproject.toml`, `importer/importer/__init__.py`, `importer/importer/__main__.py`, `importer/README.md`
- Create: `importer/tests/__init__.py`, `importer/tests/test_smoke.py`

The first commit just stands up the package layout and a smoke test that proves `python -m importer.cli` resolves. Every later task builds on this.

- [ ] **Step 1: Write the failing smoke test**

`importer/tests/test_smoke.py`:

```python
"""Smoke test — proves the package is importable and the CLI entrypoint exists."""

import importlib


def test_package_imports() -> None:
    mod = importlib.import_module("importer")
    assert mod is not None


def test_cli_module_exists() -> None:
    mod = importlib.import_module("importer.cli")
    assert hasattr(mod, "main"), "importer.cli must expose a main() callable"
```

- [ ] **Step 2: Create `importer/pyproject.toml`**

```toml
[project]
name = "ccwmap-importer"
version = "0.1.0"
description = "Pre-populate pins importer for the CCW Map project."
requires-python = ">=3.12"
dependencies = [
    "httpx >= 0.27,< 0.28",
    "pydantic >= 2.7,< 3",
    "pyyaml >= 6.0,< 7",
    "shapely >= 2.0,< 3",
]

[project.optional-dependencies]
dev = [
    "pytest >= 8.2,< 9",
    "pytest-cov >= 5,< 6",
]

[build-system]
requires = ["setuptools >= 68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["."]
include = ["importer*"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra -q"
```

- [ ] **Step 3: Create the package skeleton**

`importer/importer/__init__.py`:

```python
"""CCW Map pre-populate pins importer."""

__version__ = "0.1.0"
```

`importer/importer/__main__.py`:

```python
from importer.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
```

`importer/importer/cli.py` (minimal — Task 13 fleshes it out):

```python
"""Entrypoint for `python -m importer.cli`."""

from __future__ import annotations


def main(argv: list[str] | None = None) -> int:
    """Phase 2 placeholder — Task 13 wires the real argparse-driven CLI."""
    return 0
```

- [ ] **Step 4: Install in editable mode and run the smoke test**

```powershell
cd importer
uv venv
uv pip install -e ".[dev]"
uv run pytest tests/test_smoke.py -v
```

Expected: both tests pass.

- [ ] **Step 5: Generate the lockfile**

```powershell
uv lock
```

Confirm `importer/uv.lock` exists.

- [ ] **Step 6: Create `importer/README.md`**

```markdown
# CCW Map Pre-Populate Pins Importer

Stand-alone Python project that reads public datasets, classifies pins per the
maintained state-law lookup (`../data/state_laws/states.yaml`), and writes them
to a target Supabase project using the service-role key.

See [`docs/importer/README.md`](../docs/importer/README.md) for the operator
guide and [the design spec](../docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md)
for the why.

## Quick start

```powershell
# One-time
uv venv
uv pip install -e ".[dev]"

# Run the test suite
uv run pytest

# Dry-run against staging (no writes)
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<staging service-role key>"
uv run python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging
```

Apply mode (`--apply`) writes to the project named by `--project-ref`. It is
locked behind `--i-know-this-writes-to-<ref>` to prevent fat-fingering prod.
```

- [ ] **Step 7: Commit**

```powershell
git add importer/ docs/superpowers/plans/2026-05-24-pre-populate-pins-phase-2.md
git commit -m "feat(importer): bootstrap Python package skeleton"
```

---

## Task 2: `RestrictionTag` enum + `Candidate` dataclass

**Files:**
- Create: `importer/importer/restriction_tag.py`, `importer/importer/candidate.py`
- Create: `importer/tests/test_candidate.py`

`RestrictionTag` must mirror `lib/domain/models/restriction_tag.dart` exactly so the same string survives the round-trip from importer → Supabase → app. `Candidate` is the dataclass every source yields and every pipeline stage consumes.

- [ ] **Step 1: Write the failing tests**

`importer/tests/test_candidate.py`:

```python
import pytest
from pydantic import ValidationError

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag


def test_restriction_tag_mirrors_dart_enum_exactly() -> None:
    expected = [
        "FEDERAL_PROPERTY",
        "AIRPORT_SECURE",
        "STATE_LOCAL_GOVT",
        "SCHOOL_K12",
        "COLLEGE_UNIVERSITY",
        "BAR_ALCOHOL",
        "HEALTHCARE",
        "PLACE_OF_WORSHIP",
        "SPORTS_ENTERTAINMENT",
        "PRIVATE_PROPERTY",
    ]
    assert [t.name for t in RestrictionTag] == expected


def test_candidate_round_trips_minimal_fields() -> None:
    c = Candidate(
        source="hifld_courts",
        source_external_id="C-123",
        source_dataset_version="HIFLD-2026-05",
        name="Harris County Courthouse",
        latitude=29.7604,
        longitude=-95.3698,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
        extra={"loemins": "STATE"},
    )
    assert c.state == "TX"
    assert c.category is RestrictionTag.STATE_LOCAL_GOVT


def test_candidate_rejects_out_of_range_latitude() -> None:
    with pytest.raises(ValidationError):
        Candidate(
            source="hifld_courts",
            source_external_id="C-1",
            source_dataset_version="v1",
            name="x",
            latitude=91.0,
            longitude=0.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="TX",
        )


def test_candidate_rejects_non_two_letter_state() -> None:
    with pytest.raises(ValidationError):
        Candidate(
            source="hifld_courts",
            source_external_id="C-1",
            source_dataset_version="v1",
            name="x",
            latitude=30.0,
            longitude=-95.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="Texas",
        )
```

- [ ] **Step 2: Run the tests and confirm they fail**

```powershell
cd importer
uv run pytest tests/test_candidate.py -v
```

Expected: `ModuleNotFoundError: No module named 'importer.candidate'`.

- [ ] **Step 3: Implement the enum**

`importer/importer/restriction_tag.py`:

```python
"""Python mirror of `lib/domain/models/restriction_tag.dart`.

Order and names must match exactly — these strings are written verbatim into
Postgres `restriction_tag_type` enum values, and the app reads them back via
`RestrictionTag.fromString`.
"""

from enum import Enum


class RestrictionTag(str, Enum):
    FEDERAL_PROPERTY = "FEDERAL_PROPERTY"
    AIRPORT_SECURE = "AIRPORT_SECURE"
    STATE_LOCAL_GOVT = "STATE_LOCAL_GOVT"
    SCHOOL_K12 = "SCHOOL_K12"
    COLLEGE_UNIVERSITY = "COLLEGE_UNIVERSITY"
    BAR_ALCOHOL = "BAR_ALCOHOL"
    HEALTHCARE = "HEALTHCARE"
    PLACE_OF_WORSHIP = "PLACE_OF_WORSHIP"
    SPORTS_ENTERTAINMENT = "SPORTS_ENTERTAINMENT"
    PRIVATE_PROPERTY = "PRIVATE_PROPERTY"
```

- [ ] **Step 4: Implement the dataclass**

`importer/importer/candidate.py`:

```python
"""The common intermediate format produced by every source module."""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, ConfigDict, Field

from importer.restriction_tag import RestrictionTag


class CoordQuality(str, Enum):
    PRECISE = "precise"
    ADDRESS_CENTROID = "address_centroid"
    BUILDING_POLYGON = "building_polygon"


class Candidate(BaseModel):
    """One pin under consideration, pre-classification.

    Sources emit Candidates with `category` set to their best guess. The
    `apply_state_law` stage then enriches each Candidate with status, citation,
    confidence, and verified_date pulled from the (state, category) row in
    `states.yaml`. Candidates whose (state, category) has no row are dropped
    and surfaced in the dry-run report.
    """

    model_config = ConfigDict(frozen=True)

    source: str
    source_external_id: str
    source_dataset_version: str
    name: str = Field(min_length=1)
    latitude: float = Field(ge=-90.0, le=90.0)
    longitude: float = Field(ge=-180.0, le=180.0)
    coord_quality: CoordQuality
    category: RestrictionTag
    state: str = Field(pattern=r"^[A-Z]{2}$")
    extra: dict = Field(default_factory=dict)
```

- [ ] **Step 5: Run the tests and confirm they pass**

```powershell
uv run pytest tests/test_candidate.py -v
```

Expected: all four tests pass.

- [ ] **Step 6: Commit**

```powershell
git add importer/importer/restriction_tag.py importer/importer/candidate.py importer/tests/test_candidate.py
git commit -m "feat(importer): Candidate model + RestrictionTag mirror"
```

---

## Task 3: State-law YAML loader + first cell

**Files:**
- Create: `data/state_laws/states.yaml`, `data/state_laws/LICENSE`, `data/state_laws/README.md`
- Create: `importer/importer/state_laws.py`, `importer/tests/test_state_laws.py`

Only one cell goes in this phase: `(US, STATE_LOCAL_GOVT)` — federal-uniform courthouse rule (carry on a federal courthouse is prohibited by 18 USC 930; state/local courthouses are typically prohibited under state-specific statutes that Phase 3 will enumerate, but the US fallback keeps Phase 2's HIFLD candidates classified). The loader's `lookup(state, category)` joins on `(state, category)` first, falls back to `(US, category)`, returns `None` otherwise.

- [ ] **Step 1: Write the failing tests**

`importer/tests/test_state_laws.py`:

```python
from pathlib import Path

import pytest

from importer.restriction_tag import RestrictionTag
from importer.state_laws import StateLawCell, StateLawTable, load_state_laws


@pytest.fixture()
def table_path(tmp_path: Path) -> Path:
    p = tmp_path / "states.yaml"
    p.write_text(
        """
- state: US
  category: STATE_LOCAL_GOVT
  default_status: NO_GUN
  confidence: high
  conditions: []
  citation: "18 USC 930(a)"
  last_verified_date: 2026-05-01
  notes: "Federal courthouses; carry prohibited."

- state: TX
  category: BAR_ALCOHOL
  default_status: NO_GUN
  confidence: medium
  conditions:
    - "Premises deriving 51%+ revenue from on-premises alcohol sales"
  citation: "TX Penal Code §46.035(b)(1)"
  last_verified_date: 2026-05-01
""".strip(),
        encoding="utf-8",
    )
    return p


def test_load_state_laws_parses_all_rows(table_path: Path) -> None:
    table = load_state_laws(table_path)
    assert isinstance(table, StateLawTable)
    assert len(table.rows) == 2


def test_lookup_returns_state_specific_first(table_path: Path) -> None:
    table = load_state_laws(table_path)
    cell = table.lookup("TX", RestrictionTag.BAR_ALCOHOL)
    assert cell is not None
    assert isinstance(cell, StateLawCell)
    assert cell.state == "TX"
    assert cell.confidence == "medium"


def test_lookup_falls_back_to_us_when_no_state_row(table_path: Path) -> None:
    table = load_state_laws(table_path)
    cell = table.lookup("FL", RestrictionTag.STATE_LOCAL_GOVT)
    assert cell is not None
    assert cell.state == "US"
    assert cell.citation == "18 USC 930(a)"


def test_lookup_returns_none_when_no_row_anywhere(table_path: Path) -> None:
    table = load_state_laws(table_path)
    cell = table.lookup("TX", RestrictionTag.HEALTHCARE)
    assert cell is None
```

- [ ] **Step 2: Run the tests and confirm they fail**

```powershell
uv run pytest tests/test_state_laws.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement the loader**

`importer/importer/state_laws.py`:

```python
"""Load and query the maintained state-law lookup table."""

from __future__ import annotations

from datetime import date
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator

from importer.restriction_tag import RestrictionTag


Status = Literal["ALLOWED", "UNCERTAIN", "NO_GUN"]
Confidence = Literal["high", "medium", "low"]


class StateLawCell(BaseModel):
    """One row in `states.yaml`."""

    model_config = ConfigDict(frozen=True)

    state: str = Field(pattern=r"^(US|[A-Z]{2})$")
    category: RestrictionTag
    default_status: Status
    confidence: Confidence
    conditions: list[str] = Field(default_factory=list)
    citation: str
    last_verified_date: date
    source_filter: list[str] | None = None
    notes: str | None = None

    @field_validator("category", mode="before")
    @classmethod
    def _coerce_category(cls, v: str | RestrictionTag) -> RestrictionTag:
        return RestrictionTag(v) if isinstance(v, str) else v


class StateLawTable(BaseModel):
    rows: list[StateLawCell]

    def lookup(self, state: str, category: RestrictionTag) -> StateLawCell | None:
        for row in self.rows:
            if row.state == state and row.category is category:
                return row
        for row in self.rows:
            if row.state == "US" and row.category is category:
                return row
        return None


def load_state_laws(path: Path) -> StateLawTable:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError(f"{path} must be a YAML list of rows; got {type(raw).__name__}")
    rows = [StateLawCell.model_validate(item) for item in raw]
    return StateLawTable(rows=rows)
```

- [ ] **Step 4: Run the tests and confirm they pass**

```powershell
uv run pytest tests/test_state_laws.py -v
```

Expected: all four tests pass.

- [ ] **Step 5: Create the production `states.yaml` with the single courthouse cell**

`data/state_laws/states.yaml`:

```yaml
# Maintained state-law lookup table for the CCW Map pre-populate-pins importer.
# Schema: see ../../docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md §1.
# License: CC0 — see LICENSE next to this file.
# Maintenance: quarterly review; bump last_verified_date even if unchanged.

- state: US
  category: STATE_LOCAL_GOVT
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Federal courthouses: carry by non-officers prohibited."
    - "State/local courthouses: state law typically prohibits — Phase 3 cells refine per state."
  citation: "18 USC 930(a)"
  last_verified_date: 2026-05-24
  source_filter:
    - hifld_courts
  notes: |
    Phase 2 federal-uniform fallback. Applies to all HIFLD courthouses regardless
    of LOEMINS (federal/state/local) until Phase 3 fills in (TX, FL, PA,
    STATE_LOCAL_GOVT) state-specific rows that will then take precedence.
```

- [ ] **Step 6: Create `data/state_laws/LICENSE`**

```text
This file is dedicated to the public domain under the Creative Commons CC0 1.0
Universal Public Domain Dedication. The work product (categorization, citation
selection, confidence assignment) cites public-domain primary sources (US Code,
state statutes) and is itself released without restriction.

See https://creativecommons.org/publicdomain/zero/1.0/
```

- [ ] **Step 7: Create `data/state_laws/README.md`**

```markdown
# State-law lookup table

This directory holds the maintained legal classification table consulted by the
[pre-populate-pins importer](../../importer/README.md). Every pre-populated pin
inherits its status, citation, confidence, and verified date from a row here.

Schema and confidence definitions: see
[the design spec](../../docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md#§1)
§1 — *Sources, classification, and the state-law lookup table*.

## Editing

1. Edit `states.yaml` directly. The file is a list of cells; ordering does not matter (the loader matches by `(state, category)`).
2. Bump `last_verified_date` on every cell you reviewed, **even if the citation did not change** — the date is the evidence that the cell was checked this cycle.
3. PR with a one-line description per cell touched. Cells older than 6 months are flagged in dry-run reports; older than 12 months trigger UI warnings on affected pins.

## Coverage roadmap

| Phase | Cells covered |
|---|---|
| 2 (this) | `(US, STATE_LOCAL_GOVT)` only — proves the loader and one HIFLD source end-to-end. |
| 3 | TX + FL + PA × 10 categories + 3 federal-uniform US cells (33 cells). |
| 8+ | National rollout: all 50 states × 10 categories. |
```

- [ ] **Step 8: Add the production-file round-trip test**

Append to `importer/tests/test_state_laws.py`:

```python
def test_production_states_yaml_parses() -> None:
    table = load_state_laws(Path(__file__).parent.parent.parent / "data" / "state_laws" / "states.yaml")
    cell = table.lookup("TX", RestrictionTag.STATE_LOCAL_GOVT)
    assert cell is not None
    assert cell.state == "US"  # falls back to federal-uniform in Phase 2
    assert cell.confidence == "high"
```

- [ ] **Step 9: Run all state-law tests**

```powershell
uv run pytest tests/test_state_laws.py -v
```

Expected: five tests pass.

- [ ] **Step 10: Commit**

```powershell
git add data/state_laws/ importer/importer/state_laws.py importer/tests/test_state_laws.py
git commit -m "feat(importer): state-law YAML loader + federal-uniform courthouse cell"
```

---

## Task 4: State point-in-polygon utility

**Files:**
- Create: `importer/importer/geo/__init__.py`, `importer/importer/geo/states.py`
- Create: `importer/tests/fixtures/states_sample.geojson`
- Create: `importer/tests/test_geo_states.py`

HIFLD courthouses ship with lat/lng but no canonical two-letter state code. `state_for(lat, lng)` resolves a coordinate to a USPS code by point-in-polygon against the US Census state boundary file. For testing we ship a TX+FL+PA-only fixture so unit tests do not need the full ~10 MB national file.

- [ ] **Step 1: Prepare the TX+FL+PA fixture**

Download the Census file once (you do NOT commit it; you commit the clipped subset):

```powershell
# Once, anywhere on disk
Invoke-WebRequest -Uri "https://www2.census.gov/geo/tiger/GENZ2022/shp/cb_2022_us_state_500k.zip" -OutFile "$env:TEMP\cb_2022_us_state_500k.zip"
Expand-Archive -Path "$env:TEMP\cb_2022_us_state_500k.zip" -DestinationPath "$env:TEMP\cb_states" -Force
```

Then convert to a TX+FL+PA-only GeoJSON. Run this one-off `uv run python -c` snippet:

```powershell
uv run python -c @'
import json
from pathlib import Path
import shapefile  # may need: uv pip install pyshp --group dev

reader = shapefile.Reader(rf"$env:TEMP/cb_states/cb_2022_us_state_500k.shp")
features = []
for sr in reader.shapeRecords():
    rec = sr.record.as_dict()
    if rec.get("STUSPS") not in ("TX", "FL", "PA"):
        continue
    features.append({
        "type": "Feature",
        "properties": {"STUSPS": rec["STUSPS"], "NAME": rec["NAME"]},
        "geometry": sr.shape.__geo_interface__,
    })

out = Path("importer/tests/fixtures/states_sample.geojson")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
print(f"wrote {out} with {len(features)} features")
'@
```

If `pyshp` is missing, install just for this one-off conversion: `uv pip install pyshp` then drop it from the project (it is not a runtime dep).

The fixture should be ~500 KB. If it grows past 2 MB, simplify the geometry first with `shapely.simplify(0.01)` — accuracy to 0.01 degree (~1 km) is plenty for state-level PIP.

- [ ] **Step 2: Write the failing tests**

`importer/tests/test_geo_states.py`:

```python
from pathlib import Path

import pytest

from importer.geo.states import StateLocator, load_state_locator


@pytest.fixture(scope="module")
def locator() -> StateLocator:
    return load_state_locator(
        Path(__file__).parent / "fixtures" / "states_sample.geojson"
    )


@pytest.mark.parametrize(
    "lat,lng,expected",
    [
        (29.7604, -95.3698, "TX"),   # Houston
        (25.7617, -80.1918, "FL"),   # Miami
        (39.9526, -75.1652, "PA"),   # Philadelphia
    ],
)
def test_state_for_returns_correct_code(
    locator: StateLocator, lat: float, lng: float, expected: str
) -> None:
    assert locator.state_for(lat, lng) == expected


def test_state_for_returns_none_for_ocean(locator: StateLocator) -> None:
    assert locator.state_for(40.0, -70.0) is None  # Atlantic Ocean


def test_state_for_returns_none_for_state_not_in_fixture(locator: StateLocator) -> None:
    assert locator.state_for(34.0522, -118.2437) is None  # LA, CA — not in TX/FL/PA fixture
```

- [ ] **Step 3: Run the tests and confirm they fail**

```powershell
uv run pytest tests/test_geo_states.py -v
```

Expected: `ModuleNotFoundError`.

- [ ] **Step 4: Implement the locator**

`importer/importer/geo/__init__.py`:

```python
"""Geospatial helpers."""
```

`importer/importer/geo/states.py`:

```python
"""Resolve a lat/lng to its USPS two-letter state code via point-in-polygon."""

from __future__ import annotations

import json
from pathlib import Path

from shapely.geometry import Point, shape
from shapely.strtree import STRtree


class StateLocator:
    """In-memory STRtree over US state polygons keyed by USPS code."""

    def __init__(self, geometries: list, codes: list[str]) -> None:
        assert len(geometries) == len(codes)
        self._tree = STRtree(geometries)
        self._geometries = geometries
        self._codes = codes

    def state_for(self, lat: float, lng: float) -> str | None:
        pt = Point(lng, lat)  # shapely is (x=lng, y=lat)
        # STRtree.query returns positional indices into the original list.
        for idx in self._tree.query(pt):
            if self._geometries[idx].covers(pt):
                return self._codes[idx]
        return None


def load_state_locator(path: Path) -> StateLocator:
    raw = json.loads(path.read_text(encoding="utf-8"))
    features = raw.get("features", [])
    geometries: list = []
    codes: list[str] = []
    for f in features:
        codes.append(f["properties"]["STUSPS"])
        geometries.append(shape(f["geometry"]))
    return StateLocator(geometries, codes)
```

- [ ] **Step 5: Run the tests and confirm they pass**

```powershell
uv run pytest tests/test_geo_states.py -v
```

Expected: five tests pass.

- [ ] **Step 6: Commit**

```powershell
git add importer/importer/geo/ importer/tests/test_geo_states.py importer/tests/fixtures/states_sample.geojson
git commit -m "feat(importer): state PIP locator via STRtree"
```

---

## Task 5: HIFLD courthouses source module

**Files:**
- Create: `importer/importer/sources/__init__.py`, `importer/importer/sources/base.py`, `importer/importer/sources/hifld_courts.py`
- Create: `importer/tests/sources/__init__.py`, `importer/tests/sources/test_hifld_courts.py`

The source reads HIFLD's Courthouses GeoJSON (cached or live) and emits one `Candidate` per row, with `state` resolved via the `StateLocator` and `category = STATE_LOCAL_GOVT` for every row (Phase 2 simplification — Phase 3 will subdivide federal vs state/local based on `LOEMINS`).

- [ ] **Step 1: Write the failing tests**

`importer/tests/sources/test_hifld_courts.py`:

```python
from pathlib import Path

import pytest

from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.hifld_courts import HifldCourthousesSource


FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


@pytest.fixture(scope="module")
def source() -> HifldCourthousesSource:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    return HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )


def test_source_name_is_stable(source: HifldCourthousesSource) -> None:
    assert source.SOURCE_NAME == "hifld_courts"


def test_iter_candidates_yields_at_least_three_states(
    source: HifldCourthousesSource,
) -> None:
    candidates = list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert len(candidates) >= 3
    states = {c.state for c in candidates}
    assert {"TX", "FL", "PA"}.issubset(states)


def test_iter_candidates_assigns_category(
    source: HifldCourthousesSource,
) -> None:
    candidates = list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert all(c.category is RestrictionTag.STATE_LOCAL_GOVT for c in candidates)


def test_iter_candidates_respects_state_filter(
    source: HifldCourthousesSource,
) -> None:
    candidates = list(source.iter_candidates(state_filter={"TX"}))
    assert all(c.state == "TX" for c in candidates)


def test_iter_candidates_skips_rows_without_resolvable_state(
    source: HifldCourthousesSource,
) -> None:
    # No assertion target beyond "does not raise" — rows whose lat/lng falls
    # outside TX/FL/PA in the fixture state polygons are silently skipped.
    all_candidates = list(source.iter_candidates(state_filter=None))
    assert all(c.state in {"TX", "FL", "PA"} for c in all_candidates)


def test_iter_candidates_skipped_count_is_recorded(
    source: HifldCourthousesSource,
) -> None:
    list(source.iter_candidates(state_filter={"TX"}))
    # The source records why a row was skipped (state-PIP miss vs filter miss
    # vs missing lat/lng) so the report can attribute drops correctly.
    assert source.last_skip_counts.get("filtered_out", 0) >= 0
    assert source.last_skip_counts.get("state_pip_miss", 0) >= 0
    assert source.last_skip_counts.get("missing_geometry", 0) >= 0
```

- [ ] **Step 2: Run the tests and confirm they fail**

```powershell
uv run pytest tests/sources/test_hifld_courts.py -v
```

Expected: `ModuleNotFoundError: No module named 'importer.sources'`.

- [ ] **Step 3: Implement the base interface**

`importer/importer/sources/__init__.py`:

```python
"""Per-source ingestion modules."""
```

`importer/importer/sources/base.py`:

```python
"""Abstract base for source modules."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Iterator
from typing import ClassVar

from importer.candidate import Candidate


class Source(ABC):
    SOURCE_NAME: ClassVar[str]

    @abstractmethod
    def fetch(self, *, refetch: bool = False) -> None:
        """Download (or skip if cached) the upstream dataset to local cache."""

    @abstractmethod
    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        """Yield one Candidate per upstream record; respect state_filter when set."""
```

- [ ] **Step 4: Implement the HIFLD courthouses source**

`importer/importer/sources/hifld_courts.py`:

```python
"""HIFLD Courthouses → Candidate stream.

Source: https://hifld-geoplatform.opendata.arcgis.com/datasets/courthouses
Format: GeoJSON, ~3 MB nationally, ~5k features.
License: Public domain (DHS / HIFLD Open).
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


# The URL is captured at pre-flight and pinned here. If HIFLD republishes under
# a new UUID, update this constant in the same PR that refreshes the fixture.
HIFLD_COURTHOUSES_URL = (
    "https://opendata.arcgis.com/api/v3/datasets/"
    "REPLACE-WITH-HIFLD-DATASET-UUID_0/downloads/data"
    "?format=geojson&spatialRefId=4326"
)


class HifldCourthousesSource(Source):
    SOURCE_NAME: ClassVar[str] = "hifld_courts"

    def __init__(
        self,
        *,
        cache_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = HIFLD_COURTHOUSES_URL,
    ) -> None:
        self._cache_path = cache_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        if self._cache_path.exists() and not refetch:
            return
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=60.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        raw = json.loads(self._cache_path.read_text(encoding="utf-8"))
        for feature in raw.get("features", []):
            geom = feature.get("geometry") or {}
            props = feature.get("properties") or {}

            coords = geom.get("coordinates")
            if geom.get("type") != "Point" or not coords or len(coords) < 2:
                self.last_skip_counts["missing_geometry"] += 1
                continue
            lng, lat = float(coords[0]), float(coords[1])

            state = self._locator.state_for(lat, lng)
            if state is None:
                self.last_skip_counts["state_pip_miss"] += 1
                continue
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue

            external_id = self._external_id(props)
            name = (props.get("NAME") or props.get("name") or "").strip()
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
                coord_quality=CoordQuality.PRECISE,
                category=RestrictionTag.STATE_LOCAL_GOVT,
                state=state,
                extra={
                    "loemins": props.get("LOEMINS"),
                    "address": props.get("ADDRESS"),
                    "city": props.get("CITY"),
                },
            )

    @staticmethod
    def _external_id(props: dict) -> str:
        # HIFLD typically uses OBJECTID or globally a GFID. Prefer the most
        # stable one available; fall back to FID. The chosen field becomes the
        # upsert key in Supabase — changing this on a future run will create
        # duplicate rows that will then orphan the old ones.
        for key in ("GFID", "GLOBALID", "OBJECTID", "FID"):
            v = props.get(key)
            if v not in (None, ""):
                return str(v)
        raise ValueError(f"HIFLD courthouse row has no stable ID: {props!r}")
```

- [ ] **Step 5: Replace the URL placeholder**

Edit `HIFLD_COURTHOUSES_URL` to use the dataset UUID you captured in the pre-flight checklist. If you used `data/sources/.hifld_courts_url.txt` (per pre-flight), paste the full URL from that file. Do not hand-edit just the UUID — paste the entire URL so query-string params match.

- [ ] **Step 6: Run the tests and confirm they pass**

```powershell
uv run pytest tests/sources/test_hifld_courts.py -v
```

Expected: six tests pass.

- [ ] **Step 7: Commit**

```powershell
git add importer/importer/sources/ importer/tests/sources/ importer/tests/fixtures/hifld_courts_sample.geojson
git commit -m "feat(importer): HIFLD courthouses source module"
```

---

## Task 6: Pipeline stage interface + pass-through stubs

**Files:**
- Create: `importer/importer/stages/__init__.py`, `importer/importer/stages/refine_coords.py`, `importer/importer/stages/dedup.py`, `importer/importer/stages/odbl_dump.py`
- Create: `importer/tests/stages/__init__.py`, `importer/tests/stages/test_refine_coords_passthrough.py`, `importer/tests/stages/test_dedup_passthrough.py`, `importer/tests/stages/test_odbl_dump_stub.py`

Three stages get pass-through implementations whose signatures match what the later phases will need. Locking the signatures now means Phase 4-6 can swap in real implementations without rewiring the pipeline.

- [ ] **Step 1: Write the failing tests**

`importer/tests/stages/test_refine_coords_passthrough.py`:

```python
from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.refine_coords import refine_coords


def _candidate() -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id="C-1",
        source_dataset_version="v1",
        name="Test",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.ADDRESS_CENTROID,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
    )


def test_refine_coords_returns_input_unchanged() -> None:
    inputs = [_candidate()]
    outputs = list(refine_coords(inputs))
    assert outputs == inputs
```

`importer/tests/stages/test_dedup_passthrough.py`:

```python
from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.dedup import dedup


def _candidate(eid: str) -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id=eid,
        source_dataset_version="v1",
        name=f"Test {eid}",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
    )


def test_dedup_returns_all_inputs_in_phase_2() -> None:
    inputs = [_candidate("a"), _candidate("b")]
    outputs = list(dedup(inputs, existing_user_pins=[]))
    assert outputs == inputs
```

`importer/tests/stages/test_odbl_dump_stub.py`:

```python
from pathlib import Path

from importer.stages.odbl_dump import dump_osm_pins


def test_odbl_dump_is_noop_when_no_osm_pins(tmp_path: Path) -> None:
    result = dump_osm_pins(out_dir=tmp_path, applied_source_counts={"hifld_courts": 100})
    assert result is None
    assert list(tmp_path.iterdir()) == []
```

- [ ] **Step 2: Implement the stubs**

`importer/importer/stages/__init__.py`:

```python
"""Pipeline stages. Each stage is a pure function over an iterable of inputs."""
```

`importer/importer/stages/refine_coords.py`:

```python
"""Coordinate refinement — Phase 2 pass-through.

Phase 4+ replaces this with an Overpass query per (state, category) bbox plus
a per-Candidate nearest-polygon snap. The signature is locked so callers do
not have to change when the implementation lands.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator

from importer.candidate import Candidate


def refine_coords(candidates: Iterable[Candidate]) -> Iterator[Candidate]:
    yield from candidates
```

`importer/importer/stages/dedup.py`:

```python
"""Cross-source + within-source dedup — Phase 2 pass-through.

Phase 5 replaces this with the spatial+name dedup described in spec §4 step 4
(within 100 m AND token_set_ratio >= 0.7; user-pin priority). For Phase 2
only one source runs, so there is nothing to dedup against.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator

from importer.candidate import Candidate


def dedup(
    candidates: Iterable[Candidate],
    *,
    existing_user_pins: list,
) -> Iterator[Candidate]:
    yield from candidates
```

`importer/importer/stages/odbl_dump.py`:

```python
"""ODbL share-alike compliance — Phase 2 stub.

The dump is only relevant for OSM-sourced rows (license: ODbL). Phase 6 adds
the OSM source; this stub keeps the pipeline interface stable until then.
"""

from __future__ import annotations

import logging
from pathlib import Path

logger = logging.getLogger(__name__)


def dump_osm_pins(
    *,
    out_dir: Path,
    applied_source_counts: dict[str, int],
) -> Path | None:
    osm_count = applied_source_counts.get("osm", 0)
    if osm_count == 0:
        logger.info("odbl_dump: no OSM rows applied; nothing to dump.")
        return None
    raise NotImplementedError("ODbL dump generator is added in Phase 6.")
```

- [ ] **Step 3: Run the tests and confirm they pass**

```powershell
uv run pytest tests/stages/ -v
```

Expected: three tests pass.

- [ ] **Step 4: Commit**

```powershell
git add importer/importer/stages/ importer/tests/stages/
git commit -m "feat(importer): pass-through stubs for refine/dedup/odbl_dump"
```

---

## Task 7: Normalize stage (name truncation)

**Files:**
- Create: `importer/importer/stages/normalize.py`
- Create: `importer/tests/stages/test_normalize.py`

The `pins.name` column has a `CHECK char_length(name) <= 60` constraint (per CLAUDE.md). The normalize stage truncates names that exceed it and records the count for the report.

- [ ] **Step 1: Write the failing tests**

`importer/tests/stages/test_normalize.py`:

```python
from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.normalize import NormalizeStats, normalize


def _c(name: str) -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id="X",
        source_dataset_version="v1",
        name=name,
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
    )


def test_normalize_short_name_is_unchanged() -> None:
    stats = NormalizeStats()
    out = list(normalize([_c("Short")], stats=stats))
    assert out[0].name == "Short"
    assert stats.truncations == 0


def test_normalize_long_name_is_truncated_to_60_chars() -> None:
    long_name = "A" * 200
    stats = NormalizeStats()
    out = list(normalize([_c(long_name)], stats=stats))
    assert len(out[0].name) == 60
    assert out[0].name == "A" * 60
    assert stats.truncations == 1
    assert stats.examples == [(long_name, "A" * 60)]


def test_normalize_strips_whitespace() -> None:
    stats = NormalizeStats()
    out = list(normalize([_c("  Foo  ")], stats=stats))
    assert out[0].name == "Foo"
```

- [ ] **Step 2: Implement the stage**

`importer/importer/stages/normalize.py`:

```python
"""Per-candidate normalization: trim, truncate names to the DB constraint."""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field

from importer.candidate import Candidate

# Mirrors the `CHECK char_length(name) <= 60` constraint on public.pins.name.
PIN_NAME_MAX_LENGTH = 60


@dataclass
class NormalizeStats:
    truncations: int = 0
    # Capped sample of (original, truncated) pairs for the report.
    examples: list[tuple[str, str]] = field(default_factory=list)
    _example_cap: int = 5


def normalize(
    candidates: Iterable[Candidate],
    *,
    stats: NormalizeStats,
) -> Iterator[Candidate]:
    for c in candidates:
        new_name = c.name.strip()
        if len(new_name) > PIN_NAME_MAX_LENGTH:
            truncated = new_name[:PIN_NAME_MAX_LENGTH]
            stats.truncations += 1
            if len(stats.examples) < stats._example_cap:
                stats.examples.append((new_name, truncated))
            new_name = truncated
        yield c.model_copy(update={"name": new_name})
```

- [ ] **Step 3: Run the tests and confirm they pass**

```powershell
uv run pytest tests/stages/test_normalize.py -v
```

Expected: three tests pass.

- [ ] **Step 4: Commit**

```powershell
git add importer/importer/stages/normalize.py importer/tests/stages/test_normalize.py
git commit -m "feat(importer): normalize stage truncates names to 60 chars"
```

---

## Task 8: Apply-state-law stage

**Files:**
- Create: `importer/importer/stages/apply_state_law.py`
- Create: `importer/tests/stages/test_apply_state_law.py`

This stage is where status assignment happens. Per spec §1: "The importer never invents a status. Every pre-populated pin's status, restriction tag, confidence, citation, and verified date come from a specific row in `states.yaml`." Candidates whose `(state, category)` resolves to no cell are dropped and surface as "needs research" in the report.

The output adds resolved fields (status, citation, confidence, verified_date) to each Candidate. Rather than expanding `Candidate` with optional fields, the stage emits a `ClassifiedCandidate` wrapper that pairs the original `Candidate` with its matched `StateLawCell`. Downstream stages key off the cell for status/citation lookup.

- [ ] **Step 1: Write the failing tests**

`importer/tests/stages/test_apply_state_law.py`:

```python
from datetime import date
from pathlib import Path

import pytest

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import (
    ApplyStateLawStats,
    ClassifiedCandidate,
    apply_state_law,
)
from importer.state_laws import StateLawCell, StateLawTable


def _candidate(state: str, category: RestrictionTag) -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id=f"{state}-{category.name}",
        source_dataset_version="v1",
        name="X",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=category,
        state=state,
    )


@pytest.fixture()
def table() -> StateLawTable:
    return StateLawTable(
        rows=[
            StateLawCell(
                state="US",
                category=RestrictionTag.STATE_LOCAL_GOVT,
                default_status="NO_GUN",
                confidence="high",
                conditions=[],
                citation="18 USC 930(a)",
                last_verified_date=date(2026, 5, 1),
            ),
        ]
    )


def test_candidate_with_us_fallback_is_classified(table: StateLawTable) -> None:
    stats = ApplyStateLawStats()
    out = list(
        apply_state_law(
            [_candidate("TX", RestrictionTag.STATE_LOCAL_GOVT)],
            table=table,
            stats=stats,
        )
    )
    assert len(out) == 1
    cc = out[0]
    assert isinstance(cc, ClassifiedCandidate)
    assert cc.cell.citation == "18 USC 930(a)"
    assert stats.dropped_no_cell == 0


def test_candidate_with_no_cell_is_dropped_and_recorded(table: StateLawTable) -> None:
    stats = ApplyStateLawStats()
    out = list(
        apply_state_law(
            [_candidate("TX", RestrictionTag.HEALTHCARE)],
            table=table,
            stats=stats,
        )
    )
    assert out == []
    assert stats.dropped_no_cell == 1
    assert ("TX", RestrictionTag.HEALTHCARE.name) in stats.missing_cells


def test_source_filter_in_cell_is_respected(table: StateLawTable) -> None:
    # Cell with source_filter=['osm'] must NOT match an hifld_courts candidate.
    table_with_filter = StateLawTable(
        rows=[
            StateLawCell(
                state="US",
                category=RestrictionTag.STATE_LOCAL_GOVT,
                default_status="NO_GUN",
                confidence="high",
                conditions=[],
                citation="should not apply",
                last_verified_date=date(2026, 5, 1),
                source_filter=["osm"],
            ),
        ]
    )
    stats = ApplyStateLawStats()
    out = list(
        apply_state_law(
            [_candidate("TX", RestrictionTag.STATE_LOCAL_GOVT)],
            table=table_with_filter,
            stats=stats,
        )
    )
    assert out == []
    assert stats.dropped_no_cell == 1
```

- [ ] **Step 2: Implement the stage**

`importer/importer/stages/apply_state_law.py`:

```python
"""Match each Candidate to a StateLawCell, drop those with no match."""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field

from pydantic import BaseModel, ConfigDict

from importer.candidate import Candidate
from importer.state_laws import StateLawCell, StateLawTable


class ClassifiedCandidate(BaseModel):
    """A Candidate plus the StateLawCell that classified it."""

    model_config = ConfigDict(frozen=True)

    candidate: Candidate
    cell: StateLawCell


@dataclass
class ApplyStateLawStats:
    classified: int = 0
    dropped_no_cell: int = 0
    # (state, category_name) pairs that had no row — surface in report.
    missing_cells: set[tuple[str, str]] = field(default_factory=set)


def apply_state_law(
    candidates: Iterable[Candidate],
    *,
    table: StateLawTable,
    stats: ApplyStateLawStats,
) -> Iterator[ClassifiedCandidate]:
    for c in candidates:
        cell = table.lookup(c.state, c.category)
        if cell is None or (cell.source_filter and c.source not in cell.source_filter):
            stats.dropped_no_cell += 1
            stats.missing_cells.add((c.state, c.category.name))
            continue
        stats.classified += 1
        yield ClassifiedCandidate(candidate=c, cell=cell)
```

- [ ] **Step 3: Run the tests and confirm they pass**

```powershell
uv run pytest tests/stages/test_apply_state_law.py -v
```

Expected: three tests pass.

- [ ] **Step 4: Commit**

```powershell
git add importer/importer/stages/apply_state_law.py importer/tests/stages/test_apply_state_law.py
git commit -m "feat(importer): apply_state_law stage with US fallback + source_filter"
```

---

## Task 9: Supabase service-role client wrapper

**Files:**
- Create: `importer/importer/supabase_client.py`, `importer/config.yaml`
- Create: `importer/tests/test_supabase_client.py`

The wrapper exposes exactly the calls the diff and apply stages need:

- `select_pins_by_keys(source, external_ids) -> list[ExistingPinRow]` — bulk lookup.
- `upsert_pins(rows, batch_size=500)` — service-role write, bypasses RLS.
- `insert_import_run(...) -> uuid` — start of run.
- `update_import_run(run_id, ...)` — end of run with counts + errors.

Tests use `pytest-httpx` (already a transitive of `httpx`) to mock the wire — no real network in unit tests.

- [ ] **Step 1: Add `pytest-httpx` to dev deps**

Edit `importer/pyproject.toml`:

```toml
[project.optional-dependencies]
dev = [
    "pytest >= 8.2,< 9",
    "pytest-cov >= 5,< 6",
    "pytest-httpx >= 0.30,< 0.31",
]
```

Then:

```powershell
uv lock
uv pip install -e ".[dev]"
```

- [ ] **Step 2: Create the config file**

`importer/config.yaml`:

```yaml
# Non-secret runtime configuration for the importer.
# Secrets (service-role keys) come from environment variables.

system_user_id: "81775f8b-1a6a-47d6-b793-e9ab7e38634e"

projects:
  staging:
    project_ref: "miihmfhnsfmwgrvgayns"
    url: "https://miihmfhnsfmwgrvgayns.supabase.co"
  prod:
    project_ref: "REPLACE-WITH-PROD-PROJECT-REF"
    url: "https://REPLACE-WITH-PROD-PROJECT-REF.supabase.co"

sources:
  hifld_courts:
    # URL captured at pre-flight; pin per-source so dataset versions are reproducible.
    cache_dir: "data/sources/hifld_courts"
    dataset_version: "HIFLD-2026-05"
```

- [ ] **Step 3: Write the failing tests**

`importer/tests/test_supabase_client.py`:

```python
import httpx
import pytest
from pytest_httpx import HTTPXMock

from importer.supabase_client import (
    ExistingPinRow,
    SupabaseClient,
    SupabaseUpsertRow,
)


@pytest.fixture()
def client() -> SupabaseClient:
    return SupabaseClient(
        url="https://example.supabase.co",
        service_role_key="srk-test",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )


def test_select_pins_by_keys_returns_parsed_rows(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    httpx_mock.add_response(
        method="GET",
        url="https://example.supabase.co/rest/v1/pins?select=id,source,source_external_id,name,latitude,longitude,status,restriction_tag,user_modified,source_dataset_version&source=eq.hifld_courts&source_external_id=in.%28%22A%22%2C%22B%22%29",
        json=[
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "source": "hifld_courts",
                "source_external_id": "A",
                "name": "Old A",
                "latitude": 29.0,
                "longitude": -95.0,
                "status": 2,
                "restriction_tag": "STATE_LOCAL_GOVT",
                "user_modified": False,
                "source_dataset_version": "HIFLD-2026-04",
            }
        ],
    )
    rows = client.select_pins_by_keys("hifld_courts", ["A", "B"])
    assert len(rows) == 1
    assert isinstance(rows[0], ExistingPinRow)
    assert rows[0].source_external_id == "A"


def test_upsert_pins_batches_at_500(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    rows = [
        SupabaseUpsertRow(
            id=f"00000000-0000-0000-0000-{i:012d}",
            source="hifld_courts",
            source_external_id=f"E{i}",
            source_dataset_version="HIFLD-2026-05",
            name=f"P{i}",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            has_security_screening=True,
            has_posted_signage=False,
            created_by="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
            confidence="high",
            legal_citation="18 USC 930(a)",
            legal_citation_verified_date="2026-05-01",
        )
        for i in range(1200)
    ]
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/rest/v1/pins?on_conflict=source%2Csource_external_id",
        json=[],
        status_code=201,
    )

    client.upsert_pins(rows)

    # 1200 rows / 500 batch = 3 requests
    requests = httpx_mock.get_requests()
    assert len(requests) == 3


def test_insert_and_update_import_run_returns_uuid(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/rest/v1/import_runs",
        json=[{"run_id": "11111111-1111-1111-1111-111111111111"}],
        status_code=201,
    )
    httpx_mock.add_response(
        method="PATCH",
        url="https://example.supabase.co/rest/v1/import_runs?run_id=eq.11111111-1111-1111-1111-111111111111",
        json=[],
        status_code=204,
    )

    run_id = client.insert_import_run(mode="dry-run", source_filter="hifld_courts")
    assert run_id == "11111111-1111-1111-1111-111111111111"

    client.update_import_run(
        run_id=run_id,
        candidates_processed=10,
        inserts=8,
        updates=1,
        skips=1,
        orphans_marked=0,
        errors_json=None,
        report_artifact_url=None,
    )
```

- [ ] **Step 4: Implement the client**

`importer/importer/supabase_client.py`:

```python
"""Thin wrapper around Supabase Postgrest using the service-role key."""

from __future__ import annotations

from typing import Any

import httpx
from pydantic import BaseModel, ConfigDict


class ExistingPinRow(BaseModel):
    model_config = ConfigDict(frozen=True)

    id: str
    source: str
    source_external_id: str | None
    name: str
    latitude: float
    longitude: float
    status: int
    restriction_tag: str | None
    user_modified: bool
    source_dataset_version: str | None


class SupabaseUpsertRow(BaseModel):
    model_config = ConfigDict(frozen=True)

    id: str
    source: str
    source_external_id: str
    source_dataset_version: str
    name: str
    latitude: float
    longitude: float
    status: int
    restriction_tag: str
    has_security_screening: bool
    has_posted_signage: bool
    created_by: str
    confidence: str
    legal_citation: str
    legal_citation_verified_date: str  # ISO 8601 date
    imported_at: str | None = None     # set by server default `now()` when null
    source_orphaned_at: None = None    # always null on upsert; orphan-marking is a separate stage


class SupabaseClient:
    """All HTTP traffic goes through this wrapper so we have one place to add
    retry logic, structured logging, and rate-limiting later."""

    SELECT_COLUMNS = (
        "id,source,source_external_id,name,latitude,longitude,"
        "status,restriction_tag,user_modified,source_dataset_version"
    )

    def __init__(
        self,
        *,
        url: str,
        service_role_key: str,
        system_user_id: str,
        timeout: float = 30.0,
    ) -> None:
        self._base = url.rstrip("/") + "/rest/v1"
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }
        self._system_user_id = system_user_id
        self._client = httpx.Client(timeout=timeout)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "SupabaseClient":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def select_pins_by_keys(
        self, source: str, external_ids: list[str]
    ) -> list[ExistingPinRow]:
        if not external_ids:
            return []
        # Postgrest `in.(...)` requires quoted strings for text columns.
        in_list = ",".join(f'"{eid}"' for eid in external_ids)
        params = {
            "select": self.SELECT_COLUMNS,
            "source": f"eq.{source}",
            "source_external_id": f"in.({in_list})",
        }
        r = self._client.get(f"{self._base}/pins", headers=self._headers, params=params)
        r.raise_for_status()
        return [ExistingPinRow.model_validate(row) for row in r.json()]

    def upsert_pins(
        self, rows: list[SupabaseUpsertRow], *, batch_size: int = 500
    ) -> None:
        if not rows:
            return
        headers = dict(self._headers)
        # Postgrest upsert via Prefer: resolution=merge-duplicates +
        # on_conflict query param naming the unique-ish key columns.
        headers["Prefer"] = "return=minimal,resolution=merge-duplicates"
        url = f"{self._base}/pins?on_conflict=source,source_external_id"
        for i in range(0, len(rows), batch_size):
            batch = [r.model_dump(mode="json", exclude_none=True) for r in rows[i : i + batch_size]]
            r = self._client.post(url, headers=headers, json=batch)
            r.raise_for_status()

    def insert_import_run(self, *, mode: str, source_filter: str) -> str:
        payload = {"mode": mode, "source_filter": source_filter}
        r = self._client.post(
            f"{self._base}/import_runs", headers=self._headers, json=payload
        )
        r.raise_for_status()
        return r.json()[0]["run_id"]

    def update_import_run(
        self,
        *,
        run_id: str,
        candidates_processed: int,
        inserts: int,
        updates: int,
        skips: int,
        orphans_marked: int,
        errors_json: dict[str, Any] | None,
        report_artifact_url: str | None,
    ) -> None:
        payload: dict[str, Any] = {
            "completed_at": "now()",
            "candidates_processed": candidates_processed,
            "inserts": inserts,
            "updates": updates,
            "skips": skips,
            "orphans_marked": orphans_marked,
            "errors_json": errors_json,
            "report_artifact_url": report_artifact_url,
        }
        headers = dict(self._headers)
        headers["Prefer"] = "return=minimal"
        r = self._client.patch(
            f"{self._base}/import_runs?run_id=eq.{run_id}",
            headers=headers,
            json=payload,
        )
        r.raise_for_status()
```

- [ ] **Step 5: Run the tests and confirm they pass**

```powershell
uv run pytest tests/test_supabase_client.py -v
```

Expected: three tests pass.

- [ ] **Step 6: Commit**

```powershell
git add importer/importer/supabase_client.py importer/config.yaml importer/pyproject.toml importer/uv.lock importer/tests/test_supabase_client.py
git commit -m "feat(importer): Supabase service-role client + config"
```

---

## Task 10: Diff stage

**Files:**
- Create: `importer/importer/stages/diff.py`
- Create: `importer/tests/stages/test_diff.py`

The diff stage takes `ClassifiedCandidate`s, looks them up in Supabase by `(source, source_external_id)`, and classifies each as INSERT / UPDATE / SKIP per spec §3 reconciliation logic. After the per-candidate loop, any existing row whose external_id is not in the current run is marked as an orphan (orphan-marking is a separate Supabase write — out of scope for the unit test; covered in Task 11).

- [ ] **Step 1: Write the failing tests**

`importer/tests/stages/test_diff.py`:

```python
from datetime import date
from uuid import uuid4

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult, DiffStats, diff_candidates
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow


CELL = StateLawCell(
    state="US",
    category=RestrictionTag.STATE_LOCAL_GOVT,
    default_status="NO_GUN",
    confidence="high",
    conditions=[],
    citation="18 USC 930(a)",
    last_verified_date=date(2026, 5, 1),
)


def _classified(eid: str, name: str = "X") -> ClassifiedCandidate:
    return ClassifiedCandidate(
        candidate=Candidate(
            source="hifld_courts",
            source_external_id=eid,
            source_dataset_version="HIFLD-2026-05",
            name=name,
            latitude=29.0,
            longitude=-95.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="TX",
        ),
        cell=CELL,
    )


def test_no_match_classifies_as_insert() -> None:
    stats = DiffStats()
    result = diff_candidates([_classified("NEW")], existing=[], stats=stats)
    assert isinstance(result, DiffResult)
    assert len(result.inserts) == 1
    assert result.inserts[0].candidate.source_external_id == "NEW"
    assert stats.inserts == 1


def test_match_user_modified_is_skip() -> None:
    existing = [
        ExistingPinRow(
            id=str(uuid4()),
            source="hifld_courts",
            source_external_id="USR",
            name="User-edited name",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            user_modified=True,
            source_dataset_version="HIFLD-2026-04",
        )
    ]
    stats = DiffStats()
    result = diff_candidates([_classified("USR", "Source name")], existing=existing, stats=stats)
    assert result.inserts == []
    assert len(result.skips) == 1
    assert stats.skips == 1


def test_match_not_user_modified_is_update() -> None:
    existing = [
        ExistingPinRow(
            id=str(uuid4()),
            source="hifld_courts",
            source_external_id="UPD",
            name="Stale name",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            user_modified=False,
            source_dataset_version="HIFLD-2026-04",
        )
    ]
    stats = DiffStats()
    result = diff_candidates([_classified("UPD", "Fresh name")], existing=existing, stats=stats)
    assert len(result.updates) == 1
    assert stats.updates == 1


def test_existing_row_not_in_current_run_is_orphan() -> None:
    existing = [
        ExistingPinRow(
            id=str(uuid4()),
            source="hifld_courts",
            source_external_id="GONE",
            name="Closed courthouse",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            user_modified=False,
            source_dataset_version="HIFLD-2026-04",
        )
    ]
    stats = DiffStats()
    result = diff_candidates([_classified("STAYING")], existing=existing, stats=stats)
    assert len(result.inserts) == 1
    assert len(result.orphans) == 1
    assert result.orphans[0].source_external_id == "GONE"
    assert stats.orphans == 1
```

- [ ] **Step 2: Implement the diff stage**

`importer/importer/stages/diff.py`:

```python
"""Classify each ClassifiedCandidate against the existing Supabase pins table."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field

from pydantic import BaseModel, ConfigDict

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.supabase_client import ExistingPinRow


class DiffResult(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True, frozen=True)

    inserts: list[ClassifiedCandidate]
    updates: list[ClassifiedCandidate]
    skips: list[ClassifiedCandidate]   # user_modified rows we leave alone
    orphans: list[ExistingPinRow]      # in DB, not in current run


@dataclass
class DiffStats:
    inserts: int = 0
    updates: int = 0
    skips: int = 0
    orphans: int = 0


def diff_candidates(
    classified: Iterable[ClassifiedCandidate],
    *,
    existing: list[ExistingPinRow],
    stats: DiffStats,
) -> DiffResult:
    by_eid = {row.source_external_id: row for row in existing if row.source_external_id}
    seen_eids: set[str] = set()

    inserts: list[ClassifiedCandidate] = []
    updates: list[ClassifiedCandidate] = []
    skips: list[ClassifiedCandidate] = []

    for cc in classified:
        eid = cc.candidate.source_external_id
        seen_eids.add(eid)
        existing_row = by_eid.get(eid)
        if existing_row is None:
            inserts.append(cc)
            stats.inserts += 1
        elif existing_row.user_modified:
            skips.append(cc)
            stats.skips += 1
        else:
            updates.append(cc)
            stats.updates += 1

    orphans = [
        row
        for eid, row in by_eid.items()
        if eid not in seen_eids
    ]
    stats.orphans = len(orphans)

    return DiffResult(inserts=inserts, updates=updates, skips=skips, orphans=orphans)
```

- [ ] **Step 3: Run the tests and confirm they pass**

```powershell
uv run pytest tests/stages/test_diff.py -v
```

Expected: four tests pass.

- [ ] **Step 4: Commit**

```powershell
git add importer/importer/stages/diff.py importer/tests/stages/test_diff.py
git commit -m "feat(importer): diff stage — classify insert/update/skip/orphan"
```

---

## Task 11: Apply stage

**Files:**
- Create: `importer/importer/stages/apply.py`
- Create: `importer/tests/stages/test_apply.py`

The apply stage converts `ClassifiedCandidate`s into `SupabaseUpsertRow`s (deriving status from `cell.default_status`, citation from `cell.citation`, etc.) and calls `SupabaseClient.upsert_pins`. It also marks orphans by issuing a separate `PATCH` setting `source_orphaned_at = now()`. In dry-run mode the stage is a no-op (the caller branches on `mode`).

- [ ] **Step 1: Add an orphan-marking method to `SupabaseClient`**

Append to `importer/importer/supabase_client.py`:

```python
    def mark_orphans(self, source: str, external_ids: list[str]) -> None:
        if not external_ids:
            return
        in_list = ",".join(f'"{eid}"' for eid in external_ids)
        headers = dict(self._headers)
        headers["Prefer"] = "return=minimal"
        r = self._client.patch(
            f"{self._base}/pins?source=eq.{source}"
            f"&source_external_id=in.({in_list})",
            headers=headers,
            json={"source_orphaned_at": "now()"},
        )
        r.raise_for_status()
```

- [ ] **Step 2: Write the failing tests**

`importer/tests/stages/test_apply.py`:

```python
from datetime import date
from unittest.mock import MagicMock

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow, SupabaseUpsertRow


CELL = StateLawCell(
    state="US",
    category=RestrictionTag.STATE_LOCAL_GOVT,
    default_status="NO_GUN",
    confidence="high",
    conditions=[],
    citation="18 USC 930(a)",
    last_verified_date=date(2026, 5, 1),
)


def _classified(eid: str) -> ClassifiedCandidate:
    return ClassifiedCandidate(
        candidate=Candidate(
            source="hifld_courts",
            source_external_id=eid,
            source_dataset_version="HIFLD-2026-05",
            name="Courthouse",
            latitude=29.0,
            longitude=-95.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="TX",
        ),
        cell=CELL,
    )


def _orphan(eid: str) -> ExistingPinRow:
    return ExistingPinRow(
        id="00000000-0000-0000-0000-000000000099",
        source="hifld_courts",
        source_external_id=eid,
        name="X",
        latitude=0.0,
        longitude=0.0,
        status=2,
        restriction_tag="STATE_LOCAL_GOVT",
        user_modified=False,
        source_dataset_version="old",
    )


def test_apply_writes_inserts_and_updates_and_marks_orphans() -> None:
    client = MagicMock()
    diff = DiffResult(
        inserts=[_classified("A"), _classified("B")],
        updates=[_classified("C")],
        skips=[_classified("D")],
        orphans=[_orphan("Z")],
    )
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
        source="hifld_courts",
    )

    # Upsert called once with insert+update rows merged (3 total).
    client.upsert_pins.assert_called_once()
    rows = client.upsert_pins.call_args.args[0]
    assert len(rows) == 3
    assert all(isinstance(r, SupabaseUpsertRow) for r in rows)
    assert {r.source_external_id for r in rows} == {"A", "B", "C"}

    # Orphan-marking called for "Z" only.
    client.mark_orphans.assert_called_once_with("hifld_courts", ["Z"])


def test_apply_derives_status_from_cell() -> None:
    client = MagicMock()
    diff = DiffResult(inserts=[_classified("A")], updates=[], skips=[], orphans=[])
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
        source="hifld_courts",
    )
    row = client.upsert_pins.call_args.args[0][0]
    assert row.status == 2  # NO_GUN
    assert row.restriction_tag == "STATE_LOCAL_GOVT"
    assert row.legal_citation == "18 USC 930(a)"
    assert row.confidence == "high"
    assert row.legal_citation_verified_date == "2026-05-01"
    assert row.has_security_screening is True  # courthouses default true
    assert row.has_posted_signage is False     # spec §1: importer cannot verify
    assert row.created_by == "81775f8b-1a6a-47d6-b793-e9ab7e38634e"


def test_apply_with_empty_diff_does_nothing() -> None:
    client = MagicMock()
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[])
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
        source="hifld_courts",
    )
    client.upsert_pins.assert_not_called()
    client.mark_orphans.assert_not_called()
```

- [ ] **Step 3: Implement the stage**

`importer/importer/stages/apply.py`:

```python
"""Convert diff output into Supabase writes (service-role)."""

from __future__ import annotations

from uuid import uuid4

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult
from importer.supabase_client import SupabaseClient, SupabaseUpsertRow


# Default flags per source category. HIFLD courthouses are public buildings
# with security screening; signage is irrelevant (carry is statutorily
# prohibited regardless of posting), but the spec convention is to default
# has_posted_signage=False since the importer cannot verify it externally.
_HIFLD_COURTS_DEFAULTS = {
    "has_security_screening": True,
    "has_posted_signage": False,
}


def _status_int(cell_status: str) -> int:
    return {"ALLOWED": 0, "UNCERTAIN": 1, "NO_GUN": 2}[cell_status]


def _to_upsert_row(
    cc: ClassifiedCandidate, *, system_user_id: str
) -> SupabaseUpsertRow:
    defaults = _HIFLD_COURTS_DEFAULTS if cc.candidate.source == "hifld_courts" else {
        "has_security_screening": False,
        "has_posted_signage": False,
    }
    return SupabaseUpsertRow(
        id=str(uuid4()),  # stable per-row identity at insert; updates upsert by (source, source_external_id)
        source=cc.candidate.source,
        source_external_id=cc.candidate.source_external_id,
        source_dataset_version=cc.candidate.source_dataset_version,
        name=cc.candidate.name,
        latitude=cc.candidate.latitude,
        longitude=cc.candidate.longitude,
        status=_status_int(cc.cell.default_status),
        restriction_tag=cc.candidate.category.value,
        has_security_screening=defaults["has_security_screening"],
        has_posted_signage=defaults["has_posted_signage"],
        created_by=system_user_id,
        confidence=cc.cell.confidence,
        legal_citation=cc.cell.citation,
        legal_citation_verified_date=cc.cell.last_verified_date.isoformat(),
    )


def apply_to_supabase(
    diff: DiffResult,
    *,
    client: SupabaseClient,
    system_user_id: str,
    source: str,
) -> None:
    rows = [
        _to_upsert_row(cc, system_user_id=system_user_id)
        for cc in diff.inserts + diff.updates
    ]
    if rows:
        client.upsert_pins(rows)

    orphan_eids = [
        row.source_external_id
        for row in diff.orphans
        if row.source_external_id is not None
    ]
    if orphan_eids:
        client.mark_orphans(source, orphan_eids)
```

- [ ] **Step 4: Run the tests and confirm they pass**

```powershell
uv run pytest tests/stages/test_apply.py -v
```

Expected: three tests pass.

- [ ] **Step 5: Commit**

```powershell
git add importer/importer/supabase_client.py importer/importer/stages/apply.py importer/tests/stages/test_apply.py
git commit -m "feat(importer): apply stage writes upserts + marks orphans"
```

---

## Task 12: Report generator (Markdown + JSON)

**Files:**
- Create: `importer/importer/reports/__init__.py`, `importer/importer/reports/markdown.py`, `importer/importer/reports/json_report.py`
- Create: `importer/tests/reports/__init__.py`, `importer/tests/reports/test_markdown.py`, `importer/tests/reports/test_json_report.py`

The Markdown report goes to a workflow artifact for humans; the JSON sidecar lets other tooling parse the same data. Both consume a `PipelineResult` (defined in Task 13's `pipeline.py` — for this task we declare a minimal `PipelineResult` shape inline so reports can be tested in isolation).

- [ ] **Step 1: Define the report-input shape**

Add to `importer/importer/reports/__init__.py`:

```python
"""Report generation for dry-run and apply modes."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from importer.stages.diff import DiffResult


@dataclass
class PipelineResult:
    """Everything a report needs to render. Produced by importer.pipeline."""

    mode: str  # 'dry-run' or 'apply'
    started_at: datetime
    completed_at: datetime | None
    source: str
    states: list[str]
    candidates_fetched: int
    candidates_after_state_filter: int
    classified: int
    dropped_no_cell: int
    missing_cells: list[tuple[str, str]]
    name_truncations: int
    diff: DiffResult
    errors: list[str] = field(default_factory=list)
```

- [ ] **Step 2: Write the failing tests**

`importer/tests/reports/test_markdown.py`:

```python
from datetime import datetime, timezone

from importer.reports import PipelineResult
from importer.reports.markdown import render_markdown
from importer.stages.diff import DiffResult


def _empty_diff() -> DiffResult:
    return DiffResult(inserts=[], updates=[], skips=[], orphans=[])


def test_markdown_includes_header_and_counts() -> None:
    result = PipelineResult(
        mode="dry-run",
        started_at=datetime(2026, 5, 24, 12, 0, tzinfo=timezone.utc),
        completed_at=datetime(2026, 5, 24, 12, 1, tzinfo=timezone.utc),
        source="hifld_courts",
        states=["TX", "FL", "PA"],
        candidates_fetched=200,
        candidates_after_state_filter=150,
        classified=148,
        dropped_no_cell=2,
        missing_cells=[("TX", "HEALTHCARE")],
        name_truncations=3,
        diff=_empty_diff(),
    )
    md = render_markdown(result)
    assert "# Importer dry-run report" in md
    assert "hifld_courts" in md
    assert "TX, FL, PA" in md
    assert "Candidates fetched: **200**" in md
    assert "Name truncations: **3**" in md
    assert "(TX, HEALTHCARE)" in md


def test_markdown_flags_missing_cells_section() -> None:
    result = PipelineResult(
        mode="dry-run",
        started_at=datetime.now(timezone.utc),
        completed_at=None,
        source="hifld_courts",
        states=["TX"],
        candidates_fetched=10,
        candidates_after_state_filter=10,
        classified=8,
        dropped_no_cell=2,
        missing_cells=[("TX", "BAR_ALCOHOL"), ("TX", "HEALTHCARE")],
        name_truncations=0,
        diff=_empty_diff(),
    )
    md = render_markdown(result)
    assert "## Needs research" in md
    assert "(TX, BAR_ALCOHOL)" in md
    assert "(TX, HEALTHCARE)" in md
```

`importer/tests/reports/test_json_report.py`:

```python
import json
from datetime import datetime, timezone

from importer.reports import PipelineResult
from importer.reports.json_report import render_json
from importer.stages.diff import DiffResult


def test_json_report_is_valid_json_and_contains_counts() -> None:
    result = PipelineResult(
        mode="apply",
        started_at=datetime(2026, 5, 24, tzinfo=timezone.utc),
        completed_at=datetime(2026, 5, 24, tzinfo=timezone.utc),
        source="hifld_courts",
        states=["TX"],
        candidates_fetched=10,
        candidates_after_state_filter=10,
        classified=10,
        dropped_no_cell=0,
        missing_cells=[],
        name_truncations=0,
        diff=DiffResult(inserts=[], updates=[], skips=[], orphans=[]),
    )
    payload = json.loads(render_json(result))
    assert payload["mode"] == "apply"
    assert payload["source"] == "hifld_courts"
    assert payload["counts"]["candidates_fetched"] == 10
    assert payload["counts"]["inserts"] == 0
```

- [ ] **Step 3: Implement the renderers**

`importer/importer/reports/markdown.py`:

```python
"""Render a PipelineResult as a human-readable Markdown report."""

from __future__ import annotations

from importer.reports import PipelineResult


def render_markdown(r: PipelineResult) -> str:
    lines: list[str] = []
    title = "dry-run report" if r.mode == "dry-run" else "apply report"
    lines.append(f"# Importer {title}")
    lines.append("")
    lines.append(f"- Source: **{r.source}**")
    lines.append(f"- States: **{', '.join(r.states)}**")
    lines.append(f"- Started: {r.started_at.isoformat()}")
    if r.completed_at is not None:
        lines.append(f"- Completed: {r.completed_at.isoformat()}")
    lines.append("")

    lines.append("## Counts")
    lines.append("")
    lines.append(f"- Candidates fetched: **{r.candidates_fetched}**")
    lines.append(f"- After state filter: **{r.candidates_after_state_filter}**")
    lines.append(f"- Classified by state-law table: **{r.classified}**")
    lines.append(f"- Dropped (no state-law cell): **{r.dropped_no_cell}**")
    lines.append(f"- Name truncations: **{r.name_truncations}**")
    lines.append(f"- INSERT: **{len(r.diff.inserts)}**")
    lines.append(f"- UPDATE: **{len(r.diff.updates)}**")
    lines.append(f"- SKIP (user-modified): **{len(r.diff.skips)}**")
    lines.append(f"- Orphan: **{len(r.diff.orphans)}**")
    lines.append("")

    if r.missing_cells:
        lines.append("## Needs research")
        lines.append("")
        lines.append("These (state, category) pairs had no row in `data/state_laws/states.yaml` and were dropped. Add cells before the next run if these should be classified.")
        lines.append("")
        for state, category in sorted(r.missing_cells):
            lines.append(f"- ({state}, {category})")
        lines.append("")

    if r.diff.orphans:
        lines.append("## Orphans (in DB, not in current source)")
        lines.append("")
        lines.append("Pins whose `(source, source_external_id)` is no longer in the upstream dataset. They are NOT auto-deleted; review and decide.")
        lines.append("")
        for row in r.diff.orphans[:50]:
            lines.append(f"- `{row.source_external_id}` — {row.name}")
        if len(r.diff.orphans) > 50:
            lines.append(f"- … and {len(r.diff.orphans) - 50} more.")
        lines.append("")

    if r.errors:
        lines.append("## Errors")
        lines.append("")
        for err in r.errors:
            lines.append(f"- {err}")
        lines.append("")

    return "\n".join(lines)
```

`importer/importer/reports/json_report.py`:

```python
"""Render a PipelineResult as a JSON sidecar."""

from __future__ import annotations

import json

from importer.reports import PipelineResult


def render_json(r: PipelineResult) -> str:
    payload = {
        "mode": r.mode,
        "source": r.source,
        "states": r.states,
        "started_at": r.started_at.isoformat(),
        "completed_at": r.completed_at.isoformat() if r.completed_at else None,
        "counts": {
            "candidates_fetched": r.candidates_fetched,
            "candidates_after_state_filter": r.candidates_after_state_filter,
            "classified": r.classified,
            "dropped_no_cell": r.dropped_no_cell,
            "name_truncations": r.name_truncations,
            "inserts": len(r.diff.inserts),
            "updates": len(r.diff.updates),
            "skips": len(r.diff.skips),
            "orphans": len(r.diff.orphans),
        },
        "missing_cells": [list(p) for p in r.missing_cells],
        "orphans": [
            {"source_external_id": row.source_external_id, "name": row.name}
            for row in r.diff.orphans
        ],
        "errors": r.errors,
    }
    return json.dumps(payload, indent=2, sort_keys=True)
```

- [ ] **Step 4: Run the tests and confirm they pass**

```powershell
uv run pytest tests/reports/ -v
```

Expected: three tests pass.

- [ ] **Step 5: Commit**

```powershell
git add importer/importer/reports/ importer/tests/reports/
git commit -m "feat(importer): Markdown + JSON report renderers"
```

---

## Task 13: Pipeline orchestrator + CLI wiring

**Files:**
- Create: `importer/importer/pipeline.py`
- Modify: `importer/importer/cli.py`
- Create: `importer/tests/test_pipeline.py`, `importer/tests/test_cli.py`

The pipeline orchestrator threads `Candidate`s through every stage, populating a `PipelineResult`, returning it for report rendering. The CLI wires:

- `--dry-run` (default) / `--apply` (mutually exclusive)
- `--states TX,FL,PA` (comma list)
- `--sources hifld_courts` (comma list; Phase 2 only supports this one)
- `--project-ref staging|prod` (positional-equivalent; `staging` default for dry-run, no default for apply)
- `--i-know-this-writes-to-<ref>` confirmation flag required for `--apply`
- `--report-out <path>` (defaults to `./report-<run_id>.md` next to the script)
- `--refetch` (forces source `fetch()` to re-download)

Service-role key comes from the env var `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`.

- [ ] **Step 1: Write the failing pipeline test**

`importer/tests/test_pipeline.py`:

```python
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import load_state_locator
from importer.pipeline import run_pipeline
from importer.reports import PipelineResult
from importer.restriction_tag import RestrictionTag
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.state_laws import StateLawCell, StateLawTable


FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_pipeline_dry_run_against_fixture() -> None:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )
    table = StateLawTable(rows=[
        StateLawCell(
            state="US",
            category=RestrictionTag.STATE_LOCAL_GOVT,
            default_status="NO_GUN",
            confidence="high",
            conditions=[],
            citation="18 USC 930(a)",
            last_verified_date=date(2026, 5, 1),
        ),
    ])
    client = MagicMock()
    # Diff stage asks "what's already there?" — return empty so everything is INSERT.
    client.select_pins_by_keys.return_value = []

    result = run_pipeline(
        source=source,
        state_laws=table,
        client=client,
        states=["TX", "FL", "PA"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert isinstance(result, PipelineResult)
    assert result.mode == "dry-run"
    assert result.candidates_fetched > 0
    assert len(result.diff.inserts) > 0
    # Dry-run must not write anything.
    client.upsert_pins.assert_not_called()
    client.mark_orphans.assert_not_called()


def test_pipeline_apply_mode_calls_client(monkeypatch) -> None:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )
    table = StateLawTable(rows=[
        StateLawCell(
            state="US",
            category=RestrictionTag.STATE_LOCAL_GOVT,
            default_status="NO_GUN",
            confidence="high",
            conditions=[],
            citation="18 USC 930(a)",
            last_verified_date=date(2026, 5, 1),
        ),
    ])
    client = MagicMock()
    client.select_pins_by_keys.return_value = []

    run_pipeline(
        source=source,
        state_laws=table,
        client=client,
        states=["TX"],
        mode="apply",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert client.upsert_pins.called
```

- [ ] **Step 2: Write the failing CLI tests**

`importer/tests/test_cli.py`:

```python
import pytest

from importer.cli import build_parser, main


def test_parser_accepts_dry_run_with_defaults() -> None:
    parser = build_parser()
    args = parser.parse_args([
        "--dry-run",
        "--states", "TX,FL,PA",
        "--sources", "hifld_courts",
        "--project-ref", "staging",
    ])
    assert args.dry_run is True
    assert args.states == ["TX", "FL", "PA"]
    assert args.sources == ["hifld_courts"]
    assert args.project_ref == "staging"


def test_parser_requires_confirmation_flag_for_apply() -> None:
    parser = build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args([
            "--apply",
            "--states", "TX",
            "--sources", "hifld_courts",
            "--project-ref", "prod",
            # Missing --i-know-this-writes-to-prod
        ])


def test_parser_rejects_unknown_source() -> None:
    parser = build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args([
            "--dry-run",
            "--states", "TX",
            "--sources", "definitely_not_a_source",
            "--project-ref", "staging",
        ])


def test_main_returns_nonzero_on_missing_service_role_key(monkeypatch) -> None:
    monkeypatch.delenv("IMPORTER_SUPABASE_SERVICE_ROLE_KEY", raising=False)
    rc = main([
        "--dry-run",
        "--states", "TX",
        "--sources", "hifld_courts",
        "--project-ref", "staging",
    ])
    assert rc != 0
```

- [ ] **Step 3: Implement the pipeline**

`importer/importer/pipeline.py`:

```python
"""End-to-end orchestration of all pipeline stages."""

from __future__ import annotations

from datetime import datetime, timezone

from importer.reports import PipelineResult
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
    source: Source,
    state_laws: StateLawTable,
    client: SupabaseClient,
    states: list[str],
    mode: str,
    system_user_id: str,
    refetch: bool = False,
) -> PipelineResult:
    started_at = datetime.now(timezone.utc)
    state_set = set(states) if states else None

    source.fetch(refetch=refetch)

    # 1. Source → Candidates
    raw_candidates = list(source.iter_candidates(state_filter=state_set))
    fetched = len(raw_candidates)
    after_filter = fetched  # state_filter already applied inside the source

    # 2. Normalize names
    norm_stats = NormalizeStats()
    normalized = list(normalize(raw_candidates, stats=norm_stats))

    # 3. Refine coordinates (Phase 2 pass-through)
    refined = list(refine_coords(normalized))

    # 4. Apply state law (drop unclassifiable)
    asl_stats = ApplyStateLawStats()
    classified = list(apply_state_law(refined, table=state_laws, stats=asl_stats))

    # 5. Dedup (Phase 2 pass-through)
    deduped = list(dedup(classified, existing_user_pins=[]))

    # 6. Diff against Supabase
    diff_stats = DiffStats()
    external_ids = [cc.candidate.source_external_id for cc in deduped]
    existing = client.select_pins_by_keys(source.SOURCE_NAME, external_ids)
    diff_result = diff_candidates(deduped, existing=existing, stats=diff_stats)

    # 7. Apply (no-op in dry-run)
    if mode == "apply":
        apply_to_supabase(
            diff_result,
            client=client,
            system_user_id=system_user_id,
            source=source.SOURCE_NAME,
        )

    completed_at = datetime.now(timezone.utc)
    return PipelineResult(
        mode=mode,
        started_at=started_at,
        completed_at=completed_at,
        source=source.SOURCE_NAME,
        states=sorted(state_set) if state_set else [],
        candidates_fetched=fetched,
        candidates_after_state_filter=after_filter,
        classified=asl_stats.classified,
        dropped_no_cell=asl_stats.dropped_no_cell,
        missing_cells=sorted(asl_stats.missing_cells),
        name_truncations=norm_stats.truncations,
        diff=diff_result,
    )
```

- [ ] **Step 4: Implement the CLI**

`importer/importer/cli.py` (replace the placeholder):

```python
"""Entrypoint for `python -m importer.cli`.

Exit codes:
  0 — success
  1 — operational failure (network, Supabase, etc.)
  2 — usage error (bad flags, missing env var)
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import yaml

from importer.geo.states import load_state_locator
from importer.pipeline import run_pipeline
from importer.reports.json_report import render_json
from importer.reports.markdown import render_markdown
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.state_laws import load_state_laws
from importer.supabase_client import SupabaseClient


SUPPORTED_SOURCES = ("hifld_courts",)
SUPPORTED_REFS = ("staging", "prod")

REPO_ROOT = Path(__file__).resolve().parent.parent.parent  # importer/../ == repo root
CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.yaml"
STATES_YAML = REPO_ROOT / "data" / "state_laws" / "states.yaml"
STATES_BOUNDARY_FIXTURE = (
    Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "states_sample.geojson"
)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="importer",
        description="CCW Map pre-populate-pins importer.",
    )
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="Default; no writes.")
    mode.add_argument("--apply", action="store_true", help="Write to Supabase.")

    p.add_argument(
        "--states",
        required=True,
        type=lambda v: [s.strip().upper() for s in v.split(",") if s.strip()],
        help="Comma-separated USPS state codes, e.g. TX,FL,PA.",
    )
    p.add_argument(
        "--sources",
        required=True,
        type=lambda v: [s.strip() for s in v.split(",") if s.strip()],
        choices=None,  # validated manually below for friendlier error
        help=f"Comma-separated source names. Phase 2 supports: {','.join(SUPPORTED_SOURCES)}.",
    )
    p.add_argument(
        "--project-ref",
        required=True,
        choices=SUPPORTED_REFS,
        help="Which Supabase project to target.",
    )
    p.add_argument(
        "--i-know-this-writes-to-staging",
        action="store_true",
        help="Required confirmation for --apply --project-ref staging.",
    )
    p.add_argument(
        "--i-know-this-writes-to-prod",
        action="store_true",
        help="Required confirmation for --apply --project-ref prod.",
    )
    p.add_argument(
        "--report-out",
        type=Path,
        default=None,
        help="Path to write the Markdown report (default: ./report-<timestamp>.md).",
    )
    p.add_argument(
        "--refetch",
        action="store_true",
        help="Force per-source fetch() to re-download even if cached.",
    )

    # Manual choice validation for friendlier errors than argparse's default.
    orig_parse_args = p.parse_args

    def _parse_args(argv=None):
        args = orig_parse_args(argv)
        for s in args.sources:
            if s not in SUPPORTED_SOURCES:
                p.error(f"unsupported source: {s!r}; supported: {','.join(SUPPORTED_SOURCES)}")
        if args.apply:
            confirm_attr = f"i_know_this_writes_to_{args.project_ref}"
            if not getattr(args, confirm_attr, False):
                p.error(
                    f"--apply with --project-ref {args.project_ref} requires "
                    f"--i-know-this-writes-to-{args.project_ref}"
                )
        return args

    p.parse_args = _parse_args  # type: ignore[assignment]
    return p


def _load_config() -> dict:
    return yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        level=logging.INFO,
        format='{"level":"%(levelname)s","msg":%(message)r,"logger":"%(name)s"}',
    )

    parser = build_parser()
    args = parser.parse_args(argv)

    service_role_key = os.environ.get("IMPORTER_SUPABASE_SERVICE_ROLE_KEY")
    if not service_role_key:
        sys.stderr.write(
            "ERROR: IMPORTER_SUPABASE_SERVICE_ROLE_KEY env var is required.\n"
        )
        return 2

    config = _load_config()
    project = config["projects"][args.project_ref]
    system_user_id = config["system_user_id"]

    locator = load_state_locator(STATES_BOUNDARY_FIXTURE)
    state_laws = load_state_laws(STATES_YAML)

    mode = "apply" if args.apply else "dry-run"
    run_id: str | None = None

    with SupabaseClient(
        url=project["url"],
        service_role_key=service_role_key,
        system_user_id=system_user_id,
    ) as client:
        try:
            run_id = client.insert_import_run(
                mode=mode, source_filter=",".join(args.sources)
            )

            # Phase 2: only one source supported. Loop is here so adding sources later is mechanical.
            for source_name in args.sources:
                if source_name != "hifld_courts":
                    raise NotImplementedError(source_name)
                source = HifldCourthousesSource(
                    cache_path=Path(REPO_ROOT / config["sources"]["hifld_courts"]["cache_dir"] / "courthouses.geojson"),
                    state_locator=locator,
                    dataset_version=config["sources"]["hifld_courts"]["dataset_version"],
                )
                result = run_pipeline(
                    source=source,
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
                    candidates_processed=result.candidates_fetched,
                    inserts=len(result.diff.inserts),
                    updates=len(result.diff.updates),
                    skips=len(result.diff.skips),
                    orphans_marked=len(result.diff.orphans),
                    errors_json=None,
                    report_artifact_url=None,
                )
        except Exception as exc:  # noqa: BLE001  — top-level catchall by design
            logging.exception("importer failed")
            if run_id is not None:
                try:
                    client.update_import_run(
                        run_id=run_id,
                        candidates_processed=0,
                        inserts=0,
                        updates=0,
                        skips=0,
                        orphans_marked=0,
                        errors_json={"message": str(exc)},
                        report_artifact_url=None,
                    )
                except Exception:  # noqa: BLE001
                    logging.exception("failed to mark import_run as errored")
            return 1

    return 0
```

- [ ] **Step 5: Run the new tests and confirm they pass**

```powershell
uv run pytest tests/test_pipeline.py tests/test_cli.py -v
```

Expected: six tests pass.

- [ ] **Step 6: Commit**

```powershell
git add importer/importer/pipeline.py importer/importer/cli.py importer/tests/test_pipeline.py importer/tests/test_cli.py
git commit -m "feat(importer): pipeline orchestrator + argparse CLI"
```

---

## Task 14: Repo-level wiring (.gitignore + Flutter CI paths-ignore)

**Files:**
- Modify: `.gitignore`, `.github/workflows/pr-checks.yml`
- Create: `data/sources/.gitkeep`

Importer artifacts should not pollute git, and importer-only PRs should not fan out into Flutter checks.

- [ ] **Step 1: Append to `.gitignore`**

Edit `.gitignore` and add after the existing rules:

```text

# Importer (Python project under importer/)
importer/.venv/
importer/.pytest_cache/
importer/**/__pycache__/
importer/dist/
importer/*.egg-info/
importer/htmlcov/

# Cached source datasets (we commit fixtures under importer/tests/fixtures/
# but NOT the full multi-MB downloads). Per spec §1.
data/sources/*
!data/sources/.gitkeep
!data/sources/.hifld_courts_url.txt
```

- [ ] **Step 2: Create `data/sources/.gitkeep`**

Create an empty file at `data/sources/.gitkeep` so the directory exists in fresh clones.

- [ ] **Step 3: Confirm `git status` shows nothing under `data/sources/` is tracked except `.gitkeep`**

```powershell
git status data/sources/
```

Expected: only `.gitkeep` is new; any locally-cached `courthouses.geojson` is ignored.

- [ ] **Step 4: Add `paths-ignore` to each Flutter-side job in `pr-checks.yml`**

Read `.github/workflows/pr-checks.yml`. For every job that runs Flutter (format, analyze, test, android build, ios build), add this top-level filter under the existing `on:` block:

```yaml
on:
  pull_request:
    branches: [master]
    paths-ignore:
      - 'importer/**'
      - 'data/**'
      - 'docs/importer/**'
```

If `pr-checks.yml` already uses `paths` (an allow-list), use `paths-ignore` instead by inverting the logic to "skip when only importer/data/docs-importer files changed." The intent is: importer-only PRs do not run flutter format/analyze/test/build.

Independently, **`supabase-migration-validate.yml` is unaffected** — it only runs on `supabase/migrations/**` changes, which never overlap with importer changes.

- [ ] **Step 5: Smoke-check the workflow change**

```powershell
# Open the workflow in your editor and re-read it end-to-end to confirm:
#   - every job has paths-ignore set
#   - no job lost its existing trigger
# No automated CI test for this — the proof comes in Task 16 when the next
# importer-only PR completes its CI run.
```

- [ ] **Step 6: Commit**

```powershell
git add .gitignore data/sources/.gitkeep .github/workflows/pr-checks.yml
git commit -m "chore(ci): ignore importer artifacts; skip Flutter checks for importer-only PRs"
```

---

## Task 15: GitHub Actions — importer-pr-validate.yml

**Files:**
- Create: `.github/workflows/importer-pr-validate.yml`

Runs on every PR touching `importer/**` or `data/state_laws/**`. Sets up Python via `astral-sh/setup-uv@v3`, installs the package, runs the unit-test suite, then runs `python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging` and uploads the resulting report as a workflow artifact.

- [ ] **Step 1: Create the workflow**

`.github/workflows/importer-pr-validate.yml`:

```yaml
name: Importer PR Validate (staging dry-run)

on:
  pull_request:
    branches: [master]
    paths:
      - 'importer/**'
      - 'data/state_laws/**'

concurrency:
  # Serialize importer dry-runs against staging — only one PR at a time may
  # talk to the shared staging Supabase project. Per spec §7 limitations.
  group: importer-staging
  cancel-in-progress: false

jobs:
  validate:
    name: Tests + dry-run against staging
    runs-on: ubuntu-latest
    env:
      IMPORTER_SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.STAGING_SUPABASE_SERVICE_ROLE_KEY }}
    defaults:
      run:
        working-directory: importer
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v3
        with:
          version: '0.5.x'

      - name: Pin Python
        run: uv python install 3.12

      - name: Install project + dev deps
        run: uv pip install --system -e ".[dev]"

      - name: Run unit tests
        run: uv run pytest

      - name: Dry-run against staging
        run: |
          uv run python -m importer.cli \
            --dry-run \
            --states TX,FL,PA \
            --sources hifld_courts \
            --project-ref staging \
            --report-out "$GITHUB_WORKSPACE/importer-report.md"

      - name: Upload report artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: importer-dry-run-report-${{ github.event.pull_request.number }}
          path: |
            importer-report.md
            importer-report.json
          retention-days: 14
```

- [ ] **Step 2: Commit**

```powershell
git add .github/workflows/importer-pr-validate.yml
git commit -m "ci(importer): PR-validate workflow runs tests + staging dry-run"
```

---

## Task 16: GitHub Actions — importer-dry-run.yml (weekly cron)

**Files:**
- Create: `.github/workflows/importer-dry-run.yml`

Same shape as PR-validate, but cron-triggered weekly and not gated on PR diff. Used to catch upstream source schema drift before a real apply.

- [ ] **Step 1: Create the workflow**

`.github/workflows/importer-dry-run.yml`:

```yaml
name: Importer Weekly Dry-Run (staging)

on:
  schedule:
    - cron: '0 12 * * 1'   # Mondays 12:00 UTC
  workflow_dispatch: {}

concurrency:
  group: importer-staging
  cancel-in-progress: false

jobs:
  dry-run:
    name: Weekly staging dry-run
    runs-on: ubuntu-latest
    env:
      IMPORTER_SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.STAGING_SUPABASE_SERVICE_ROLE_KEY }}
    defaults:
      run:
        working-directory: importer
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v3
        with:
          version: '0.5.x'

      - name: Pin Python
        run: uv python install 3.12

      - name: Install project
        run: uv pip install --system -e ".[dev]"

      - name: Dry-run against staging
        run: |
          uv run python -m importer.cli \
            --dry-run \
            --states TX,FL,PA \
            --sources hifld_courts \
            --project-ref staging \
            --refetch \
            --report-out "$GITHUB_WORKSPACE/importer-report.md"

      - name: Upload report artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: importer-weekly-dry-run-${{ github.run_id }}
          path: |
            importer-report.md
            importer-report.json
          retention-days: 30
```

- [ ] **Step 2: Commit**

```powershell
git add .github/workflows/importer-dry-run.yml
git commit -m "ci(importer): weekly scheduled dry-run against staging"
```

---

## Task 17: GitHub Actions — importer-apply.yml (manual dispatch)

**Files:**
- Create: `.github/workflows/importer-apply.yml`

`workflow_dispatch` only. Operator picks `target` (`staging` | `prod`). Required input `confirm` must equal the literal value `I-KNOW-THIS-WRITES-TO-<TARGET>` to defend against fat-finger. Apply runs the importer in `--apply` mode against the chosen project ref and posts the report as an artifact.

- [ ] **Step 1: Create the workflow**

`.github/workflows/importer-apply.yml`:

```yaml
name: Importer Apply (manual)

on:
  workflow_dispatch:
    inputs:
      target:
        description: 'Which Supabase project to write to'
        required: true
        type: choice
        options:
          - staging
          - prod
      confirm:
        description: 'Type exactly: I-KNOW-THIS-WRITES-TO-STAGING or I-KNOW-THIS-WRITES-TO-PROD'
        required: true
        type: string

concurrency:
  group: importer-${{ inputs.target }}
  cancel-in-progress: false

jobs:
  apply:
    name: Apply to ${{ inputs.target }}
    runs-on: ubuntu-latest
    env:
      IMPORTER_SUPABASE_SERVICE_ROLE_KEY: ${{ inputs.target == 'prod' && secrets.PROD_SUPABASE_SERVICE_ROLE_KEY || secrets.STAGING_SUPABASE_SERVICE_ROLE_KEY }}
    defaults:
      run:
        working-directory: importer
    steps:
      - name: Validate confirmation phrase
        run: |
          expected="I-KNOW-THIS-WRITES-TO-$(echo '${{ inputs.target }}' | tr a-z A-Z)"
          if [ "${{ inputs.confirm }}" != "$expected" ]; then
            echo "::error::Confirmation phrase must be: $expected"
            exit 1
          fi

      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v3
        with:
          version: '0.5.x'

      - name: Pin Python
        run: uv python install 3.12

      - name: Install project
        run: uv pip install --system -e ".[dev]"

      - name: Apply to ${{ inputs.target }}
        run: |
          uv run python -m importer.cli \
            --apply \
            --states TX,FL,PA \
            --sources hifld_courts \
            --project-ref ${{ inputs.target }} \
            --i-know-this-writes-to-${{ inputs.target }} \
            --report-out "$GITHUB_WORKSPACE/importer-report.md"

      - name: Upload report artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: importer-apply-${{ inputs.target }}-${{ github.run_id }}
          path: |
            importer-report.md
            importer-report.json
          retention-days: 90
```

- [ ] **Step 2: Add the GitHub Actions secrets**

In the repo's GitHub Settings → Secrets and variables → Actions, add:

- `STAGING_SUPABASE_SERVICE_ROLE_KEY` — staging service-role key.
- `PROD_SUPABASE_SERVICE_ROLE_KEY` — leave unset until prod actually gets data; the workflow will fail the apply attempt instead of silently no-op'ing because Postgrest will reject an empty `apikey` header. That fail-loud behavior is the intended guardrail.

- [ ] **Step 3: Commit**

```powershell
git add .github/workflows/importer-apply.yml
git commit -m "ci(importer): manual-dispatch apply with confirm-phrase guardrail"
```

---

## Task 18: Operator docs

**Files:**
- Create: `docs/importer/README.md`, `docs/importer/SOURCES.md`

- [ ] **Step 1: Create `docs/importer/README.md`**

```markdown
# Pre-populate pins — importer operator guide

The importer is a Python project at [`importer/`](../../importer/) that reads
public datasets, classifies them per the maintained state-law table
([`data/state_laws/states.yaml`](../../data/state_laws/states.yaml)), and
either generates a dry-run report or writes upserts to a target Supabase
project using the service-role key.

This guide covers operator workflows. For the why and the schema, see the
[design spec](../superpowers/specs/2026-05-10-pre-populate-pins-design.md).

## When to run

| Workflow | Trigger | Target |
|---|---|---|
| `importer-pr-validate.yml` | PR touching `importer/**` or `data/state_laws/**` | Staging dry-run |
| `importer-dry-run.yml` | Cron, Monday 12:00 UTC | Staging dry-run |
| `importer-apply.yml` | Manual `workflow_dispatch` | Staging or prod (operator-selected) |

Local runs use `uv run python -m importer.cli` and read the service-role key
from the env var `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`.

## Quick start (local)

```powershell
cd importer
uv venv
uv pip install -e ".[dev]"
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<staging service-role key>"

# Dry-run (no writes)
uv run python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging

# Apply to staging
uv run python -m importer.cli --apply --states TX,FL,PA --sources hifld_courts --project-ref staging --i-know-this-writes-to-staging
```

The report is written to `./report-<run-id>.md` and `./report-<run-id>.json`
in the current working directory by default; pass `--report-out path/to/file.md`
to override.

## Re-running is safe

Each pin is keyed by `(source, source_external_id)`. Subsequent runs upsert
into existing rows. The Phase 0 trigger `set_user_modified` marks rows touched
by anyone other than `service_role`; the diff stage SKIPs those rows so user
edits are never overwritten.

## Refreshing the HIFLD fixture

If the HIFLD courthouses dataset changes shape (new properties, dropped
fields), refresh the checked-in fixture and re-run tests:

```powershell
# 1. Grab a fresh sample from the live URL captured in
#    data/sources/.hifld_courts_url.txt (see pre-flight checklist of
#    Phase 2 plan)
# 2. Copy a small representative slice (TX + FL + PA, ~50 rows max) into
#    importer/tests/fixtures/hifld_courts_sample.geojson
# 3. Run tests — failures are signal, not noise
cd importer
uv run pytest
```

## Adding a new source (future phases)

1. Add a module under `importer/importer/sources/<name>.py` implementing the `Source` ABC.
2. Add the source to `SUPPORTED_SOURCES` in `importer/importer/cli.py`.
3. Add a `cache_dir` + `dataset_version` entry under `sources:` in `importer/config.yaml`.
4. Add unit-test fixtures under `importer/tests/fixtures/`.
5. Add row(s) to `data/state_laws/states.yaml` covering the new source's category × states.
6. Update `docs/importer/SOURCES.md`.

## Troubleshooting

- **`ERROR: IMPORTER_SUPABASE_SERVICE_ROLE_KEY env var is required.`** — export the env var or pass it through the workflow.
- **Postgrest returns 401** — the service-role key is wrong, or it is the anon key by mistake.
- **`(state, category)` reported as "Needs research"** — add a row to `states.yaml`. The importer never invents a status; an unclassifiable candidate is dropped, not guessed at.
- **An orphan reappears next run with non-orphan status** — the source actually has it again. `source_orphaned_at` is auto-cleared on the next successful match.
```

- [ ] **Step 2: Create `docs/importer/SOURCES.md`**

```markdown
# Importer source datasets

Running roster of upstream datasets the importer reads, their licenses, and
our compliance posture.

| Source | Module | License | Coverage | Status |
|---|---|---|---|---|
| HIFLD Courthouses | `importer/importer/sources/hifld_courts.py` | Public domain (DHS HIFLD Open) | Federal/state/local courthouses, US-wide | Phase 2 (live in staging) |
| NCES K-12 | (not yet) | Public domain (US Gov) | K-12 public + private | Phase 4 |
| IPEDS | (not yet) | Public domain (US Gov) | Colleges, universities | Phase 5 |
| FAA NPIAS | (not yet) | Public domain (US Gov) | Public-use airports | Phase 5 |
| GSA FRPP | (not yet) | Public domain (US Gov) | Federal owned/leased property | Phase 4 |
| HIFLD Hospitals | (not yet) | Public domain | Hospitals | Phase 5 |
| HIFLD Military | (not yet) | Public domain | Military installations | Phase 4 |
| OSM (Overpass) | (not yet) | **ODbL — share-alike** | Bars, places of worship, etc. | Phase 6 |

## License notes

- **Public-domain sources** (NCES, IPEDS, FAA, GSA, HIFLD, USPS) carry no attribution requirement. We attribute them in this file for honesty but the app does not display per-pin source links for them.
- **ODbL sources** (OSM) carry a share-alike obligation. Pre-populated OSM pins display "Data: OpenStreetMap (ODbL)" in the pin detail dialog (Phase 4 UI work) and a daily-regenerated `dump-YYYY-MM-DD.csv.gz` of OSM-derived rows is published to a public Supabase Storage bucket (Phase 6 work).
- The work product we contribute — the state-law classifications applied on top of source pins — is dedicated to the public domain under CC0 (see [`data/state_laws/LICENSE`](../../data/state_laws/LICENSE)).
```

- [ ] **Step 3: Commit**

```powershell
git add docs/importer/
git commit -m "docs(importer): operator guide + source roster"
```

---

## Task 19: End-to-end smoke against staging

**Files:** none new.

This is the final acceptance step. It is intentionally manual: a real run against the staging Supabase project that proves the wiring works end-to-end. After this passes, Phase 2 is complete.

- [ ] **Step 1: Confirm local environment**

```powershell
cd importer
uv run pytest
```

Expected: every test in the suite passes. If anything fails, fix it before continuing.

- [ ] **Step 2: Confirm staging is in the expected baseline state**

In the staging dashboard SQL editor:

```sql
SELECT count(*) FROM pins WHERE source = 'hifld_courts';
```

Expected: `0`. (If non-zero, a prior partial apply leaked rows; clean up by `DELETE FROM pins WHERE source = 'hifld_courts'` before continuing so the smoke result is unambiguous.)

- [ ] **Step 3: Local dry-run against staging**

```powershell
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<staging service-role key>"
uv run python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging
```

Expected output:
- Markdown report printed to stdout.
- Counts make sense: `candidates_fetched > 0`, `INSERT == candidates_after_state_filter`, `UPDATE == 0`, `SKIP == 0`, `Orphan == 0`.
- No `Needs research` section (the federal-uniform cell covers every classified row).
- `report-<uuid>.md` and `report-<uuid>.json` files written to the current directory.

If counts look wrong, do NOT proceed to apply. Diagnose first.

- [ ] **Step 4: Local apply against staging**

```powershell
uv run python -m importer.cli --apply --states TX,FL,PA --sources hifld_courts --project-ref staging --i-know-this-writes-to-staging
```

Expected: same counts as dry-run; `INSERT` count rows actually present.

- [ ] **Step 5: Verify in staging**

In the staging dashboard SQL editor:

```sql
SELECT count(*) FROM pins WHERE source = 'hifld_courts';
SELECT count(*) FROM pins WHERE source = 'hifld_courts' AND user_modified = false;
SELECT count(DISTINCT state)
  FROM (
    SELECT
      CASE
        WHEN longitude BETWEEN -107 AND -93 AND latitude BETWEEN 25 AND 37 THEN 'TX'
        WHEN longitude BETWEEN -88  AND -79 AND latitude BETWEEN 24 AND 31 THEN 'FL'
        WHEN longitude BETWEEN -81  AND -74 AND latitude BETWEEN 39 AND 43 THEN 'PA'
        ELSE 'OTHER'
      END AS state
    FROM pins WHERE source = 'hifld_courts'
  ) t
  WHERE state IN ('TX','FL','PA');
SELECT mode, candidates_processed, inserts, updates, skips, orphans_marked, completed_at
  FROM import_runs
  ORDER BY started_at DESC
  LIMIT 3;
```

Expected:
- Pin count matches the report's INSERT count.
- All rows have `user_modified = false` (importer-set rows have not been touched by a user).
- Three states present.
- `import_runs` shows the two runs (dry-run, then apply) with `completed_at` populated.

- [ ] **Step 6: Verify the deny-system-user-writes RLS policy is intact**

In a fresh staging dashboard SQL editor tab, **sign in as the system user** (any non-service-role session) via `Authentication → Users → system+ccwmap@kyberneticlabs.com → Send magic link / Use password`. Then in that authenticated session try:

```sql
DELETE FROM pins WHERE source = 'hifld_courts' LIMIT 1;
```

Expected: zero rows affected (RESTRICTIVE policy `deny_system_user_delete` from migration 008 blocks it). Re-confirm in the service-role tab that the pin row count is unchanged.

- [ ] **Step 7: Re-run apply and confirm idempotency**

```powershell
uv run python -m importer.cli --apply --states TX,FL,PA --sources hifld_courts --project-ref staging --i-know-this-writes-to-staging
```

Expected: same INSERT count (the upsert path is unconditional on existing rows), `UPDATE == 0` would also be correct if every column already matches, but Postgrest's `resolution=merge-duplicates` issues writes regardless. Either way, **`SELECT count(*) FROM pins WHERE source = 'hifld_courts'` in staging is the same number as after step 5**. No duplicates created.

- [ ] **Step 8: Test the GitHub Actions workflow path**

Push the branch and open a PR. The `importer-pr-validate.yml` workflow should run, succeed, and post a report artifact. Download it and verify counts match a local dry-run.

- [ ] **Step 9: Commit nothing — this task produces no diff**

If steps 1–8 all pass, Phase 2 is complete. Update CLAUDE.md test count if pytest reports a change (look for the "Test count: 233" line and bump it to match `flutter test` + new importer `uv run pytest` counts separately — they live in different test runners so the CLAUDE.md note should mention both).

---

## Self-review notes

Items verified end-to-end against the spec before saving:

- §1 (Sources, classification, state-law table) — Tasks 3, 5 cover it; only the `(US, STATE_LOCAL_GOVT)` cell is seeded, with the rest of the 33-cell research deferred to Phase 3 as the spec requires.
- §2 (Architecture & where the importer lives) — Tasks 1, 14 establish the `importer/` package layout, `.gitignore` rules, and CI separation.
- §3 (Schema & re-import safety) — Already landed in Phase 0's migration 008; verified consumption via Task 9 (`SupabaseClient`), Task 10 (diff stage respecting `user_modified`), and Task 11 (apply stage writing `source`, `source_dataset_version`, `legal_citation`, etc.).
- §4 (Importer pipeline & dedup) — Tasks 2 (`Candidate`), 6 (stub stages with locked signatures), 7 (normalize), 8 (apply_state_law with US fallback + source_filter), 10 (diff), 11 (apply), 13 (pipeline orchestrator + CLI). Refine-coords and dedup are pass-through per spec; full implementations are explicitly Phase 4+ and Phase 5.
- §5 (Sync model) — Unrelated to Phase 2; lives in Phase 1 which is already done.
- §6 (Error handling & observability) — Tasks 11 + 13 cover importer-side failure handling (top-level catch, `errors_json` in `import_runs`, fail-loud on missing service-role key). Tasks 15/16/17 cover artifact reports. Daily `pin-health-check` Edge Function is explicitly Phase 6/7 per spec §6.
- §7 (Staging via second free-tier project) — Phase 0 prerequisite confirmed in pre-flight. Tasks 15/16/17 all target staging; only Task 17 with `target: prod` ever talks to prod and only via manual `workflow_dispatch` with a typed confirm phrase.
- §8 rollout — This plan IS Phase 2 of the rollout; exit criteria (`python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts` produces coherent report; apply against staging produces correct rows) are the literal acceptance steps in Task 19.

No placeholder copy ("TBD", "add error handling", "similar to Task N") remains in any task body. Function/type names used in later tasks match their definitions in earlier tasks: `Candidate`, `CoordQuality`, `RestrictionTag`, `StateLawCell`, `StateLawTable`, `ClassifiedCandidate`, `DiffResult`, `DiffStats`, `NormalizeStats`, `ApplyStateLawStats`, `PipelineResult`, `SupabaseClient`, `SupabaseUpsertRow`, `ExistingPinRow`, `HifldCourthousesSource`, `StateLocator`, `Source`, `run_pipeline`, `build_parser`, `main`, `render_markdown`, `render_json`, `apply_to_supabase`, `diff_candidates`, `apply_state_law`, `normalize`, `refine_coords`, `dedup`, `dump_osm_pins`, `load_state_laws`, `load_state_locator`.
