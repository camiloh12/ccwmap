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
