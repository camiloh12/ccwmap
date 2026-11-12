"""Resolve a report on an imported pin, run by .github/workflows/resolve-pin-report.yml.

    TARGET=staging CONFIRM=... REPORT_ID=... ACTION=remove|move|dismiss \\
    LATITUDE=... LONGITUDE=... STAGING_SERVICE_ROLE_KEY=... \\
        python3 ci/resolve_pin_report.py

Calls the resolve_pin_report() Postgres function (migration 014) over PostgREST
with the service-role key. Inputs arrive only through the environment.

The repo and its Actions logs are public: this never prints the key, and never
prints a report's note or reporter id (the function does not return them, and
the summary is built from an allow-list of keys anyway).
Spec: docs/superpowers/specs/2026-11-11-v0.9.0-report-a-problem-design.md section 4.5
"""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass

PROJECT_REFS = {"staging": "miihmfhnsfmwgrvgayns", "prod": "gqbxloaqamokbolcvesg"}
KEY_ENV = {"staging": "STAGING_SERVICE_ROLE_KEY", "prod": "PROD_SERVICE_ROLE_KEY"}
ACTIONS = ("remove", "move", "dismiss")
REQUIRED_REF = "refs/heads/master"
LAT_RANGE = (24.396308, 49.384358)
LNG_RANGE = (-125.0, -66.93457)
HTTP_TIMEOUT_S = 30
MESSAGE_LIMIT = 200


class InputError(Exception):
    pass


class ResolveError(Exception):
    pass


@dataclass(frozen=True)
class ResolveRequest:
    target: str
    report_id: str
    action: str
    latitude: float | None
    longitude: float | None


def _coordinate(name: str, text: str, lo: float, hi: float) -> float:
    try:
        value = float(text)
    except ValueError:
        raise InputError(f"{name} is not a number") from None
    if not lo <= value <= hi:  # also rejects NaN
        raise InputError(f"{name} must be between {lo} and {hi} (continental US)")
    return value


def validate_inputs(
    *, target: str, confirm: str, ref: str, report_id: str, action: str, latitude: str, longitude: str
) -> ResolveRequest:
    if target not in PROJECT_REFS:
        raise InputError("target must be staging or prod")
    if target == "prod" and ref != REQUIRED_REF:
        raise InputError(f"prod runs only from master, not {ref or '(unknown ref)'}")
    expected = f"I-KNOW-THIS-WRITES-TO-{target.upper()}"
    if confirm != expected:
        raise InputError(f"confirmation phrase must be exactly: {expected}")
    try:
        report_id = str(uuid.UUID(report_id.strip()))
    except ValueError:
        raise InputError("report_id is not a UUID") from None
    if action not in ACTIONS:
        raise InputError("action must be one of: " + ", ".join(ACTIONS))
    lat_text, lng_text = latitude.strip(), longitude.strip()
    if action == "move":
        if not lat_text or not lng_text:
            raise InputError("a move needs both latitude and longitude")
        lat = _coordinate("latitude", lat_text, *LAT_RANGE)
        lng = _coordinate("longitude", lng_text, *LNG_RANGE)
        return ResolveRequest(target, report_id, action, lat, lng)
    if lat_text or lng_text:
        raise InputError(f"{action} takes no coordinates: leave latitude and longitude empty")
    return ResolveRequest(target, report_id, action, None, None)


def key_ref(key: str) -> str | None:
    """The `ref` claim of a JWT, or None when the key isn't a JWT."""
    parts = key.split(".")
    if len(parts) != 3:
        return None
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
    except (ValueError, UnicodeDecodeError):
        return None
    ref = claims.get("ref") if isinstance(claims, dict) else None
    return ref if isinstance(ref, str) else None


