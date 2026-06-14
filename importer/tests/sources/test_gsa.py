from pathlib import Path

import pytest

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.gsa import GsaSource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"


class _FakeGeocoder:
    """Returns a coord for the one row that lacks lat/lng; misses nothing else."""
    def __init__(self):
        self.calls = []

    def geocode(self, records):
        self.calls.append([r.id for r in records])
        return {"RPUID-TX-2": (29.7604, -95.3698)}


@pytest.fixture
def source(tmp_path):
    return GsaSource(
        cache_path=FIXTURE_DIR / "gsa_frpp_sample.xlsx",
        dataset_version="FRPP-FIXTURE",
        geocoder=_FakeGeocoder(),
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
    )


def test_source_name_is_stable(source):
    assert source.SOURCE_NAME == "gsa"


def test_uses_existing_coords_and_geocodes_missing(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX"})}
    assert cands["RPUID-TX-1"].coord_quality is CoordQuality.PRECISE
    assert cands["RPUID-TX-2"].coord_quality is CoordQuality.ADDRESS_CENTROID
    assert cands["RPUID-TX-2"].latitude == pytest.approx(29.7604)
    assert all(c.category is RestrictionTag.FEDERAL_PROPERTY for c in cands.values())


def test_filters_state_before_geocoding(source):
    list(source.iter_candidates(state_filter={"TX"}))
    # The fake geocoder must only ever be asked about the TX row that lacked coords.
    assert source._geocoder.calls == [["RPUID-TX-2"]]


def test_excludes_land_and_no_address(source):
    cands = {c.source_external_id for c in source.iter_candidates(state_filter={"TX"})}
    assert "RPUID-TX-3" not in cands  # Land
    assert "RPUID-TX-4" not in cands  # no street address
    assert source.last_skip_counts["not_federal_facility"] >= 1
    assert source.last_skip_counts["missing_address"] >= 1


def test_drops_row_whose_coord_is_outside_claimed_state(source):
    # RPUID-TX-5 claims TEXAS but its lat/lng is in Milwaukee, WI (the real
    # ALLEGHENY-NATIONAL-FOREST-in-Milwaukee bug). The point-in-polygon check
    # must catch the disagreement and drop it.
    cands = {c.source_external_id for c in source.iter_candidates(state_filter={"TX"})}
    assert "RPUID-TX-5" not in cands
    assert source.last_skip_counts["coord_state_mismatch"] >= 1
    # A legitimately in-state row is unaffected.
    assert "RPUID-TX-1" in cands


def test_composes_label_for_city_and_address_names(source):
    cands = {c.source_external_id: c for c in source.iter_candidates(state_filter={"TX"})}
    # City-only installation name "DALLAS, TX" -> "{Use} — {City}, {ST}".
    assert cands["RPUID-TX-6"].name == "Office — Dallas, TX"
    # Address installation name "1234 Main Street" -> composed from Use + City.
    assert cands["RPUID-TX-7"].name == "Warehouses — Austin, TX"
    # A real installation name is left untouched.
    assert cands["RPUID-TX-1"].name == "Federal Office Building"
