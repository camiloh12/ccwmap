# Daily Health Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scheduled GitHub Actions workflow that checks prod and staging every day, stays silent when healthy, opens or comments on one `health-check` GitHub issue when not, and keeps free-tier staging from auto-pausing.

**Architecture:** `.github/workflows/health-check.yml` runs two check jobs (`staging` with no environment; `prod` in the master-only `production-plan` environment). Both jobs run one stdlib-only script, `ci/health_check.py`. The script runs one read-only SQL query (`ci/health_check.sql`) through `psql` and makes one REST call to `get_pins_in_view` as a signed-out user. It turns the results into findings, writes a markdown digest to the job summary, and publishes the findings as a one-line JSON job output. A third job, `alert`, runs only when a check job failed. It is the only job with `issues: write`, and it opens the issue or comments on the one already open.

**Tech Stack:** Python 3 stdlib (`subprocess`, `urllib`, `json`), `psql` (preinstalled on `ubuntu-latest`), PostgreSQL/PostGIS on Supabase, GitHub Actions (`actions/github-script@v7`), pytest + PyYAML (tests only, via `uv`).

**Spec:** `docs/superpowers/specs/2026-09-27-daily-health-check-design.md`

## Global Constraints

- `ci/` scripts are **stdlib only** (like `ci/check_db_url.py`, `ci/redact.py`); tests may use pytest + PyYAML.
- Never print a DB URL. Validate it with `problems()` from `ci/check_db_url.py` before use; pass every captured tool output and traceback through `redact()` from `ci/redact.py`.
- `PROD_DB_URL` is read only by the `prod` job, in environment `production-plan`. No job in this workflow may use environment `production`.
- DB session: `default_transaction_read_only = on` and `statement_timeout = '30s'`; the SQL is a single `SELECT` (no INSERT/UPDATE/DELETE/TRUNCATE/ALTER/DROP/CREATE/GRANT).
- System user ("imported" pins): `81775f8b-1a6a-47d6-b793-e9ab7e38634e`.
- Schedule `'0 11 * * *'` (11:00 UTC = 07:00 ET); `workflow_dispatch` input `simulate_failure` (boolean, default `false`).
- Thresholds: all deletions/24 h `> 50`; user edits of imported pins/24 h `> 50`; orphaned imported pins `> 100`; imported deletes, statutory flips, stale citations `> 0`; imported total `= 0`.
- Cluster probe: `get_pins_in_view(sw_lat 25.0, sw_lng -107.0, ne_lat 37.0, ne_lng -93.0, zoom 5)` with the anon key.
- Staging judges only rule 1 (DB reachable) and rule 2 (clusters). Its digest shows the other counts without judging them.
- Top-level `permissions: contents: read`; only `alert` gets `issues: write`.
- Run ci tests with: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q` (from the repo root; 75 pass before this work).
- On Windows the interpreter is `python`, not `python3` (CI uses `python3`).
- Migrations/DB: Claude has **staging** MCP access only, never prod.
- The owner's terminal hard-wraps long pasted lines, so keep SQL the owner will copy at 70 characters per line or less.
- Every commit ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
  ```

## Review Focus

1. **User-editable pin names inside findings** (012 lets users rename imported pins). A name containing a newline, U+2028, a backtick, `@owner`, `#12` or `::error::` must come out as one inert line inside a code span in the issue, the job output and the log annotation. Pinned by `test_hostile_pin_names_stay_one_inert_line` (Task 1).
2. **Findings reaching the `alert` script.** They must arrive only through `env:`, never through `${{ }}` in the script body. Otherwise a crafted pin name would run JavaScript with `issues: write`. Pinned by `test_alert_runs_no_repo_code_and_never_interpolates_findings` (Task 4).
3. **psql failure text that echoes the DB URL or password over several lines** must be redacted, collapsed to one line and length-bounded. Timeouts must not leak the command line (which holds the URL). Pinned by `test_unreachable_database_is_redacted_and_one_line` and `test_psql_timeout_is_a_finding` (Task 2).
4. **Staging REST variables not set yet** (before rollout, or on a fork). The finding must name the missing variables, and no request goes to a relative URL. Pinned by `test_missing_rest_config_is_named_and_not_called` (Task 2).
5. **SQL and Python drifting apart** (a metric renamed in one file only). A structure test must catch it in CI, and at runtime it must become a finding instead of a `KeyError` crash. Pinned by `test_sql_returns_exactly_the_metric_keys` (Task 1) and `test_unexpected_psql_output_is_a_finding` (Task 2).

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `ci/health_check.sql` | create | The one read-only query; returns every metric as one JSON object |
| `ci/health_check.py` | create | Rules and thresholds (Task 1), collectors: psql + REST (Task 2), digest + CLI (Task 3) |
| `ci/tests/test_health_check.py` | create | Unit tests for the script and SQL structure |
| `.github/workflows/health-check.yml` | create | Schedule/dispatch, `staging` / `prod` / `alert` jobs |
| `ci/tests/test_health_check_workflow.py` | create | Workflow structure and security tests |
| `.github/workflows/db-migrations.yml` | modify | Also run `workflow-tests` when `health-check.yml` changes |
| `ci/tests/test_db_migrations_workflow.py` | modify | Expect the new PR path |
| `docs/importer/PROD_HEALTH_CHECK.md` | rewrite | "Automated daily check" section, finding guide, restore SQL; manual query kept |
| `docs/dev/STAGING.md` | modify | "Keeping staging alive" now points at the daily job |
| `CLAUDE.md` | modify | Workflow list gains `health-check.yml` |
| `docs/superpowers/specs/2026-09-27-daily-health-check-design.md` | modify | Status line: approved |

---

### Task 1: Metrics query and the rules that judge it

