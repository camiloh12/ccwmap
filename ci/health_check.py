"""Daily health check of prod and staging, run by .github/workflows/health-check.yml.

    DB_URL=... SUPABASE_URL=... SUPABASE_ANON_KEY=... \\
        python3 ci/health_check.py --env prod [--simulate-failure]

Runs ci/health_check.sql in a read-only psql session and asks get_pins_in_view
for clusters over Texas as a signed-out user, then turns the results into
findings. Writes a markdown digest to $GITHUB_STEP_SUMMARY and the findings as
a one-line JSON list to $GITHUB_OUTPUT (`findings`); exits 1 if there are any.
Staging judges only reachability and clusters: its data is wiped and
re-imported during testing.

Never prints the DB URL: check_db_url.problems() checks its shape first, and
all tool output goes through redact.redact().
Spec: docs/superpowers/specs/2026-09-27-daily-health-check-design.md
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import subprocess
import sys
import traceback
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from check_db_url import problems
from redact import redact

# Thresholds: a finding is raised when a value is past these.
MAX_DELETIONS_24H = 50  # rule 5: all pin deletions, last 24 h
MAX_IMPORTED_EDITS_24H = 50  # rule 7: user edits of imported pins, last 24 h
MAX_ORPHANED = 100  # rule 8: imported pins whose source record disappeared
FLIPPED_SAMPLE = 20  # rule 6 lists this many pins (the LIMIT in health_check.sql)

# Rule 2: clusters over Texas at zoom 5, fetched as a signed-out user.
CLUSTER_QUERY = {"sw_lat": 25.0, "sw_lng": -107.0, "ne_lat": 37.0, "ne_lng": -93.0, "zoom": 5}

SQL_PATH = Path(__file__).with_name("health_check.sql")
CONNECT_TIMEOUT_S = 15
STATEMENT_TIMEOUT = "30s"
PSQL_TIMEOUT_S = 90
HTTP_TIMEOUT_S = 30
EXCERPT_CHARS = 300

# Where the workflow reads each value from; findings name these.
DB_URL_NAMES = {"staging": "STAGING_DB_URL", "prod": "PROD_DB_URL"}
REST_NAMES = {
    "staging": ("STAGING_SUPABASE_URL", "STAGING_SUPABASE_ANON_KEY"),
    "prod": ("SUPABASE_URL", "SUPABASE_ANON_KEY"),
}
STATUS_NAMES = {0: "ALLOWED", 1: "UNCERTAIN", 2: "NO_GUN"}
STAGING_PAUSED_HINT = "staging may be paused: resume it in the dashboard (90-day window)"


@dataclass(frozen=True)
class Finding:
    check: str  # "database", "clusters", a metric key, or "simulated"
    message: str  # one line; pin names inside are sanitized with _code()


@dataclass(frozen=True)
class RestResult:
    status: int | None = None  # HTTP status; None when no response came back
    clusters: int = 0  # rows with kind == 'cluster'
    problem: str | None = None  # why the call can't be judged by status/clusters


@dataclass(frozen=True)
class Rule:
    num: int
    key: str  # metric key in health_check.sql
    label: str
    alert_when: str
    breached: Callable[[int], bool]
    message: Callable[[int, dict], str]


def _one_line(text: object, limit: int = 80) -> str:
    """Printable, single-line, backtick-free and bounded: pin names are user-editable."""
    s = "".join(ch if ch.isprintable() else " " for ch in str(text if text is not None else ""))
    s = " ".join(s.split()).replace("`", "'")
    return s if len(s) <= limit else s[: limit - 1] + "…"


def _code(text: object, limit: int = 80) -> str:
    """Inline code span: in an issue, `@owner` or `#12` inside it stays inert text."""
    return f"`{_one_line(text, limit) or '(empty)'}`"


def _flipped_message(n: int, m: dict) -> str:
    sample = m["statutory_flipped_sample"]
    pins = "; ".join(
        f"{p['id']} {_code(p['name'])} "
        f"({_one_line(p['source'])}, now {STATUS_NAMES.get(p['status'], p['status'])})"
        for p in sample
    )
    more = f"; and {n - len(sample)} more" if n > len(sample) else ""
    return (
        f"{n} statutory imported pin(s) are no longer NO_GUN: "
        f"{pins}{more}. Restore steps: docs/importer/PROD_HEALTH_CHECK.md"
    )


METRIC_RULES: tuple[Rule, ...] = (
    Rule(
        3, "imported_total", "Imported pins total", "= 0",
        lambda n: n == 0,
        lambda n, m: "prod has no imported pins (about 23,800 expected): a mass delete or a failed import",
    ),
    Rule(
        4, "imported_deleted_24h", "Imported pins deleted, last 24 h", "> 0",
        lambda n: n > 0,
        lambda n, m: (
            f"{n} imported pin(s) deleted in the last 24 h; users can't delete them (012), "
            "so this is an admin error, a leaked key or a policy regression"
        ),
    ),
    Rule(
        5, "deletions_24h", "All pin deletions, last 24 h", f"> {MAX_DELETIONS_24H}",
        lambda n: n > MAX_DELETIONS_24H,
        lambda n, m: f"{n} pin deletions in the last 24 h (threshold {MAX_DELETIONS_24H}): possible scripted mass delete",
    ),
    Rule(
        6, "statutory_flipped", "Statutory imported pins no longer NO_GUN", "> 0",
        lambda n: n > 0,
        _flipped_message,
    ),
    Rule(
        7, "imported_user_edits_24h", "User edits of imported pins, last 24 h", f"> {MAX_IMPORTED_EDITS_24H}",
        lambda n: n > MAX_IMPORTED_EDITS_24H,
        lambda n, m: (
            f"{n} imported pins edited by users in the last 24 h "
            f"(threshold {MAX_IMPORTED_EDITS_24H}): check for vandalism"
        ),
    ),
    Rule(
        8, "imported_orphaned", "Orphaned imported pins", f"> {MAX_ORPHANED}",
        lambda n: n > MAX_ORPHANED,
        lambda n, m: (
            f"{n} imported pins are orphaned (threshold {MAX_ORPHANED}): "
            "a source dropped records; review before the next import"
        ),
    ),
    Rule(
        9, "stale_citations", "Imported pins citing law verified > 12 months ago", "> 0",
        lambda n: n > 0,
        lambda n, m: (
            f"{n} imported pin(s) cite law last verified more than 12 months ago: "
            "re-verify data/state_laws/states.yaml, then re-import"
        ),
    ),
)

# Every key health_check.sql returns; test_health_check.py keeps the two in sync.
METRIC_KEYS = frozenset(
    {r.key for r in METRIC_RULES}
    | {
        "statutory_flipped_sample",
        "imported_by_source_status",
        "user_pins_total",
        "imported_user_corrected",
        "imported_reports_7d",
    }
)


def _rest_problem(rest: RestResult) -> str | None:
    if rest.problem:
        return f"clusters check failed: {rest.problem}"
    if rest.status != 200:
        return f"get_pins_in_view returned HTTP {rest.status} for a signed-out user"
    if rest.clusters == 0:
        return "get_pins_in_view returned no clusters over Texas at zoom 5 for a signed-out user"
    return None


def evaluate(env: str, metrics: dict | None, rest: RestResult) -> list[Finding]:
    """Findings for rule 2 (both envs) and rules 3-9 (prod only).

    `metrics` is None when the database check failed; check_db() reports
    that (rule 1) itself.
    """
    findings = []
    problem = _rest_problem(rest)
    if problem:
        findings.append(Finding("clusters", problem))
    if env == "prod" and metrics is not None:
        for rule in METRIC_RULES:
            n = metrics[rule.key]
            if rule.breached(n):
                findings.append(Finding(rule.key, rule.message(n, metrics)))
    return findings


# ── Rule 1: the database ─────────────────────────────────────────────


def _unreachable(env: str, detail: str) -> Finding:
    msg = f"database unreachable: {_code(detail, EXCERPT_CHARS)}"
    if env == "staging":
        msg += f"; {STAGING_PAUSED_HINT}"
    return Finding("database", msg)


def parse_metrics(stdout: str) -> dict:
    # Not splitlines(): pin names may hold U+2028/U+2029/U+0085, which
    # Postgres's JSON leaves unescaped. psql ends rows with "\n" only.
    lines = [line for line in stdout.split("\n") if line.strip()]
    if not lines:
        raise ValueError("psql printed nothing")
    metrics = json.loads(lines[-1])
    if not isinstance(metrics, dict):
        raise ValueError("expected a JSON object")
    missing = METRIC_KEYS - metrics.keys()
    if missing:
        raise ValueError(f"missing keys: {', '.join(sorted(missing))}")
    return metrics


def check_db(env: str, db_url: str, run: Callable = subprocess.run) -> tuple[dict | None, Finding | None]:
    """Rule 1: metrics from health_check.sql, or the finding that explains why there are none."""
    found = problems(db_url)
    if found:
        return None, Finding("database", f"{DB_URL_NAMES[env]} is malformed: {'; '.join(found)}")
    cmd = [
        "psql", "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-d", db_url,
        "-c", "SET default_transaction_read_only = on",
        "-c", f"SET statement_timeout = '{STATEMENT_TIMEOUT}'",
        "-f", str(SQL_PATH),
    ]
    env_vars = {
        **os.environ,
        "PGCONNECT_TIMEOUT": str(CONNECT_TIMEOUT_S),
        "PGSSLMODE": "require",
        "PGAPPNAME": "ccwmap-health-check",
    }
    try:
        proc = run(cmd, capture_output=True, text=True, timeout=PSQL_TIMEOUT_S, env=env_vars)
    except subprocess.TimeoutExpired:  # its message holds cmd, and cmd holds the URL
        return None, _unreachable(env, f"psql did not finish within {PSQL_TIMEOUT_S}s")
    if proc.returncode != 0:
        detail = proc.stderr or proc.stdout or f"psql exited {proc.returncode}"
        return None, _unreachable(env, redact(detail, db_url))
    try:
        return parse_metrics(proc.stdout), None
    except ValueError as e:
        return None, Finding(
            "database", f"health_check.sql output wasn't the expected JSON: {_code(redact(str(e), db_url))}"
        )


# ── Rule 2: clusters over REST, signed out ───────────────────────────


def rest_headers(anon_key: str) -> dict[str, str]:
    headers = {"apikey": anon_key, "Content-Type": "application/json", "Accept": "application/json"}
    if anon_key.startswith("eyJ"):
        # Legacy anon keys are JWTs and also go in Authorization; new
        # sb_publishable_ keys aren't JWTs and belong only in apikey.
        headers["Authorization"] = f"Bearer {anon_key}"
    return headers


def _http_post(url: str, headers: dict[str, str], body: bytes) -> tuple[int, bytes]:
    """(status, body). An HTTP error returns its status and an empty body; network errors raise."""
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        e.close()  # never read an error body: it could echo request headers
        return e.code, b""


def count_clusters(body: bytes) -> int:
    rows = json.loads(body)
    if not isinstance(rows, list):
        raise ValueError("expected a JSON array of rows")
    return sum(1 for row in rows if isinstance(row, dict) and row.get("kind") == "cluster")


def check_clusters(env: str, base_url: str, anon_key: str, post: Callable = _http_post) -> RestResult:
    """Rule 2: get_pins_in_view over Texas at zoom 5, as a signed-out user."""
    if not base_url or not anon_key:
        return RestResult(problem=f"{' / '.join(REST_NAMES[env])} not set")
    url = base_url.rstrip("/") + "/rest/v1/rpc/get_pins_in_view"
    try:
        status, body = post(url, rest_headers(anon_key), json.dumps(CLUSTER_QUERY).encode())
    except (OSError, http.client.HTTPException) as e:
        return RestResult(problem=f"no response ({type(e).__name__})")
    if status != 200:
        return RestResult(status=status)
    try:
        return RestResult(status=200, clusters=count_clusters(body))
    except ValueError:
        return RestResult(status=200, problem="HTTP 200 but the body wasn't a JSON array of rows")


# ── Digest ───────────────────────────────────────────────────────────


def _rest_value(rest: RestResult) -> str:
    if rest.problem:
        return f"— ({_one_line(rest.problem)})"
    return f"{rest.clusters:,} clusters (HTTP {rest.status})"


def render_digest(env: str, metrics: dict | None, rest: RestResult, findings: list[Finding]) -> str:
    """Markdown for the job summary: every signal with its value and threshold, then the counts."""
    judged = env == "prod"

    def result(bad: bool) -> str:
        return "🔴 alert" if bad else "✅ ok"

    lines = [
        f"## Daily health check: {env}",
        "",
        "| # | Signal | Value | Alert when | Result |",
        "|---|---|---|---|---|",
        f"| 1 | Database reachable | {'yes' if metrics is not None else 'no'} "
        f"| connection or query fails | {result(metrics is None)} |",
        f"| 2 | Clusters over TX at zoom 5, signed out | {_rest_value(rest)} "
        f"| HTTP ≠ 200 or 0 clusters | {result(_rest_problem(rest) is not None)} |",
    ]
    for rule in METRIC_RULES:
        if metrics is None:
            value, res = "—", "no data"
        else:
            n = metrics[rule.key]
            value = f"{n:,}"
            res = result(rule.breached(n)) if judged else "not judged"
        lines.append(f"| {rule.num} | {rule.label} | {value} | {rule.alert_when} | {res} |")
    if not judged:
        lines += ["", "Staging data is wiped and re-imported during testing, so only checks 1 and 2 are judged here."]
    if metrics is not None:
        lines += ["", "### Imported pins by source and status", "", "| Source | Status | Pins |", "|---|---|---|"]
        for row in metrics["imported_by_source_status"]:
            status = STATUS_NAMES.get(row["status"], row["status"])
            lines.append(f"| {_one_line(row['source'])} | {status} | {row['count']:,} |")
        lines += [
            "",
            f"- User pins: {metrics['user_pins_total']:,}",
            f"- Imported pins users have corrected (all time): {metrics['imported_user_corrected']:,}",
            f"- Reports filed on imported pins, last 7 days: {metrics['imported_reports_7d']:,}",
        ]
    lines += ["", "### Findings", ""]
    lines += [f"- {f.message}" for f in findings] or ["None."]
    return "\n".join(lines) + "\n"


# ── Orchestration and CLI ────────────────────────────────────────────

SIMULATED = Finding("simulated", "simulated failure (manual run with simulate_failure); nothing is wrong")


def run_checks(
    env: str,
    db_url: str,
    base_url: str,
    anon_key: str,
    simulate: bool = False,
    *,
    run: Callable = subprocess.run,
    post: Callable = _http_post,
) -> tuple[list[Finding], str]:
    metrics, db_finding = check_db(env, db_url, run=run)
    rest = check_clusters(env, base_url, anon_key, post=post)
    findings = ([db_finding] if db_finding else []) + evaluate(env, metrics, rest)
    if simulate:
        findings.append(SIMULATED)
    return findings, render_digest(env, metrics, rest, findings)


def _append(path: str | None, text: str) -> None:
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)


def _annotation(message: str) -> str:
    # Workflow-command escaping for the message part of ::error::
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Daily health check of prod or staging.")
    parser.add_argument("--env", required=True, choices=sorted(DB_URL_NAMES))
    parser.add_argument("--simulate-failure", action="store_true")
    args = parser.parse_args(argv)
    findings, digest = run_checks(
        args.env,
        os.environ.get("DB_URL", ""),
        os.environ.get("SUPABASE_URL", ""),
        os.environ.get("SUPABASE_ANON_KEY", ""),
        args.simulate_failure,
    )
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        _append(summary, digest)
    else:
        print(digest)
    # One line of JSON: json.dumps escapes newlines, so no multi-line delimiter
    # (which a crafted pin name could forge) is needed.
    _append(os.environ.get("GITHUB_OUTPUT"), f"findings={json.dumps([f.message for f in findings])}\n")
    for f in findings:
        print(f"::error title=Health check ({args.env})::{_annotation(f.message)}")
    if not findings:
        print(f"{args.env}: all checks passed")
    return 1 if findings else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # the alert job reports this as "ended before reporting"
        sys.stderr.write(redact(traceback.format_exc(), os.environ.get("DB_URL")))
        sys.exit(1)
