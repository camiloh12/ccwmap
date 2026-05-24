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
    all_candidates = list(source.iter_candidates(state_filter=None))
    assert all(c.state in {"TX", "FL", "PA"} for c in all_candidates)


def test_iter_candidates_skipped_count_is_recorded(
    source: HifldCourthousesSource,
) -> None:
    list(source.iter_candidates(state_filter={"TX"}))
    # FL (2) + PA (2) = 4 rows pass PIP but fail the TX filter.
    assert source.last_skip_counts["filtered_out"] >= 4
    # The fixture's CA courthouse falls outside TX/FL/PA polygons.
    assert source.last_skip_counts["state_pip_miss"] >= 1
    # The fixture has one row with geometry: null.
    assert source.last_skip_counts["missing_geometry"] >= 1
