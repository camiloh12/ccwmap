"""Fail fast — without ever printing it — when a DB URL secret is malformed.

    DB_URL=... python3 ci/check_db_url.py STAGING_DB_URL

A malformed URL makes the Supabase CLI echo the whole string in its error,
and GitHub masks only the exact stored secret, so a mis-pasted value was
published in PR #56's log. Run this before any CLI call. Checks: postgres
scheme, exactly one '@', a user and a percent-encoded password, the Supabase
session pooler host on port 5432, and no whitespace.
"""

from __future__ import annotations

import os
import re
import sys

_UNRESERVED_OR_PCT = re.compile(r"(?:[A-Za-z0-9\-._~]|%[0-9A-Fa-f]{2})+")


def problems(url: str) -> list[str]:
    """Human-readable problems with `url`; never includes any part of it."""
    if not url:
        return ["is empty"]
    found = []
    if any(c.isspace() for c in url):
        found.append("contains whitespace (a leading/trailing space or newline from pasting?)")
    scheme, sep, rest = url.strip().partition("://")
    if not sep or scheme not in ("postgres", "postgresql"):
        return found + ["must start with postgresql://"]
    netloc = rest.split("/", 1)[0]
    if netloc.count("@") != 1:
        return found + [
            "must contain exactly one '@' - the literal separator before the host "
            "(an '@' inside the password must be encoded as %40)"
        ]
    userinfo, hostport = netloc.split("@")
    user, colon, password = userinfo.partition(":")
    if not user:
        found.append("has no username (expected postgres.<project-ref>)")
    if not colon or not password:
        found.append("has no password")
    elif not _UNRESERVED_OR_PCT.fullmatch(password):
        found.append(
            "has a password with characters that must be percent-encoded "
            "($ -> %24, ? -> %3F, @ -> %40, # -> %23, / -> %2F, : -> %3A, % -> %25)"
        )
    host, colon, port = hostport.rpartition(":")
    if not colon:
        host, port = hostport, ""
    if not host.endswith(".pooler.supabase.com"):
        found.append(
            "must use the Supabase session pooler host (*.pooler.supabase.com); the direct "
            "db.<ref>.supabase.co host is IPv6-only and unreachable from GitHub runners"
        )
    if port != "5432":
        found.append("must use port 5432 (session mode); 6543 is transaction mode and breaks migrations")
    return found


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    label = argv[0] if argv else "DB_URL"
    found = problems(os.environ.get("DB_URL", ""))
    if found:
        for p in found:
            print(f"::error::{label} {p}. Fix the secret; its value is never printed.")
        return 1
    print(f"{label}: shape OK (session pooler, port 5432, encoded password).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