**Files:**
- Create: `ci/health_check.sql`
- Create: `ci/health_check.py`
- Create: `ci/tests/test_health_check.py`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces (in `ci/health_check.py`):
  - constants `MAX_DELETIONS_24H = 50`, `MAX_IMPORTED_EDITS_24H = 50`, `MAX_ORPHANED = 100`, `FLIPPED_SAMPLE = 20`, `CLUSTER_QUERY: dict`, `SQL_PATH: Path`, `CONNECT_TIMEOUT_S = 15`, `STATEMENT_TIMEOUT = "30s"`, `PSQL_TIMEOUT_S = 90`, `HTTP_TIMEOUT_S = 30`, `EXCERPT_CHARS = 300`, `DB_URL_NAMES: dict[str, str]`, `REST_NAMES: dict[str, tuple[str, str]]`, `STATUS_NAMES: dict[int, str]`, `STAGING_PAUSED_HINT: str`
  - `@dataclass(frozen=True) Finding(check: str, message: str)`
  - `@dataclass(frozen=True) RestResult(status: int | None = None, clusters: int = 0, problem: str | None = None)`
  - `@dataclass(frozen=True) Rule(num, key, label, alert_when, breached: Callable[[int], bool], message: Callable[[int, dict], str])`
  - `METRIC_RULES: tuple[Rule, ...]` (rules 3–9), `METRIC_KEYS: frozenset[str]`
  - `_one_line(text: object, limit: int = 80) -> str`, `_code(text: object, limit: int = 80) -> str`
  - `_rest_problem(rest: RestResult) -> str | None`
  - `evaluate(env: str, metrics: dict | None, rest: RestResult) -> list[Finding]`
  - In the test file: `HEALTHY`, `REST_OK`, `ALL_BREACHED`, `metrics(**overrides)`, `_flipped(i, name=...)`. Tasks 2 and 3 reuse these.

- [ ] **Step 1: Write the failing tests**

Create `ci/tests/test_health_check.py`:

