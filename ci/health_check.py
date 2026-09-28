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

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

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
        f"{n} statutory imported pin(s) are no longer NO_GUN, which 013 should prevent: "
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
