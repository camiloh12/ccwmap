import subprocess
import sys
from pathlib import Path

import pytest

from check_db_url import problems

ROOT = Path(__file__).resolve().parents[2]
PW = "Xy7%24q%3FLm9"  # percent-encoded password (decodes to Xy7$q?Lm9)
GOOD = f"postgresql://postgres.miihmfhnsfmwgrvgayns:{PW}@aws-1-us-east-1.pooler.supabase.com:5432/postgres"


def test_good_session_pooler_url_passes():
    assert problems(GOOD) == []


@pytest.mark.parametrize(
    "bad, reason",
    [
        ("", "empty"),
        (GOOD + " ", "whitespace"),
        (" " + GOOD, "whitespace"),
        (GOOD + "\n", "whitespace"),
        (GOOD.replace("@aws", "%40aws"), "exactly one '@'"),  # the mistake seen in Task 1
        (GOOD.replace(PW, "Xy7$q?Lm9"), "percent-encoded"),  # raw specials in the password
        (GOOD.replace(":5432/", ":6543/"), "5432"),  # transaction pooler breaks DDL
        (GOOD.replace("aws-1-us-east-1.pooler.supabase.com", "db.miihmfhnsfmwgrvgayns.supabase.co"), "pooler"),
        (GOOD.replace("postgresql://", "https://"), "postgres"),
        (GOOD.replace(f":{PW}@", "@"), "password"),
    ],
)
def test_bad_urls_are_rejected_with_a_reason(bad, reason):
    found = problems(bad)
    assert found, bad
    assert any(reason in p for p in found), found


def _run(url: str):
    return subprocess.run(
        [sys.executable, str(ROOT / "ci" / "check_db_url.py"), "STAGING_DB_URL"],
        env={"DB_URL": url, "SYSTEMROOT": "C:\\Windows", "PATH": ""},
        capture_output=True,
        text=True,
    )


def test_cli_passes_quietly_for_a_good_url():
    proc = _run(GOOD)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert PW not in proc.stdout + proc.stderr


@pytest.mark.parametrize(
    "bad",
    [
        GOOD + " ",
        GOOD.replace("@aws", "%40aws"),
        GOOD.replace(PW, "Xy7$q?Lm9"),
        GOOD.replace(":5432/", ":6543/"),
    ],
)
def test_cli_rejects_without_ever_printing_the_url(bad):
    proc = _run(bad)
    out = proc.stdout + proc.stderr
    assert proc.returncode == 1
    assert "::error::" in out and "STAGING_DB_URL" in out
    for leaked in ("postgresql://", PW, "Xy7$q?Lm9", "Xy7", "pooler.supabase.com:"):
        assert leaked not in out
