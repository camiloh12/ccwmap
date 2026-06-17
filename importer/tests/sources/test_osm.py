import json
from pathlib import Path

import pytest
from pytest_httpx import HTTPXMock

from importer.candidate import CoordQuality
from importer.geo.states import load_state_locator
from importer.restriction_tag import RestrictionTag
from importer.sources.osm import OsmSource
from importer.state_laws import load_state_laws

FIXTURE_DIR = Path(__file__).parent.parent / "fixtures"
STATES_YAML = Path(__file__).parents[3] / "data" / "state_laws" / "states.yaml"


def _make_source(tmp_path: Path, states: list[str]) -> OsmSource:
    return OsmSource(
        cache_dir=tmp_path,
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
        state_laws=load_state_laws(STATES_YAML),
        states=states,
        dataset_version="OSM-FIXTURE",
        overpass_url="https://overpass.example/api/interpreter",
        area_selector_template='["ISO3166-2"="US-{state}"]',
        category_tags={"BAR_ALCOHOL": ["amenity=bar", "amenity=pub"]},
    )


def test_source_name_is_stable(tmp_path):
    assert _make_source(tmp_path, ["TX"]).SOURCE_NAME == "osm"


def test_query_plan_is_per_state_autoscoped(tmp_path):
    src = _make_source(tmp_path, ["TX", "FL", "PA"])
    plan = src.build_query_plan(["TX", "FL", "PA"])
    # TX/FL have a BAR_ALCOHOL osm cell; PA does not -> no PA query at all.
    assert set(plan) == {"TX", "FL"}
    assert plan["TX"] == ["amenity=bar", "amenity=pub"]


def test_fetch_posts_overpass_query_and_caches(tmp_path, httpx_mock: HTTPXMock):
    httpx_mock.add_response(
        method="POST",
        url="https://overpass.example/api/interpreter",
        json={"elements": []},
    )
    src = _make_source(tmp_path, ["TX"])
    src.fetch()
    assert (tmp_path / "TX.json").exists()
    req = httpx_mock.get_requests()[0]
    body = req.content.decode()
    assert '["ISO3166-2"="US-TX"]' in body
    assert 'nwr["amenity"="bar"]' in body
    assert 'nwr["amenity"="pub"]' in body


def test_fetch_sends_descriptive_user_agent(tmp_path, httpx_mock: HTTPXMock):
    # Overpass's front-end returns HTTP 406 for the default python-httpx
    # User-Agent (anti-scraper filter); fetch() must send a descriptive UA that
    # identifies the importer and a contact, per Overpass etiquette.
    httpx_mock.add_response(
        method="POST",
        url="https://overpass.example/api/interpreter",
        json={"elements": []},
    )
    src = _make_source(tmp_path, ["TX"])
    src.fetch()
    ua = httpx_mock.get_requests()[0].headers["User-Agent"]
    assert "ccwmap" in ua.lower()
    assert "httpx" not in ua.lower()  # not the default library UA


def test_iter_candidates_parses_nodes_and_way_centers(tmp_path):
    (tmp_path / "TX.json").write_bytes(
        (FIXTURE_DIR / "osm_tx_bars_sample.json").read_bytes()
    )
    src = _make_source(tmp_path, ["TX"])
    cands = {c.source_external_id: c for c in src.iter_candidates(state_filter={"TX"})}

    assert set(cands) == {"node/1001", "way/2002"}
    assert cands["node/1001"].coord_quality is CoordQuality.PRECISE
    assert cands["way/2002"].coord_quality is CoordQuality.BUILDING_POLYGON
    assert all(c.category is RestrictionTag.BAR_ALCOHOL for c in cands.values())
    assert all(c.state == "TX" for c in cands.values())
    assert src.last_skip_counts["missing_name"] == 1          # node/1003
    assert src.last_skip_counts["coord_state_mismatch"] == 1  # node/1004


def test_iter_candidates_skips_states_with_no_plan(tmp_path):
    src = _make_source(tmp_path, ["PA"])
    assert list(src.iter_candidates(state_filter={"PA"})) == []
