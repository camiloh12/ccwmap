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
    assert set(cands) == {"480001607910", "120039000390", "420001300318"}
    assert {c.state for c in cands.values()} == {"TX", "FL", "PA"}
    assert all(c.category is RestrictionTag.SCHOOL_K12 for c in cands.values())
    assert all(c.coord_quality is CoordQuality.PRECISE for c in cands.values())


def test_drops_closed_school(source):
    cands = {c.source_external_id for c in source.iter_candidates(state_filter={"TX", "FL", "PA"})}
    assert "120003002975" not in cands  # FEARNSIDE FAMILY SERVICES CENTER — SY_STATUS=2 (closed)
    assert source.last_skip_counts["not_operational"] >= 1


def test_drops_mislocated_school_and_filters_out_of_region(source):
    list(source.iter_candidates(state_filter={"TX", "FL", "PA"}))
    assert source.last_skip_counts["coord_state_mismatch"] >= 1  # 480020709350 claims TX, coords WI
    assert source.last_skip_counts["filtered_out"] >= 1          # CA school
