"""Smoke-check send-moderation-email after a prod deploy, naming the real cause.

    HEALTH_URL=... ANON_KEY=... python3 ci/functions_smoke.py

Run by the `prod` job of .github/workflows/edge-functions.yml. Calls the
function's /health (up to 3 tries, 10 s apart) and, on failure, says which of
three things is wrong, because they need opposite fixes:
  - HTTP 401/403: the Supabase gateway rejected the anon key (JWT checking is
    on), so the SUPABASE_ANON_KEY repo secret is wrong — not Brevo, not the
    deploy;
  - HTTP 500 from the Brevo check: Brevo rejected BREVO_API_KEY or it is
    unset — the deploy is fine (healthCheck() in
    supabase/functions/send-moderation-email/index.ts returns 500, never 401,
    for this);
  - anything else: the function itself is failing after this deploy.
The anon key is never printed. Stdlib only.
"""

from __future__ import annotations

import os
import re
import sys
import time
import urllib.error

from functions_preflight import _http_get

ATTEMPTS = 3
DELAY_S = 10
# The Brevo check's failure body: {"check":"brevo-account",...} or the
# "BREVO_API_KEY secret is not set" error. Whitespace-tolerant JSON match.
_BREVO_FAILURE = re.compile(rb'"check"\s*:\s*"brevo-|BREVO_API_KEY')


def diagnose(status: int, body: bytes) -> str | None:
    """None when healthy; otherwise what is wrong and where to look."""
    if status == 200:
        return None
    if status == 0:
        return "could not reach /health (network error); re-run the job before suspecting the deploy."
    if status in (401, 403):
        return (
            f"the Supabase gateway refused the anon key (HTTP {status}): check the SUPABASE_ANON_KEY "
            "repo secret is prod's anon key. Not Brevo, and not this deploy."
        )
    if status == 500 and _BREVO_FAILURE.search(body):
        return (
            "Brevo rejected BREVO_API_KEY (or it is unset), HTTP 500 from the Brevo check: the deploy is fine. "
            "Rotate the key per docs/dev/DEPLOY.md (see brevo-keepalive.yml)."
        )
    return (
        f"send-moderation-email answered HTTP {status} after this deploy: check its logs "
        "(dashboard → Edge Functions → send-moderation-email → Logs)."
    )


def main(env=None, get=None, sleep=None) -> int:
    env = os.environ if env is None else env
    get = get or _http_get
    sleep = sleep or time.sleep
    url, key = env.get("HEALTH_URL", ""), env.get("ANON_KEY", "")
    if not url or not key:
        print("::error::HEALTH_URL and ANON_KEY must both be set for the smoke check.")
        return 1
    headers = {"Authorization": f"Bearer {key}", "User-Agent": "ccwmap-ci"}
    status, body = 0, b""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            status, body = get(url, headers)
        except (urllib.error.URLError, OSError):
            status, body = 0, b""
        print(f"attempt {attempt}: HTTP {status}")
        if diagnose(status, body) is None:
            print("send-moderation-email is healthy.")
            return 0
        if attempt < ATTEMPTS:
            sleep(DELAY_S)
    # The body is Brevo's or the gateway's error text: useful for triage, no secret
    # (the same rule as brevo-keepalive.yml).
    print(f"response: {body[:500].decode('utf-8', errors='replace')}")
    print(f"::error::send-moderation-email deployed, but /health returned HTTP {status}: {diagnose(status, body)}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
