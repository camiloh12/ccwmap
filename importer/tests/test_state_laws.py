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


def test_production_states_yaml_parses() -> None:
    table = load_state_laws(Path(__file__).parent.parent.parent / "data" / "state_laws" / "states.yaml")
    cell = table.lookup("TX", RestrictionTag.STATE_LOCAL_GOVT)
    assert cell is not None
    assert cell.state == "US"  # falls back to federal-uniform in Phase 2
    assert cell.confidence == "high"
