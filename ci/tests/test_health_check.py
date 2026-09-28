import io
import json
import re
import subprocess
import sys
import urllib.error
from pathlib import Path

import pytest

import health_check as hc
from health_check import Finding, RestResult, check_clusters, check_db, count_clusters, evaluate, rest_headers

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


# ── Database collector (rule 1) ──────────────────────────────────────

PW = "Pw9%24test"  # percent-encoded (decodes to Pw9$test)
DB_URL = f"postgresql://postgres.testref:{PW}@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
LEAKS = ("postgresql://", PW, "Pw9$test", "Pw9")


class FakeRun:
    """Stands in for subprocess.run; records calls."""

    def __init__(self, returncode=0, stdout="", stderr="", raises=None):
        self.returncode, self.stdout, self.stderr, self.raises = returncode, stdout, stderr, raises
        self.calls = []

    def __call__(self, cmd, **kwargs):
        self.calls.append((cmd, kwargs))
        if self.raises:
            raise self.raises
        return subprocess.CompletedProcess(cmd, self.returncode, self.stdout, self.stderr)


def test_check_db_parses_the_json_line():
    m, finding = check_db("prod", DB_URL, run=FakeRun(stdout=json.dumps(HEALTHY) + "\n"))
    assert finding is None and m == HEALTHY


def test_check_db_runs_psql_read_only_with_timeouts():
    run = FakeRun(stdout=json.dumps(HEALTHY))
    check_db("prod", DB_URL, run=run)
    ((cmd, kwargs),) = run.calls
    assert cmd[0] == "psql"
    assert "ON_ERROR_STOP=1" in cmd
    ro = "SET default_transaction_read_only = on"
    timeout = f"SET statement_timeout = '{hc.STATEMENT_TIMEOUT}'"
    assert ro in cmd and timeout in cmd
    # Session settings first, then the query file.
    assert cmd.index(ro) < cmd.index("-f") and cmd.index(timeout) < cmd.index("-f")
    assert cmd[-2:] == ["-f", str(hc.SQL_PATH)]
    assert kwargs["timeout"] == hc.PSQL_TIMEOUT_S
    assert kwargs["env"]["PGCONNECT_TIMEOUT"] == str(hc.CONNECT_TIMEOUT_S)
    assert kwargs["env"]["PGSSLMODE"] == "require"


def test_malformed_url_is_reported_without_running_psql_or_leaking_it():
    run = FakeRun()
    m, f = check_db("staging", DB_URL.replace(":5432/", ":6543/") + " ", run=run)
    assert m is None and run.calls == []
    assert f.check == "database" and f.message.startswith("STAGING_DB_URL is malformed:")
    for leaked in LEAKS:
        assert leaked not in f.message


def test_unreachable_database_is_redacted_and_one_line():
    stderr = (
        f"psql: error: connection to server failed: {DB_URL}\n"
        "FATAL:  password authentication failed password=Pw9$test\n"
    )
    m, f = check_db("prod", DB_URL, run=FakeRun(returncode=2, stderr=stderr))
    assert m is None and f.check == "database"
    assert f.message.startswith("database unreachable:")
    assert "\n" not in f.message
    for leaked in LEAKS:
        assert leaked not in f.message
    assert hc.STAGING_PAUSED_HINT not in f.message


def test_unreachable_staging_mentions_the_pause():
    _, f = check_db("staging", DB_URL, run=FakeRun(returncode=2, stderr="timeout expired"))
    assert hc.STAGING_PAUSED_HINT in f.message


def test_psql_timeout_is_a_finding():
    # TimeoutExpired carries the command line, which holds the URL: never print it.
    timeout = subprocess.TimeoutExpired(["psql", "-d", DB_URL], hc.PSQL_TIMEOUT_S)
    _, f = check_db("prod", DB_URL, run=FakeRun(raises=timeout))
    assert f.message.startswith("database unreachable:")
    for leaked in LEAKS:
        assert leaked not in f.message


@pytest.mark.parametrize("stdout", ["", "not json", "[1, 2]", json.dumps({"imported_total": 1})])
def test_unexpected_psql_output_is_a_finding(stdout):
    m, f = check_db("prod", DB_URL, run=FakeRun(stdout=stdout))
    assert m is None and f.check == "database"
    assert "expected JSON" in f.message


