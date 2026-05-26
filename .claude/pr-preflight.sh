#!/usr/bin/env bash
# .claude/pr-preflight.sh — local CI-equivalent fast checks for this
# Flutter + Python (importer/) monorepo.
#
# The global pr-preflight skill defers to this file when it exists. The skill's
# default detection is first-match-wins on root marker files, which picks
# pubspec.yaml (Flutter) and never sees the importer's pyproject.toml in a
# subdir — that gap is exactly why an importer PR's checks got skipped once.
# This override runs the stack(s) the branch actually touched vs origin/master:
# an importer-only change runs the importer pytest, a lib/ change runs the
# Flutter checks, a change to both runs both.
#
# Also invoked by .claude/hooks/pr-preflight-gate.sh (the PreToolUse gate on
# `gh pr create` / `git push -u`).
#
# Exit 0 = clean (safe to open the PR). Non-zero = a check failed.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

fail() { echo "✗ $1 failed" >&2; exit 1; }

# Which files did this branch change vs the PR base (origin/master)? Include
# uncommitted edits too. If we can't determine the base, run everything.
base=""
git rev-parse --verify -q origin/master >/dev/null 2>&1 && \
  base="$(git merge-base HEAD origin/master 2>/dev/null || true)"
if [ -n "$base" ]; then
  changed="$(git diff --name-only "$base"...HEAD; git diff --name-only HEAD)"
else
  changed=""
fi

run_flutter=0
run_importer=0
if [ -z "$changed" ]; then
  run_flutter=1
  run_importer=1
else
  printf '%s\n' "$changed" | grep -qE '^(lib/|test/|integration_test/|pubspec\.(yaml|lock)|analysis_options\.yaml)' && run_flutter=1
  printf '%s\n' "$changed" | grep -qE '^importer/' && run_importer=1
fi

if [ "$run_flutter" = 0 ] && [ "$run_importer" = 0 ]; then
  echo "PR preflight: no Flutter or importer source changed (docs/ci/config only) — nothing to check."
  exit 0
fi

echo "PR preflight — flutter=$run_flutter importer=$run_importer"

if [ "$run_flutter" = 1 ]; then
  echo "== Flutter: dart format check =="
  dart format --output=none --set-exit-if-changed . || fail "dart format"
  echo "== Flutter: analyze =="
  flutter analyze --no-fatal-infos || fail "flutter analyze"
  echo "== Flutter: test =="
  flutter test || fail "flutter test"
fi

if [ "$run_importer" = 1 ]; then
  echo "== importer: uv sync + pytest =="
  ( cd importer && uv sync --frozen --extra dev && uv run --no-sync pytest -q ) || fail "importer pytest"
fi

echo "✓ PR preflight clean."
