import json
from pathlib import Path

import pytest
from pytest_httpx import HTTPXMock

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


def test_iter_candidates_raises_on_arcgis_error_body(tmp_path) -> None:
    # An ArcGIS error (e.g. an expired signed-blob URL) comes back as HTTP 200
    # with an {"error": {...}} body, not a FeatureCollection. That must not be
    # read as "zero candidates".
    cache_path = tmp_path / "courts.geojson"
    cache_path.write_text(
        json.dumps({"error": {"code": 400, "message": "Invalid or missing input parameters"}}),
        encoding="utf-8",
    )
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=cache_path, state_locator=locator, dataset_version="HIFLD-FIXTURE",
    )
    with pytest.raises(RuntimeError, match="hifld_courts"):
        list(source.iter_candidates(state_filter=None))


def test_iter_candidates_raises_on_empty_features(tmp_path) -> None:
    cache_path = tmp_path / "courts.geojson"
    cache_path.write_text(
        json.dumps({"type": "FeatureCollection", "features": []}),
        encoding="utf-8",
    )
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=cache_path, state_locator=locator, dataset_version="HIFLD-FIXTURE",
    )
    with pytest.raises(RuntimeError, match="hifld_courts"):
        list(source.iter_candidates(state_filter=None))


HUB_URL = "https://hub.example/api/download/v1/items/x/geojson?redirect=true&layers=3"
BLOB_URL = "https://blob.example/courthouses.geojson"
# What the Hub answered on 2026-10-19 while it rebuilt the export.
PENDING_BODY = {
    "message": "Up to date download file is being generated. Please check back again later.",
    "status": "Pending",
    "created": "2026-10-19T00:28:54.633Z",
    "modified": "2026-10-19T00:28:54.633Z",
}
GOOD_BODY = (FIXTURE_DIR / "hifld_courts_sample.geojson").read_bytes()
OLD_CACHE = b'{"type": "FeatureCollection", "features": [{"old": true}]}'


def _fetch_source(cache_path: Path) -> HifldCourthousesSource:
    return HifldCourthousesSource(
        cache_path=cache_path,
        state_locator=load_state_locator(FIXTURE_DIR / "states_sample.geojson"),
        dataset_version="HIFLD-FIXTURE",
        url=HUB_URL,
    )


def _add_pending(httpx_mock: HTTPXMock) -> None:
    httpx_mock.add_response(url=HUB_URL, status_code=202, json=PENDING_BODY)


def _add_ready(httpx_mock: HTTPXMock, content: bytes = GOOD_BODY) -> None:
    # A ready export redirects to a signed blob holding the GeoJSON.
    httpx_mock.add_response(url=HUB_URL, status_code=302, headers={"Location": BLOB_URL})
    httpx_mock.add_response(url=BLOB_URL, content=content)


def test_fetch_waits_out_a_pending_export(tmp_path, httpx_mock: HTTPXMock, monkeypatch):
    # The Hub rebuilds the export on demand and answers 202 Pending meanwhile.
    # fetch() used to cache that status body and fail the whole run.
    sleeps: list[float] = []
    monkeypatch.setattr("time.sleep", sleeps.append)
    _add_pending(httpx_mock)
    _add_ready(httpx_mock)
    cache = tmp_path / "courts.geojson"
    _fetch_source(cache).fetch()
    assert cache.read_bytes() == GOOD_BODY
    assert len(sleeps) == 1 and sleeps[0] > 0      # waited before asking again


def test_fetch_gives_up_on_an_export_that_stays_pending(
    tmp_path, httpx_mock: HTTPXMock, monkeypatch
):
    # Bounded: a Hub stuck on Pending fails the run, and the copy already on
    # disk survives.
    monkeypatch.setattr("time.sleep", lambda *a, **k: None)
    for _ in range(HifldCourthousesSource._MAX_ATTEMPTS):
        _add_pending(httpx_mock)
    cache = tmp_path / "courts.geojson"
    cache.write_bytes(OLD_CACHE)
    with pytest.raises(RuntimeError, match="still pending"):
        _fetch_source(cache).fetch(refetch=True)
    assert len(httpx_mock.get_requests()) == HifldCourthousesSource._MAX_ATTEMPTS
    assert cache.read_bytes() == OLD_CACHE


@pytest.mark.parametrize(
    "body",
    [
        b'{"error": {"code": 400, "message": "Invalid or missing input parameters"}}',
        b'{"type": "FeatureCollection", "features": []}',
        b"<html><body>Service Unavailable</body></html>",
    ],
    ids=["arcgis-error", "no-features", "html"],
)
def test_fetch_keeps_the_cache_when_the_download_has_no_features(
    tmp_path, httpx_mock: HTTPXMock, body: bytes
):
    _add_ready(httpx_mock, content=body)
    cache = tmp_path / "courts.geojson"
    cache.write_bytes(OLD_CACHE)
    with pytest.raises(RuntimeError, match="hifld_courts"):
        _fetch_source(cache).fetch(refetch=True)
    assert cache.read_bytes() == OLD_CACHE
