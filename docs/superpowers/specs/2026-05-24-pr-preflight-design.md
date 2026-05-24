# pr-preflight skill — Design

**Date:** 2026-05-24
**Author:** Camilo Hurtado
**Status:** Approved (pending implementation plan)

## Problem

PR Checks in this repo (and similar checks in other projects) often fail on
mechanical issues that would have been caught by running the same commands
locally before pushing. Most recent example: PR #27 failed because
`dart format --set-exit-if-changed .` flagged one file that had not been run
through `dart format`. The fix is a one-liner; the cost is a full CI cycle
plus a context switch.

The pattern is not Flutter-specific. Every project I work on has a fast set
of "format / lint / test" checks that are runnable locally in under two
minutes and catch the vast majority of CI failures. I want a single personal
skill that runs those checks before a PR is opened, regardless of stack.

## Goals

- **Catch CI-class failures before push.** Specifically format, analyze/lint,
  and test failures. The three checks that account for nearly every
  preventable PR-Checks failure on this repo and equivalents elsewhere.
- **Work generically.** Apply to Dart/Flutter, Node, Rust, Go, and Python
  projects without per-invocation configuration.
- **Allow project-specific overrides.** A repo can ship its own preflight
  script for unusual layouts (monorepos, custom tooling) and the skill
  defers to it.
- **Auto-fix what is mechanical.** Format issues are mechanical — the skill
  runs the autofix and reports the changed files. Analyze/test failures are
  not mechanical — they surface for the user to decide.

## Non-goals

- **Do not run platform builds.** Android APK / iOS / desktop builds are slow
  (~5–10 min) and rarely surface format/analyze/test failures earlier than
  the cheap checks already do. They stay in CI.
- **Do not run security scans.** Gitleaks already runs in CI; running it
  locally adds little value and depends on the action's ruleset.
- **Do not call `gh pr create` itself.** The skill clears the runway; the
  caller (me, or the model in a PR-creation flow) calls `gh pr create`
  after.
- **Do not stage or commit autofix output.** If `dart format .` (or the
  equivalent) modifies files, the skill surfaces the diff. Staging is a
  separate decision.

## Design

### Location and trigger

- **Personal skill** at `~/.claude/skills/pr-preflight/SKILL.md`. Available
  in every project Claude Code runs in for this user.
- **Trigger description:** matches phrases like "create a PR", "open a pull
  request", "preflight before pushing", and the literal `gh pr create`
  invocation. The system reminder lists this skill whenever a PR-creation
  intent is in play, so the model invokes it before pushing.
- **Manual invocation:** also available as `/pr-preflight` for when the user
  wants to run it explicitly without a PR-creation flow.

### Flow

```
1. Check for .claude/pr-preflight.sh in repo root.
   - exists  → run it via Bash; capture exit code and stdout/stderr; done.
   - missing → continue to auto-detect.

2. Auto-detect stack by checking marker files in repo root, first match wins:
     pubspec.yaml   → Dart/Flutter
     Cargo.toml     → Rust
     go.mod         → Go
     pyproject.toml → Python
     package.json   → Node
   If no marker file matches, stop and tell the user no recipe was detected;
   offer to write a stub .claude/pr-preflight.sh.

3. For the detected stack, run the steps below in sequence. Stop on first
   hard failure.
     a. Format check.
        - If clean, continue.
        - If dirty, run the stack's autofix, then re-run the format check
          to confirm clean. Report the changed files.
     b. Analyze / lint.
     c. Test.

4. Report results:
     ✓ Format clean (or "auto-fixed: <files>")
     ✓ Analyze clean
     ✓ Tests pass
     → preflight clean, safe to run `gh pr create`

   On hard failure: show the failing step's output, do NOT proceed.
```

### Per-stack defaults

