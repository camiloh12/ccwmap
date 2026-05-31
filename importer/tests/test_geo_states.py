from pathlib import Path

import pytest

from importer.geo.states import StateLocator, load_state_locator


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
