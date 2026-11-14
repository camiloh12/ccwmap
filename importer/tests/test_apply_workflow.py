import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

WORKFLOW = (
    Path(__file__).resolve().parents[2] / ".github" / "workflows" / "importer-apply.yml"
)

BASH = shutil.which("bash")
needs_bash = pytest.mark.skipif(BASH is None, reason="runs the workflow's bash steps")

# Typed into a free-text input, this creates ./pwned if the value ever
# reaches the shell as script text instead of as data.
INJECTION = "$(touch pwned)"

DISPATCH = {
    "target": "staging",
    "confirm": "I-KNOW-THIS-WRITES-TO-STAGING",
    "sources": "gsa,faa",
    "states": "TX,FL",
    "delete_orphans": "false",
    "orphan_delete_cap": "",
}


def _steps() -> list:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))["jobs"]["apply"]["steps"]


def _step(marker: str) -> dict:
    (step,) = [s for s in _steps() if marker in s.get("run", "")]
    return step


def _render(text: str, inputs: dict) -> str:
    """What GitHub does before bash starts: paste each ${{ inputs.X }} in as raw text."""
    out = re.sub(r"\$\{\{\s*inputs\.(\w+)\s*\}\}", lambda m: inputs[m.group(1)], text)
    assert "${{" not in out, "this renderer only handles ${{ inputs.X }}"
    return out


def _run(step: dict, tmp_path: Path, **overrides) -> subprocess.CompletedProcess:
    inputs = {**DISPATCH, **overrides}
    env = {k: _render(str(v), inputs) for k, v in step.get("env", {}).items()}
    # Stand-in for the real importer: record the argv the step hands it.
    script = "uv() { printf '%s\\n' \"$@\" > uv-argv; }\n" + _render(step["run"], inputs)
    return subprocess.run(
        [BASH, "--noprofile", "--norc", "-eo", "pipefail", "-c", script],
        cwd=tmp_path,
        env={
            **os.environ,
            **env,
            "GITHUB_STEP_SUMMARY": (tmp_path / "summary.md").as_posix(),
            "GITHUB_WORKSPACE": tmp_path.as_posix(),
        },
        capture_output=True,
        text=True,
    )


def _argv(tmp_path: Path) -> list[str]:
    return (tmp_path / "uv-argv").read_text(encoding="utf-8").splitlines()


@needs_bash
def test_confirm_step_accepts_the_phrase_for_the_chosen_target(tmp_path):
    step = _step("Confirmation phrase")
    assert _run(step, tmp_path, target="prod", confirm="I-KNOW-THIS-WRITES-TO-PROD").returncode == 0


@needs_bash
def test_confirm_step_rejects_the_other_targets_phrase(tmp_path):
    step = _step("Confirmation phrase")
    result = _run(step, tmp_path, target="prod", confirm="I-KNOW-THIS-WRITES-TO-STAGING")
    assert result.returncode != 0
    assert "Confirmation phrase must be: I-KNOW-THIS-WRITES-TO-PROD" in result.stdout


@needs_bash
def test_confirm_text_is_never_run_as_shell(tmp_path):
    result = _run(_step("Confirmation phrase"), tmp_path, confirm=INJECTION)
    assert result.returncode != 0
    assert not (tmp_path / "pwned").exists()


@needs_bash
@pytest.mark.parametrize("target, other", [("staging", "prod"), ("prod", "staging")])
def test_apply_hands_each_input_to_the_cli_as_one_argument(tmp_path, target, other):
    result = _run(_step("importer.cli"), tmp_path, target=target, states="TX, FL", sources="gsa,faa")
    assert result.returncode == 0, result.stderr
    argv = _argv(tmp_path)
    assert argv[argv.index("--states") + 1] == "TX, FL"
    assert argv[argv.index("--sources") + 1] == "gsa,faa"
    assert argv[argv.index("--project-ref") + 1] == target
    assert f"--i-know-this-writes-to-{target}" in argv
    assert f"--i-know-this-writes-to-{other}" not in argv
    assert "--delete-orphans" not in argv