# ── REST collector (rule 2) ──────────────────────────────────────────

ROWS = [{"kind": "cluster", "cluster_count": 40}, {"kind": "cluster", "cluster_count": 3}, {"kind": "pin"}]


class FakePost:
    """Stands in for _http_post; records calls."""

    def __init__(self, status=200, body=b"[]", raises=None):
        self.status, self.body, self.raises = status, body, raises
        self.calls = []

    def __call__(self, url, headers, body):
        self.calls.append((url, headers, json.loads(body)))
        if self.raises:
            raise self.raises
        return self.status, self.body


def test_count_clusters_counts_only_cluster_rows():
    assert count_clusters(json.dumps(ROWS).encode()) == 2


@pytest.mark.parametrize("body", [b"{}", b"<html>paused</html>", b""])
def test_count_clusters_rejects_non_row_bodies(body):
    with pytest.raises(ValueError):
        count_clusters(body)


def test_check_clusters_posts_the_texas_query():
    post = FakePost(body=json.dumps(ROWS).encode())
    rest = check_clusters("prod", "https://ref.supabase.co/", "sb_publishable_test", post=post)
    assert rest == RestResult(status=200, clusters=2)
    ((url, _headers, payload),) = post.calls
    assert url == "https://ref.supabase.co/rest/v1/rpc/get_pins_in_view"
    assert payload == hc.CLUSTER_QUERY


def test_publishable_key_goes_only_in_apikey():
    headers = rest_headers("sb_publishable_test")
    assert headers["apikey"] == "sb_publishable_test"
    assert "Authorization" not in headers


def test_legacy_jwt_anon_key_also_goes_in_authorization():
    headers = rest_headers("eyJtest.anon.key")
    assert headers["apikey"] == "eyJtest.anon.key"
    assert headers["Authorization"] == "Bearer eyJtest.anon.key"


@pytest.mark.parametrize(
    "env, url, key, names",
    [
        ("staging", "", "k", "STAGING_SUPABASE_URL / STAGING_SUPABASE_ANON_KEY"),
        ("prod", "https://x.supabase.co", "", "SUPABASE_URL / SUPABASE_ANON_KEY"),
    ],
)
def test_missing_rest_config_is_named_and_not_called(env, url, key, names):
    post = FakePost()
    rest = check_clusters(env, url, key, post=post)
    assert post.calls == []
    assert rest.status is None and names in rest.problem


def test_http_error_keeps_only_the_status():
    rest = check_clusters("prod", "https://x.supabase.co", "k", post=FakePost(status=401, body=b"echo"))
    assert rest == RestResult(status=401)


def test_network_error_is_a_problem():
    rest = check_clusters("prod", "https://x.supabase.co", "k", post=FakePost(raises=OSError("boom")))
    assert rest.status is None and "no response" in rest.problem


def test_non_json_200_is_a_problem():
    rest = check_clusters("prod", "https://x.supabase.co", "k", post=FakePost(body=b"<html>"))
    assert rest.status == 200 and "JSON" in rest.problem


def test_http_post_returns_an_http_errors_status_without_its_body(monkeypatch):
    def fake_urlopen(req, timeout):
        raise urllib.error.HTTPError(req.full_url, 503, "Service Unavailable", {}, io.BytesIO(b"echo"))

    monkeypatch.setattr(hc.urllib.request, "urlopen", fake_urlopen)
    assert hc._http_post("https://x.supabase.co/rest/v1/rpc/f", {}, b"{}") == (503, b"")


# ── Digest ───────────────────────────────────────────────────────────


def test_digest_shows_every_signal_and_the_counts():
    d = hc.render_digest("prod", HEALTHY, REST_OK, [])
    assert "## Daily health check: prod" in d
    for rule in hc.METRIC_RULES:
        assert rule.label in d
    assert "23,813" in d and "| nces | NO_GUN | 15,414 |" in d and "| osm | UNCERTAIN | 3,287 |" in d
    assert "User pins: 199" in d
    assert "Imported pins users have corrected (all time): 7" in d
    assert "Reports filed on imported pins, last 7 days: 0" in d
    assert "28 clusters (HTTP 200)" in d
    assert "🔴" not in d
    assert d.rstrip().endswith("None.")


