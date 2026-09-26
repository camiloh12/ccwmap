"""Redact database credentials from Supabase CLI output.

    supabase ... 2>&1 | python3 ci/redact.py     # filter; reads DB_URL from env

Never rely on GitHub's secret masking for CLI output: it only replaces the
exact stored secret string, and a CLI error echoing a mis-pasted (e.g.
whitespace-padded) secret was published unmasked in PR #56's staging log.
Redacts the exact DB_URL (raw and stripped), its password (raw and
URL-decoded), anything URL-shaped, and `password=` values.
"""

from __future__ import annotations

import os
import re
import sys
import urllib.parse

_DB_URL = re.compile(r"postgres(?:ql)?://\S+")
_PASSWORD_KV = re.compile(r"(password=)\S+", re.IGNORECASE)
_USER_PASSWORD = re.compile(r"postgres(?:ql)?://[^:/@\s]+:(.*)@[^@]*$")
_MIN_SECRET_LEN = 4  # never blank out short, common substrings


def _secret_variants(db_url: str | None) -> list[str]:
    if not db_url:
        return []
    variants = {db_url, db_url.strip()}
    m = _USER_PASSWORD.match(db_url.strip())
    if m:
        variants |= {m.group(1), urllib.parse.unquote(m.group(1))}
    return sorted((v for v in variants if len(v) >= _MIN_SECRET_LEN), key=len, reverse=True)


def redact(text: str, db_url: str | None) -> str:
    for secret in _secret_variants(db_url):
        text = text.replace(secret, "***")
    text = _DB_URL.sub("<db-url>", text)
    return _PASSWORD_KV.sub(r"\1<redacted>", text)


def main() -> int:
    db_url = os.environ.get("DB_URL")
    for line in sys.stdin:  # line by line keeps CLI progress visible
        sys.stdout.write(redact(line, db_url))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
