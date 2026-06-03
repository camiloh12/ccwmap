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
