import subprocess
import sys
from pathlib import Path

from redact import redact

ROOT = Path(__file__).resolve().parents[2]

PASSWORD_ENC = "ab%24cd%3Fef"  # decodes to ab$cd?ef
URL = f"postgresql://postgres.ref:{PASSWORD_ENC}@aws-1-us-east-1.pooler.supabase.com:5432/postgres"


def test_exact_secret_is_redacted_even_with_surrounding_whitespace():
    # A mis-pasted secret (trailing space) broke GitHub's masking in PR #56.
    secret = URL + " "
    out = redact(f"failed to parse connection string: {secret}", secret)
    assert PASSWORD_ENC not in out and "ab$cd?ef" not in out
    assert "postgresql://" not in out


def test_decoded_password_is_redacted():
    out = redact("auth failed for password ab$cd?ef", URL)
    assert "ab$cd?ef" not in out


def test_any_db_url_is_redacted_without_knowing_the_secret():
    out = redact(f"failed to parse connection string: {URL}", None)
    assert out == "failed to parse connection string: <db-url>"


def test_password_keyword_is_redacted():
    assert redact("host=x password=hunter2 user=y", None) == "host=x password=<redacted> user=y"


def test_ordinary_output_is_untouched():
    text = "Applying migration 012_system_pins_user_correctable.sql...\n   LOCAL | REMOTE\n"
    assert redact(text, URL) == text


def test_filter_mode_reads_db_url_from_env(tmp_path):
    proc = subprocess.run(
        [sys.executable, str(ROOT / "ci" / "redact.py")],
        input=f"error: {URL}\nnext line\n",
        env={"DB_URL": URL, "SYSTEMROOT": "C:\\Windows", "PATH": ""},
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert PASSWORD_ENC not in proc.stdout
    assert "next line" in proc.stdout
