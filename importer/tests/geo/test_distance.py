import pytest

from importer.geo.distance import DEG_LAT_M, meters_between


def test_same_point_is_zero() -> None:
    assert meters_between(30.0, -97.0, 30.0, -97.0) == 0.0


def test_one_degree_of_latitude() -> None:
    assert meters_between(30.0, -97.0, 31.0, -97.0) == pytest.approx(DEG_LAT_M)


def test_longitude_degrees_shrink_with_latitude() -> None:
    # 0.00031 deg of longitude at 30.23 N: the NAS Jacksonville site-point fixture.
    assert meters_between(30.23, -81.66, 30.23, -81.65969) == pytest.approx(29.8, abs=0.2)
