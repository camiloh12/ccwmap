# DB Migrations Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy `supabase/migrations/*.sql` to staging (on PR) and prod (on merge, after owner approval) through GitHub Actions with the pinned Supabase CLI, so nobody needs prod DB credentials locally and every environment has an authoritative migration history.

**Architecture:**
- `db-migrations.yml` has five jobs. On PRs: `workflow-tests` → `staging-pr`. On merge or manual dispatch: `staging` → `plan` → `apply`.
- `plan` does a JSON dry-run against prod, parsed by `ci/db_plan.py`. `apply` waits for approval in a master-only `production` environment, then re-checks that what it's about to apply still equals the approved list.
- `db-repair.yml` + `ci/db_repair.sh` edit only the history table, for the one-time baseline and future hand-fixes.
- Structure tests in `ci/tests/` lock in the security properties.

**Tech Stack:**
- GitHub Actions; Supabase CLI **2.118.0** via `supabase/setup-cli@v3`.
- Python 3 (stdlib only) for `ci/db_plan.py`; bash for `ci/db_repair.sh`.
- pytest + PyYAML, run through `uv`.

**Spec:** `docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md`

## Global Constraints

- **CLI pin:** Supabase CLI version is **`2.118.0`**. It is set exactly once per workflow as `env.SUPABASE_CLI_VERSION`, and every setup step is `supabase/setup-cli@v3` with `version: ${{ env.SUPABASE_CLI_VERSION }}`.
- **Project refs:** staging `miihmfhnsfmwgrvgayns`, prod `gqbxloaqamokbolcvesg`.
- **DB URLs:** session-mode pooler only, in the form `postgresql://postgres.<ref>:<percent-encoded-password>@aws-0-<region>.pooler.supabase.com:5432/postgres`. Never the direct `db.<ref>.supabase.co` host (it is IPv6-only).
- **Secrets:**
  - `STAGING_DB_URL` stays a **repo** secret.
  - `PROD_DB_URL` exists **only** as an environment secret in `production-plan` and `production`, both limited to deployment branch `master`.
  - `production` has required reviewer `camiloh12`.
- **Who does what:** Claude never receives, prints, or stores the prod DB URL or password. Claude never uses Supabase MCP `apply_migration` for repo migrations; the MCP server stays bound to staging.
- **Workflow permissions:** `permissions: contents: read`.
- **Workflow inputs:** passed to `run:` scripts through `env:`, never interpolated as `${{ inputs.* }}` inside `run:` (prevents script injection).
- **CI test command** (repo root): `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
- **Local staging URL:** kept only in `.local/staging_db_url`. `.local/` is already gitignored; never commit it.
- **Commit trailers:** every commit ends with:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
  ```

## Review Focus

1. **The CLI prints an error as JSON but exits 0.** `{"_tag":"Error",…}` must make `plan` fail, never read as "up to date" (so a deploy is never skipped by mistake). Pinned by `test_error_envelope_is_a_plan_error` (Task 2).
2. **Non-JSON noise on stdout before the result line** (e.g. a "new CLI version available" notice). The parser must still find the result line. Pinned by `test_noise_before_json_is_ignored` (Task 2).
3. **The pending list changes between approval and apply** (prod changed in between). `apply` must refuse rather than apply something that wasn't approved. Pinned by `test_expect_mismatch_fails` (Task 2) plus `test_apply_is_gated` asserting `--expect` (Task 3).
4. **Operator enters versions as `008,009` or with stray spaces, or a typo like `008;`.** Commas and spaces are accepted, anything non-numeric is rejected before touching the DB. Pinned by `test_commas_and_spaces_are_accepted` and `test_non_numeric_version_is_rejected` (Task 4).
5. **A workflow-only PR adds no migrations.** `staging-pr` must not call `migration repair` with an empty version list. Pinned by `test_pr_reapply_only_touches_added_migrations` (Task 3), which asserts the `if [ -n "$versions" ]` guard.

---

### Task 1: Staging test + staging history cleanup (no code)

Confirms the pinned CLI works with this repo (`NNN_` versions, no `config.toml`), then puts staging's history on CLI versions. Captures two real dry-run outputs as test fixtures for Task 2.

**Files:**
- Create (local only, never committed): `.local/staging_db_url`, `.local/dryrun-uptodate.json`, `.local/dryrun-pending.json`

**Interfaces:**
- Produces: staging `supabase_migrations.schema_migrations` containing exactly versions `000 004 005 006 007 008 009 010 011 012`; two captured JSON files used as fixtures in Task 2.

- [ ] **Step 1: Owner provides the staging URL (staging only)**

Ask the owner to write the **staging** session-pooler URL (percent-encoded password) into `.local/staging_db_url` as a single line. It is the same value as the `STAGING_DB_URL` GitHub secret. Confirm it's ignored:

Run: `git check-ignore -v .local/staging_db_url`
Expected: a line naming `.gitignore` and the `.local/` rule. If there's no output, STOP; the file is not ignored.

Also confirm it's the staging project: `grep -c miihmfhnsfmwgrvgayns .local/staging_db_url` → `1`. If it contains `gqbxloaqamokbolcvesg`, STOP: that's prod.

- [ ] **Step 2: Confirm a CLI error exits non-zero**

Run (Git Bash, repo root):
```bash
npx -y supabase@2.118.0 db push --dry-run --include-all --output-format json \
  --db-url "postgresql://postgres:x@127.0.0.1:59999/postgres"; echo "exit=$?"
```
Expected: a `{"_tag":"Error",...DbConnectError...}` line, then `exit=` followed by a **non-zero** number. If `exit=0`, record that. `ci/db_plan.py` (Task 2) already treats an error line as a failure, so the pipeline stays safe either way.

- [ ] **Step 3: List staging history (tests `NNN_` parsing)**

