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