```python
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
    name = "Evil`\n::error::x @owner [link](http://x) \u2028#12"
    flipped = metrics(statutory_flipped=1, statutory_flipped_sample=[_flipped(1, name)])
    (f,) = evaluate("prod", flipped, REST_OK)
    assert "\n" not in f.message and "\u2028" not in f.message
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check.py -q`
Expected: collection error, `FileNotFoundError` for `ci/health_check.sql` (or `ModuleNotFoundError: No module named 'health_check'`).

- [ ] **Step 3: Write the SQL**

Create `ci/health_check.sql`:

```sql
-- Daily health check metrics: one row holding one JSON object.
-- Read by ci/health_check.py (run by .github/workflows/health-check.yml),
-- which runs it in a read-only session with a statement_timeout. Every
-- top-level key is one of health_check.py's METRIC_KEYS; the ci tests keep
-- the two in sync. "Imported" = owned by the system user the importer
-- writes as.
-- Spec: docs/superpowers/specs/2026-09-27-daily-health-check-design.md
WITH sys AS (
  SELECT '81775f8b-1a6a-47d6-b793-e9ab7e38634e'::uuid AS id
),
imported AS (
  SELECT p.id, p.name, p.source, p.status, p.confidence, p.user_modified,
         p.last_modified, p.source_orphaned_at,
         p.legal_citation_verified_date
  FROM pins p, sys
  WHERE p.created_by = sys.id
),
-- Statutory pins (confidence 'high') are NO_GUN by law, and 013 keeps
-- signed-in users from changing their status.
flipped AS (
  SELECT id, name, source, status, last_modified
  FROM imported
  WHERE confidence = 'high' AND user_modified AND status <> 2
)
SELECT json_build_object(
  'imported_total', (SELECT count(*) FROM imported),
  'imported_deleted_24h', (SELECT count(*) FROM pin_deletions d, sys
                           WHERE d.original_created_by = sys.id
                             AND d.deleted_at > now() - interval '24 hours'),
  'deletions_24h', (SELECT count(*) FROM pin_deletions
                    WHERE deleted_at > now() - interval '24 hours'),
  'statutory_flipped', (SELECT count(*) FROM flipped),
  'statutory_flipped_sample', (SELECT coalesce(json_agg(json_build_object(
                                   'id', f.id, 'name', f.name,
                                   'source', f.source, 'status', f.status)
                                 ORDER BY f.last_modified DESC), '[]'::json)
                               FROM (SELECT * FROM flipped
                                     ORDER BY last_modified DESC
                                     LIMIT 20) f),
  'imported_user_edits_24h', (SELECT count(*) FROM imported
                              WHERE user_modified
                                AND last_modified > now() - interval '24 hours'),
  'imported_orphaned', (SELECT count(*) FROM imported
                        WHERE source_orphaned_at IS NOT NULL),
  'stale_citations', (SELECT count(*) FROM imported
                      WHERE legal_citation_verified_date
                            < current_date - interval '12 months'),
  'imported_by_source_status', (SELECT coalesce(json_agg(json_build_object(
                                    'source', s.source, 'status', s.status,
                                    'count', s.n)
                                  ORDER BY s.source, s.status), '[]'::json)
                                FROM (SELECT source, status, count(*) AS n
                                      FROM imported
                                      GROUP BY source, status) s),
  'user_pins_total', (SELECT count(*) FROM pins p, sys
                      WHERE p.created_by IS DISTINCT FROM sys.id),
  'imported_user_corrected', (SELECT count(*) FROM imported
                              WHERE user_modified),
  'imported_reports_7d', (SELECT count(*) FROM pin_reports r
                          JOIN imported i ON i.id = r.pin_id
                          WHERE r.created_at > now() - interval '7 days')
);
```

- [ ] **Step 4: Write the rules module**

Create `ci/health_check.py`:

```python
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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check.py -q`
Expected: all pass (20 tests).

- [ ] **Step 6: Run the SQL against staging (live check)**

Run the full contents of `ci/health_check.sql` through the Supabase MCP `execute_sql` tool. The MCP server is bound to staging, ref `miihmfhnsfmwgrvgayns`; pass that ref if the tool asks for a project id. If staging is paused, stop and ask the owner to resume it in the dashboard.

Expected: one row, one JSON object with exactly the 12 keys in `METRIC_KEYS`. `imported_total` is in the tens of thousands (staging holds about 23,800 system pins unless it was wiped). `imported_by_source_status` is a list of `{source, status, count}`. `statutory_flipped_sample` is a list (probably `[]`). No error. If a column name is wrong (a `42703` error), fix the SQL, re-run Step 5, and run this step again.

- [ ] **Step 7: Commit**

```bash
git add ci/health_check.sql ci/health_check.py ci/tests/test_health_check.py
git commit -F - <<'EOF'
feat(ci): health check metrics query and rules

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
```

---

### Task 2: Collectors — the psql query and the REST cluster probe

**Files:**
- Modify: `ci/health_check.py` (add imports; append the database and REST sections after `evaluate`)
- Modify: `ci/tests/test_health_check.py` (add imports; append tests)

**Interfaces:**
- Consumes (Task 1): `Finding`, `RestResult`, `METRIC_KEYS`, `SQL_PATH`, `CONNECT_TIMEOUT_S`, `STATEMENT_TIMEOUT`, `PSQL_TIMEOUT_S`, `HTTP_TIMEOUT_S`, `EXCERPT_CHARS`, `DB_URL_NAMES`, `REST_NAMES`, `CLUSTER_QUERY`, `STAGING_PAUSED_HINT`, `_code`; test helpers `HEALTHY`.
- Consumes (existing): `problems(url) -> list[str]` from `ci/check_db_url.py`; `redact(text, db_url) -> str` from `ci/redact.py`.
- Produces:
  - `check_db(env: str, db_url: str, run: Callable = subprocess.run) -> tuple[dict | None, Finding | None]`
  - `parse_metrics(stdout: str) -> dict` (raises `ValueError`)
  - `rest_headers(anon_key: str) -> dict[str, str]`
  - `_http_post(url: str, headers: dict[str, str], body: bytes) -> tuple[int, bytes]` (raises `OSError` / `http.client.HTTPException` on network failure)
  - `count_clusters(body: bytes) -> int` (raises `ValueError`)
  - `check_clusters(env: str, base_url: str, anon_key: str, post: Callable = _http_post) -> RestResult`
  - Test helpers `FakeRun`, `FakePost`, `DB_URL`, `ROWS`, `LEAKS` (Task 3 reuses them).

- [ ] **Step 1: Write the failing tests**

In `ci/tests/test_health_check.py`, change the import block at the top to:

```python
import io
import json
import re
import subprocess
import urllib.error
from pathlib import Path

import pytest

import health_check as hc
from health_check import Finding, RestResult, check_clusters, check_db, count_clusters, evaluate, rest_headers
```

Append:

```python
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check.py -q`
Expected: collection error, `ImportError: cannot import name 'check_clusters' from 'health_check'`.

- [ ] **Step 3: Implement the collectors**

In `ci/health_check.py`, replace the import block with:

```python
from __future__ import annotations

import http.client
import json
import os
import subprocess
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from check_db_url import problems
from redact import redact
```

Append after `evaluate`:

```python
# ── Rule 1: the database ─────────────────────────────────────────────


def _unreachable(env: str, detail: str) -> Finding:
    msg = f"database unreachable: {_code(detail, EXCERPT_CHARS)}"
    if env == "staging":
        msg += f"; {STAGING_PAUSED_HINT}"
    return Finding("database", msg)


def parse_metrics(stdout: str) -> dict:
    lines = [line for line in stdout.splitlines() if line.strip()]
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check.py -q`
Expected: all pass.

- [ ] **Step 5: Probe staging's REST API with the real code (live check)**

Get staging's URL and keys from the Supabase MCP tools `get_project_url` and `get_publishable_keys` (bound to staging). Confirm the URL contains `miihmfhnsfmwgrvgayns`. Pick the `sb_publishable_…` key if one exists; otherwise use the legacy `anon` key. Then, from the repo root:

```bash
cd ci && uv run --no-project python -c "import health_check as h; print(h.check_clusters('staging', 'https://miihmfhnsfmwgrvgayns.supabase.co', '<KEY>'))"
```

Expected: `RestResult(status=200, clusters=<N > 0>, problem=None)`. If the publishable key returns 401, repeat with the legacy anon key. Write down which key worked; Task 6 sets it as `STAGING_SUPABASE_ANON_KEY`. Both keys are public (they ship in app builds), so they aren't secrets.

- [ ] **Step 6: Commit**

```bash
git add ci/health_check.py ci/tests/test_health_check.py
git commit -F - <<'EOF'
feat(ci): health check collectors (read-only psql + REST cluster probe)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
```

---

### Task 3: Digest, orchestration and the CLI

**Files:**
- Modify: `ci/health_check.py` (add imports; append the digest and CLI sections)
- Modify: `ci/tests/test_health_check.py` (append tests)

**Interfaces:**
- Consumes (Tasks 1–2): `METRIC_RULES`, `STATUS_NAMES`, `_one_line`, `_rest_problem`, `evaluate`, `check_db`, `check_clusters`, `_http_post`, `redact`; test helpers `HEALTHY`, `REST_OK`, `ALL_BREACHED`, `metrics`, `FakeRun`, `FakePost`, `DB_URL`, `ROWS`, `LEAKS`, `ROOT`.
- Produces:
  - `render_digest(env: str, metrics: dict | None, rest: RestResult, findings: list[Finding]) -> str`
  - `SIMULATED: Finding`
  - `run_checks(env, db_url, base_url, anon_key, simulate=False, *, run=subprocess.run, post=_http_post) -> tuple[list[Finding], str]`
  - `main(argv: list[str] | None = None) -> int`. CLI: `python3 ci/health_check.py --env staging|prod [--simulate-failure]`. It reads env `DB_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GITHUB_STEP_SUMMARY`, `GITHUB_OUTPUT`, and writes `findings=<one-line JSON list of messages>` to `GITHUB_OUTPUT`. Task 4's workflow and alert script rely on this contract.

- [ ] **Step 1: Write the failing tests**

Append to `ci/tests/test_health_check.py`:

```python
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
        env={"DB_URL": DB_URL, "SYSTEMROOT": "C:\\Windows", "PATH": ""},
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 1
    assert "Traceback" in proc.stderr
    for leaked in LEAKS:
        assert leaked not in proc.stdout + proc.stderr
```

Also add `import sys` to the test file's imports (after `import subprocess`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check.py -q`
Expected: the new tests fail with `AttributeError: module 'health_check' has no attribute 'render_digest'` (and similar for `run_checks` / `main`). `test_unexpected_error_exits_1_with_a_redacted_traceback` fails because the script has no `__main__` yet (return code 0).

- [ ] **Step 3: Implement the digest and CLI**

In `ci/health_check.py`, add `import argparse` at the top of the stdlib imports, and `import sys` and `import traceback` after `import subprocess`, keeping alphabetical order. The stdlib block becomes:

```python
import argparse
import http.client
import json
import os
import subprocess
import sys
import traceback
import urllib.error
import urllib.request
```

Append at the end of the file:

```python
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check.py -q`
Expected: all pass.

- [ ] **Step 5: Run the whole ci suite**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: the 75 existing tests plus the new ones all pass.

- [ ] **Step 6: Commit**

```bash
git add ci/health_check.py ci/tests/test_health_check.py
git commit -F - <<'EOF'
feat(ci): health check digest and CLI

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
```

---

### Task 4: The workflow

**Files:**
- Create: `.github/workflows/health-check.yml`
- Create: `ci/tests/test_health_check_workflow.py`
- Modify: `.github/workflows/db-migrations.yml` (the `pull_request.paths` list)
- Modify: `ci/tests/test_db_migrations_workflow.py` (`test_triggers`)

**Interfaces:**
- Consumes (Task 3): CLI `python3 ci/health_check.py --env staging|prod [--simulate-failure]`; reads env `DB_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`; writes step output `findings` (one-line JSON list of strings); exits 1 when there are findings, or on a crash with no output written.
- Produces: workflow `Daily Health Check` with jobs `staging`, `prod`, `alert`; issue title `Daily health check failing`, label `health-check`. Task 5's docs and Task 6's rollout refer to these names.

- [ ] **Step 1: Write the failing tests**

Create `ci/tests/test_health_check_workflow.py`:

```python
import json
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "health-check.yml"
PROD_CREDS = ("secrets.PROD_DB_URL", "secrets.SUPABASE_URL", "secrets.SUPABASE_ANON_KEY")


def _on(wf: dict) -> dict:
    # PyYAML (YAML 1.1) parses the bare key `on` as boolean True.
    return wf.get("on", wf.get(True))


def _text(obj) -> str:
    return json.dumps(obj)


def _check_step(job: dict) -> dict:
    (step,) = [s for s in job["steps"] if s.get("id") == "check"]
    return step


@pytest.fixture(scope="module")
def wf() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def jobs(wf) -> dict:
    return wf["jobs"]


def test_triggers(wf):
    on = _on(wf)
    assert set(on) == {"schedule", "workflow_dispatch"}
    assert on["schedule"] == [{"cron": "0 11 * * *"}]
    sim = on["workflow_dispatch"]["inputs"]["simulate_failure"]
    assert sim["type"] == "boolean" and sim["default"] is False


def test_read_only_and_serialized(wf):
    assert wf["permissions"] == {"contents": "read"}
    assert wf["concurrency"]["group"] == "health-check"


def test_jobs(jobs):
    assert set(jobs) == {"staging", "prod", "alert"}


def test_prod_uses_the_plan_environment_and_nothing_uses_production(jobs):
    assert jobs["prod"]["environment"] == "production-plan"
    for name in ("staging", "alert"):
        assert "environment" not in jobs[name], name
    for name, job in jobs.items():
        assert job.get("environment") != "production", name


def test_prod_credentials_only_in_the_prod_job(jobs):
    for name, job in jobs.items():
        if name != "prod":
            for cred in PROD_CREDS:
                assert cred not in _text(job), (name, cred)


def test_check_jobs_run_the_script_with_credentials_on_the_step_only(jobs):
    for name in ("staging", "prod"):
        job = jobs[name]
        assert "env" not in job, name
        assert "permissions" not in job, name  # inherits contents: read
        assert job["outputs"] == {"findings": "${{ steps.check.outputs.findings }}"}
        check = _check_step(job)
        assert check["run"].startswith(f"python3 ci/health_check.py --env {name}")
        assert "--simulate-failure" in check["run"]
        assert set(check["env"]) == {"DB_URL", "SUPABASE_URL", "SUPABASE_ANON_KEY", "SIMULATE_FAILURE"}
        for step in job["steps"]:
            if step is not check:
                assert "env" not in step, (name, step.get("name"))


def test_check_step_always_publishes_findings_then_fails_the_job(jobs):
    # continue-on-error lets the step's outputs publish; the next step turns
    # its failure back into a failed job (same pattern as brevo-keepalive.yml).
    for name in ("staging", "prod"):
        steps = jobs[name]["steps"]
        check = _check_step(jobs[name])
        assert check["continue-on-error"] is True
        after = steps[steps.index(check) + 1]
        assert after["if"] == "steps.check.outcome == 'failure'"
        assert after["run"].strip() == "exit 1"


def test_staging_reads_its_rest_config_from_variables(jobs):
    env = _check_step(jobs["staging"])["env"]
    assert env["DB_URL"] == "${{ secrets.STAGING_DB_URL }}"
    assert env["SUPABASE_URL"] == "${{ vars.STAGING_SUPABASE_URL }}"
    assert env["SUPABASE_ANON_KEY"] == "${{ vars.STAGING_SUPABASE_ANON_KEY }}"


def test_prod_reads_the_prod_credentials(jobs):
    env = _check_step(jobs["prod"])["env"]
    assert env["DB_URL"] == "${{ secrets.PROD_DB_URL }}"
    assert env["SUPABASE_URL"] == "${{ secrets.SUPABASE_URL }}"
    assert env["SUPABASE_ANON_KEY"] == "${{ secrets.SUPABASE_ANON_KEY }}"


def test_only_alert_can_write_issues(jobs):
    assert jobs["alert"]["permissions"] == {"issues": "write"}
    for name in ("staging", "prod"):
        assert "issues" not in _text(jobs[name].get("permissions", {})), name


def test_alert_runs_after_both_checks_even_when_they_fail(jobs):
    alert = jobs["alert"]
    assert alert["needs"] == ["staging", "prod"]
    assert alert["if"].startswith("always()")
    assert "needs.staging.result != 'success'" in alert["if"]
    assert "needs.prod.result != 'success'" in alert["if"]


def test_alert_runs_no_repo_code_and_never_interpolates_findings(jobs):
    # Findings carry user-editable pin names: they reach the script only as
    # env vars. A ${{ }} expression in the script body would be script injection.
    (step,) = jobs["alert"]["steps"]
    assert step["uses"].startswith("actions/github-script@")
    script = step["with"]["script"]
    assert "${{" not in script
    assert step["env"]["STAGING_FINDINGS"] == "${{ needs.staging.outputs.findings }}"
    assert step["env"]["PROD_FINDINGS"] == "${{ needs.prod.outputs.findings }}"
    assert step["env"]["STAGING_RESULT"] == "${{ needs.staging.result }}"
    assert step["env"]["PROD_RESULT"] == "${{ needs.prod.result }}"
    assert "labels: 'health-check'" in script and "state: 'open'" in script
    assert "createComment" in script and "Daily health check failing" in script
```

In `ci/tests/test_db_migrations_workflow.py`, `test_triggers`, change the tuple to:

```python
    for p in (
        "supabase/migrations/**",
        ".github/workflows/db-migrations.yml",
        ".github/workflows/db-repair.yml",
        ".github/workflows/health-check.yml",
        "ci/**",
    ):
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_health_check_workflow.py ci/tests/test_db_migrations_workflow.py -q`
Expected: `FileNotFoundError` for `health-check.yml`, and `test_triggers` in the migrations test fails on the missing path.

- [ ] **Step 3: Write the workflow**

Create `.github/workflows/health-check.yml`:

```yaml
name: Daily Health Check

# Checks prod and staging every day. Silent while healthy; when something is
# wrong the run goes red and `alert` opens one issue (label health-check), or
# comments on the one already open. Querying staging daily also keeps the
# free-tier project from auto-pausing.
#   staging → database reachable + clusters (its data is wiped during testing,
#             so its other counts are shown in the run summary, never judged).
#   prod    → every check. Runs in `production-plan` (master-only, no approval)
#             for PROD_DB_URL; never in `production`.
#   alert   → only after a failed check job; the only job that can write issues.
# ci/health_check.py opens a read-only session with a statement_timeout, checks
# the DB URL's shape without printing it, and redacts all tool output.
# Findings carry user-editable pin names: they reach the alert script only
# through env vars, never ${{ }} inside the script.
# Spec: docs/superpowers/specs/2026-09-27-daily-health-check-design.md
# Runbook: docs/importer/PROD_HEALTH_CHECK.md

on:
  schedule:
    - cron: '0 11 * * *'  # daily, 11:00 UTC = 07:00 ET
  workflow_dispatch:
    inputs:
      simulate_failure:
        description: 'Add a synthetic finding to test the alert issue (run from master)'
        type: boolean
        default: false

permissions:
  contents: read

concurrency:
  group: health-check
  cancel-in-progress: false

jobs:
  staging:
    name: Staging
    runs-on: ubuntu-latest
    timeout-minutes: 10
    outputs:
      findings: ${{ steps.check.outputs.findings }}
    steps:
      - uses: actions/checkout@v4
      - name: Check staging
        id: check
        continue-on-error: true # publish the findings output even when the check fails
        env:
          DB_URL: ${{ secrets.STAGING_DB_URL }}
          SUPABASE_URL: ${{ vars.STAGING_SUPABASE_URL }}
          SUPABASE_ANON_KEY: ${{ vars.STAGING_SUPABASE_ANON_KEY }}
          SIMULATE_FAILURE: ${{ inputs.simulate_failure && '1' || '' }}
        run: python3 ci/health_check.py --env staging ${SIMULATE_FAILURE:+--simulate-failure}
      - name: Fail if the check found problems
        if: steps.check.outcome == 'failure'
        run: exit 1

  prod:
    name: Prod
    runs-on: ubuntu-latest
    timeout-minutes: 10
    environment: production-plan
    outputs:
      findings: ${{ steps.check.outputs.findings }}
    steps:
      - uses: actions/checkout@v4
      - name: Check prod
        id: check
        continue-on-error: true # publish the findings output even when the check fails
        env:
          DB_URL: ${{ secrets.PROD_DB_URL }}
          SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
          SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_ANON_KEY }}
          SIMULATE_FAILURE: ${{ inputs.simulate_failure && '1' || '' }}
        run: python3 ci/health_check.py --env prod ${SIMULATE_FAILURE:+--simulate-failure}
      - name: Fail if the check found problems
        if: steps.check.outcome == 'failure'
        run: exit 1

  alert:
    name: Open or update the alert issue
    needs: [staging, prod]
    if: always() && (needs.staging.result != 'success' || needs.prod.result != 'success')
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      issues: write
    steps:
      - uses: actions/github-script@v7
        env:
          STAGING_RESULT: ${{ needs.staging.result }}
          STAGING_FINDINGS: ${{ needs.staging.outputs.findings }}
          PROD_RESULT: ${{ needs.prod.result }}
          PROD_FINDINGS: ${{ needs.prod.outputs.findings }}
        with:
          script: |
            const { owner, repo } = context.repo;
            const runUrl = `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`;
            const envs = [
              ['staging', process.env.STAGING_RESULT, process.env.STAGING_FINDINGS],
              ['prod', process.env.PROD_RESULT, process.env.PROD_FINDINGS],
            ];
            const sections = [];
            for (const [name, result, raw] of envs) {
              if (result === 'success') continue;
              let findings = [];
              try { findings = JSON.parse(raw || '[]'); } catch (e) { findings = []; }
              if (!Array.isArray(findings)) findings = [];
              sections.push(`### ${name}`, '');
              if (findings.length) {
                for (const f of findings) sections.push(`- ${String(f)}`);
              } else {
                sections.push(`- The ${name} job ended (${result}) before reporting findings; see the run.`);
              }
              sections.push('');
            }
            const body = [
              `Run: ${runUrl}`,
              '',
              ...sections,
              'What each finding means and what to do: `docs/importer/PROD_HEALTH_CHECK.md` → "Automated daily check". Close this issue once the cause is fixed.',
            ].join('\n');
            const { data } = await github.rest.issues.listForRepo({
              owner, repo, labels: 'health-check', state: 'open', per_page: 20,
            });
            const open = data.filter((i) => !i.pull_request);
            if (open.length) {
              await github.rest.issues.createComment({ owner, repo, issue_number: open[0].number, body });
              core.info(`Commented on #${open[0].number}`);
            } else {
              const { data: issue } = await github.rest.issues.create({
                owner, repo, title: 'Daily health check failing', labels: ['health-check'], body,
              });
              core.info(`Opened #${issue.number}`);
            }
