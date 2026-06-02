from pathlib import Path

import pytest

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
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


PROD_TABLE = Path(__file__).parent.parent.parent / "data" / "state_laws" / "states.yaml"


# (candidate_state, category, expected_cell_state) for the 12 written cells.
# Federal-uniform categories resolve to the US cell via fallback.
WRITTEN_RESOLUTIONS = [
    ("TX", RestrictionTag.FEDERAL_PROPERTY, "US"),
    ("FL", RestrictionTag.FEDERAL_PROPERTY, "US"),
    ("PA", RestrictionTag.FEDERAL_PROPERTY, "US"),
    ("TX", RestrictionTag.AIRPORT_SECURE, "US"),
    ("FL", RestrictionTag.AIRPORT_SECURE, "US"),
    ("PA", RestrictionTag.AIRPORT_SECURE, "US"),
    ("TX", RestrictionTag.STATE_LOCAL_GOVT, "TX"),
    ("FL", RestrictionTag.STATE_LOCAL_GOVT, "FL"),
    ("PA", RestrictionTag.STATE_LOCAL_GOVT, "PA"),
    ("TX", RestrictionTag.SCHOOL_K12, "TX"),
    ("FL", RestrictionTag.SCHOOL_K12, "FL"),
    ("PA", RestrictionTag.SCHOOL_K12, "PA"),
    ("TX", RestrictionTag.BAR_ALCOHOL, "TX"),
    ("FL", RestrictionTag.BAR_ALCOHOL, "FL"),
    ("FL", RestrictionTag.COLLEGE_UNIVERSITY, "FL"),
]

# Intentional omissions (no row anywhere -> lookup returns None). 12 combos.
OMISSIONS = [
    ("TX", RestrictionTag.COLLEGE_UNIVERSITY),
    ("TX", RestrictionTag.HEALTHCARE),
    ("TX", RestrictionTag.PLACE_OF_WORSHIP),
    ("TX", RestrictionTag.SPORTS_ENTERTAINMENT),
    ("FL", RestrictionTag.HEALTHCARE),
    ("FL", RestrictionTag.PLACE_OF_WORSHIP),
    ("FL", RestrictionTag.SPORTS_ENTERTAINMENT),
    ("PA", RestrictionTag.COLLEGE_UNIVERSITY),
    ("PA", RestrictionTag.BAR_ALCOHOL),
    ("PA", RestrictionTag.HEALTHCARE),
    ("PA", RestrictionTag.PLACE_OF_WORSHIP),
    ("PA", RestrictionTag.SPORTS_ENTERTAINMENT),
]


@pytest.mark.parametrize("cand_state, category, expected_state", WRITTEN_RESOLUTIONS)
def test_written_cells_resolve_to_no_gun(cand_state, category, expected_state):
    table = load_state_laws(PROD_TABLE)
    cell = table.lookup(cand_state, category)
    assert cell is not None, f"{cand_state}/{category.name} must resolve to a cell"
    assert cell.state == expected_state
    assert cell.default_status == "NO_GUN"
    assert cell.citation  # non-empty
    assert cell.last_verified_date is not None


def test_bar_cells_are_medium_confidence():
    table = load_state_laws(PROD_TABLE)
    for st in ("TX", "FL"):
        cell = table.lookup(st, RestrictionTag.BAR_ALCOHOL)
        assert cell is not None and cell.state == st
        assert cell.confidence == "medium"


@pytest.mark.parametrize("state", ["TX", "PA"])
def test_campus_carry_is_not_pre_asserted(state):
    # TX (SB11 campus carry) and PA (institution-policy) must NOT pre-assert NO_GUN
    # at colleges. A row here would be the worst-case error in the risk register.
    table = load_state_laws(PROD_TABLE)
    assert table.lookup(state, RestrictionTag.COLLEGE_UNIVERSITY) is None


@pytest.mark.parametrize("state, category", OMISSIONS)
def test_documented_omissions_have_no_cell(state, category):
    table = load_state_laws(PROD_TABLE)
    assert table.lookup(state, category) is None


def _candidate(source: str, state: str, category: RestrictionTag) -> Candidate:
    return Candidate(
        source=source,
        source_external_id=f"{source}-{state}-{category.name}",
        source_dataset_version="v1",
        name="X",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=category,
        state=state,
    )


def test_source_filter_drop_edge_holds():
    # FEDERAL_PROPERTY US cell is source_filter=[gsa, hifld_military].
    # A gsa candidate is classified; an osm candidate is dropped (not classified).
    table = load_state_laws(PROD_TABLE)

    stats_ok = ApplyStateLawStats()
    classified = list(
        apply_state_law([_candidate("gsa", "TX", RestrictionTag.FEDERAL_PROPERTY)],
                        table=table, stats=stats_ok)
    )
    assert len(classified) == 1
    assert stats_ok.classified == 1

    stats_drop = ApplyStateLawStats()
    dropped = list(
        apply_state_law([_candidate("osm", "TX", RestrictionTag.FEDERAL_PROPERTY)],
                        table=table, stats=stats_drop)
    )
    assert dropped == []
    assert stats_drop.dropped_no_cell == 1
