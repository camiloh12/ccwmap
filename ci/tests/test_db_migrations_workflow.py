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