def test_digest_flags_breached_rules():
    m = metrics(deletions_24h=51)
    d = hc.render_digest("prod", m, REST_OK, evaluate("prod", m, REST_OK))
    assert "| 5 | All pin deletions, last 24 h | 51 | > 50 | 🔴 alert |" in d
    assert "- 51 pin deletions in the last 24 h" in d


def test_staging_digest_shows_counts_without_judging():
    d = hc.render_digest("staging", ALL_BREACHED, REST_OK, [])
    assert "not judged" in d and "🔴" not in d
    assert "999" in d


def test_digest_without_a_database_marks_no_data():
    f = Finding("database", "database unreachable: `x`")
    d = hc.render_digest("prod", None, REST_OK, [f])
    assert "| 1 | Database reachable | no |" in d and "no data" in d
    assert "Imported pins by source" not in d
    assert "- database unreachable: `x`" in d


# ── Orchestration and CLI ────────────────────────────────────────────


def test_simulate_failure_adds_exactly_one_finding():
    run = FakeRun(stdout=json.dumps(HEALTHY))
    post = FakePost(body=json.dumps(ROWS).encode())
    base, _ = hc.run_checks("prod", DB_URL, "https://x.supabase.co", "k", False, run=run, post=post)
    sim, digest = hc.run_checks("prod", DB_URL, "https://x.supabase.co", "k", True, run=run, post=post)
    assert base == []
    assert sim == [hc.SIMULATED]
    assert hc.SIMULATED.message in digest


def test_run_checks_reports_the_database_and_still_probes_rest():
    post = FakePost(body=json.dumps(ROWS).encode())
    findings, digest = hc.run_checks(
        "staging", DB_URL, "https://x.supabase.co", "k", run=FakeRun(returncode=2, stderr="refused"), post=post
    )
    assert [f.check for f in findings] == ["database"]
    assert len(post.calls) == 1
    assert "2 clusters (HTTP 200)" in digest


def _main(monkeypatch, tmp_path, findings, argv=("--env", "prod")):
    out, summary = tmp_path / "out", tmp_path / "summary"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    monkeypatch.setattr(hc, "run_checks", lambda *a, **k: (findings, "## digest\n"))
    rc = hc.main(list(argv))
    return rc, out.read_text(encoding="utf-8"), summary.read_text(encoding="utf-8")


def test_main_green(monkeypatch, tmp_path, capsys):
    rc, out, summary = _main(monkeypatch, tmp_path, [])
    assert rc == 0
    assert out == "findings=[]\n"
    assert summary == "## digest\n"
    assert "prod: all checks passed" in capsys.readouterr().out


def test_main_red_writes_one_line_of_findings(monkeypatch, tmp_path, capsys):
    findings = [Finding("clusters", "get_pins_in_view returned HTTP 503"), Finding("x", "100% broken")]
    rc, out, _ = _main(monkeypatch, tmp_path, findings)
    assert rc == 1
    assert out.count("\n") == 1 and out.startswith("findings=")
    assert json.loads(out[len("findings="):]) == [f.message for f in findings]
    assert "::error title=Health check (prod)::100%25 broken" in capsys.readouterr().out


def test_main_passes_the_environment_and_flag(monkeypatch, tmp_path):
    seen = []
    monkeypatch.setenv("DB_URL", DB_URL)
    monkeypatch.setenv("SUPABASE_URL", "https://x.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "k")
    monkeypatch.setenv("GITHUB_OUTPUT", str(tmp_path / "out"))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(tmp_path / "summary"))
    monkeypatch.setattr(hc, "run_checks", lambda *a, **k: seen.append(a) or ([], ""))
    assert hc.main(["--env", "staging", "--simulate-failure"]) == 0
    assert seen == [("staging", DB_URL, "https://x.supabase.co", "k", True)]


def test_unexpected_error_exits_1_with_a_redacted_traceback():
    # PATH is empty, so psql isn't found and the script crashes after the URL check.
    proc = subprocess.run(
        [sys.executable, str(ROOT / "ci" / "health_check.py"), "--env", "prod"],
        env={"DB_URL": DB_URL, "SYSTEMROOT": "C:\Windows", "PATH": ""},
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 1
    assert "Traceback" in proc.stderr
    for leaked in LEAKS:
        assert leaked not in proc.stdout + proc.stderr
