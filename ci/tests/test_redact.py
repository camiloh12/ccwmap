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
    deploy = "Deployed Functions on project miihmfhnsfmwgrvgayns: send-moderation-email\n"
    assert redact(deploy, None, "sbp_fc" + "a" * 38) == deploy


def test_any_access_token_is_redacted_without_knowing_it():
    out = redact("Using token sbp_fc0123abcd_XYZ for deploy", None)
    assert out == "Using token <access-token> for deploy"


def test_exact_access_token_is_redacted_even_if_malformed():
    # A mis-pasted token (spaces, odd characters) escapes the sbp_ pattern and
    # GitHub's exact-string masking alike; the exact value must still go.
    token = " sbp_fc!!odd "
    out = redact(f"invalid access token format: {token.strip()}", None, token)
    assert "sbp_fc!!odd" not in out and "!!odd" not in out


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


def test_filter_mode_reads_access_token_from_env():
    proc = subprocess.run(
        [sys.executable, str(ROOT / "ci" / "redact.py")],
        input="x tok-not-sbp-shaped y\n",
        env={"SUPABASE_ACCESS_TOKEN": "tok-not-sbp-shaped", "SYSTEMROOT": "C:\\Windows", "PATH": ""},
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout == "x *** y\n"
