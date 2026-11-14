import json
import urllib.error

import functions_smoke as fs

ENV = {"HEALTH_URL": "https://example.test/functions/v1/send-moderation-email/health", "ANON_KEY": "anon-secret-xyz"}
# What send-moderation-email's /health returns when Brevo rejects the key or it is unset
# (supabase/functions/send-moderation-email/index.ts healthCheck): HTTP 500, never 401.
BREVO_REJECTED = json.dumps({"ok": False, "check": "brevo-account", "status": 401, "error": "Key not found"}).encode()
BREVO_UNSET = json.dumps({"ok": False, "error": "BREVO_API_KEY secret is not set"}).encode()


class FakeGet:
    """Stands in for the HTTP helper: replays canned replies (or raises them)."""

    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = []

    def __call__(self, url, headers):
        self.calls.append((url, headers))
        reply = self.replies.pop(0) if len(self.replies) > 1 else self.replies[0]
        if isinstance(reply, Exception):
            raise reply
        return reply


def test_diagnose_ok_is_none():
    assert fs.diagnose(200, b'{"ok":true}') is None


def test_diagnose_gateway_401_names_anon_key_not_brevo():
    message = fs.diagnose(401, b'{"msg":"Invalid JWT"}')
    assert "SUPABASE_ANON_KEY" in message
    assert "BREVO" not in message


def test_diagnose_brevo_failure_names_brevo_key():
    for body in (BREVO_REJECTED, BREVO_UNSET):
        message = fs.diagnose(500, body)
        assert "BREVO_API_KEY" in message and "deploy is fine" in message


def test_diagnose_other_failure_points_at_function_logs():
    for status, body in ((503, b'{"code":"BOOT_ERROR"}'), (500, b"error: boom")):
        message = fs.diagnose(status, body)
        assert "Logs" in message and "BREVO" not in message


def test_diagnose_network_failure():
    assert "could not reach" in fs.diagnose(0, b"")


def test_main_retries_until_healthy():
    get = FakeGet([(503, b"booting"), (200, b'{"ok":true}')])
    sleeps = []
    assert fs.main(env=ENV, get=get, sleep=sleeps.append) == 0
    assert len(get.calls) == 2 and sleeps == [10]
    assert get.calls[0][1]["Authorization"] == "Bearer anon-secret-xyz"


def test_main_reports_the_diagnosis_after_three_failures(capsys):
    get = FakeGet([(500, BREVO_REJECTED)])
    sleeps = []
    assert fs.main(env=ENV, get=get, sleep=sleeps.append) == 1
    assert len(get.calls) == 3 and sleeps == [10, 10]
    out = capsys.readouterr().out
    errors = [line for line in out.splitlines() if line.startswith("::error::")]
    assert len(errors) == 1 and "HTTP 500" in errors[0] and "BREVO_API_KEY" in errors[0]


def test_main_treats_network_errors_as_unreachable(capsys):
    get = FakeGet([urllib.error.URLError("dns failure")])
    assert fs.main(env=ENV, get=get, sleep=lambda s: None) == 1
    assert "could not reach" in capsys.readouterr().out


def test_main_never_prints_the_anon_key(capsys):
    get = FakeGet([(401, b'{"msg":"Invalid JWT"}')])
    fs.main(env=ENV, get=get, sleep=lambda s: None)
    assert "anon-secret-xyz" not in capsys.readouterr().out


def test_main_requires_its_env(capsys):
    assert fs.main(env={}, get=FakeGet([(200, b"")]), sleep=lambda s: None) == 1
    assert "::error::" in capsys.readouterr().out
