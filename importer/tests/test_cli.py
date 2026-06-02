import os
import subprocess
import sys

import pytest

from importer.cli import build_parser, main


def test_parser_accepts_dry_run_with_defaults() -> None:
    parser = build_parser()
    args = parser.parse_args([
        "--dry-run",
        "--states", "TX,FL,PA",
        "--sources", "hifld_courts",
        "--project-ref", "staging",
    ])
    assert args.dry_run is True
    assert args.states == ["TX", "FL", "PA"]
    assert args.sources == ["hifld_courts"]
    assert args.project_ref == "staging"


def test_parser_requires_confirmation_flag_for_apply() -> None:
    parser = build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args([
            "--apply",
            "--states", "TX",
            "--sources", "hifld_courts",
            "--project-ref", "prod",
            # Missing --i-know-this-writes-to-prod
        ])


def test_parser_rejects_unknown_source() -> None:
    parser = build_parser()
    with pytest.raises(SystemExit):
        parser.parse_args([
            "--dry-run",
            "--states", "TX",
            "--sources", "definitely_not_a_source",
            "--project-ref", "staging",
        ])


def test_main_returns_nonzero_on_missing_service_role_key(monkeypatch) -> None:
    monkeypatch.delenv("IMPORTER_SUPABASE_SERVICE_ROLE_KEY", raising=False)
    rc = main([
        "--dry-run",
        "--states", "TX",
        "--sources", "hifld_courts",
        "--project-ref", "staging",
    ])
    assert rc != 0


def test_supported_sources_includes_gsa_and_military():
    from importer.cli import SUPPORTED_SOURCES
    assert "gsa" in SUPPORTED_SOURCES
    assert "hifld_military" in SUPPORTED_SOURCES


def test_build_source_factory_constructs_each(tmp_path):
    from pathlib import Path
    from importer.cli import _build_source
    from importer.geo.states import load_state_locator
    fixtures = Path(__file__).parent / "fixtures"
    locator = load_state_locator(fixtures / "states_sample.geojson")
    config = {
        "sources": {
            "hifld_courts": {"cache_dir": "data/sources/hifld_courts", "dataset_version": "v", "url": "u"},
            "gsa": {"cache_dir": "data/sources/gsa", "dataset_version": "v", "url": "u"},
            "hifld_military": {"cache_dir": "data/sources/hifld_military", "dataset_version": "v", "url": "u"},
        }
    }
    for name in ("hifld_courts", "gsa", "hifld_military"):
        src = _build_source(name, config=config, locator=locator, repo_root=tmp_path)
        assert src.SOURCE_NAME == name


def test_module_entrypoint_actually_runs_main() -> None:
    # `python -m importer.cli ...` is the invocation used by every CI workflow,
    # the operator README, and the Task 19 smoke. Without an
    # `if __name__ == "__main__"` guard in cli.py, the module imports and exits
    # 0 without ever calling main() — a silent no-op that would make CI go green
    # while doing nothing. The other tests call main() directly and cannot catch
    # this, so exercise the real module-execution path via a subprocess.
    env = {k: v for k, v in os.environ.items() if k != "IMPORTER_SUPABASE_SERVICE_ROLE_KEY"}
    result = subprocess.run(
        [
            sys.executable, "-m", "importer.cli",
            "--dry-run",
            "--states", "TX",
            "--sources", "hifld_courts",
            "--project-ref", "staging",
        ],
        capture_output=True,
        text=True,
        env=env,
    )
    # main() reaches the missing-env-var guard and returns 2.
    assert result.returncode == 2
    assert "IMPORTER_SUPABASE_SERVICE_ROLE_KEY" in result.stderr
