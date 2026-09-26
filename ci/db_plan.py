"""Read `supabase db push --dry-run --output-format json` output for the DB
migrations workflow (docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md).

    python3 ci/db_plan.py PLAN_JSON
        plan job: append pending=/migrations= to $GITHUB_OUTPUT and a
        "Pending for prod" section to $GITHUB_STEP_SUMMARY.
    python3 ci/db_plan.py PLAN_JSON --expect "a.sql b.sql"
        apply job: exit 1 unless the pending list is exactly the approved one.

Stdlib only; runs on the stock ubuntu-latest python3.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass

from redact import redact


class PlanError(ValueError):
    """The dry-run output is unreadable or reports an error."""


@dataclass(frozen=True)
class Plan:
    pending: bool
    migrations: tuple[str, ...]


def _load_json(text: str) -> object:
    """Whole text as JSON, else the last line that parses as a JSON object
    (tolerates non-JSON noise such as CLI update notices)."""
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    for line in reversed(text.strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    raise PlanError("no JSON object found in `supabase db push` output")


def _find_result(obj: object) -> dict | None:
    """Depth-first search for the object carrying `upToDate` (envelope-agnostic)."""
    if isinstance(obj, dict):
        if "upToDate" in obj:
            return obj
        children = obj.values()
    elif isinstance(obj, list):
        children = obj
    else:
        return None
    for child in children:
        found = _find_result(child)
        if found is not None:
            return found
    return None


def parse_plan(text: str) -> Plan:
    doc = _load_json(text)
    if isinstance(doc, dict) and doc.get("_tag") == "Error":
        err = doc.get("error") or {}
        raise PlanError(
            f"`supabase db push` reported an error: {err.get('code')}: {err.get('message')}"
        )
    result = _find_result(doc)
    if result is None:
        raise PlanError("`supabase db push` output has no upToDate field")
    up_to_date = result["upToDate"]
    if not isinstance(up_to_date, bool):
        raise PlanError(f"upToDate is not a boolean: {up_to_date!r}")
    migrations = tuple(result.get("migrations") or ())
    if not up_to_date and not migrations:
        raise PlanError("upToDate is false but no migrations are listed")
    return Plan(pending=not up_to_date, migrations=migrations)


def summary_markdown(plan: Plan) -> str:
    if not plan.pending:
        return "### Pending for prod\n\nNothing pending — prod is up to date.\n"
    lines = [
        "### Pending for prod",
        "",
        "Approving the `apply` job applies exactly these, in order:",
        "",
        *(f"- `{m}`" for m in plan.migrations),
    ]
    return "\n".join(lines) + "\n"


def _gh_error(message: str) -> None:
    """Print one `::error::` workflow command, safe for a public log.

    CLI errors can echo the connection string. GitHub masks the secret only as
    the exact string, and it unescapes %25/%0D/%0A in workflow commands BEFORE
    masking, so a percent-encoded password could slip through: redact URLs and
    password= values, then escape the command data.
    """
    message = redact(message, os.environ.get("DB_URL"))
    message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error::{message}")


def _append(env_var: str, text: str) -> None:
    path = os.environ.get(env_var)
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan_json")
    parser.add_argument("--expect", help="space-separated approved migration filenames")
    args = parser.parse_args(argv)

    with open(args.plan_json, encoding="utf-8") as f:
        text = f.read()
    try:
        plan = parse_plan(text)
    except PlanError as e:
        _gh_error(str(e))
        return 1

    if args.expect is not None:
        approved = tuple(args.expect.split())
        if plan.migrations != approved:
            _gh_error(
                "pending migrations changed since approval: "
                f"approved {list(approved)}, now {list(plan.migrations)}"
            )
            return 1
        print(f"Pending list matches the approved plan: {list(approved)}")
        return 0

    _append("GITHUB_OUTPUT", f"pending={'true' if plan.pending else 'false'}\n")
    _append("GITHUB_OUTPUT", f"migrations={' '.join(plan.migrations)}\n")
    summary = summary_markdown(plan)
    _append("GITHUB_STEP_SUMMARY", summary)
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
