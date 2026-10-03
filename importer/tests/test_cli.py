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


def test_supported_sources_includes_all_phase4_and_phase5():
    from importer.cli import SUPPORTED_SOURCES
    for name in ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa"):
        assert name in SUPPORTED_SOURCES


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
            "nces": {"cache_dir": "data/sources/nces", "dataset_version": "v", "url": "u", "directory_url": "d"},
            "ipeds": {"cache_dir": "data/sources/ipeds", "dataset_version": "v", "url": "u"},
            "faa": {"cache_dir": "data/sources/faa", "dataset_version": "v", "url": "u", "nasr_url": "n"},
        }
    }
    for name in ("hifld_courts", "gsa", "hifld_military", "nces", "ipeds", "faa"):
        src = _build_source(name, config=config, locator=locator, repo_root=tmp_path)
        assert src.SOURCE_NAME == name


def test_osm_is_a_supported_source():
    from importer.cli import SUPPORTED_SOURCES
    assert "osm" in SUPPORTED_SOURCES


def test_build_source_constructs_osm(tmp_path):
    import yaml
    from pathlib import Path
    from importer.cli import _build_source, CONFIG_PATH, STATES_BOUNDARY_FIXTURE, STATES_YAML
    from importer.geo.states import load_state_locator
    from importer.state_laws import load_state_laws
    from importer.sources.osm import OsmSource

    config = yaml.safe_load(Path(CONFIG_PATH).read_text(encoding="utf-8"))
    locator = load_state_locator(STATES_BOUNDARY_FIXTURE)
    laws = load_state_laws(STATES_YAML)
    src = _build_source(
        "osm", config=config, locator=locator, repo_root=tmp_path,
        state_laws=laws, states=["TX", "FL", "PA"],
    )
    assert isinstance(src, OsmSource)
    assert src.SOURCE_NAME == "osm"


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


def test_prod_project_ref_is_configured_not_placeholder():
    """The prod target must be a real Supabase ref before any prod apply.
    A leftover REPLACE-WITH-PROD-PROJECT-REF builds a garbage URL that
    silently points at a non-existent host."""
    import yaml
    from pathlib import Path
    from importer.cli import CONFIG_PATH

    config = yaml.safe_load(Path(CONFIG_PATH).read_text(encoding="utf-8"))
    prod = config["projects"]["prod"]
    assert prod["project_ref"] == "gqbxloaqamokbolcvesg"
    assert prod["url"] == "https://gqbxloaqamokbolcvesg.supabase.co"
    assert "REPLACE-WITH" not in prod["project_ref"]
    assert "REPLACE-WITH" not in prod["url"]


def test_main_errors_on_placeholder_project_url(monkeypatch):
    """If a project url is ever re-blanked to a placeholder, main() must
    refuse to run rather than build a client against a non-existent host."""
    import importer.cli as cli

    monkeypatch.setenv("IMPORTER_SUPABASE_SERVICE_ROLE_KEY", "dummy")
    monkeypatch.setattr(cli, "_load_config", lambda: {
        "system_user_id": "x",
        "projects": {
            "prod": {
                "project_ref": "REPLACE-WITH-PROD-PROJECT-REF",
                "url": "https://REPLACE-WITH-PROD-PROJECT-REF.supabase.co",
            }
        },
        "sources": {},
    })
    rc = cli.main([
        "--dry-run", "--states", "TX",
        "--sources", "hifld_courts", "--project-ref", "prod",
    ])
    assert rc == 2


def test_build_source_wires_military_site_points(tmp_path):
    from pathlib import Path
    from importer.cli import _build_source
    from importer.geo.states import load_state_locator

    locator = load_state_locator(Path(__file__).parent / "fixtures" / "states_sample.geojson")
    config = {"sources": {"hifld_military": {
        "cache_dir": "data/sources/hifld_military", "dataset_version": "v",
        "url": "u", "points_url": "p",
    }}}
    src = _build_source("hifld_military", config=config, locator=locator, repo_root=tmp_path)
    assert src._points_url == "p"
    assert src._points_cache_path == tmp_path / "data/sources/hifld_military" / "military_points.geojson"


