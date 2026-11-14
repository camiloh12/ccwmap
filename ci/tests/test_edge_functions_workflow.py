import json
from pathlib import Path

import pytest
import yaml

import functions_preflight

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
WORKFLOW = WORKFLOWS / "edge-functions.yml"
DEPLOY_JOBS = ("staging-pr", "staging", "prod")
TARGET = {"staging-pr": "staging", "staging": "staging", "prod": "prod"}
GROUPS = {
    "staging-pr": "functions-staging",
    "staging": "functions-staging-deploy",
    "prod": "functions-prod-deploy",
}
STAGING_TOKEN = "STAGING_SUPABASE_ACCESS_TOKEN"
PROD_TOKEN = "PROD_SUPABASE_ACCESS_TOKEN"
PROD_REF = functions_preflight.PROJECT_REFS["prod"]


def _on(wf: dict) -> dict:
    # PyYAML (YAML 1.1) parses the bare key `on` as boolean True.
    return wf.get("on", wf.get(True))


def _text(obj) -> str:
    return json.dumps(obj)


def _runs(job: dict) -> str:
    return "\n".join(step.get("run", "") for step in job.get("steps", []))


def _step(job: dict, needle: str) -> dict:
    matches = [s for s in job["steps"] if needle in s.get("run", "")]
    assert len(matches) == 1, (needle, [s.get("name") for s in matches])
    return matches[0]


def _deploy_step(job: dict) -> dict:
    return _step(job, "supabase functions deploy")


@pytest.fixture(scope="module")
def wf() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def jobs(wf) -> dict:
    return wf["jobs"]


def test_triggers(wf):
    on = _on(wf)
    assert on["pull_request"]["branches"] == ["master"]
    assert set(on["pull_request"]["paths"]) == {
        "supabase/functions/**",
        ".github/workflows/edge-functions.yml",
        "ci/**",
    }
    assert on["push"]["branches"] == ["master"]
    assert on["push"]["paths"] == ["supabase/functions/**"]
    assert "workflow_dispatch" in on


def test_permissions_read_only(wf):
    assert wf["permissions"] == {"contents": "read"}


def test_shell_uses_pipefail(wf):
    # Default bash on Actions is `bash -e` (no pipefail): a failing deploy piped
    # through ci/redact.py would otherwise pass.
    assert wf["defaults"] == {"run": {"shell": "bash"}}


def test_pr_jobs_never_touch_prod(jobs):
    pr_jobs = {n for n, j in jobs.items() if j.get("if") == "github.event_name == 'pull_request'"}
    assert pr_jobs == {"workflow-tests", "staging-pr"}
    for n in pr_jobs:
        assert "environment" not in jobs[n]
        assert PROD_TOKEN not in _text(jobs[n])
        assert PROD_REF not in _text(jobs[n])


def test_deploy_jobs_never_run_on_pull_request(jobs):
    for n in ("staging", "prod"):
        assert "github.event_name != 'pull_request'" in jobs[n]["if"]


def test_prod_token_only_in_the_gated_prod_job(jobs):
    holders = {n for n, j in jobs.items() if PROD_TOKEN in _text(j)}
    assert holders == {"prod"}
    prod = jobs["prod"]
    assert prod["environment"] == "production"
    assert prod["needs"] == "staging"
    assert STAGING_TOKEN not in _text(prod)


def test_tokens_only_on_preflight_and_deploy_steps(jobs):
    for name, job in jobs.items():
        assert "ACCESS_TOKEN" not in _text(job.get("env", {})), name
        for step in job.get("steps", []):
            has_token = "SUPABASE_ACCESS_TOKEN" in _text(step.get("env", {}))
            run = step.get("run", "")
            needs_token = "ci/functions_preflight.py" in run or "supabase functions deploy" in run
            assert has_token == needs_token, (name, step.get("name"))


def test_preflight_runs_before_deploy(jobs):
    for n in DEPLOY_JOBS:
        steps = jobs[n]["steps"]
        preflight = _step(jobs[n], "ci/functions_preflight.py")
        deploy = _deploy_step(jobs[n])
        assert preflight.get("id") == "preflight", n
        assert steps.index(preflight) < steps.index(deploy), n
        assert deploy["env"]["FUNCTIONS"] == "${{ steps.preflight.outputs.functions }}", n


