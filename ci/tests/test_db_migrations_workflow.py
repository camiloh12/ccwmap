import json
import re
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "db-migrations.yml"
REPAIR_WORKFLOW = ROOT / ".github" / "workflows" / "db-repair.yml"
PROD_ENVIRONMENTS = {"production-plan", "production"}
# Third-party action that receives no secrets but runs in prod-credentialed
# jobs: pinned to an immutable commit (the `v3` tag moved on 2026-09-24).
SETUP_CLI_PIN = re.compile(r"supabase/setup-cli@[0-9a-f]{40}")
DEPLOY_GROUPS = {"db-staging-deploy", "db-prod-deploy"}


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
        ".github/workflows/health-check.yml",
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
    for n, group in (
        ("staging-pr", "db-staging"),
        ("staging", "db-staging-deploy"),
        ("apply", "db-prod-deploy"),
    ):
        c = jobs[n]["concurrency"]
        assert c["group"] == group
        assert c["cancel-in-progress"] is False


def test_deploy_chain_groups_are_exclusive(jobs):
    # GitHub cancels a PENDING job when a newer one enters the same group. The
    # merge deploy chain gets groups no other job uses, so it can only be
    # superseded by a newer deploy run — which applies a superset.
    repair_jobs = yaml.safe_load(REPAIR_WORKFLOW.read_text(encoding="utf-8"))["jobs"]
    for name, job in {**jobs, **{f"repair:{k}": v for k, v in repair_jobs.items()}}.items():
        group = (job.get("concurrency") or {}).get("group")
        if name in ("staging", "apply"):
            assert group in DEPLOY_GROUPS, name
        else:
            assert group not in DEPLOY_GROUPS, name


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
        assert SETUP_CLI_PIN.fullmatch(s["uses"]), s["uses"]
        assert s["with"]["version"] == "${{ env.SUPABASE_CLI_VERSION }}"


CLI_CALL = re.compile(r"\bsupabase (db|migration)\b")


def _needs_db_url(step: dict) -> bool:
    run = step.get("run", "")
    return bool(CLI_CALL.search(run)) or "ci/check_db_url.py" in run


def test_db_url_only_on_steps_that_run_supabase(jobs):
    # DB credentials must not reach checkout or the setup-cli composite action:
    # no job-level env, and a step gets DB_URL only if its own script calls the
    # CLI (or checks the URL's shape).
    for name, job in jobs.items():
        assert "DB_URL" not in json.dumps(job.get("env", {})), name
        for step in job.get("steps", []):
            has_url = "DB_URL" in json.dumps(step.get("env", {}))
            assert has_url == _needs_db_url(step), (name, step.get("name"))


def test_shell_uses_pipefail(wf):
    # Default bash on Actions is `bash -e` (no pipefail): a failing CLI piped
    # through ci/redact.py would otherwise pass.
    assert wf["defaults"] == {"run": {"shell": "bash"}}


def test_every_db_job_checks_the_url_before_the_cli(jobs):
    for name, job in jobs.items():
        db_steps = [s for s in job.get("steps", []) if "DB_URL" in json.dumps(s.get("env", {}))]
        if not db_steps:
            continue
        assert "ci/check_db_url.py" in db_steps[0]["run"], name


def test_cli_output_is_always_redacted(jobs):
    # Never rely on GitHub masking (it failed in PR #56): every CLI call pipes
    # through ci/redact.py, or captures stderr to a file that is redacted, with
    # stdout going to a plan file parsed by ci/db_plan.py (which redacts too).
    for name, job in jobs.items():
        runs = _runs(job)
        for line in runs.splitlines():
            if CLI_CALL.search(line):
                piped = "| python3 ci/redact.py" in line
                captured = re.search(r"> (re)?plan\.json 2> (re)?plan\.err", line)
                assert piped or captured, (name, line)
                if captured:
                    err_file = captured.group(0).split("2> ")[1]
                    assert f"python3 ci/redact.py < {err_file}" in runs, (name, err_file)


def test_plan_and_apply_surface_cli_errors(jobs):
    # The CLI writes its JSON error to stdout (captured into the plan file) and
    # exits non-zero: keep going long enough for db_plan.py to print it.
    for n, plan_file in (("plan", "plan.json"), ("apply", "replan.json")):
        runs = _runs(jobs[n])
        assert re.search(rf"> {plan_file} 2> \w+\.err \|\| rc=\$\?", runs), n
        assert runs.index("|| rc=$?") < runs.index(f"ci/db_plan.py {plan_file}")
    assert 'exit "$rc"' in _runs(jobs["plan"])
    apply_runs = _runs(jobs["apply"])
    assert apply_runs.index('exit "$rc"') < apply_runs.index("supabase db push --include-all --yes")


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