```bash
URL="$(cat .local/staging_db_url)"
npx -y supabase@2.118.0 migration list --db-url "$URL"
```
Expected: the LOCAL column lists `000 004 005 006 007 008 009 010 011 012`. The REMOTE column lists three 14-digit timestamp versions: `20260706014751`, `20260706014826`, and one from 2026-09-26 (012's MCP apply). If the local column is empty, or the command errors about the migrations directory or `config.toml`, STOP and report: the CLI can't use this repo layout, which is the spec's fallback trigger.

- [ ] **Step 4: Remove the MCP timestamp rows**

```bash
npx -y supabase@2.118.0 migration repair --status reverted 20260706014751 20260706014826 <012-timestamp-from-step-3> --db-url "$URL"
```
Expected: success. The schema is untouched; only history rows are deleted.

- [ ] **Step 5: Record the in-effect versions**

```bash
npx -y supabase@2.118.0 migration repair --status applied 000 004 005 006 007 008 009 010 011 012 --db-url "$URL"
npx -y supabase@2.118.0 migration list --db-url "$URL"
```
Expected: LOCAL and REMOTE columns identical, `000`…`012`.

- [ ] **Step 6: Capture the "up to date" dry-run**

```bash
npx -y supabase@2.118.0 db push --dry-run --include-all --output-format json --db-url "$URL" > .local/dryrun-uptodate.json
cat .local/dryrun-uptodate.json
```
Expected: one JSON line containing `"upToDate":true`.

- [ ] **Step 7: Rehearse the PR re-apply loop and capture a "pending" dry-run**

```bash
npx -y supabase@2.118.0 migration repair --status reverted 012 --db-url "$URL"
npx -y supabase@2.118.0 db push --dry-run --include-all --output-format json --db-url "$URL" > .local/dryrun-pending.json
cat .local/dryrun-pending.json
npx -y supabase@2.118.0 db push --include-all --yes --db-url "$URL"
npx -y supabase@2.118.0 migration list --db-url "$URL"
npx -y supabase@2.118.0 migration repair --status reverted 999 --db-url "$URL"; echo "exit=$?"
```
Expected:
- `dryrun-pending.json` has `"upToDate":false` and `"migrations":["012_system_pins_user_correctable.sql"]`.
- The real push re-applies 012; it is idempotent (DROP/CREATE POLICY).
- The list shows `012` on both sides again.
- Reverting the never-recorded `999` gives `exit=0` (a DELETE of zero rows). This is what makes `staging-pr` safe on a PR's first push.

- [ ] **Step 8: Check the captured files contain no connection details**

Run: `grep -ciE "pooler|postgres\.|password|@aws" .local/dryrun-uptodate.json .local/dryrun-pending.json`
Expected: `0` for both. Both files become committed fixtures in Task 2. If either is non-zero, STOP.

(No commit: this task produces no repo files.)

---

### Task 2: `ci/db_plan.py`: parse the dry-run and guard the approved list

**Files:**
- Create: `ci/db_plan.py`
- Create: `ci/tests/conftest.py`
- Create: `ci/tests/test_db_plan.py`
- Create: `ci/tests/fixtures/dryrun_up_to_date.json` (copied from `.local/dryrun-uptodate.json`, Task 1)
- Create: `ci/tests/fixtures/dryrun_pending.json` (copied from `.local/dryrun-pending.json`, Task 1)

**Interfaces:**
- Consumes: the Task 1 fixture files.
- Produces, used by Task 3's workflow:
  - `python3 ci/db_plan.py <plan.json>`: exit 0. Appends `pending=true|false` and `migrations=<space-separated filenames>` to `$GITHUB_OUTPUT`, and a Markdown "Pending for prod" section to `$GITHUB_STEP_SUMMARY`. Exit 1 plus a `::error::` line if the output is unreadable or reports an error.
  - `python3 ci/db_plan.py <plan.json> --expect "<space-separated filenames>"`: exit 0 only if the pending list equals the expected list exactly, else exit 1.
  - Python: `parse_plan(text: str) -> Plan`, where `Plan(pending: bool, migrations: tuple[str, ...])`; `PlanError(ValueError)`; `summary_markdown(plan: Plan) -> str`; `main(argv: list[str] | None = None) -> int`.

- [ ] **Step 1: Copy the real fixtures**

```bash
mkdir -p ci/tests/fixtures
cp .local/dryrun-uptodate.json ci/tests/fixtures/dryrun_up_to_date.json
cp .local/dryrun-pending.json ci/tests/fixtures/dryrun_pending.json
```

- [ ] **Step 2: Write the failing tests**

`ci/tests/conftest.py`:
```python
import sys
from pathlib import Path

# Make `ci/` importable as a flat module directory (ci/db_plan.py -> `import db_plan`).
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

`ci/tests/test_db_plan.py`:
```python
from pathlib import Path

import pytest

from db_plan import Plan, PlanError, main, parse_plan, summary_markdown

FIXTURES = Path(__file__).parent / "fixtures"

UP_TO_DATE = (
    '{"_tag":"Success","message":"Remote database is up to date.",'
    '"data":{"upToDate":true,"dryRun":true,"migrations":[],"seeds":[],"roles":[]}}'
)
PENDING = (
    '{"_tag":"Success","message":"Finished supabase db push.",'
    '"data":{"upToDate":false,"dryRun":true,'
    '"migrations":["011_location_geography_parity.sql","012_system_pins_user_correctable.sql"],'
    '"seeds":[],"roles":[]}}'
)


def test_real_up_to_date_output():
    plan = parse_plan((FIXTURES / "dryrun_up_to_date.json").read_text(encoding="utf-8"))
    assert plan == Plan(pending=False, migrations=())


def test_real_pending_output():
    plan = parse_plan((FIXTURES / "dryrun_pending.json").read_text(encoding="utf-8"))
    assert plan == Plan(pending=True, migrations=("012_system_pins_user_correctable.sql",))


def test_pending_keeps_cli_order():
    assert parse_plan(PENDING).migrations == (
        "011_location_geography_parity.sql",
        "012_system_pins_user_correctable.sql",
    )


def test_envelope_agnostic():
    # The result object may be top-level or nested; only `upToDate` matters.
    assert parse_plan('{"upToDate": true, "migrations": []}').pending is False


def test_error_envelope_is_a_plan_error():
    err = (
        '{"_tag":"Error","error":{"code":"DbConnectError",'
        '"message":"failed to connect to postgres"}}'
    )
    with pytest.raises(PlanError, match="DbConnectError"):
        parse_plan(err)


def test_noise_before_json_is_ignored():
    text = "A new version of Supabase CLI is available: v9.9.9\n" + UP_TO_DATE + "\n"
    assert parse_plan(text).pending is False


def test_no_json_is_a_plan_error():
    with pytest.raises(PlanError):
        parse_plan("Connecting to remote database...\n")


def test_missing_up_to_date_is_a_plan_error():
    with pytest.raises(PlanError):
        parse_plan('{"_tag":"Success","data":{"migrations":[]}}')


def test_pending_without_migrations_is_a_plan_error():
    with pytest.raises(PlanError):
        parse_plan('{"upToDate": false, "migrations": []}')


def test_summary_lists_pending_in_order():
    md = summary_markdown(parse_plan(PENDING))
    assert "### Pending for prod" in md
    assert md.index("011_location_geography_parity.sql") < md.index(
        "012_system_pins_user_correctable.sql"
    )


def test_summary_when_up_to_date():
    assert "Nothing pending" in summary_markdown(parse_plan(UP_TO_DATE))


def test_main_writes_outputs_and_summary(tmp_path, monkeypatch):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(PENDING, encoding="utf-8")
    out, summ = tmp_path / "out", tmp_path / "summary"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summ))

    assert main([str(plan_file)]) == 0
    assert out.read_text(encoding="utf-8").splitlines() == [
        "pending=true",
        "migrations=011_location_geography_parity.sql 012_system_pins_user_correctable.sql",
    ]
    assert "012_system_pins_user_correctable.sql" in summ.read_text(encoding="utf-8")


def test_main_error_output_exits_1(tmp_path, capsys):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text('{"_tag":"Error","error":{"code":"X","message":"boom"}}', encoding="utf-8")
    assert main([str(plan_file)]) == 1
    assert "::error::" in capsys.readouterr().out


def test_expect_match_passes(tmp_path):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(PENDING, encoding="utf-8")
    expected = "011_location_geography_parity.sql 012_system_pins_user_correctable.sql"
    assert main([str(plan_file), "--expect", expected]) == 0


