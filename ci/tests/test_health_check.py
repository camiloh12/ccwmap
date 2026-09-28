import re
from pathlib import Path

import pytest

import health_check as hc
from health_check import Finding, RestResult, evaluate

ROOT = Path(__file__).resolve().parents[2]
SQL = (ROOT / "ci" / "health_check.sql").read_text(encoding="utf-8")

HEALTHY = {
    "imported_total": 23813,
    "imported_deleted_24h": 0,
    "deletions_24h": 3,
    "statutory_flipped": 0,
    "statutory_flipped_sample": [],
    "imported_user_edits_24h": 2,
    "imported_orphaned": 0,
    "stale_citations": 0,
    "imported_by_source_status": [
        {"source": "nces", "status": 2, "count": 15414},
        {"source": "osm", "status": 1, "count": 3287},
    ],
    "user_pins_total": 199,
    "imported_user_corrected": 7,
    "imported_reports_7d": 0,
}
REST_OK = RestResult(status=200, clusters=28)


def metrics(**overrides):
    return {**HEALTHY, **overrides}


ALL_BREACHED = metrics(
    imported_total=0,
    imported_deleted_24h=9,
    deletions_24h=999,
    statutory_flipped=3,
    imported_user_edits_24h=999,
    imported_orphaned=999,
    stale_citations=9,
)


def _flipped(i, name="Lincoln Elementary"):
    return {"id": f"00000000-0000-0000-0000-{i:012d}", "name": name, "source": "nces", "status": 0}


def test_healthy_prod_has_no_findings():
    assert evaluate("prod", HEALTHY, REST_OK) == []


@pytest.mark.parametrize(
    "key, ok_value, bad_value",
    [
        ("imported_total", 1, 0),
        ("imported_deleted_24h", 0, 1),
        ("deletions_24h", hc.MAX_DELETIONS_24H, hc.MAX_DELETIONS_24H + 1),
        ("statutory_flipped", 0, 1),
        ("imported_user_edits_24h", hc.MAX_IMPORTED_EDITS_24H, hc.MAX_IMPORTED_EDITS_24H + 1),
        ("imported_orphaned", hc.MAX_ORPHANED, hc.MAX_ORPHANED + 1),
        ("stale_citations", 0, 1),
    ],
)
def test_each_prod_rule_fires_only_past_its_threshold(key, ok_value, bad_value):
    assert evaluate("prod", metrics(**{key: ok_value}), REST_OK) == []
    found = evaluate("prod", metrics(**{key: bad_value}), REST_OK)
    assert [f.check for f in found] == [key]
    assert found[0].message and "\n" not in found[0].message


def test_staging_judges_only_clusters():
    assert evaluate("staging", ALL_BREACHED, REST_OK) == []
    found = evaluate("staging", ALL_BREACHED, RestResult(status=503))
    assert [f.check for f in found] == ["clusters"]


def test_prod_without_metrics_judges_only_clusters():
    # check_db() reports the database failure itself (rule 1).
    assert evaluate("prod", None, REST_OK) == []


@pytest.mark.parametrize(
    "rest, expected",
    [
        (RestResult(status=503), "HTTP 503"),
        (RestResult(status=200, clusters=0), "no clusters"),
        (RestResult(problem="no response (URLError)"), "no response"),
    ],
)
def test_cluster_rule(rest, expected):
    found = evaluate("prod", HEALTHY, rest)
    assert [f.check for f in found] == ["clusters"]
    assert expected in found[0].message


def test_flipped_statutory_pins_are_listed_and_capped():
    sample = [_flipped(i) for i in range(hc.FLIPPED_SAMPLE)]
    (f,) = evaluate("prod", metrics(statutory_flipped=25, statutory_flipped_sample=sample), REST_OK)
    for p in sample:
        assert p["id"] in f.message
    assert "`Lincoln Elementary`" in f.message
    assert "now ALLOWED" in f.message
    assert "5 more" in f.message


def test_hostile_pin_names_stay_one_inert_line():
    # Users can rename imported pins (012). The name lands in an issue, a job
    # output and a log annotation: one line, inside a code span.
    name = "Evil`\n::error::x @owner [link](http://x)  #12"
    flipped = metrics(statutory_flipped=1, statutory_flipped_sample=[_flipped(1, name)])
    (f,) = evaluate("prod", flipped, REST_OK)
    assert "\n" not in f.message and " " not in f.message
    assert "`Evil' ::error::x @owner [link](http://x) #12`" in f.message


def test_long_names_are_truncated():
    flipped = metrics(statutory_flipped=1, statutory_flipped_sample=[_flipped(1, "x" * 500)])
    (f,) = evaluate("prod", flipped, REST_OK)
    assert "x" * 80 not in f.message


# ── ci/health_check.sql structure ────────────────────────────────────

WRITE_KEYWORDS = re.compile(
    r"\b(INSERT|UPDATE|DELETE|TRUNCATE|ALTER|DROP|CREATE|GRANT|REVOKE|COPY|CALL|MERGE)\b",
    re.IGNORECASE,
)


def _sql_code() -> str:
    return re.sub(r"--[^\n]*", "", SQL)


def test_sql_is_one_read_only_statement():
    code = _sql_code()
    assert not WRITE_KEYWORDS.search(code), WRITE_KEYWORDS.search(code)
    assert code.count(";") == 1 and code.rstrip().endswith(";")
    assert code.lstrip().upper().startswith(("WITH", "SELECT"))


def test_sql_returns_exactly_the_metric_keys():
    keys = set(re.findall(r"'(\w+)',\s*\(SELECT", SQL))
    assert keys == hc.METRIC_KEYS


def test_sql_caps_the_flipped_sample():
    assert f"LIMIT {hc.FLIPPED_SAMPLE}" in SQL


def test_sql_filters_on_the_system_user():
    assert "81775f8b-1a6a-47d6-b793-e9ab7e38634e" in SQL
