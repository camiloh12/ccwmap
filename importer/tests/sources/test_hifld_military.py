import json
from pathlib import Path

import pytest
from shapely.geometry import Point, shape

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.hifld_military import HifldMilitarySource

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"
BOUNDARIES = FIXTURE_DIR / "hifld_military_sample.geojson"
POINTS = FIXTURE_DIR / "hifld_military_points_sample.geojson"
LOCATOR = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
PILOT = {"TX", "FL", "PA"}
ZERO = "00000000-0000-0000-0000-000000000000"


def _source(cache_path=BOUNDARIES, points_cache_path=POINTS, **kw):
    return HifldMilitarySource(
        cache_path=cache_path,
        points_cache_path=points_cache_path,
        state_locator=LOCATOR,
        dataset_version="HIFLD-MIL-FIXTURE",
        **kw,
    )


@pytest.fixture(scope="module")
def run():
    """(candidates by external id, skip counts) for one pass over the pilot states."""
    src = _source()
    cands = {c.source_external_id: c for c in src.iter_candidates(state_filter=PILOT)}
    return cands, src.last_skip_counts


def _parts(name):
    """Polygon parts of every fixture boundary record with this SITENAME."""
    raw = json.loads(BOUNDARIES.read_text(encoding="utf-8"))
    out = []
    for f in raw["features"]:
        if f["properties"]["SITENAME"] == name and f["geometry"]:
            g = shape(f["geometry"])
            out.extend(getattr(g, "geoms", [g]))
    return out


def _at(c):
    return Point(c.longitude, c.latitude)


def test_source_name_is_stable():
    assert HifldMilitarySource.SOURCE_NAME == "hifld_military"


def test_yields_pilot_states_as_federal_property(run):
    cands, _ = run
    assert {c.state for c in cands.values()} == PILOT
    assert all(c.category is RestrictionTag.FEDERAL_PROPERTY for c in cands.values())
    assert all(c.coord_quality is CoordQuality.BUILDING_POLYGON for c in cands.values())


def test_real_sdsid_is_the_key(run):
    cands, _ = run
    assert {"MIL-TX-1", "MIL-FL-1", "MIL-PA-1", "MIL-TX-JBSA", "MIL-FL-JAX"} <= cands.keys()


def test_blank_and_all_zero_sdsids_key_on_state_and_name(run):
    cands, _ = run
    assert "TX:NG CAMP MABRY" in cands
    assert "FL:CAMP BLANDING" in cands
    assert " " not in cands and ZERO not in cands


def test_records_sharing_a_key_merge_into_one_candidate(run):
    cands, skips = run
    swift = [c for c in cands.values() if c.name == "NG Camp Swift"]
    assert [c.source_external_id for c in swift] == ["TX:NG CAMP SWIFT"]
    assert skips["merged_records"] == 1
    largest = max(_parts("NG Camp Swift"), key=lambda g: g.area)
    assert largest.covers(_at(swift[0]))  # no site point: inside the largest part


def test_site_point_on_the_base_is_used(run):
    cands, _ = run
    assert (cands["MIL-TX-1"].latitude, cands["MIL-TX-1"].longitude) == (31.145, -97.775)


def test_site_point_within_50_m_of_the_boundary_is_used(run):
    cands, _ = run
    assert cands["MIL-FL-1"].longitude == -81.65969  # ~30 m east of the boundary


def test_site_point_on_a_small_part_beats_the_largest_part(run):
    cands, _ = run
    assert (cands["MIL-TX-JBSA"].latitude, cands["MIL-TX-JBSA"].longitude) == (29.38, -98.62)


def test_site_point_matches_on_state_and_name_ignoring_case_and_spacing(run):
    cands, _ = run
    mabry = cands["TX:NG CAMP MABRY"]
    assert (mabry.latitude, mabry.longitude) == (30.325, -97.755)


def test_far_site_point_falls_back_inside_the_largest_part(run):
    cands, _ = run
    largest = max(_parts("Jacksonville IAP (ANG)"), key=lambda g: g.area)
    assert largest.covers(_at(cands["MIL-FL-JAX"]))


def test_without_a_site_point_the_pin_is_inside_the_boundary(run):
    cands, _ = run
    (carlisle,) = _parts("Carlisle Barracks")
    assert carlisle.covers(_at(cands["MIL-PA-1"]))


def test_closed_sites_are_skipped_and_caretaker_sites_stay(run):
    cands, skips = run
    assert "MIL-TX-CLOSED" not in cands
    assert skips["closed"] == 1
    assert "MIL-PA-CARE" in cands


def test_legacy_identity_only_when_the_id_changed(run):
    cands, _ = run
    mabry = cands["TX:NG CAMP MABRY"]
    assert mabry.legacy_external_id == " "  # the old MIRTALOCATIONSIDPK fallback
    assert mabry.legacy_point == pytest.approx((30.32, -97.76))  # old centroid, not the site point
    assert cands["FL:CAMP BLANDING"].legacy_external_id == ZERO
    assert cands["MIL-TX-1"].legacy_external_id is None
    assert cands["MIL-TX-1"].legacy_point is None


def test_merged_site_takes_its_legacy_identity_from_the_first_record(run):
    cands, _ = run
    swift = cands["TX:NG CAMP SWIFT"]
    assert swift.legacy_external_id == " "
    assert swift.legacy_point == pytest.approx((30.28, -97.29))


def test_skips_null_geometry_and_out_of_state(run):
    _, skips = run
    assert skips["missing_geometry"] == 1
    assert skips["state_pip_miss"] == 1  # Camp Pendleton, CA


def test_missing_points_file_is_an_error(tmp_path):
    src = _source(points_cache_path=tmp_path / "absent.geojson")
    with pytest.raises(RuntimeError, match="site-points file missing"):
        list(src.iter_candidates(state_filter=PILOT))


@pytest.mark.parametrize("which", ["boundary", "site-points"])
def test_an_arcgis_error_body_is_an_error_not_an_empty_layer(tmp_path, which):
    bad = tmp_path / "bad.geojson"
    bad.write_text('{"error": {"code": 400, "message": "Invalid query"}}', encoding="utf-8")
    src = _source(cache_path=bad) if which == "boundary" else _source(points_cache_path=bad)
    with pytest.raises(RuntimeError, match=f"{which} file has no features"):
        list(src.iter_candidates(state_filter=PILOT))


def test_fetch_downloads_both_layers(tmp_path, httpx_mock):
    httpx_mock.add_response(url="https://example.test/boundaries", content=b'{"features": [1]}')
    httpx_mock.add_response(url="https://example.test/points", content=b'{"features": [2]}')
    src = _source(
        cache_path=tmp_path / "military.geojson",
        points_cache_path=tmp_path / "military_points.geojson",
        url="https://example.test/boundaries",
        points_url="https://example.test/points",
    )
    src.fetch()
    assert (tmp_path / "military.geojson").read_bytes() == b'{"features": [1]}'
    assert (tmp_path / "military_points.geojson").read_bytes() == b'{"features": [2]}'


def test_fetch_requires_a_points_url(tmp_path):
    src = _source(
        cache_path=tmp_path / "military.geojson",
        points_cache_path=tmp_path / "military_points.geojson",
        url="https://example.test/boundaries",
    )
    with pytest.raises(RuntimeError, match="points_url"):
        src.fetch()
