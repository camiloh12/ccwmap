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
    assert cands["DFW"].latitude == pytest.approx(32.89723305)
    assert cands["DFW"].name == "Dallas-Fort Worth International"  # mixed-case from CS list


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
