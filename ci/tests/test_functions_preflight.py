import json
import urllib.error

import pytest

import functions_preflight as fp

SCOPED = "sbp_fc" + "a" * 38
CLASSIC = "sbp_" + "a" * 40


class FakeGet:
    """Stands in for fp._http_get: records calls, returns a canned reply."""

    def __init__(self, status: int = 200, body: object = ()):
        self.status = status
        self.body = body if isinstance(body, bytes) else json.dumps(list(body)).encode()
        self.calls: list[tuple[str, dict]] = []

    def __call__(self, url: str, headers: dict) -> tuple[int, bytes]:
        self.calls.append((url, headers))
        return self.status, self.body


def _functions_tree(root, *names):
    for name in names:
        d = root / "supabase" / "functions" / name
        d.mkdir(parents=True)
        (d / "index.ts").write_text("// fn\n")
    return root


def test_token_problems_accepts_a_scoped_token():
    assert fp.token_problems(SCOPED) == []


def test_token_problems_refuses_classic_and_malformed_tokens():
    classic = fp.token_problems(CLASSIC)
    assert any("not a scoped token" in p for p in classic)
    assert fp.token_problems("") == ["is empty"]
    assert any("whitespace" in p for p in fp.token_problems("sbp_fcabc\n"))
    assert any("unexpected characters" in p for p in fp.token_problems("sbp_fc-a"))
    for token in (CLASSIC, "sbp_fcabc\n", "sbp_fc-a"):
        for problem in fp.token_problems(token):
            assert token.strip() not in problem


def test_local_functions_skips_shared_and_incomplete_dirs(tmp_path):
    functions = tmp_path / "functions"
    for name in ("b-fn", "a-fn", "_shared"):
        (functions / name).mkdir(parents=True)
        (functions / name / "index.ts").write_text("// fn\n")
    (functions / "no-entry").mkdir()
    (functions / "no-entry" / "deno.json").write_text("{}\n")
    assert fp.local_functions(functions) == ["a-fn", "b-fn"]


def test_list_deployed_calls_the_target_project():
    get = FakeGet(200, [{"slug": "x", "version": 3, "verify_jwt": True}])
    deployed = fp.list_deployed("staging", "sbp_fcTOKEN", get=get)
    assert deployed == [{"slug": "x", "version": 3, "verify_jwt": True}]
    url, headers = get.calls[0]
    assert url.endswith("/v1/projects/miihmfhnsfmwgrvgayns/functions")
    assert headers["Authorization"] == "Bearer sbp_fcTOKEN"


def test_list_deployed_403_names_target_not_token():
    get = FakeGet(403, b'{"message":"forbidden sbp_fcTOKEN"}')
    with pytest.raises(fp.PreflightError) as exc:
        fp.list_deployed("prod", "sbp_fcTOKEN", get=get)
    message = str(exc.value)
    assert "prod" in message and "HTTP 403" in message
    assert "sbp_fc" not in message


def test_list_deployed_401_says_expired_or_revoked():
    # Every scoped token expires within a year, so this is the error the owner
    # will certainly see; it must point at rotation, not at scopes.
    with pytest.raises(fp.PreflightError) as exc:
        fp.list_deployed("prod", "sbp_fcTOKEN", get=FakeGet(401, b'{"message":"Unauthorized"}'))
    message = str(exc.value)
    assert "HTTP 401" in message and "expired or revoked" in message
    assert "PROD_SUPABASE_ACCESS_TOKEN" in message and "docs/dev/DEPLOY.md" in message
    assert "sbp_fc" not in message


def test_list_deployed_server_error_is_not_blamed_on_scope():
    with pytest.raises(fp.PreflightError) as exc:
        fp.list_deployed("staging", "sbp_fcTOKEN", get=FakeGet(502, b"bad gateway"))
    message = str(exc.value)
    assert "HTTP 502" in message and "scoped" not in message


