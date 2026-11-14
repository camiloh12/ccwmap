import json
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "resolve-pin-report.yml"


@pytest.fixture(scope="module")
def wf() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


def _steps(wf) -> list:
    (job,) = wf["jobs"].values()
    return job["steps"]


def _run_step(wf) -> dict:
    (step,) = [s for s in _steps(wf) if "ci/resolve_pin_report.py" in s.get("run", "")]
    return step


def test_name(wf):
    assert wf["name"] == "Resolve pin report"


def test_manual_trigger_with_inputs(wf):
    on = wf.get("on", wf.get(True))
    assert set(on) == {"workflow_dispatch"}
    inputs = on["workflow_dispatch"]["inputs"]
    assert set(inputs) == {"target", "confirm", "report_id", "action", "latitude", "longitude"}
    assert inputs["target"]["type"] == "choice" and inputs["target"]["options"] == ["staging", "prod"]
    assert inputs["action"]["type"] == "choice" and inputs["action"]["options"] == ["remove", "move", "dismiss"]


def test_permissions_read_only(wf):
    assert wf["permissions"] == {"contents": "read"}


def test_serialized_per_target(wf):
    assert "inputs.target" in wf["concurrency"]["group"]
    assert wf["concurrency"]["cancel-in-progress"] is False


def test_no_input_interpolated_into_run(wf):
    for step in _steps(wf):
        assert "${{" not in step.get("run", ""), step


def test_each_target_sees_only_its_own_key(wf):
    env = _run_step(wf)["env"]
    assert env["PROD_SERVICE_ROLE_KEY"] == (
        "${{ inputs.target == 'prod' && secrets.PROD_SUPABASE_SERVICE_ROLE_KEY || '' }}"
    )
    assert env["STAGING_SERVICE_ROLE_KEY"] == (
        "${{ inputs.target == 'staging' && secrets.STAGING_SUPABASE_SERVICE_ROLE_KEY || '' }}"
    )
    assert "secrets" not in json.dumps({k: v for k, v in wf.items() if k != "jobs"})


def test_inputs_reach_the_script_via_env(wf):
    env = _run_step(wf)["env"]
    for k, i in [("TARGET", "target"), ("CONFIRM", "confirm"), ("REPORT_ID", "report_id"),
                 ("ACTION", "action"), ("LATITUDE", "latitude"), ("LONGITUDE", "longitude")]:
        assert env[k] == "${{ inputs.%s }}" % i


def test_runs_the_script(wf):
    steps = _steps(wf)
    checkout = [i for i, s in enumerate(steps) if s.get("uses", "").startswith("actions/checkout@")]
    run = steps.index(_run_step(wf))
    assert checkout and checkout[0] < run
    assert _run_step(wf)["run"].strip().startswith("python3 ci/resolve_pin_report.py")
