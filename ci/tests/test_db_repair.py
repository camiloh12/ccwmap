import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "ci" / "db_repair.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "db-repair.yml"
MIGRATIONS_WORKFLOW = ROOT / ".github" / "workflows" / "db-migrations.yml"
BASH = shutil.which("bash")
STUB_URL = "postgresql://postgres.ref:s3cr%24tPass@aws-1-x.pooler.supabase.com:5432/postgres"


def _on(wf: dict) -> dict:
    return wf.get("on", wf.get(True))


# ---------- ci/db_repair.sh (with a stub `supabase` on PATH) ----------


@pytest.fixture
def run_script(tmp_path):
    if BASH is None:
        pytest.skip("bash not available")
    log = tmp_path / "calls.log"
    stub = tmp_path / "supabase"
    # The stub echoes the DB URL to stderr, like a real CLI connection error.
    stub.write_text(
        '#!/usr/bin/env bash\necho "$*" >> "$STUB_LOG"\necho "LOCAL | REMOTE"\n'
        'echo "failed to connect: $DB_URL" >&2\n',
        encoding="utf-8",
    )
    stub.chmod(0o755)
    summary = tmp_path / "summary.md"

    def run(action: str, versions: str = ""):
        env = {
            **os.environ,
            "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
            "STUB_LOG": str(log),
            "DB_URL": STUB_URL,
            "GITHUB_STEP_SUMMARY": str(summary),
            "PYTHON": sys.executable,
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
    assert calls == [f"migration list --db-url {STUB_URL}"]
    assert "LOCAL | REMOTE" in summary.read_text(encoding="utf-8")


def test_applied_marks_versions_then_lists(run_script):
    proc, calls, _ = run_script("applied", "000 004 005")
    assert proc.returncode == 0, proc.stderr
    assert calls == [
        f"migration repair --status applied 000 004 005 --db-url {STUB_URL}",
        f"migration list --db-url {STUB_URL}",
    ]


def test_commas_and_spaces_are_accepted(run_script):
    proc, calls, _ = run_script("reverted", " 20260705144447,20260705144509  010 ")
    assert proc.returncode == 0, proc.stderr
    assert calls[0] == (
        "migration repair --status reverted 20260705144447 20260705144509 010 "
        f"--db-url {STUB_URL}"
    )


def test_cli_output_never_contains_the_db_url(run_script):
    # The stub echoes DB_URL on stderr, like a real CLI error. The script must
    # redact it from its own output and from the step summary.
    for action, versions in (("list", ""), ("applied", "008")):
        proc, _, summary = run_script(action, versions)
        assert proc.returncode == 0, proc.stderr
        published = proc.stdout + proc.stderr + summary.read_text(encoding="utf-8")
        for leaked in (STUB_URL, "s3cr%24tPass", "s3cr$tPass", "postgresql://"):
            assert leaked not in published, (action, leaked)


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


def test_db_url_only_on_check_and_repair_steps(wf):
    for name, job in wf["jobs"].items():
        assert "DB_URL" not in json.dumps(job.get("env", {})), name
        db_steps = []
        for step in job["steps"]:
            run = step.get("run", "")
            has_url = "DB_URL" in json.dumps(step.get("env", {}))
            assert has_url == ("ci/db_repair.sh" in run or "ci/check_db_url.py" in run), (name, step.get("name"))
            if has_url:
                db_steps.append(run)
        # The URL's shape is checked before the CLI ever sees it.
        assert "ci/check_db_url.py" in db_steps[0], name


def test_repair_shell_uses_pipefail(wf):
    assert wf["defaults"] == {"run": {"shell": "bash"}}
