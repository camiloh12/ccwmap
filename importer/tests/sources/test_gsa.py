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