def test_project_refs_match_preflight(jobs):
    for n in DEPLOY_JOBS:
        target = TARGET[n]
        assert _deploy_step(jobs[n])["env"]["PROJECT_REF"] == functions_preflight.PROJECT_REFS[target], n
        assert f"ci/functions_preflight.py {target}" in _step(jobs[n], "ci/functions_preflight.py")["run"], n
        token = PROD_TOKEN if target == "prod" else STAGING_TOKEN
        for step in (_step(jobs[n], "ci/functions_preflight.py"), _deploy_step(jobs[n])):
            assert step["env"]["SUPABASE_ACCESS_TOKEN"] == f"${{{{ secrets.{token} }}}}", n


def test_deploy_command_is_safe(wf, jobs):
    for n in DEPLOY_JOBS:
        lines = [l for l in _runs(jobs[n]).splitlines() if "supabase functions deploy" in l]
        assert lines, n
        for line in lines:
            assert "--use-api" in line, line
            assert '--project-ref "$PROJECT_REF"' in line, line
            assert "| python3 ci/redact.py" in line, line
    text = WORKFLOW.read_text(encoding="utf-8")
    for banned in ("--prune", "--no-verify-jwt", "supabase link"):
        assert banned not in text, banned
    # A config file could change how the CLI behaves in the DB workflows too.
    assert not (ROOT / "supabase" / "config.toml").exists()


def test_deploy_loop_stops_at_the_first_failure(jobs):
    for n in DEPLOY_JOBS:
        assert _deploy_step(jobs[n])["run"].lstrip().startswith("set -euo pipefail"), n


def test_no_expressions_inside_run(jobs):
    for name, job in jobs.items():
        for step in job.get("steps", []):
            assert "${{" not in step.get("run", ""), (name, step.get("name"))


def test_cli_pin_matches_db_migrations(wf, jobs):
    migrations = yaml.safe_load((WORKFLOWS / "db-migrations.yml").read_text(encoding="utf-8"))
    assert wf["env"]["SUPABASE_CLI_VERSION"] == migrations["env"]["SUPABASE_CLI_VERSION"]
    migrations_setup = next(
        s["uses"]
        for j in migrations["jobs"].values()
        for s in j.get("steps", [])
        if str(s.get("uses", "")).startswith("supabase/setup-cli")
    )
    for n in DEPLOY_JOBS:
        setups = [s for s in jobs[n]["steps"] if str(s.get("uses", "")).startswith("supabase/setup-cli")]
        assert len(setups) == 1, n
        assert setups[0]["uses"] == migrations_setup, n
        assert setups[0]["with"]["version"] == "${{ env.SUPABASE_CLI_VERSION }}", n


def test_concurrency_never_cancels_and_is_own(jobs):
    for n, group in GROUPS.items():
        c = jobs[n]["concurrency"]
        assert c["group"] == group, n
        assert c["cancel-in-progress"] is False, n
    for other in ("db-migrations.yml", "db-repair.yml"):
        other_jobs = yaml.safe_load((WORKFLOWS / other).read_text(encoding="utf-8"))["jobs"]
        for name, job in other_jobs.items():
            assert (job.get("concurrency") or {}).get("group") not in GROUPS.values(), (other, name)


def test_smoke_check_after_prod_deploy(jobs):
    prod = jobs["prod"]
    smoke = prod["steps"][-1]
    steps = prod["steps"]
    assert steps.index(_deploy_step(prod)) < steps.index(smoke)
    env = smoke["env"]
    assert PROD_REF in env["HEALTH_URL"]
    assert env["HEALTH_URL"].endswith("/send-moderation-email/health")
    assert env["ANON_KEY"] == "${{ secrets.SUPABASE_ANON_KEY }}"
    assert "ACCESS_TOKEN" not in _text(smoke)


def test_smoke_check_uses_the_diagnosing_script(jobs):
    # Retries and the cause-specific error (anon key vs Brevo vs the function)
    # live in ci/functions_smoke.py, unit-tested in test_functions_smoke.py.
    assert jobs["prod"]["steps"][-1]["run"].strip() == "python3 ci/functions_smoke.py"