```

In `.github/workflows/db-migrations.yml`, add the new path to `on.pull_request.paths` (after `db-repair.yml`) so the structure tests run when the health-check workflow changes:

```yaml
    paths:
      - 'supabase/migrations/**'
      - '.github/workflows/db-migrations.yml'
      - '.github/workflows/db-repair.yml'
      - '.github/workflows/health-check.yml'
      - 'ci/**'
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: all pass (the existing tests plus the new ones).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/health-check.yml .github/workflows/db-migrations.yml ci/tests/test_health_check_workflow.py ci/tests/test_db_migrations_workflow.py
git commit -F - <<'EOF'
feat(ci): daily health check workflow with a deduplicated alert issue

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
```

---

### Task 5: Docs

**Files:**
- Rewrite: `docs/importer/PROD_HEALTH_CHECK.md`
- Modify: `docs/dev/STAGING.md` ("Keeping staging alive" section, around lines 182–191)
- Modify: `CLAUDE.md` ("Current workflow state" list, after the `weekly-scans.yml` bullet, around line 111)
- Modify: `docs/superpowers/specs/2026-09-27-daily-health-check-design.md` (line 3)

**Interfaces:**
- Consumes (Tasks 1–4): workflow name `Daily Health Check`, jobs `staging`/`prod`/`alert`, issue title `Daily health check failing`, label `health-check`, input `simulate_failure`, finding texts from `METRIC_RULES` and `check_db`.
- Produces: the section heading `## Automated daily check` in `PROD_HEALTH_CHECK.md`, which the alert issue body points to.