def test_config_pins_the_mirta_site_points_layer():
    import yaml
    from pathlib import Path
    from importer.cli import CONFIG_PATH

    cfg = yaml.safe_load(Path(CONFIG_PATH).read_text(encoding="utf-8"))["sources"]["hifld_military"]
    assert cfg["points_url"].endswith(
        "/mirta/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson"
    )


APPLY_STAGING = ["--apply", "--states", "TX", "--sources", "gsa",
                 "--project-ref", "staging", "--i-know-this-writes-to-staging"]


def test_parser_accepts_orphan_flags_with_apply() -> None:
    args = build_parser().parse_args(APPLY_STAGING + ["--delete-orphans", "--orphan-delete-cap", "7"])
    assert args.delete_orphans is True
    assert args.orphan_delete_cap == 7


def test_parser_rejects_delete_orphans_with_dry_run() -> None:
    with pytest.raises(SystemExit):
        build_parser().parse_args([
            "--dry-run", "--states", "TX", "--sources", "gsa",
            "--project-ref", "staging", "--delete-orphans",
        ])


def test_parser_rejects_a_negative_cap() -> None:
    with pytest.raises(SystemExit):
        build_parser().parse_args(APPLY_STAGING + ["--orphan-delete-cap", "-1"])


class _FakeClient:
    def __init__(self):
        self.updates = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return None

    def insert_import_run(self, **kw):
        return "run-1"

    def update_import_run(self, **kw):
        self.updates.append(kw)


def _fake_main(monkeypatch, run_pipeline):
    import importer.cli as cli

    monkeypatch.setenv("IMPORTER_SUPABASE_SERVICE_ROLE_KEY", "dummy")
    fake = _FakeClient()
    monkeypatch.setattr(cli, "SupabaseClient", lambda **kw: fake)
    monkeypatch.setattr(cli, "_build_source", lambda name, **kw: object())
    monkeypatch.setattr(cli, "run_pipeline", run_pipeline)
    return cli, fake


def test_main_passes_orphan_flags_and_records_counts(monkeypatch, tmp_path) -> None:
    from datetime import datetime, timezone
    from importer.reports import DedupReport, PipelineResult, SourceResult
    from importer.stages.diff import DiffResult
    from importer.stages.orphans import OrphanPlan
    from importer.supabase_client import ExistingPinRow

    kept = ExistingPinRow(id="k", source="gsa", source_external_id="E", name="N", latitude=30.0,
                          longitude=-97.0, status=2, restriction_tag="FEDERAL_PROPERTY",
                          user_modified=True, source_dataset_version="v")
    captured = {}

    def fake_run(**kw):
        captured.update(kw)
        return PipelineResult(
            mode="apply", started_at=datetime.now(timezone.utc), completed_at=None,
            states=["TX"], dedup=DedupReport(),
            sources=[SourceResult(source="gsa", candidates_fetched=1, candidates_after_state_filter=1,
                                  classified=1, dropped_no_cell=0, missing_cells=[], name_truncations=0,
                                  diff=DiffResult(inserts=[], updates=[], skips=[], orphans=[kept]),
                                  orphan_plan=OrphanPlan(keep=[kept]))],
        )

    cli, fake = _fake_main(monkeypatch, fake_run)
    rc = cli.main(APPLY_STAGING + ["--delete-orphans", "--orphan-delete-cap", "7",
                                   "--report-out", str(tmp_path / "r.md")])
    assert rc == 0
    assert captured["delete_orphans"] is True
    assert captured["orphan_delete_cap"] == 7
    assert captured["state_locator"] is not None
    assert fake.updates[-1]["orphans_marked"] == 1


def test_main_exits_1_and_records_a_cap_breach(monkeypatch, tmp_path) -> None:
    from importer.stages.orphans import OrphanCapExceeded

    def breach(**kw):
        raise OrphanCapExceeded("gsa: 300 orphan deletions exceed the cap of 211; nothing was written")

    cli, fake = _fake_main(monkeypatch, breach)
    rc = cli.main(APPLY_STAGING + ["--delete-orphans", "--report-out", str(tmp_path / "r.md")])
    assert rc == 1
    assert "exceed the cap" in fake.updates[-1]["errors_json"]["message"]
