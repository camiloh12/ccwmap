import json
from pathlib import Path

import pytest

from importer.geo.states import US_STATES_AND_DC, StateLocator, load_state_locator

NATIONAL = Path(__file__).resolve().parents[2] / "data" / "geo" / "us_states_500k.geojson"


@pytest.fixture(scope="module")
def locator() -> StateLocator:
    return load_state_locator(
        Path(__file__).parent / "fixtures" / "states_sample.geojson"
    )


@pytest.mark.parametrize(
    "lat,lng,expected",
    [
        (29.7604, -95.3698, "TX"),   # Houston
        (25.7617, -80.1918, "FL"),   # Miami
        (39.9526, -75.1652, "PA"),   # Philadelphia
    ],
)
def test_state_for_returns_correct_code(
    locator: StateLocator, lat: float, lng: float, expected: str
) -> None:
    assert locator.state_for(lat, lng) == expected


def test_state_for_returns_none_for_ocean(locator: StateLocator) -> None:
    assert locator.state_for(40.0, -70.0) is None  # Atlantic Ocean


def test_state_for_returns_none_for_state_not_in_fixture(locator: StateLocator) -> None:
    assert locator.state_for(34.0522, -118.2437) is None  # LA, CA — not in TX/FL/PA fixture


@pytest.fixture(scope="module")
def national():
    return load_state_locator(NATIONAL)


@pytest.mark.parametrize("lat, lng, code", [
    (39.7392, -104.9903, "CO"),
    (47.6062, -122.3321, "WA"),
    (41.8781, -87.6298, "IL"),
    (38.8977, -77.0365, "DC"),
    (28.5729, -80.6490, "FL"),  # Kennedy Space Center: needs the 500k coastline
])
def test_national_file_resolves_states_outside_the_pilot(national, lat, lng, code):
    assert national.state_for(lat, lng) == code


def test_national_file_resolves_nothing_offshore(national):
    assert national.state_for(36.0, -72.0) is None


def test_national_file_holds_the_50_states_and_dc():
    raw = json.loads(NATIONAL.read_text(encoding="utf-8"))
    assert len(raw["features"]) == 51
    assert {f["properties"]["STUSPS"] for f in raw["features"]} == US_STATES_AND_DC
    assert NATIONAL.stat().st_size < 10_000_000
