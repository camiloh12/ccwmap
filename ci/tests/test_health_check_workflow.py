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
