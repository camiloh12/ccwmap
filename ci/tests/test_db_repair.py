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
    migrations_setup = next(
        s["uses"]
        for j in migrations["jobs"].values()
        for s in j.get("steps", [])
        if str(s.get("uses", "")).startswith("supabase/setup-cli")
    )
    for job in wf["jobs"].values():
        setup = [s for s in job["steps"] if str(s.get("uses", "")).startswith("supabase/setup-cli")]
        assert setup and setup[0]["uses"] == migrations_setup  # same SHA pin
        assert setup[0]["with"]["version"] == "${{ env.SUPABASE_CLI_VERSION }}"


def test_db_url_only_on_repair_step(wf):
    for name, job in wf["jobs"].items():
        assert "DB_URL" not in json.dumps(job.get("env", {})), name
        for step in job["steps"]:
            has_url = "DB_URL" in json.dumps(step.get("env", {}))
            assert has_url == ("ci/db_repair.sh" in step.get("run", "")), (name, step.get("name"))