def check_key(target: str, key: str) -> None:
    key = key.strip()
    if not key:
        raise InputError(f"{KEY_ENV[target]} is not set for {target}")
    if any(c.isspace() or not c.isprintable() for c in key):
        # Never echo the key: a bad header value would leak it in a traceback.
        raise InputError(f"{KEY_ENV[target]} contains whitespace or control characters")
    if key_ref(key) != PROJECT_REFS[target]:
        raise InputError(f"the service key is not for the {target} project")


def _http_post(url: str, headers: dict[str, str], body: bytes) -> tuple[int, bytes]:
    """(status, body). An HTTP error returns its status and body; network errors raise."""
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read()
        finally:
            e.close()


def _server_message(status: int, body: bytes) -> str:
    # Only the PostgREST `message` field is surfaced, never the raw body.
    try:
        data = json.loads(body)
        message = data.get("message") if isinstance(data, dict) else None
    except ValueError:
        message = None
    if not isinstance(message, str) or not message:
        return f"HTTP {status}"
    return "".join(c if c.isprintable() else " " for c in message)[:MESSAGE_LIMIT]


def call_resolve(req: ResolveRequest, key: str, post=None) -> dict:
    post = post or _http_post
    url = f"https://{PROJECT_REFS[req.target]}.supabase.co/rest/v1/rpc/resolve_pin_report"
    key = key.strip()
    headers = {"apikey": key, "Content-Type": "application/json", "Accept": "application/json"}
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    body = json.dumps(
        {
            "p_report_id": req.report_id,
            "p_action": req.action,
            "p_latitude": req.latitude,
            "p_longitude": req.longitude,
        }
    ).encode()
    try:
        status, raw = post(url, headers, body)
    except OSError as e:
        raise ResolveError(f"no response ({type(e).__name__})") from None
    if not 200 <= status < 300:
        raise ResolveError(_server_message(status, raw))
    try:
        result = json.loads(raw)
    except ValueError:
        raise ResolveError("response was not JSON") from None
    if not isinstance(result, dict):
        raise ResolveError("response was not a JSON object")
    return result


def _cell(value: object) -> str:
    s = "".join(c if c.isprintable() else " " for c in str(value if value is not None else ""))
    s = " ".join(s.split()).replace("`", "'")
    return f"`{s[:80] or '(none)'}`"


def render_summary(req: ResolveRequest, result: dict) -> str:
    """Markdown for $GITHUB_STEP_SUMMARY, from an allow-list of result keys."""
    rows = [
        ("Target", req.target),
        ("Report", result.get("report_id", req.report_id)),
        ("Action", result.get("action", req.action)),
        ("Pin", result.get("pin_name")),
        ("Source", result.get("pin_source")),
        ("Latitude", result.get("latitude")),
        ("Longitude", result.get("longitude")),
        ("Pin deleted", result.get("pin_deleted")),
        ("Reports closed", result.get("closed_reports")),
    ]
    lines = ["## Resolve pin report", "", "| Field | Value |", "|---|---|"]
    lines += [f"| {k} | {_cell(v)} |" for k, v in rows]
    return "\n".join(lines) + "\n"


def _annotation(message: str) -> str:
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main() -> int:
    env = os.environ.get
    try:
        req = validate_inputs(
            target=env("TARGET", ""),
            confirm=env("CONFIRM", ""),
            ref=env("GITHUB_REF", ""),
            report_id=env("REPORT_ID", ""),
            action=env("ACTION", ""),
            latitude=env("LATITUDE", ""),
            longitude=env("LONGITUDE", ""),
        )
        key = env(KEY_ENV[req.target], "").strip()
        check_key(req.target, key)
        result = call_resolve(req, key)
    except (InputError, ResolveError) as e:
        print(f"::error::{_annotation(str(e))}")
        return 1
    except Exception as e:  # type only: its message could hold a header value (the key)
        print(f"::error::unexpected {type(e).__name__}")
        return 1
    summary = render_summary(req, result)
    path = env("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(summary)
    else:
        print(summary)
    print(f"Resolved report {result.get('report_id', req.report_id)} on {req.target}: {req.action}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
