"""Check an Edge Functions deploy before it runs, without printing the token.

    SUPABASE_ACCESS_TOKEN=... python3 ci/functions_preflight.py staging

Run by .github/workflows/edge-functions.yml before `supabase functions
deploy`. It refuses a token that is not a scoped personal access token
(sbp_fc...), lists the target project's deployed functions through the
Management API (a token for another project fails here with a 403, before
anything is written), and refuses to deploy over a function whose JWT
verification is off: the CLI deploys with verification on, so it would
silently flip that setting under whatever calls the function. On success it
writes the function names to $GITHUB_OUTPUT (`functions=a b`) and a summary
table to $GITHUB_STEP_SUMMARY. Stdlib only.
Design: docs/superpowers/specs/2026-11-13-edge-functions-pipeline-design.md
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_REFS = {"staging": "miihmfhnsfmwgrvgayns", "prod": "gqbxloaqamokbolcvesg"}
SECRET_NAMES = {"staging": "STAGING_SUPABASE_ACCESS_TOKEN", "prod": "PROD_SUPABASE_ACCESS_TOKEN"}
API_URL = "https://api.supabase.com/v1/projects/{ref}/functions"
HTTP_TIMEOUT_S = 30
ROOT = Path(__file__).resolve().parents[1]

_TOKEN_CHARS = re.compile(r"[A-Za-z0-9_]+")


class PreflightError(Exception):
    pass


def token_problems(token: str) -> list[str]:
    """Readable problems with `token`; never includes any part of it."""
    if not token:
        return ["is empty"]
    found = []
    if any(c.isspace() for c in token):
        found.append("contains whitespace (a newline from pasting?)")
    stripped = token.strip()
    if not stripped.startswith("sbp_fc"):
        found.append(
            "is not a scoped token (expected the sbp_fc prefix; "
            "classic full-access tokens are refused)"
        )
    if not _TOKEN_CHARS.fullmatch(stripped):
        found.append("has unexpected characters")
    return found


def local_functions(functions_dir: Path) -> list[str]:
    """Folders with an index.ts, skipping shared code such as `_shared/`."""
    return sorted(
        d.name
        for d in functions_dir.iterdir()
        if d.is_dir() and not d.name.startswith("_") and (d / "index.ts").is_file()
    )


def _http_get(url: str, headers: dict[str, str]) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def list_deployed(target: str, token: str, get=None) -> list[dict]:
    get = get or _http_get
    url = API_URL.format(ref=PROJECT_REFS[target])
    headers = {"Authorization": f"Bearer {token}", "User-Agent": "ccwmap-ci"}
    try:
        status, body = get(url, headers)
    except (urllib.error.URLError, OSError) as e:
        # Only the exception's class: its text is not ours to print.
        raise PreflightError(
            f"could not reach the Supabase Management API ({type(e).__name__}); re-run the job"
        ) from None
    # The body is never shown: it is server text we don't control.
    if status == 401:
        raise PreflightError(
            f"the {target} token was refused (HTTP 401): it is expired or revoked. Rotate "
            f"{SECRET_NAMES[target]} (docs/dev/DEPLOY.md, Access tokens)"
        )
    if status == 403:
        raise PreflightError(
            f"cannot list {target} functions (HTTP 403): the token must be "
            f"scoped to the {target} project with Edge Functions read-write"
        )
    if status != 200:
        raise PreflightError(
            f"the Supabase Management API answered HTTP {status} for {target}; re-run the job later"
        )
    try:
        deployed = json.loads(body)
    except ValueError:
        deployed = None
    if not isinstance(deployed, list) or not all(isinstance(f, dict) for f in deployed):
        raise PreflightError("unexpected response from the Management API (not a list of functions)")
    return deployed


def jwt_off(deployed: list[dict], names: list[str]) -> list[str]:
    wanted = set(names)
    return sorted(
        f["slug"] for f in deployed if f.get("slug") in wanted and f.get("verify_jwt") is False
    )


def render_summary(target: str, names: list[str], deployed: list[dict], sha: str) -> str:
    versions = {f.get("slug"): f.get("version") for f in deployed}
    lines = [
        f"### Edge Functions → {target}",
        "",
        "| Function | Deployed now | After this run |",
        "|---|---|---|",
    ]
    for name in names:
        now = f"v{versions[name]}" if name in versions else "not deployed"
        lines.append(f"| {name} | {now} | {sha[:7]} |")
    return "\n".join(lines) + "\n"


def _append(env_var: str, text: str) -> None:
    path = os.environ.get(env_var)
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)


def _fail(label: str, problems: list[str]) -> int:
    for p in problems:
        print(f"::error::{label} {p}")
    return 1


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    target = argv[0] if argv else ""
    if target not in PROJECT_REFS:
        return _fail("target", [f"must be one of {', '.join(PROJECT_REFS)}"])
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    found = token_problems(token)
    if found:
        return _fail(SECRET_NAMES[target], [f"{p}. Fix the secret; its value is never printed." for p in found])
    names = local_functions(ROOT / "supabase" / "functions")
    if not names:
        return _fail("supabase/functions", ["has no function folders with an index.ts"])
    try:
        deployed = list_deployed(target, token.strip(), get=_http_get)
    except PreflightError as e:
        return _fail("preflight:", [str(e)])
    off = jwt_off(deployed, names)
    if off:
        return _fail(
            "preflight:",
            [
                f"{name} is deployed on {target} with JWT verification off; this "
                "workflow deploys with it on, which could break whatever calls it. "
                "Decide by hand before deploying."
                for name in off
            ],
        )
    _append("GITHUB_OUTPUT", f"functions={' '.join(names)}\n")
    _append("GITHUB_STEP_SUMMARY", render_summary(target, names, deployed, os.environ.get("GITHUB_SHA", "unknown")))
    print(f"preflight: {target} OK, will deploy {' '.join(names)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
