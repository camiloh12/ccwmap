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
