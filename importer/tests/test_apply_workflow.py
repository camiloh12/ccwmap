from pathlib import Path

import yaml

WORKFLOW = (
    Path(__file__).resolve().parents[2] / ".github" / "workflows" / "importer-apply.yml"
)


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

    # The run step references the inputs, not a hardcoded source.
    assert "${{ inputs.sources }}" in raw
    assert "${{ inputs.states }}" in raw

    # The old hardcoded line must be gone.
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