- [ ] **Step 1: Rewrite `docs/importer/PROD_HEALTH_CHECK.md`**

Replace the whole file with:

````markdown
# Production health check

## Automated daily check

`.github/workflows/health-check.yml` (Actions → *Daily Health Check*) checks
prod and staging every day at 11:00 UTC (07:00 ET). It stays silent while
everything is fine.

- **Digest:** open a run → *Summary*. Each environment lists every signal
  with its value and threshold, imported pins by source and status, user
  pins, imported pins users have corrected, and reports filed on imported
  pins in the last 7 days.
- **Alert:** when a check fails, the run goes red and the `alert` job opens
  one issue, *Daily health check failing* (label `health-check`), listing the
  findings per environment. While that issue is open, each failing run adds a
  comment instead of opening another. Close it once the cause is fixed.
- **Staging** is judged only on checks 1–2, because its data is wiped and
  re-imported during testing. The daily query also keeps the free-tier
  project from auto-pausing.
- **Test the alert path:** *Run workflow* from `master` with
  *simulate_failure* checked. From any other branch the `prod` job can't read
  `PROD_DB_URL` (`production-plan` allows only `master`), so it fails.
- Thresholds are at the top of `ci/health_check.py`; the query is
  `ci/health_check.sql`. Both are read-only.