def test_list_deployed_network_error_is_a_preflight_error():
    def unreachable(url, headers):
        raise urllib.error.URLError("dns failure")

    with pytest.raises(fp.PreflightError) as exc:
        fp.list_deployed("staging", "sbp_fcTOKEN", get=unreachable)
    assert "could not reach" in str(exc.value)


def test_list_deployed_unexpected_body_is_a_preflight_error():
    for body in (b'"oops"', b"not json", b'["x"]'):
        with pytest.raises(fp.PreflightError) as exc:
            fp.list_deployed("staging", "sbp_fcTOKEN", get=FakeGet(200, body))
        assert "unexpected response" in str(exc.value)


def test_main_names_the_github_secret(ci_env, monkeypatch, capsys):
    monkeypatch.setenv("SUPABASE_ACCESS_TOKEN", "")
    monkeypatch.setattr(fp, "_http_get", FakeGet(200, []))
    assert fp.main(["prod"]) == 1
    assert "PROD_SUPABASE_ACCESS_TOKEN" in capsys.readouterr().out


def test_jwt_off_only_checks_functions_about_to_deploy():
    deployed = [
        {"slug": "a", "verify_jwt": False},
        {"slug": "b", "verify_jwt": True},
        {"slug": "c", "verify_jwt": False},
    ]
    assert fp.jwt_off(deployed, ["a", "b"]) == ["a"]


def test_render_summary_marks_new_functions():
    out = fp.render_summary("prod", ["a", "b"], [{"slug": "a", "version": 7}], "abcdef1234")
    assert "| a | v7 | abcdef1 |" in out
    assert "| b | not deployed | abcdef1 |" in out


@pytest.fixture
def ci_env(tmp_path, monkeypatch):
    root = _functions_tree(tmp_path / "repo", "b-fn", "a-fn")
    output = tmp_path / "github_output"
    summary = tmp_path / "step_summary"
    monkeypatch.setattr(fp, "ROOT", root)
    monkeypatch.setenv("SUPABASE_ACCESS_TOKEN", SCOPED)
    monkeypatch.setenv("GITHUB_SHA", "0123456789abcdef")
    monkeypatch.setenv("GITHUB_OUTPUT", str(output))
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary))
    return output, summary


def test_main_writes_functions_output_and_summary(ci_env, monkeypatch):
    output, summary = ci_env
    get = FakeGet(200, [{"slug": "a-fn", "version": 2, "verify_jwt": True}])
    monkeypatch.setattr(fp, "_http_get", get)
    assert fp.main(["staging"]) == 0
    assert "functions=a-fn b-fn" in output.read_text(encoding="utf-8")
    # GitHub reads both files as UTF-8; Windows' default codec would garble "→".
    text = summary.read_text(encoding="utf-8")
    assert "### Edge Functions → staging" in text
    assert SCOPED not in text


def test_main_refuses_classic_token_before_any_http(ci_env, monkeypatch, capsys):
    monkeypatch.setenv("SUPABASE_ACCESS_TOKEN", CLASSIC)
    get = FakeGet(200, [])
    monkeypatch.setattr(fp, "_http_get", get)
    assert fp.main(["prod"]) == 1
    assert get.calls == []
    out = capsys.readouterr().out
    assert "::error::" in out and CLASSIC not in out


def test_main_refuses_when_jwt_is_off(ci_env, monkeypatch, capsys):
    get = FakeGet(200, [{"slug": "a-fn", "version": 2, "verify_jwt": False}])
    monkeypatch.setattr(fp, "_http_get", get)
    assert fp.main(["staging"]) == 1
    out = capsys.readouterr().out
    assert "::error::" in out and "a-fn" in out


def test_main_rejects_unknown_target(ci_env, monkeypatch):
    monkeypatch.setattr(fp, "_http_get", FakeGet(200, []))
    assert fp.main(["dev"]) == 1
