#!/usr/bin/env bash
# ci/db_repair.sh — edit the Supabase migration history table. Never runs
# migration SQL. Used by .github/workflows/db-repair.yml.
#
#   DB_URL=<pooler url> bash ci/db_repair.sh <list|applied|reverted> "<versions>"
#
# versions: space- and/or comma-separated digits (e.g. "000 004,005").
set -euo pipefail

# All CLI output goes through the redactor: CLI errors can echo the DB URL, and
# GitHub masks only the exact stored secret (a mis-pasted one leaked in PR #56).
redact=("${PYTHON:-python3}" "$(dirname "$0")/redact.py")

action="${1:-}"
versions="$(printf '%s' "${2:-}" | tr ',' ' ' | xargs)"

case "$action" in
  list) ;;
  applied|reverted)
    if [ -z "$versions" ]; then
      echo "::error::versions are required for '$action'"
      exit 2
    fi
    for v in $versions; do
      if ! [[ "$v" =~ ^[0-9]+$ ]]; then
        echo "::error::invalid migration version '$v' (digits only, e.g. 008 or 20260705144447)"
        exit 2
      fi
    done
    # shellcheck disable=SC2086 # intentionally unquoted: one argument per version
    supabase migration repair --status "$action" $versions --db-url "$DB_URL" 2>&1 | "${redact[@]}"
    ;;
  *)
    echo "::error::unknown action '$action' (expected list, applied or reverted)"
    exit 2
    ;;
esac

# Capture the status instead of letting set -e exit here: a failed list must
# still print its (redacted) error, or the step fails with no output at all.
rc=0
listing="$(supabase migration list --db-url "$DB_URL" 2>&1 | "${redact[@]}")" || rc=$?
echo "$listing"
{
  if [ "$rc" -eq 0 ]; then
    echo "### Migration history after \`$action\`"
  else
    echo "### \`supabase migration list\` failed (exit $rc) after \`$action\`"
  fi
  echo '```'
  echo "$listing"
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit "$rc"