def test_expect_mismatch_fails(tmp_path, capsys):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(PENDING, encoding="utf-8")
    assert main([str(plan_file), "--expect", "012_system_pins_user_correctable.sql"]) == 1
    assert "changed since approval" in capsys.readouterr().out
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: collection error, `ModuleNotFoundError: No module named 'db_plan'`.

- [ ] **Step 4: Implement `ci/db_plan.py`**

```python
"""Read `supabase db push --dry-run --output-format json` output for the DB
migrations workflow (docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md).

    python3 ci/db_plan.py PLAN_JSON
        plan job: append pending=/migrations= to $GITHUB_OUTPUT and a
        "Pending for prod" section to $GITHUB_STEP_SUMMARY.
    python3 ci/db_plan.py PLAN_JSON --expect "a.sql b.sql"
        apply job: exit 1 unless the pending list is exactly the approved one.

Stdlib only; runs on the stock ubuntu-latest python3.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass


class PlanError(ValueError):
    """The dry-run output is unreadable or reports an error."""


@dataclass(frozen=True)
class Plan:
    pending: bool
    migrations: tuple[str, ...]


def _load_json(text: str) -> object:
    """Whole text as JSON, else the last line that parses as a JSON object
    (tolerates non-JSON noise such as CLI update notices)."""
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    for line in reversed(text.strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    raise PlanError("no JSON object found in `supabase db push` output")


def _find_result(obj: object) -> dict | None:
    """Depth-first search for the object carrying `upToDate` (envelope-agnostic)."""
    if isinstance(obj, dict):
        if "upToDate" in obj:
            return obj
        children = obj.values()
    elif isinstance(obj, list):
        children = obj
    else:
        return None
    for child in children:
        found = _find_result(child)
        if found is not None:
            return found
    return None


def parse_plan(text: str) -> Plan:
    doc = _load_json(text)
    if isinstance(doc, dict) and doc.get("_tag") == "Error":
        err = doc.get("error") or {}
        raise PlanError(
            f"`supabase db push` reported an error: {err.get('code')}: {err.get('message')}"
        )
    result = _find_result(doc)
    if result is None:
        raise PlanError("`supabase db push` output has no upToDate field")
    up_to_date = result["upToDate"]
    if not isinstance(up_to_date, bool):
        raise PlanError(f"upToDate is not a boolean: {up_to_date!r}")
    migrations = tuple(result.get("migrations") or ())
    if not up_to_date and not migrations:
        raise PlanError("upToDate is false but no migrations are listed")
    return Plan(pending=not up_to_date, migrations=migrations)


def summary_markdown(plan: Plan) -> str:
    if not plan.pending:
        return "### Pending for prod\n\nNothing pending — prod is up to date.\n"
    lines = [
        "### Pending for prod",
        "",
        "Approving the `apply` job applies exactly these, in order:",
        "",
        *(f"- `{m}`" for m in plan.migrations),
    ]
    return "\n".join(lines) + "\n"


def _append(env_var: str, text: str) -> None:
    path = os.environ.get(env_var)
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan_json")
    parser.add_argument("--expect", help="space-separated approved migration filenames")
    args = parser.parse_args(argv)

    with open(args.plan_json, encoding="utf-8") as f:
        text = f.read()
    try:
        plan = parse_plan(text)
    except PlanError as e:
        print(f"::error::{e}")
        return 1

    if args.expect is not None:
        approved = tuple(args.expect.split())
        if plan.migrations != approved:
            print(
                "::error::pending migrations changed since approval: "
                f"approved {list(approved)}, now {list(plan.migrations)}"
            )
            return 1
        print(f"Pending list matches the approved plan: {list(approved)}")
        return 0

    _append("GITHUB_OUTPUT", f"pending={'true' if plan.pending else 'false'}\n")
    _append("GITHUB_OUTPUT", f"migrations={' '.join(plan.migrations)}\n")
    summary = summary_markdown(plan)
    _append("GITHUB_STEP_SUMMARY", summary)
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: `15 passed`. If the two real-fixture tests fail, the CLI's real JSON differs from the assumptions. Adjust the **parser** (`_find_result` / `_load_json`) to the fixture, never the fixture to the parser.

- [ ] **Step 6: Commit**

```bash
git add ci/db_plan.py ci/tests/conftest.py ci/tests/test_db_plan.py ci/tests/fixtures/
git commit -m "$(cat <<'EOF'
feat(ci): parse Supabase db push dry-run for the migrations pipeline

ci/db_plan.py reads `db push --dry-run --output-format json`, writes the
plan job's pending/migrations outputs and summary, and with --expect
fails the apply job if the pending list differs from what was approved.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
)"
```

---

### Task 3: `db-migrations.yml` + structure tests + preflight hook-in

**Files:**
- Create: `.github/workflows/db-migrations.yml`
- Create: `ci/tests/test_db_migrations_workflow.py`
- Delete: `.github/workflows/supabase-migration-validate.yml`
- Modify: `.claude/pr-preflight.sh` (add a `ci` stack)

**Interfaces:**
- Consumes: `ci/db_plan.py` CLI (Task 2).
- Produces:
  - Job ids `workflow-tests`, `staging-pr`, `staging`, `plan`, `apply`.
  - `plan` outputs `pending` and `migrations`.
  - Concurrency groups `db-staging` and `db-prod` (Task 4 reuses both names).

- [ ] **Step 1: Write the failing structure tests**

`ci/tests/test_db_migrations_workflow.py`:
```python
import json
import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "db-migrations.yml"
PROD_ENVIRONMENTS = {"production-plan", "production"}


def _on(wf: dict) -> dict:
    # PyYAML (YAML 1.1) parses the bare key `on` as boolean True.
    return wf.get("on", wf.get(True))


def _text(obj) -> str:
    return json.dumps(obj)


def _runs(job: dict) -> str:
    return "\n".join(step.get("run", "") for step in job.get("steps", []))


@pytest.fixture(scope="module")
def wf() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def jobs(wf) -> dict:
    return wf["jobs"]


def test_triggers(wf):
    on = _on(wf)
    pr_paths = on["pull_request"]["paths"]
    for p in (
        "supabase/migrations/**",
        ".github/workflows/db-migrations.yml",
        ".github/workflows/db-repair.yml",
        "ci/**",
    ):
        assert p in pr_paths
    assert on["pull_request"]["branches"] == ["master"]
    assert on["push"]["branches"] == ["master"]
    assert on["push"]["paths"] == ["supabase/migrations/**"]
    assert "workflow_dispatch" in on


def test_permissions_read_only(wf):
    assert wf["permissions"] == {"contents": "read"}


def test_prod_secret_only_in_prod_environment_jobs(jobs):
    for name, job in jobs.items():
        if "PROD_DB_URL" in _text(job):
            assert job.get("environment") in PROD_ENVIRONMENTS, name


def test_pr_jobs_never_touch_prod(jobs):
    pr_jobs = {n for n, j in jobs.items() if j.get("if") == "github.event_name == 'pull_request'"}
    assert pr_jobs == {"workflow-tests", "staging-pr"}
    for n in pr_jobs:
        assert "PROD_DB_URL" not in _text(jobs[n])
        assert "environment" not in jobs[n]


