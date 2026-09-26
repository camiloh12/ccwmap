#!/usr/bin/env bash
# ci/db_repair.sh — edit the Supabase migration history table. Never runs
# migration SQL. Used by .github/workflows/db-repair.yml.
#
#   DB_URL=<pooler url> bash ci/db_repair.sh <list|applied|reverted> "<versions>"
#
# versions: space- and/or comma-separated digits (e.g. "000 004,005").
set -euo pipefail

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
    supabase migration repair --status "$action" $versions --db-url "$DB_URL"
    ;;
  *)
    echo "::error::unknown action '$action' (expected list, applied or reverted)"
    exit 2
    ;;
esac

listing="$(supabase migration list --db-url "$DB_URL")"
echo "$listing"
{
  echo "### Migration history after \`$action\`"
  echo '```'
  echo "$listing"
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
