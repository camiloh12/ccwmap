"""Redact database credentials and access tokens from Supabase CLI output.

    supabase ... 2>&1 | python3 ci/redact.py
    # filter; reads DB_URL and SUPABASE_ACCESS_TOKEN from env

Never rely on GitHub's secret masking for CLI output: it only replaces the
exact stored secret string, and a CLI error echoing a mis-pasted (e.g.
whitespace-padded) secret was published unmasked in PR #56's staging log.
Redacts the exact DB_URL (raw and stripped), its password (raw and
URL-decoded), anything URL-shaped, and `password=` values; and the exact
SUPABASE_ACCESS_TOKEN (raw and stripped) plus anything shaped like a Supabase
access token (`sbp_...`).
"""

from __future__ import annotations

import os
import re
import sys
import urllib.parse

_DB_URL = re.compile(r"postgres(?:ql)?://\S+")
_PASSWORD_KV = re.compile(r"(password=)\S+", re.IGNORECASE)
_USER_PASSWORD = re.compile(r"postgres(?:ql)?://[^:/@\s]+:(.*)@[^@]*$")
_ACCESS_TOKEN = re.compile(r"sbp_[A-Za-z0-9_]+")
_MIN_SECRET_LEN = 4  # never blank out short, common substrings


def _secret_variants(db_url: str | None, access_token: str | None) -> list[str]:
    variants = set()
    if db_url:
        variants |= {db_url, db_url.strip()}
        m = _USER_PASSWORD.match(db_url.strip())
        if m:
            variants |= {m.group(1), urllib.parse.unquote(m.group(1))}
    if access_token:
        variants |= {access_token, access_token.strip()}
    return sorted((v for v in variants if len(v) >= _MIN_SECRET_LEN), key=len, reverse=True)


def redact(text: str, db_url: str | None, access_token: str | None = None) -> str:
    for secret in _secret_variants(db_url, access_token):
        text = text.replace(secret, "***")
    text = _DB_URL.sub("<db-url>", text)
    text = _ACCESS_TOKEN.sub("<access-token>", text)
    return _PASSWORD_KV.sub(r"\1<redacted>", text)


def main() -> int:
    db_url = os.environ.get("DB_URL")
    access_token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    for line in sys.stdin:  # line by line keeps CLI progress visible
        sys.stdout.write(redact(line, db_url, access_token))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