### What each finding means

| # | Finding | Likely cause | What to do |
|---|---|---|---|
| 1 | `database unreachable` | staging auto-paused; a password reset the pooler hasn't picked up yet | staging: resume it in the dashboard (90-day window). Otherwise see `docs/dev/STAGING.md` → Troubleshooting |
| 1 | `<NAME> is malformed` | a mis-pasted secret | re-set it from its `.local/` file (`docs/dev/STAGING.md`); the value is never printed |
| 2 | clusters: HTTP ≠ 200 or no clusters | `get_pins_in_view` broke (BUG-005 looked like this), or anon grants changed | run the manual query below in the dashboard; look at the last migration |
| 3 | prod has no imported pins | a mass delete, or someone ran the rollback | check `pin_deletions` and `import_runs` |
| 4 | imported pins deleted | users can't delete them (012), so: an admin delete, a leaked service key, or an RLS regression | `pin_deletions.deleted_by` for rows whose `original_created_by` is the system user says who |
| 5 | more than 50 deletions in 24 h | a scripted mass delete | `pin_deletions.deleted_by`; Postgres logs show `P0001` if the rate limit fired |
| 6 | statutory pins no longer NO_GUN | an edit made between 012 and 013, a 013 regression, or a dashboard edit | restore them (below), then find out how it happened |
| 7 | more than 50 user edits of imported pins in 24 h | vandalism or a buggy client | look at those pins' names and `last_modified` |
| 8 | more than 100 orphaned imported pins | a source dropped records in the last import | review the import report before the next apply |
| 9 | stale citations | a `data/state_laws/states.yaml` cell's `last_verified_date` is over a year old | re-verify the law, bump the date, re-import |
| — | a job *ended before reporting* | the script crashed or timed out | open the run log (tool output there is redacted) |

