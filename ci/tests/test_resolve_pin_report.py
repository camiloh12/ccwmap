import base64
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import resolve_pin_report as rpr  # noqa: E402

UUID = "123e4567-e89b-12d3-a456-426614174000"
MASTER = "refs/heads/master"


def _args(**over):
    base = dict(
        target="staging",
        confirm="I-KNOW-THIS-WRITES-TO-STAGING",
        ref=MASTER,
        report_id=UUID,
        action="remove",
        latitude="",
        longitude="",
    )
    base.update(over)
    return base


def _jwt(payload: dict) -> str:
    def b64(d: bytes) -> str:
        return base64.urlsafe_b64encode(d).rstrip(b"=").decode()

    return ".".join([b64(b'{"alg":"HS256"}'), b64(json.dumps(payload).encode()), "sig"])


def test_validate_accepts_remove():
    req = rpr.validate_inputs(**_args())
    assert req == rpr.ResolveRequest("staging", UUID, "remove", None, None)


def test_validate_accepts_move_inside_box():
    req = rpr.validate_inputs(**_args(action="move", latitude="29.7", longitude="-95.2"))
    assert (req.latitude, req.longitude) == (29.7, -95.2)


def test_validate_rejects_wrong_confirm_phrase():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(confirm="I-KNOW-THIS-WRITES-TO-PROD"))


def test_validate_rejects_non_master_ref_for_prod():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(
            **_args(
                target="prod",
                confirm="I-KNOW-THIS-WRITES-TO-PROD",
                ref="refs/heads/feature/x",
            )
        )


def test_validate_accepts_prod_from_master():
    req = rpr.validate_inputs(
        **_args(target="prod", confirm="I-KNOW-THIS-WRITES-TO-PROD")
    )
    assert req.target == "prod"


def test_validate_accepts_staging_from_non_master_ref():
    req = rpr.validate_inputs(**_args(ref="refs/heads/feature/x"))
    assert req.target == "staging"


def test_validate_rejects_bad_uuid():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(report_id="not-a-uuid"))


def test_validate_rejects_unknown_action():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(action="explode"))


def test_move_rejects_swapped_coordinates():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(action="move", latitude="-95.2", longitude="29.7"))


def test_move_needs_both_coordinates():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(action="move", latitude="29.7"))
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(action="move"))


def test_dismiss_rejects_coordinates():
    with pytest.raises(rpr.InputError):
        rpr.validate_inputs(**_args(action="dismiss", latitude="29.7", longitude="-95.2"))


def test_key_ref_reads_jwt_claim():
    key = _jwt({"ref": "miihmfhnsfmwgrvgayns", "role": "service_role"})
    assert rpr.key_ref(key) == "miihmfhnsfmwgrvgayns"


def test_key_ref_none_for_non_jwt():
    assert rpr.key_ref("sb_secret_abc") is None


def test_check_key_rejects_other_projects_key():
    key = _jwt({"ref": rpr.PROJECT_REFS["prod"], "role": "service_role"})
    with pytest.raises(rpr.InputError):
        rpr.check_key("staging", key)
    rpr.check_key("prod", key)


def test_check_key_rejects_empty():
    with pytest.raises(rpr.InputError):
        rpr.check_key("staging", "")


def _req(**over):
    base = dict(target="staging", report_id=UUID, action="move", latitude=29.7, longitude=-95.2)
    base.update(over)
    return rpr.ResolveRequest(**base)


def test_call_resolve_posts_rpc():
    seen = {}

    def post(url, headers, body):
        seen.update(url=url, headers=headers, body=json.loads(body))
        return 200, json.dumps({"report_id": UUID}).encode()

    out = rpr.call_resolve(_req(), "KEY", post=post)
    assert out == {"report_id": UUID}
    assert seen["url"] == "https://miihmfhnsfmwgrvgayns.supabase.co/rest/v1/rpc/resolve_pin_report"
    assert seen["body"] == {
        "p_report_id": UUID,
        "p_action": "move",
        "p_latitude": 29.7,
        "p_longitude": -95.2,
    }
    assert seen["headers"]["apikey"] == "KEY"


def test_call_resolve_surfaces_server_error():
    def post(url, headers, body):
        return 400, b'{"message": "report_already_resolved"}'

    with pytest.raises(rpr.ResolveError) as e:
        rpr.call_resolve(_req(), "KEY", post=post)
    assert str(e.value) == "report_already_resolved"


def test_summary_never_contains_note_or_reporter():
    result = {
        "report_id": UUID,
        "action": "remove",
        "pin_id": "p1",
        "pin_name": "Courthouse",
        "pin_source": "hifld_courts",
        "latitude": 29.7,
        "longitude": -95.2,
        "pin_deleted": True,
        "closed_reports": 2,
        "note": "SECRET-NOTE-TEXT",
        "reporter_id": "SECRET-REPORTER-ID",
    }
    out = rpr.render_summary(_req(action="remove", latitude=None, longitude=None), result)
    assert "Courthouse" in out and "hifld_courts" in out and UUID in out
    for bad in ("note", "reporter", "SECRET"):
        assert bad not in out


@pytest.mark.parametrize("suffix", ["\n", "\r\n", "\r"])
def test_key_with_trailing_newline_is_stripped(suffix):
    key = _jwt({"ref": rpr.PROJECT_REFS["staging"], "role": "service_role"})
    rpr.check_key("staging", key + suffix)
    seen = {}

    def post(url, headers, body):
        seen.update(headers)
        return 200, b"{}"

    rpr.call_resolve(_req(), key + suffix, post=post)
    assert seen["apikey"] == key and "\n" not in seen["Authorization"] and "\r" not in seen["Authorization"]


def test_key_with_interior_whitespace_is_rejected_without_echo():
    key = _jwt({"ref": rpr.PROJECT_REFS["staging"], "role": "service_role"})
    bad = key[:10] + " " + key[10:]
    with pytest.raises(rpr.InputError) as e:
        rpr.check_key("staging", bad)
    assert key[:10] not in str(e.value)


def test_main_never_prints_key_on_unexpected_exception(monkeypatch, capsys):
    key = _jwt({"ref": rpr.PROJECT_REFS["staging"], "role": "service_role"})
    for k, v in dict(TARGET="staging", CONFIRM="I-KNOW-THIS-WRITES-TO-STAGING", GITHUB_REF=MASTER,
                     REPORT_ID=UUID, ACTION="remove", LATITUDE="", LONGITUDE="",
                     STAGING_SERVICE_ROLE_KEY=key + "\n").items():
        monkeypatch.setenv(k, v)
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)

    def post(url, headers, body):
        raise ValueError("Invalid header value 'SECRET'")

    monkeypatch.setattr(rpr, "_http_post", post)
    assert rpr.main() == 1
    out = capsys.readouterr()
    for text in (out.out, out.err):
        assert "SECRET" not in text and key not in text
