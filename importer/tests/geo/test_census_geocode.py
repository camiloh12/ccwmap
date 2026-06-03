from pathlib import Path

import pytest

from importer.geo.census_geocode import AddressRecord, CensusGeocoder

FIXTURE = Path(__file__).parent.parent / "fixtures" / "census_batch_response.txt"


def test_geocode_parses_match_and_skips_no_match(httpx_mock, tmp_path):
    httpx_mock.add_response(text=FIXTURE.read_text(encoding="utf-8"))
    geocoder = CensusGeocoder(cache_path=tmp_path / "geocoded.json")
    records = [
        AddressRecord(id="1", street="100 Main St", city="Austin", state="TX", zip="78701"),
        AddressRecord(id="2", street="999 Nowhere Rd", city="Austin", state="TX", zip="78701"),
    ]
    out = geocoder.geocode(records)
    assert out["1"] == pytest.approx((30.2672, -97.7431))
    assert "2" not in out


def test_geocode_uses_cache_on_second_call(httpx_mock, tmp_path):
    httpx_mock.add_response(text=FIXTURE.read_text(encoding="utf-8"))
    cache = tmp_path / "geocoded.json"
    rec = [AddressRecord(id="1", street="100 Main St", city="Austin", state="TX", zip="78701")]
    first = CensusGeocoder(cache_path=cache)
    first.geocode(rec)
    # Second geocoder, no new HTTP response registered — must hit cache or it errors.
    second = CensusGeocoder(cache_path=cache)
    out = second.geocode(rec)
    assert out["1"] == pytest.approx((30.2672, -97.7431))