def test_deploy_jobs_never_run_on_pull_request(jobs):
    for n in ("staging", "plan", "apply"):
        assert "github.event_name != 'pull_request'" in jobs[n]["if"]


def test_plan_job(jobs):
    plan = jobs["plan"]
    assert plan["environment"] == "production-plan"
    assert plan["needs"] == "staging"
    assert set(plan["outputs"]) == {"pending", "migrations"}
    runs = _runs(plan)
    assert "--dry-run" in runs and "--output-format json" in runs
    assert "ci/db_plan.py" in runs


def test_apply_is_gated(jobs):
    apply = jobs["apply"]
    assert apply["environment"] == "production"
    assert set(apply["needs"]) == {"staging", "plan"}
    assert "needs.plan.outputs.pending == 'true'" in apply["if"]
    runs = _runs(apply)
    # Approved list == applied list: re-plan, compare, only then push.
    assert "--expect" in runs
    assert runs.index("--expect") < runs.index("supabase db push --include-all --yes")


def test_concurrency_never_cancels(jobs):
    for n, group in (("staging-pr", "db-staging"), ("staging", "db-staging"), ("apply", "db-prod")):
        c = jobs[n]["concurrency"]
        assert c["group"] == group
        assert c["cancel-in-progress"] is False


def test_cli_version_pinned(wf, jobs):
    assert re.fullmatch(r"\d+\.\d+\.\d+", wf["env"]["SUPABASE_CLI_VERSION"])
    setups = [
        s
        for j in jobs.values()
        for s in j.get("steps", [])
        if str(s.get("uses", "")).startswith("supabase/setup-cli")
    ]
    assert len(setups) == 4  # staging-pr, staging, plan, apply
    for s in setups:
        assert s["uses"] == "supabase/setup-cli@v3"
        assert s["with"]["version"] == "${{ env.SUPABASE_CLI_VERSION }}"


def test_real_pushes_are_noninteractive_and_include_all(jobs):
    for job in jobs.values():
        for line in _runs(job).splitlines():
            if "supabase db push" in line and "--dry-run" not in line:
                assert "--include-all" in line and "--yes" in line, line


def test_pr_reapply_only_touches_added_migrations(jobs):
    runs = _runs(jobs["staging-pr"])
    assert "--diff-filter=A" in runs
    assert 'if [ -n "$versions" ]' in runs
    assert runs.index("migration repair --status reverted") < runs.index("supabase db push")


def test_old_validate_workflow_removed():
    assert not (ROOT / ".github" / "workflows" / "supabase-migration-validate.yml").exists()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_db_migrations_workflow.py -q`
Expected: errors with `FileNotFoundError` for `db-migrations.yml`. `test_old_validate_workflow_removed` also fails.

- [ ] **Step 3: Write `.github/workflows/db-migrations.yml`**

```yaml
name: DB Migrations

# Applies supabase/migrations/*.sql with the pinned Supabase CLI.
#   PR     → staging-pr: re-applies this PR's own new migrations, then db push.
#   merge  → staging → plan (prod dry-run, listed in the run summary)
#            → apply (waits for owner approval in the `production` environment).
# PROD_DB_URL exists only as an environment secret of `production-plan` and
# `production`, both limited to master — PR code can never read it.
# Design: docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md
# Operator guide: docs/dev/STAGING.md "Applying migrations".

on:
  pull_request:
    branches: [master]
    paths:
      - 'supabase/migrations/**'
      - '.github/workflows/db-migrations.yml'
      - '.github/workflows/db-repair.yml'
      - 'ci/**'
  push:
    branches: [master]
    paths:
      - 'supabase/migrations/**'
  workflow_dispatch:

permissions:
  contents: read

env:
  SUPABASE_CLI_VERSION: '2.118.0'