### Restore a flipped statutory pin

Run in the **prod dashboard SQL editor** once per pin id from the issue. The
dashboard runs as `postgres`, which 013's lock doesn't apply to. The tag
comes from the pin's source (`data/state_laws/states.yaml`). `user_modified`
stays true, so the next import still leaves the pin's other user
corrections alone; the finding clears because the status is NO_GUN again.

```sql
UPDATE pins
SET status = 2,
    restriction_tag = (CASE source
      WHEN 'gsa'            THEN 'FEDERAL_PROPERTY'
      WHEN 'hifld_military' THEN 'FEDERAL_PROPERTY'
      WHEN 'faa'            THEN 'AIRPORT_SECURE'
      WHEN 'hifld_courts'   THEN 'STATE_LOCAL_GOVT'
      WHEN 'nces'           THEN 'SCHOOL_K12'
      WHEN 'ipeds'          THEN 'COLLEGE_UNIVERSITY'
    END)::restriction_tag_type
WHERE id = '<pin id>'
  AND created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
  AND confidence = 'high'
  AND source IN ('gsa', 'hifld_military', 'faa',
                 'hifld_courts', 'nces', 'ipeds')
RETURNING id, name, source, status, restriction_tag;
```

If it returns no row, the pin isn't a statutory imported pin: stop and look
at it by hand.

---

## Manual query (ad hoc)

For a look outside the daily run. The pilot's 7-day gate (Stage B / B5)
closed on 2026-09-26.

- **System user** (owns every imported pin): `81775f8b-1a6a-47d6-b793-e9ab7e38634e`
- **Prod project ref:** `gqbxloaqamokbolcvesg`
- Run all SQL in the **prod dashboard SQL editor** (read-only; no MCP repoint needed).

One read-only statement. The SQL editor only renders the last statement's
result, so the four checks are combined into a single result set (the `chk`
column says which check each row belongs to).
````

Then copy the rest of the old file **verbatim**, from the ```` ```sql ```` block that starts `-- 1_source_status / 1_total:` down to the end of the rollback `DELETE` block. That covers the query, "Expected output (import baseline, 2026-07-06)", the source-key and `osm` notes, "What counts as a clean day", "Also glance (prod dashboard)", and "Gate + rollback". Make two changes to that copied text:
- Rename the heading `## Gate + rollback` to `## Rollback`, and delete its `- **Gate:** …` bullet (the gate is closed).
- Delete the whole `## Follow-up: automate this` section at the end (this work replaces it).

Before rewriting, copy the old file's text from `git show HEAD:docs/importer/PROD_HEALTH_CHECK.md` so the copied part is exact.

- [ ] **Step 2: Update `docs/dev/STAGING.md`**

Replace the "Keeping staging alive" section body (from "Free-tier projects pause when idle." through "…only its backup can be downloaded.") with:

```markdown
Free-tier projects pause when idle. A weekly ping is **not** enough: staging
paused between 2026-09-07 and 2026-09-14 despite the Monday
`importer-dry-run.yml`. The daily `health-check.yml` (11:00 UTC) queries
staging's database and REST API, which keeps it awake. If staging pauses
anyway, that run fails with "staging may be paused" and opens a
`health-check` issue. A paused free project can be resumed from the
dashboard for 90 days; after that, only its backup can be downloaded.
```

- [ ] **Step 3: Update `CLAUDE.md`**

In "CI/CD & Build Flags" → "Current workflow state", after the `weekly-scans.yml` bullet, add:

```markdown
  - `.github/workflows/health-check.yml` — daily 11:00 UTC read-only check of prod and staging (DB reachable, clusters for a signed-out user, imported-pin tripwires); opens or comments on one `health-check` issue when something is wrong. Flag not applicable. See `docs/importer/PROD_HEALTH_CHECK.md`.
```

- [ ] **Step 4: Mark the spec approved**

In `docs/superpowers/specs/2026-09-27-daily-health-check-design.md`, change line 3 from
`**Date:** 2026-09-27 · **Status:** approved design, pending spec review`
to
`**Date:** 2026-09-27 · **Status:** approved (owner, 2026-09-27)`.