| Marker         | Stack       | Format check                                          | Autofix          | Analyze / lint                       | Test                       |
|----------------|-------------|-------------------------------------------------------|------------------|--------------------------------------|----------------------------|
| pubspec.yaml   | Dart/Flutter| `dart format --output=none --set-exit-if-changed .`   | `dart format .`  | `flutter analyze --no-fatal-infos` (or `dart analyze` if Flutter not detected) | `flutter test` (or `dart test`) |
| Cargo.toml     | Rust        | `cargo fmt --check`                                   | `cargo fmt`      | `cargo clippy -- -D warnings`        | `cargo test`               |
| go.mod         | Go          | `test -z "$(gofmt -l .)"`                             | `gofmt -w .`     | `go vet ./...`                       | `go test ./...`            |
| pyproject.toml | Python      | `ruff format --check` (if ruff configured) or `black --check .` (if black configured) | `ruff format` / `black .` | `ruff check` (if configured)         | `pytest` (if configured)   |
| package.json   | Node        | `npm run format:check` if `scripts.format:check` exists; else skip | `npm run format` if `scripts.format` exists; else skip | `npm run lint` if `scripts.lint` exists; else skip | `npm test` if `scripts.test` exists; else skip |

**Flutter vs Dart-only detection:** if `pubspec.yaml` contains `flutter:`
under `dependencies`, use the `flutter` toolchain commands. Otherwise use
plain `dart` commands.

**Node script discovery:** the skill reads `package.json` and runs only the
scripts that actually exist. Avoids inventing commands the project hasn't
defined.

### Override: `.claude/pr-preflight.sh`

When present in the repo root, the skill runs it instead of auto-detection.
The script's exit code is the verdict (0 = pass, non-zero = fail). The
script's stdout/stderr are surfaced to the user.

Example minimal content for a monorepo:

```sh
#!/usr/bin/env bash
set -e
cd packages/web && npm run format:check && npm run lint && npm test
cd ../../packages/api && npm run format:check && npm run lint && npm test
```

The skill should also offer to **create** a stub `.claude/pr-preflight.sh`
when no marker file is detected — a 3-line skeleton the user can fill in.

### Edge cases

- **No marker file and no override script.** Skill reports "no preflight
  recipe detected" and offers to write a stub. Does NOT block the PR — the
  caller decides whether to proceed without preflight.
- **Autofix changes files.** Skill reports the changed file paths
  explicitly. The caller decides whether to amend the current commit, make
  a new commit, or stash. Skill does not stage or commit.
- **Test failures.** Hard fail. Do not proceed to `gh pr create`. Real bugs,
  not mechanical.
- **Analyze warnings vs errors.** Only errors block. Warnings/infos surface
  but do not fail the preflight. Matches the `--no-fatal-infos` posture in
  this repo's CI.
- **Detection picks the wrong stack** (e.g., a Node `tools/` dir inside a
  Rust repo where `Cargo.toml` is checked first). User creates
  `.claude/pr-preflight.sh` to override. The escape hatch resolves it.
- **Skill auto-fixes but a subsequent step still fails.** The autofixed
  files remain in the working tree. The caller sees the failure report and
  decides what to do with the partial fixes.

### What the skill body looks like

- Single `SKILL.md` at `~/.claude/skills/pr-preflight/SKILL.md`.
- ~80–120 lines of markdown.
- No helper scripts. The skill describes the commands; the model executes
  them via Bash.
- Structure:
  1. Front matter (`name`, `description`).
  2. "When to invoke" (short).
  3. Flowchart (the dot graph above, or a numbered list).
  4. Stack-detection table.
  5. Per-stack command reference.
  6. Edge-case handling.
  7. Reporting format (so the model produces consistent output).

## Alternatives considered

### A — Pure auto-detect, no override
Simpler skill but no escape hatch. Rejected because monorepos and unusual
toolchains (e.g., Bazel, Nx, custom Makefiles) would constantly fight the
defaults.

### B — Pure per-project script
Skill is trivially simple — just runs `.claude/pr-preflight.sh`. Rejected
because it requires a 3-line setup step on every new project before the
skill provides any value. The hybrid keeps day-one ergonomics while leaving
the override available.

### Claude Code hook on `gh pr create` (PreToolUse)
Considered but not selected. A hook is harness-enforced and cannot be
skipped by the model, which is a real advantage. But hooks are
project-scoped and harder to adjust per-invocation (e.g., when intentionally
opening a draft PR for in-progress work). The skill approach is
description-triggered: the model invokes it as part of the PR-creation
flow, and the user can opt out for a single PR by saying so. May reconsider
adding a hook layer later if the skill alone proves insufficient.

## Open questions

None at design time. Implementation plan will resolve any remaining detail
(exact wording of the SKILL.md description, the exact bash incantations for
edge cases like Windows path quoting).