@needs_bash
@pytest.mark.parametrize("name", ["states", "sources"])
def test_apply_never_runs_states_or_sources_as_shell(tmp_path, name):
    _run(_step("importer.cli"), tmp_path, **{name: INJECTION})
    assert not (tmp_path / "pwned").exists()
    argv = _argv(tmp_path)
    # The payload reaches the CLI as plain text, where --states/--sources validation rejects it.
    assert argv[argv.index(f"--{name}") + 1] == INJECTION


def test_no_run_script_contains_an_expression():
    """GitHub pastes ${{ }} into the script before bash parses it, so any input
    there is shell code. Inputs reach run: scripts only through env:."""
    for step in _steps():
        assert "${{" not in step.get("run", ""), step.get("name")


def test_apply_workflow_parametrizes_sources_and_states():
    """The prod apply path must take sources/states as inputs, defaulting to
    the full 7-source pilot set — never a hardcoded single source."""
    raw = WORKFLOW.read_text(encoding="utf-8")

    # Must remain valid YAML.
    yaml.safe_load(raw)

    # Inputs declared.
    assert "sources:" in raw
    assert "states:" in raw

    # Default is the full pilot source set.
    assert "hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm" in raw

    # The old hardcoded line must be gone. That the CLI receives the inputs
    # is covered by test_apply_hands_each_input_to_the_cli_as_one_argument.
    assert "--sources hifld_courts" not in raw


def test_no_run_step_relies_on_importer_cwd_before_checkout():
    """Every `run:` step inherits `defaults.run.working-directory: importer`,
    but that directory does not exist on the runner until `actions/checkout`
    populates it. A `run:` step placed before checkout dies at bash startup
    with "No such file or directory" — exactly what the confirm-phrase
    guardrail hit on the first real prod dispatch (run 28748037747). Guarantee:
    any run step before checkout overrides working-directory to a path that
    exists pre-checkout (e.g. the workspace root)."""
    wf = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    job = wf["jobs"]["apply"]
    default_wd = job.get("defaults", {}).get("run", {}).get("working-directory")
    steps = job["steps"]

    checkout_idx = next(
        i for i, s in enumerate(steps)
        if str(s.get("uses", "")).startswith("actions/checkout")
    )

    for step in steps[:checkout_idx]:
        if "run" not in step:
            continue
        step_wd = step.get("working-directory", default_wd)
        assert step_wd not in (default_wd, "importer"), (
            f"Step {step.get('name')!r} runs before checkout but uses "
            f"working-directory {step_wd!r}, which does not exist yet."
        )


def test_delete_orphans_is_an_opt_in_checkbox():
    raw = WORKFLOW.read_text(encoding="utf-8")
    wf = yaml.safe_load(raw)
    inputs = wf[True]["workflow_dispatch"]["inputs"]  # PyYAML reads the `on:` key as True
    assert inputs["delete_orphans"]["type"] == "boolean"
    assert inputs["delete_orphans"]["default"] is False
    step = next(s for s in wf["jobs"]["apply"]["steps"] if "importer.cli" in s.get("run", ""))
    assert step["env"]["DELETE_ORPHANS"] == "${{ inputs.delete_orphans }}"
    assert '[ "$DELETE_ORPHANS" = "true" ]' in step["run"]
    assert "--delete-orphans" in step["run"]


def test_orphan_delete_cap_is_a_per_source_override_that_needs_delete_orphans():
    wf = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    inputs = wf[True]["workflow_dispatch"]["inputs"]
    assert (inputs["orphan_delete_cap"]["type"], inputs["orphan_delete_cap"]["default"]) == ("string", "")
    assert inputs["states"]["default"] == "TX,FL,PA"
    step = next(s for s in wf["jobs"]["apply"]["steps"] if "importer.cli" in s.get("run", ""))
    assert step["env"]["ORPHAN_DELETE_CAP"] == "${{ inputs.orphan_delete_cap }}"
    run = step["run"]
    assert '[ -n "$ORPHAN_DELETE_CAP" ]' in run
    assert '[ "$DELETE_ORPHANS" != "true" ]' in run
    assert "orphan_delete_cap needs delete_orphans" in run
    assert '--orphan-delete-cap "$ORPHAN_DELETE_CAP"' in run
    assert "GITHUB_STEP_SUMMARY" in run
    # Operator text reaches the shell only through env, never through ${{ }} in the script.
    assert "inputs.orphan_delete_cap" not in run