jobs:
  workflow-tests:
    name: Workflow structure tests
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
        with:
          version: '0.5.x'
      - name: Run ci/tests
        run: uv run --no-project --with pytest --with pyyaml pytest ci/tests -q

  staging-pr:
    name: Apply to staging (PR)
    if: github.event_name == 'pull_request'
    needs: workflow-tests
    runs-on: ubuntu-latest
    concurrency:
      group: db-staging
      cancel-in-progress: false
    env:
      DB_URL: ${{ secrets.STAGING_DB_URL }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # origin/master is needed to find this PR's added migrations
      - uses: supabase/setup-cli@v3
        with:
          version: ${{ env.SUPABASE_CLI_VERSION }}
      - name: Re-apply this PR's own new migrations
        # A migration added by this PR may already be recorded on staging from an
        # earlier push of the same PR. Clearing its history row makes db push run
        # the (possibly edited) SQL again — safe because migrations are idempotent
        # by convention. Reverting a never-recorded version is a no-op DELETE.
        run: |
          set -euo pipefail
          versions=$(git diff --name-only --diff-filter=A origin/master...HEAD -- 'supabase/migrations/*.sql' \
            | xargs -r -n1 basename | cut -d_ -f1 | sort -u | tr '\n' ' ')
          if [ -n "$versions" ]; then
            echo "Clearing staging history rows for: $versions"
            # shellcheck disable=SC2086 # intentionally unquoted: one argument per version
            supabase migration repair --status reverted $versions --db-url "$DB_URL"
          else
            echo "This PR adds no migrations."
          fi
      - name: Push to staging
        run: supabase db push --include-all --yes --db-url "$DB_URL"
      - name: Summary
        if: always()
        run: |
          {
            echo '### Staging migration history'
            echo '```'
            supabase migration list --db-url "$DB_URL" 2>&1 || true
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

  staging:
    name: Apply to staging
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    concurrency:
      group: db-staging
      cancel-in-progress: false
    env:
      DB_URL: ${{ secrets.STAGING_DB_URL }}
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v3
        with:
          version: ${{ env.SUPABASE_CLI_VERSION }}
      - name: Push to staging
        run: supabase db push --include-all --yes --db-url "$DB_URL"
      - name: Summary
        if: always()
        run: |
          {
            echo '### Staging migration history'
            echo '```'
            supabase migration list --db-url "$DB_URL" 2>&1 || true
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

  plan:
    name: Plan prod (dry run)
    if: github.event_name != 'pull_request'
    needs: staging
    runs-on: ubuntu-latest
    environment: production-plan
    outputs:
      pending: ${{ steps.plan.outputs.pending }}
      migrations: ${{ steps.plan.outputs.migrations }}
    env:
      DB_URL: ${{ secrets.PROD_DB_URL }}
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v3
        with:
          version: ${{ env.SUPABASE_CLI_VERSION }}
      - name: Dry-run against prod
        id: plan
        run: |
          set -euo pipefail
          supabase db push --dry-run --include-all --output-format json --db-url "$DB_URL" > plan.json
          python3 ci/db_plan.py plan.json

  apply:
    name: Apply to prod
    if: github.event_name != 'pull_request' && needs.plan.outputs.pending == 'true'
    needs: [staging, plan]
    runs-on: ubuntu-latest
    environment: production
    concurrency:
      group: db-prod
      cancel-in-progress: false
    env:
      DB_URL: ${{ secrets.PROD_DB_URL }}
      APPROVED: ${{ needs.plan.outputs.migrations }}
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v3
        with:
          version: ${{ env.SUPABASE_CLI_VERSION }}
      - name: Push the approved migrations to prod
        run: |
          set -euo pipefail
          # Re-plan and refuse if prod's pending list is no longer what was approved.
          supabase db push --dry-run --include-all --output-format json --db-url "$DB_URL" > replan.json
          python3 ci/db_plan.py replan.json --expect "$APPROVED"
          supabase db push --include-all --yes --db-url "$DB_URL"
      - name: Summary
        if: always()
        run: |
          {
            echo '### Prod migration history'
            echo '```'
            supabase migration list --db-url "$DB_URL" 2>&1 || true
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 4: Delete the old workflow**

Run: `git rm .github/workflows/supabase-migration-validate.yml`

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: `27 passed` (15 from Task 2 + 12 here).

- [ ] **Step 6: Lint the workflow**

Run: `uvx --from actionlint-py actionlint .github/workflows/db-migrations.yml`
Expected: no output, exit 0. Fix any reported issue in the YAML; don't suppress it.

- [ ] **Step 7: Hook `ci/tests` into the local preflight**

In `.claude/pr-preflight.sh`, make these four edits.

Replace:
```bash
run_flutter=0
run_importer=0
if [ -z "$changed" ]; then
  run_flutter=1
  run_importer=1
else
```
with:
```bash
run_flutter=0
run_importer=0
run_ci=0
if [ -z "$changed" ]; then
  run_flutter=1
  run_importer=1
  run_ci=1
else
```

After the line `  printf '%s\n' "$changed" | grep -qE '^importer/' && run_importer=1`, add:
```bash
  printf '%s\n' "$changed" | grep -qE '^(ci/|\.github/workflows/db-)' && run_ci=1
```

Replace:
```bash
if [ "$run_flutter" = 0 ] && [ "$run_importer" = 0 ]; then
  echo "PR preflight: no Flutter or importer source changed (docs/ci/config only) — nothing to check."
  exit 0
fi

echo "PR preflight — flutter=$run_flutter importer=$run_importer"
```
with:
```bash
if [ "$run_flutter" = 0 ] && [ "$run_importer" = 0 ] && [ "$run_ci" = 0 ]; then
  echo "PR preflight: no Flutter, importer, or DB-pipeline source changed (docs/config only) — nothing to check."
  exit 0
fi

echo "PR preflight — flutter=$run_flutter importer=$run_importer ci=$run_ci"
```

Before the final `echo "✓ PR preflight clean."`, add:
```bash
if [ "$run_ci" = 1 ]; then
  echo "== ci: DB pipeline workflow + script tests =="
  uv run --no-project --with pytest --with pyyaml pytest ci/tests -q || fail "ci tests"
fi
```

- [ ] **Step 8: Verify the preflight picks up the ci stack**

Run: `bash .claude/pr-preflight.sh 2>&1 | grep -E "PR preflight —|== ci|passed|✓|✗"`
Expected: `PR preflight — flutter=0 importer=0 ci=1`, `== ci: …`, `27 passed`, `✓ PR preflight clean.`

- [ ] **Step 9: Commit**

```bash
git add .github/workflows/db-migrations.yml ci/tests/test_db_migrations_workflow.py .claude/pr-preflight.sh
git commit -m "$(cat <<'EOF'
feat(ci): GitHub Actions pipeline for Supabase migrations

db-migrations.yml replaces supabase-migration-validate.yml: PRs push to
staging (re-applying the PR's own new migrations), merges push to
staging then dry-run prod in `plan` and apply to prod only after owner
approval in the master-only `production` environment. Structure tests
lock in that PROD_DB_URL is reachable only from those environment jobs.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
)"
```

---

### Task 4: `db-repair.yml` + `ci/db_repair.sh`

**Files:**
- Create: `ci/db_repair.sh`
- Create: `.github/workflows/db-repair.yml`
- Create: `ci/tests/test_db_repair.py`

**Interfaces:**
- Consumes: the concurrency group names `db-staging` / `db-prod` and the CLI pin value `2.118.0` (Task 3).
- Produces: `DB_URL=<url> bash ci/db_repair.sh <list|applied|reverted> "<versions>"`.
  - Exit 2 on bad input, before any `supabase` call.
  - Otherwise runs `supabase migration repair --status <action> <versions...> --db-url "$DB_URL"` (skipped for `list`), then `supabase migration list --db-url "$DB_URL"`, and appends that listing to `$GITHUB_STEP_SUMMARY`.

- [ ] **Step 1: Write the failing tests**

`ci/tests/test_db_repair.py`:
```python
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "ci" / "db_repair.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "db-repair.yml"
MIGRATIONS_WORKFLOW = ROOT / ".github" / "workflows" / "db-migrations.yml"
BASH = shutil.which("bash")


def _on(wf: dict) -> dict:
    return wf.get("on", wf.get(True))


# ---------- ci/db_repair.sh (with a stub `supabase` on PATH) ----------


@pytest.fixture
def run_script(tmp_path):
    if BASH is None:
        pytest.skip("bash not available")
    log = tmp_path / "calls.log"
    stub = tmp_path / "supabase"
    stub.write_text('#!/usr/bin/env bash\necho "$*" >> "$STUB_LOG"\necho "LOCAL | REMOTE"\n', encoding="utf-8")
    stub.chmod(0o755)
    summary = tmp_path / "summary.md"

    def run(action: str, versions: str = ""):
        env = {
            **os.environ,
            "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
            "STUB_LOG": str(log),
            "DB_URL": "postgresql://stub",
            "GITHUB_STEP_SUMMARY": str(summary),
        }
        proc = subprocess.run(
            [BASH, str(SCRIPT), action, versions], env=env, capture_output=True, text=True
        )
        calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
        return proc, calls, summary

    return run


def test_list_only_lists(run_script):
    proc, calls, summary = run_script("list")
    assert proc.returncode == 0, proc.stderr
    assert calls == ["migration list --db-url postgresql://stub"]
    assert "LOCAL | REMOTE" in summary.read_text(encoding="utf-8")


def test_applied_marks_versions_then_lists(run_script):
    proc, calls, _ = run_script("applied", "000 004 005")
    assert proc.returncode == 0, proc.stderr
    assert calls == [
        "migration repair --status applied 000 004 005 --db-url postgresql://stub",
        "migration list --db-url postgresql://stub",
    ]


def test_commas_and_spaces_are_accepted(run_script):
    proc, calls, _ = run_script("reverted", " 20260705144447,20260705144509  010 ")
    assert proc.returncode == 0, proc.stderr
    assert calls[0] == (
        "migration repair --status reverted 20260705144447 20260705144509 010 "
        "--db-url postgresql://stub"
    )


def test_non_numeric_version_is_rejected(run_script):
    proc, calls, _ = run_script("applied", "008;")
    assert proc.returncode == 2
    assert "invalid migration version" in proc.stdout + proc.stderr
    assert calls == []


def test_versions_required_for_repair(run_script):
    proc, calls, _ = run_script("reverted", "   ")
    assert proc.returncode == 2
    assert calls == []


def test_unknown_action_is_rejected(run_script):
    proc, calls, _ = run_script("drop", "008")
    assert proc.returncode == 2
    assert calls == []


# ---------- .github/workflows/db-repair.yml ----------


@pytest.fixture(scope="module")
def wf() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


def test_inputs(wf):
    inputs = _on(wf)["workflow_dispatch"]["inputs"]
    assert inputs["target"]["options"] == ["staging", "prod"]
    assert inputs["action"]["options"] == ["list", "applied", "reverted"]
    assert inputs["versions"]["type"] == "string"


def test_permissions_read_only(wf):
    assert wf["permissions"] == {"contents": "read"}


def test_prod_repair_requires_approval(wf):
    jobs = wf["jobs"]
    assert set(jobs) == {"repair-staging", "repair-prod"}
    assert jobs["repair-prod"]["if"] == "inputs.target == 'prod'"
    assert jobs["repair-prod"]["environment"] == "production"
    assert jobs["repair-prod"]["concurrency"] == {"group": "db-prod", "cancel-in-progress": False}
    assert jobs["repair-staging"]["if"] == "inputs.target == 'staging'"
    assert "environment" not in jobs["repair-staging"]
    assert jobs["repair-staging"]["concurrency"] == {"group": "db-staging", "cancel-in-progress": False}


def test_prod_secret_only_in_prod_job(wf):
    jobs = wf["jobs"]
    assert "PROD_DB_URL" in json.dumps(jobs["repair-prod"])
    assert "PROD_DB_URL" not in json.dumps(jobs["repair-staging"])


def test_inputs_reach_run_steps_only_via_env(wf):
    for job in wf["jobs"].values():
        for step in job["steps"]:
            assert "${{ inputs." not in step.get("run", ""), step


def test_cli_pin_matches_migrations_workflow(wf):
    migrations = yaml.safe_load(MIGRATIONS_WORKFLOW.read_text(encoding="utf-8"))
    assert wf["env"]["SUPABASE_CLI_VERSION"] == migrations["env"]["SUPABASE_CLI_VERSION"]
    for job in wf["jobs"].values():
        setup = [s for s in job["steps"] if str(s.get("uses", "")).startswith("supabase/setup-cli")]
        assert setup and setup[0]["uses"] == "supabase/setup-cli@v3"
        assert setup[0]["with"]["version"] == "${{ env.SUPABASE_CLI_VERSION }}"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_db_repair.py -q`
Expected: failures. The script tests fail with non-zero exit and empty call logs (`ci/db_repair.sh` doesn't exist); the workflow tests fail with `FileNotFoundError`.

- [ ] **Step 3: Implement `ci/db_repair.sh`**

```bash
#!/usr/bin/env bash
# ci/db_repair.sh — edit the Supabase migration history table. Never runs
# migration SQL. Used by .github/workflows/db-repair.yml.
#
#   DB_URL=<pooler url> bash ci/db_repair.sh <list|applied|reverted> "<versions>"
#
# versions: space- and/or comma-separated digits (e.g. "000 004,005").
set -euo pipefail

action="${1:-}"
versions="$(printf '%s' "${2:-}" | tr ',' ' ' | xargs)"

case "$action" in
  list) ;;
  applied|reverted)
    if [ -z "$versions" ]; then
      echo "::error::versions are required for '$action'"
      exit 2
    fi
    for v in $versions; do
      if ! [[ "$v" =~ ^[0-9]+$ ]]; then
        echo "::error::invalid migration version '$v' (digits only, e.g. 008 or 20260705144447)"
        exit 2
      fi
    done
    # shellcheck disable=SC2086 # intentionally unquoted: one argument per version
    supabase migration repair --status "$action" $versions --db-url "$DB_URL"
    ;;
  *)
    echo "::error::unknown action '$action' (expected list, applied or reverted)"
    exit 2
    ;;
esac

listing="$(supabase migration list --db-url "$DB_URL")"
echo "$listing"
{
  echo "### Migration history after \`$action\`"
  echo '```'
  echo "$listing"
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
```

Then mark it executable in git: `git add ci/db_repair.sh && git update-index --chmod=+x ci/db_repair.sh`

- [ ] **Step 4: Write `.github/workflows/db-repair.yml`**

```yaml
name: DB Repair (manual)

# Edits supabase_migrations.schema_migrations only — never runs migration SQL.
# For the one-time history baseline and for recording emergency hand-fixes.
# target=prod runs in the `production` environment → waits for owner approval.
# Operator guide: docs/dev/STAGING.md "Applying migrations".

on:
  workflow_dispatch:
    inputs:
      target:
        description: 'Which database'
        required: true
        type: choice
        options:
          - staging
          - prod
      action:
        description: 'list = show history; applied / reverted = mark versions'
        required: true
        type: choice
        options:
          - list
          - applied
          - reverted
      versions:
        description: 'For applied/reverted: versions, space- or comma-separated (e.g. 000 004 005)'
        required: false
        type: string
        default: ''

permissions:
  contents: read

env:
  SUPABASE_CLI_VERSION: '2.118.0'

jobs:
  repair-staging:
    name: Repair staging history
    if: inputs.target == 'staging'
    runs-on: ubuntu-latest
    concurrency:
      group: db-staging
      cancel-in-progress: false
    env:
      DB_URL: ${{ secrets.STAGING_DB_URL }}
      ACTION: ${{ inputs.action }}
      VERSIONS: ${{ inputs.versions }}
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v3
        with:
          version: ${{ env.SUPABASE_CLI_VERSION }}
      - name: Repair
        run: bash ci/db_repair.sh "$ACTION" "$VERSIONS"

  repair-prod:
    name: Repair prod history
    if: inputs.target == 'prod'
    runs-on: ubuntu-latest
    environment: production
    concurrency:
      group: db-prod
      cancel-in-progress: false
    env:
      DB_URL: ${{ secrets.PROD_DB_URL }}
      ACTION: ${{ inputs.action }}
      VERSIONS: ${{ inputs.versions }}
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v3
        with:
          version: ${{ env.SUPABASE_CLI_VERSION }}
      - name: Repair
        run: bash ci/db_repair.sh "$ACTION" "$VERSIONS"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests -q`
Expected: `39 passed` (27 + 12). On Windows, run this from Git Bash so its `bash` comes first on `PATH`. If the six script tests fail **only** locally on Windows (Git Bash path conversion of the stub or log paths) while everything else passes, don't change the script. Confirm they pass on Linux in the PR's `workflow-tests` job (Task 6 Step 4); CI is the authority.

- [ ] **Step 6: Lint**

Run: `uvx --from actionlint-py actionlint .github/workflows/db-repair.yml .github/workflows/db-migrations.yml`
Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add ci/db_repair.sh .github/workflows/db-repair.yml ci/tests/test_db_repair.py
git commit -m "$(cat <<'EOF'
feat(ci): db-repair workflow for Supabase migration history

Manual workflow_dispatch that lists or marks versions applied/reverted in
supabase_migrations.schema_migrations without running any SQL, for the
one-time baseline and emergency hand-fixes. Prod runs need approval in
the `production` environment; inputs reach the script only via env.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
)"
```

---

### Task 5: Docs

**Files:**
- Modify: `docs/dev/STAGING.md` (intro paragraph, `## Applying migrations`, bootstrap check, `## GitHub Actions secrets`, `## Migration history` note)
- Modify: `CLAUDE.md` (new subsection under `## CI/CD & Build Flags`; toolchain line)
- Modify: `docs/dev/GIT_FLOW.md` (PR Workflow section)
- Modify: `docs/dev/DEPLOY.md` (`## Migrations`)

**Interfaces:** none (docs only).

- [ ] **Step 1: `docs/dev/STAGING.md` intro**

Replace the sentence `New migrations apply here first via the` / `` `.github/workflows/supabase-migration-validate.yml` workflow before they `` / `ever touch prod.` with:

```markdown
New migrations apply here first via the
`.github/workflows/db-migrations.yml` pipeline (on every PR) before they
ever touch prod.
```

- [ ] **Step 2: `docs/dev/STAGING.md` — replace the whole `## Applying migrations` section**

Replace everything from `## Applying migrations` up to (not including) `## Bootstrap (one-time)` with:

````markdown
## Applying migrations

Migrations reach staging and prod **only** through GitHub Actions, using the
pinned Supabase CLI (`supabase db push`). Design:
`docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md`.

| When | Workflow → job | Target |
|---|---|---|
| PR touching `supabase/migrations/**` | `db-migrations.yml` → `staging-pr` | staging (re-applies the PR's own new migrations on every push) |
| Merge to `master`, or **Run workflow** | `db-migrations.yml` → `staging` → `plan` → `apply` | staging, then prod after **owner approval** |
| Manual | `db-repair.yml` | the history table only (`list` / `applied` / `reverted`); never runs SQL |

**Approving a prod deploy.** The run pauses at `apply`. Open the run and read
the `plan` job's summary ("Pending for prod"). Approve only if every listed
migration is safe for the app version users currently run (rule 5 below).
Reject to hold it: it stays pending, reappears in the next plan, and **Run
workflow** on `db-migrations.yml` deploys it later. `apply` re-checks that
prod's pending list still equals the approved one and refuses otherwise.

**What's applied where:**
- `supabase_migrations.schema_migrations` in each database (dashboard →
  Database → Migrations);
- the `production` environment's deployment log on GitHub (commit, run,
  approver);
- every run's summary (`supabase migration list`).

### Rules

1. Never apply repo migrations by hand or via MCP `apply_migration`: MCP
   records timestamp versions that break the CLI's history. After an
   emergency hand-fix in the dashboard, record it with `db-repair`
   (`applied <version>`).
2. Never edit an applied migration's SQL; fix forward with a new migration.
3. Keep migrations idempotent (`IF NOT EXISTS`, `CREATE OR REPLACE`,
   `DROP … IF EXISTS` before `CREATE`). The PR loop re-applies them on every push.
4. No transaction-unsafe statements (`CREATE INDEX CONCURRENTLY`, `VACUUM`).
   Each migration runs in one transaction.
5. A migration the currently deployed app can't handle is **rejected at the
   approval gate** until the new app version is adopted.

### Troubleshooting

- **"Remote migration versions not found in local migrations directory"**:
  the database has a migration the checkout lacks.
  - On a PR: merge `master` into the branch.
  - Otherwise it's an abandoned PR's migration left on staging. Remove it with
    `db-repair` (`staging` / `reverted` / `<version>`), and undo its schema by
    hand if needed.
- **Staging unreachable** (`Name or service not known`): the free-tier project
  auto-paused; resume it from the dashboard. Prod deploys wait on staging.
````

- [ ] **Step 3: `docs/dev/STAGING.md` bootstrap check**

Replace:
```
  (SELECT count(*) FROM pg_policy WHERE polrelid='public.pins'::regclass AND polname='deny_system_user_writes') AS deny_policy_exists;
```
with:
```
  (SELECT count(*) FROM pg_policy WHERE polrelid='public.pins'::regclass AND polname IN ('deny_system_user_insert','deny_system_user_update','deny_system_user_delete')) AS deny_policies;
```
and replace `trigger_count=4, rpc=1, deny_policy=1.` with `trigger_count=4, rpc=1, deny_policies=3.`

- [ ] **Step 4: `docs/dev/STAGING.md` secrets table**

Replace the two table rows (`STAGING_DB_URL …` and `PROD_DB_URL …`) with:
```markdown
| `STAGING_DB_URL` | **Repo** secret. Postgres connection string via the **Session mode pooler** (port 5432, NOT the direct-connect host), password percent-encoded. Format: `postgresql://postgres.miihmfhnsfmwgrvgayns:<DB_PASSWORD>@aws-0-<region>.pooler.supabase.com:5432/postgres` | `db-migrations.yml` (`staging-pr`, `staging`), `db-repair.yml` (`repair-staging`) |
| `PROD_DB_URL` | **Environment** secret, set in **both** `production-plan` and `production` (both limited to `master`; `production` requires owner approval). Same pooler format with `postgres.gqbxloaqamokbolcvesg`. Never a repo secret. | `db-migrations.yml` (`plan`, `apply`), `db-repair.yml` (`repair-prod`) |
```

- [ ] **Step 5: `docs/dev/STAGING.md` migration history note**

Directly under the `## Migration history` heading, insert:
```markdown
> **Frozen 2026-09-26 at the pipeline cutover.** The authoritative record is now
> `supabase_migrations.schema_migrations` in each database (`supabase migration
> list`, or dashboard → Database → Migrations). This table is kept as history.
```

- [ ] **Step 6: `CLAUDE.md`**

Under `## CI/CD & Build Flags`, after the `### Flutter version is pinned in CI` subsection (i.e. immediately before `## Project Overview`), insert:

```markdown
### DB migrations pipeline

Migrations reach staging and prod **only** through GitHub Actions: never the
dashboard SQL editor, and never Supabase MCP `apply_migration` (it records
timestamp versions that break the CLI's history). The MCP server stays bound
to **staging**; Claude never needs prod access.

- `.github/workflows/db-migrations.yml`:
  - **PR:** `staging-pr` pushes to staging, re-applying the PR's own new
    migrations on every push.
  - **Merge to master** (or **Run workflow**): `staging` → `plan` (prod dry
    run, listed in the run summary) → `apply`. `apply` waits for owner
    approval in the master-only `production` environment and refuses if the
    pending list changed since approval.
- `.github/workflows/db-repair.yml`: manual; edits only
  `supabase_migrations.schema_migrations` (`list` / `applied` / `reverted`).
- The Supabase CLI is **pinned** (`SUPABASE_CLI_VERSION: '2.118.0'` in both
  workflows; the `ci/tests` structure tests enforce that both match).
  Upgrading it is one deliberate PR, like the Flutter pin.
- `PROD_DB_URL` exists only as an environment secret of `production-plan` and
  `production`. PR code can never read it.
- Rules:
  - migrations must be idempotent;
  - never edit an applied migration;
  - no transaction-unsafe statements;
  - reject at the approval gate any migration the deployed app can't handle
    yet ("schema after app release").
- Operator guide: `docs/dev/STAGING.md` → "Applying migrations". Design:
  `docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md`.
```

Also in `### Toolchain versions`, after the `- **Test count**` line, add:
```markdown
- **Supabase CLI** 2.118.0 (CI only; pinned in `db-migrations.yml` + `db-repair.yml`)
```

- [ ] **Step 7: `docs/dev/GIT_FLOW.md`**

After the line `Merge strategy: **Squash and merge** (keeps master history clean).` in `## PR Workflow`, add:
```markdown

PRs that touch `supabase/migrations/**` also run `DB Migrations` (applies
to staging). After merge, the same workflow deploys to prod once you approve
the `apply` job; see `docs/dev/STAGING.md` → "Applying migrations".
```

- [ ] **Step 8: `docs/dev/DEPLOY.md`**

Replace the body of `## Migrations` (the paragraph beginning `Migrations under supabase/migrations/*.sql are applied manually`) with:
```markdown
Migrations under `supabase/migrations/*.sql` are deployed by the
`db-migrations.yml` GitHub Actions pipeline: staging on every PR, prod after
merge once the owner approves the `apply` job. Never apply them by hand. See
`docs/dev/STAGING.md` → "Applying migrations".
```

- [ ] **Step 9: Check for stale references**

Run: `grep -rn "supabase-migration-validate" --include=*.md --include=*.yml --include=*.sh . | grep -v "docs/superpowers/"`
Expected: no output. Historical specs and plans under `docs/superpowers/` may keep the old name.

- [ ] **Step 10: Commit**

```bash
git add docs/dev/STAGING.md CLAUDE.md docs/dev/GIT_FLOW.md docs/dev/DEPLOY.md
git commit -m "$(cat <<'EOF'
docs: document the DB migrations pipeline

STAGING.md "Applying migrations" rewritten for db-migrations.yml /
db-repair.yml (approval, rules, troubleshooting, secrets); CLAUDE.md
gains a DB migrations pipeline subsection and the CLI pin; GIT_FLOW and
DEPLOY point at it. Also fixes STAGING.md's stale bootstrap check that
still named the pre-split deny_system_user_writes policy.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UbGohWWFx8ZBHApJgkMWrW
EOF
)"
```

---

### Task 6: GitHub environments, PR, and self-exercise (operator)

**Files:** none.

**Interfaces:**
- Produces: environments `production-plan` and `production` with `PROD_DB_URL`; an open PR whose `DB Migrations` checks are green.

- [ ] **Step 1: Get the owner's consent, then create the environments**

These are outward-facing repository settings, so ask the owner first. On a yes:
```bash
UID=$(gh api user --jq .id)
for ENV in production-plan production; do
  if [ "$ENV" = production ]; then
    REVIEWERS="[{\"type\":\"User\",\"id\":$UID}]"
  else
    REVIEWERS="[]"
  fi
  gh api -X PUT "repos/camiloh12/ccwmap/environments/$ENV" --input - <<JSON
{"reviewers": $REVIEWERS, "prevent_self_review": false,
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
  gh api -X POST "repos/camiloh12/ccwmap/environments/$ENV/deployment-branch-policies" -f name=master -f type=branch
done
gh api repos/camiloh12/ccwmap/environments --jq '.environments[] | "\(.name) rules=\([.protection_rules[]?.type]|join(","))"'
```
Expected: `production-plan rules=branch_policy` and `production rules=required_reviewers,branch_policy`.

- [ ] **Step 2: Owner adds the prod secret (Claude never sees it)**

Ask the owner to add `PROD_DB_URL` to **both** environments: GitHub → Settings → Environments → `<env>` → Add environment secret. The value is the prod session-pooler URL: `postgresql://postgres.gqbxloaqamokbolcvesg:<percent-encoded password>@aws-0-<region>.pooler.supabase.com:5432/postgres`, taken from the prod dashboard's **Connect** modal, **Session mode** tab. Verify only the names:
```bash
for ENV in production-plan production; do gh secret list --env "$ENV"; done
```
Expected: `PROD_DB_URL` listed under both.

- [ ] **Step 3: Full preflight, push, open the PR**

Run: `bash .claude/pr-preflight.sh`, which must end `✓ PR preflight clean.` Then push `feature/db-migrations-pipeline` and open a PR to `master`. The PR body summarizes Tasks 2–5, links the spec, and lists the post-merge steps (Task 7).

- [ ] **Step 4: Confirm the self-exercise ran for real**

On the PR, `DB Migrations` → `Workflow structure tests` and `Apply to staging (PR)` must pass with real durations (not ~4 s skips), and the staging job's summary must show matching local/remote history `000`–`012`.

Run: `gh pr checks <PR#>`
Expected: both DB Migrations jobs `pass`. Check that the durations are longer than 10 s.

---

### Task 7: Merge, prod history cleanup, first deploy (operator, owner-approved)

**Files:** none (memory files updated at the end).

**Interfaces:**
- Consumes: the Task 6 environments and secret; the merged workflows.

- [ ] **Step 1: Owner merges the pipeline PR**

The merge doesn't touch `supabase/migrations/**`, so `DB Migrations` does not run on it. That's expected.

- [ ] **Step 2: Prod `list` (owner approves)**

Run: `gh workflow run db-repair.yml -f target=prod -f action=list`. The owner approves the run in GitHub. Read the run summary.
Expected: LOCAL `000 004 005 006 007 008 009 010 011 012`; REMOTE shows timestamp versions only (expected: 008 = `20260705144447`, 009 = `20260705144509`, plus 010's).

- [ ] **Step 3: Prod `reverted` for exactly the timestamps shown in Step 2 (owner approves)**

Run: `gh workflow run db-repair.yml -f target=prod -f action=reverted -f versions="<timestamps from step 2>"`
Expected: the summary's REMOTE column is empty.

- [ ] **Step 4: Prod `applied` for the in-effect versions (owner approves)**

Run: `gh workflow run db-repair.yml -f target=prod -f action=applied -f versions="000 004 005 006 007 008 009 010"`
Expected: REMOTE `000 004 005 006 007 008 009 010`; LOCAL additionally `011 012`.

- [ ] **Step 5: First real deploy**

Run: `gh workflow run db-migrations.yml`
Expected:
- `staging` passes (nothing pending).
- The `plan` summary lists exactly `011_location_geography_parity.sql` and `012_system_pins_user_correctable.sql`.
- After the owner approves `apply`, it passes. Its summary shows REMOTE = LOCAL `000`–`012`, and its log includes the notice `pins.location already geography (or absent) — no change` from 011.

- [ ] **Step 6: Verify BUG-006 on prod (owner, prod SQL editor)**

The owner runs the check query from the 2026-09-26 session (also in PR #55's thread).
Expected error text: `PROBE(rolled back) locked_cols_updatable=0 user.update_sys=1 user_modified=true user.delete_sys=0 system.update=0`.

- [ ] **Step 7: Update memory**

- `project_system_pins_uneditable.md`: 012 applied to prod via the pipeline on <date>, verified.
- New feedback memory: "no MCP `apply_migration` for repo migrations; the pipeline is the only path".
- `reference_supabase_staging.md`: staging history is on CLI versions since 2026-09-26.
- Update the `MEMORY.md` index lines.