- [ ] **Step 5: Check the docs**

Run: `git diff --stat` and read `docs/importer/PROD_HEALTH_CHECK.md` top to bottom. Expected: the manual query and baseline table are unchanged from the old file (compare with `git show HEAD:docs/importer/PROD_HEALTH_CHECK.md`), no "Why manual" or "Follow-up" text is left, and every SQL line in the restore block is at most 70 characters (check with `awk 'length > 70' docs/importer/PROD_HEALTH_CHECK.md` and confirm no hits fall inside the restore block).

- [ ] **Step 6: Commit**

```bash
git add docs/importer/PROD_HEALTH_CHECK.md docs/dev/STAGING.md CLAUDE.md docs/superpowers/specs/2026-09-27-daily-health-check-design.md
git commit -F - <<'EOF'
docs: daily health check runbook, staging keep-alive, workflow list

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
```

---

### Task 6: Rollout and live verification

**Files:** none (repo settings, PR, workflow runs).

**Interfaces:**
- Consumes: the staging key chosen in Task 2 Step 5; workflow `health-check.yml`; label `health-check`.
- Produces: repo variables `STAGING_SUPABASE_URL` and `STAGING_SUPABASE_ANON_KEY`; label `health-check`; the PR; a verified alert path.

- [ ] **Step 1: Full local verification**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: every test passes; note the count for the PR body.

- [ ] **Step 2: Set the staging repo variables**

```bash
gh variable set STAGING_SUPABASE_URL --body "https://miihmfhnsfmwgrvgayns.supabase.co"
gh variable set STAGING_SUPABASE_ANON_KEY --body "<the key that returned status=200 in Task 2 Step 5>"
gh variable list
```

Expected: both variables listed. These are repo **variables**, not secrets: the key ships in every app build.

- [ ] **Step 3: Create the alert label**

```bash
gh label create health-check --color B60205 --description "Daily health check alert (health-check.yml)" --force
```

Expected: `✓ Label "health-check" created` (or updated).

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin feature/daily-health-check
gh pr create --base master --title "Daily health check (prod + staging)" --body-file - <<'EOF'
## Summary
- `.github/workflows/health-check.yml`: daily 11:00 UTC check of prod and staging. Silent when healthy; when something is wrong it opens one `health-check` issue (or comments on the open one).
- `ci/health_check.{py,sql}`: one read-only query (read-only session + `statement_timeout`) plus a signed-out `get_pins_in_view` probe. The prod tripwires: imported pins deleted, statutory pins no longer NO_GUN, stale citations; volume thresholds for deletions, user edits and orphans. Staging judges only reachability and clusters, and the daily query keeps it from auto-pausing.
- The prod job runs in `production-plan` (master-only); only `alert` can write issues. Findings reach the alert script only through env vars, because they carry user-editable pin names.
- Runbook: `docs/importer/PROD_HEALTH_CHECK.md` → "Automated daily check", including restore SQL for a flipped statutory pin.

Spec: `docs/superpowers/specs/2026-09-27-daily-health-check-design.md`
Plan: `docs/superpowers/plans/2026-09-27-daily-health-check.md`

## Test plan
- [x] `pytest ci/tests`: <N> passed
- [x] `ci/health_check.sql` run against staging via MCP: all 12 keys returned
- [x] REST probe against staging with the real `check_clusters()`: HTTP 200, clusters > 0
- [ ] After merge: dispatch from `master` (expect green, two digests)
- [ ] After merge: dispatch with `simulate_failure` twice (expect one issue, then a comment); close it

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
```

Replace `<N>` with the count from Step 1 before running. Then check CI with `gh pr checks`. `DB Migrations / Workflow structure tests` must pass. `staging-pr` runs too and should report "This PR adds no migrations." Per project memory, a `pr-checks` job that goes green in about 4 s was skipped by its paths filter, which is expected here: nothing app-facing changed.

- [ ] **Step 5: Owner merges**

Stop and ask the owner to review and merge the PR. Merging to `master` is the owner's call.

- [ ] **Step 6: Normal run after merge**

```bash
gh workflow run health-check.yml --ref master
gh run list --workflow health-check.yml --limit 1
gh run watch <run id> --exit-status
gh run view <run id> --log | grep -E "all checks passed|::error"
```

Expected: green. The logs contain `staging: all checks passed` and `prod: all checks passed`, and the `alert` job is skipped. Give the owner the run URL so they can check both digests on the *Summary* page: prod shows about 23,800 imported pins by source and status, and rule 2 shows clusters. If rule 6 fires, the finding lists statutory pins flipped before 013. That isn't a workflow bug: hand the owner the restore SQL from the runbook, since Claude has no prod access.

- [ ] **Step 7: Exercise the alert path**

```bash
gh workflow run health-check.yml --ref master -f simulate_failure=true
gh run watch <run id>
gh issue list --label health-check --state open
gh issue view <issue number>
```

Expected: the run is red. One open issue, *Daily health check failing*, has `### staging` and `### prod` sections, each listing `simulated failure (manual run with simulate_failure); nothing is wrong`. It must **not** say "ended … before reporting", because that would mean the findings output didn't reach `alert`.

Run the simulated dispatch a second time, then:

```bash
gh issue view <issue number> --comments
gh issue list --label health-check --state open
```

Expected: still exactly one open issue, now with one comment holding the second run's findings. Close it:

```bash
gh issue close <issue number> --comment "Alert path verified (two simulated runs); closing the test issue."
```

- [ ] **Step 8: First scheduled run**

The next day, after 11:00 UTC: `gh run list --workflow health-check.yml --event schedule --limit 1`. Expected: green. If it's red, triage the issue with the runbook's finding table.
