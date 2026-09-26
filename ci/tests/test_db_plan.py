import json
from pathlib import Path

import pytest

from db_plan import Plan, PlanError, main, parse_plan, summary_markdown

FIXTURES = Path(__file__).parent / "fixtures"

UP_TO_DATE = (
    '{"_tag":"Success","message":"Remote database is up to date.",'
    '"data":{"upToDate":true,"dryRun":true,"migrations":[],"seeds":[],"roles":[]}}'
)
PENDING = (
    '{"_tag":"Success","message":"Finished supabase db push.",'
    '"data":{"upToDate":false,"dryRun":true,'
    '"migrations":["011_location_geography_parity.sql","012_system_pins_user_correctable.sql"],'
    '"seeds":[],"roles":[]}}'
)


def test_real_up_to_date_output():
    plan = parse_plan((FIXTURES / "dryrun_up_to_date.json").read_text(encoding="utf-8"))
    assert plan == Plan(pending=False, migrations=())


def test_real_pending_output():
    plan = parse_plan((FIXTURES / "dryrun_pending.json").read_text(encoding="utf-8"))
    assert plan == Plan(pending=True, migrations=("012_system_pins_user_correctable.sql",))


def test_pending_keeps_cli_order():
    assert parse_plan(PENDING).migrations == (
        "011_location_geography_parity.sql",
        "012_system_pins_user_correctable.sql",
    )


def test_envelope_agnostic():
    # The result object may be top-level or nested; only `upToDate` matters.
    assert parse_plan('{"upToDate": true, "migrations": []}').pending is False


def test_error_envelope_is_a_plan_error():
    err = (
        '{"_tag":"Error","error":{"code":"DbConnectError",'
        '"message":"failed to connect to postgres"}}'
    )
    with pytest.raises(PlanError, match="DbConnectError"):
        parse_plan(err)


def test_noise_before_json_is_ignored():
    text = "A new version of Supabase CLI is available: v9.9.9\n" + UP_TO_DATE + "\n"
    assert parse_plan(text).pending is False


def test_no_json_is_a_plan_error():
    with pytest.raises(PlanError):
        parse_plan("Connecting to remote database...\n")


def test_missing_up_to_date_is_a_plan_error():
    with pytest.raises(PlanError):
        parse_plan('{"_tag":"Success","data":{"migrations":[]}}')


def test_pending_without_migrations_is_a_plan_error():
    with pytest.raises(PlanError):
        parse_plan('{"upToDate": false, "migrations": []}')


def test_summary_lists_pending_in_order():
    md = summary_markdown(parse_plan(PENDING))
    assert "### Pending for prod" in md
    assert md.index("011_location_geography_parity.sql") < md.index(
        "012_system_pins_user_correctable.sql"
    )


def test_summary_when_up_to_date():
    assert "Nothing pending" in summary_markdown(parse_plan(UP_TO_DATE))


def test_main_writes_outputs_and_summary(tmp_path, monkeypatch):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(PENDING, encoding="utf-8")
    out, summ = tmp_path / "out", tmp_path / "summary"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summ))

    assert main([str(plan_file)]) == 0
    assert out.read_text(encoding="utf-8").splitlines() == [
        "pending=true",
        "migrations=011_location_geography_parity.sql 012_system_pins_user_correctable.sql",
    ]
    assert "012_system_pins_user_correctable.sql" in summ.read_text(encoding="utf-8")


def test_main_error_output_exits_1(tmp_path, capsys):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text('{"_tag":"Error","error":{"code":"X","message":"boom"}}', encoding="utf-8")
    assert main([str(plan_file)]) == 1
    assert "::error::" in capsys.readouterr().out


def _error_file(tmp_path, message: str) -> Path:
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(
        json.dumps({"_tag": "Error", "error": {"code": "DbConfigParseUrlError", "message": message}}),
        encoding="utf-8",
    )
    return plan_file


def test_error_output_redacts_db_url(tmp_path, capsys):
    # The CLI echoes the whole connection string in some errors. The runner
    # unescapes %25 in workflow commands BEFORE masking, so a percent-encoded
    # password would slip past GitHub's secret masking — never print the URL.
    url = "postgresql://postgres.ref:pa%25ss%40word@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
    plan_file = _error_file(tmp_path, f"failed to parse connection string: {url}")
    assert main([str(plan_file)]) == 1
    out = capsys.readouterr().out
    assert "<db-url>" in out
    for leaked in ("postgresql://", "pa%25ss", "pa%ss", "word@aws"):
        assert leaked not in out


def test_error_output_redacts_password_keyword(tmp_path, capsys):
    plan_file = _error_file(tmp_path, "connect failed: host=db.x user=postgres password=hunter2 dbname=postgres")
    assert main([str(plan_file)]) == 1
    out = capsys.readouterr().out
    assert "hunter2" not in out
    assert "password=<redacted>" in out


def test_error_output_is_one_escaped_workflow_command(tmp_path, capsys):
    plan_file = _error_file(tmp_path, "100% broken\r\nsecond line")
    assert main([str(plan_file)]) == 1
    lines = capsys.readouterr().out.strip().splitlines()
    assert len(lines) == 1
    assert lines[0].startswith("::error::")
    assert "100%25 broken%0D%0Asecond line" in lines[0]


def test_expect_match_passes(tmp_path):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(PENDING, encoding="utf-8")
    expected = "011_location_geography_parity.sql 012_system_pins_user_correctable.sql"
    assert main([str(plan_file), "--expect", expected]) == 0


def test_expect_mismatch_fails(tmp_path, capsys):
    plan_file = tmp_path / "plan.json"
    plan_file.write_text(PENDING, encoding="utf-8")
    assert main([str(plan_file), "--expect", "012_system_pins_user_correctable.sql"]) == 1
    assert "changed since approval" in capsys.readouterr().out
