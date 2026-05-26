#!/usr/bin/env bash
# .claude/hooks/pr-preflight-gate.sh
# PreToolUse(Bash) gate. settings.json scopes this — via the hook `if` filters
# Bash(gh pr create*) and Bash(git push -u*) — to PR-creating commands only, so
# this just runs the preflight and translates a failure into exit code 2, which
# blocks the tool call and feeds the reason back to Claude. Routine pushes
# (plain `git push`) never reach here.
#
# Stdin carries the PreToolUse JSON payload; we don't need it (the `if` filter
# already decided this should run), so it's ignored.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/.claude/pr-preflight.sh"

if [ ! -f "$script" ]; then
  echo "pr-preflight-gate: $script not found; allowing the command." >&2
  exit 0
fi

if bash "$script" >&2; then
  exit 0
fi

echo "" >&2
echo "⛔ PR preflight failed — blocking this command. Fix the checks above, then retry." >&2
exit 2
