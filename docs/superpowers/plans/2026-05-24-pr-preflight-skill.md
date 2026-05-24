# pr-preflight Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal Claude Code skill that runs format, analyze/lint, and test locally before a PR is opened — catching the class of mechanical CI failures that hit PR #27 (`dart format --set-exit-if-changed`), and applying generically across Dart/Flutter, Rust, Go, Python, and Node projects.

**Architecture:** Single SKILL.md at `~/.claude/skills/pr-preflight/SKILL.md`. Description-triggered: matches PR-creation phrases so the model invokes it ahead of `gh pr create`. Body specifies a deterministic flow — check for `.claude/pr-preflight.sh` override first, otherwise auto-detect stack by repo-root marker file, then run the conventional format/lint/test commands for that stack. Format failures are auto-fixed; analyze/test failures block. The skill describes the commands; the model executes them via Bash.

**Tech Stack:** Markdown (SKILL.md format), Bash (for the override script and command execution at runtime). No code dependencies.

**Spec:** `docs/superpowers/specs/2026-05-24-pr-preflight-design.md`

**Verification model:** Skill changes load on Claude Code session start. Inner-loop "TDD" doesn't apply — the loop is: write a chunk → read it back to confirm → restart Claude Code → verify behavior in a fresh session. Tasks 1–4 build the file with read-back checks; Task 5 is end-to-end verification in a new session.

**Note on commits:** The SKILL.md lives in `~/.claude/skills/`, NOT in the ccwmap repo. There's nothing to commit for Tasks 1–4. The spec (already committed at `8e7abef`) is the only artifact tracked in git. The plan itself will be committed before execution.

---

## File Structure

**Created during this plan:**
- `C:\Users\camil\.claude\skills\pr-preflight\SKILL.md` — the skill (single file, ~120 lines)

**No other files touched.** No helper scripts, no settings.json changes, no project-repo changes beyond the spec and this plan.

---

### Task 1: Create skill directory and write front matter + "When to invoke" section

**Files:**
- Create: `C:\Users\camil\.claude\skills\pr-preflight\SKILL.md`

- [ ] **Step 1: Confirm parent directory exists**

Run:
```powershell
Test-Path C:\Users\camil\.claude\skills
```
Expected: `True`

- [ ] **Step 2: Create the skill directory**

Run:
```powershell
New-Item -ItemType Directory -Force C:\Users\camil\.claude\skills\pr-preflight
```
Expected: directory exists at `C:\Users\camil\.claude\skills\pr-preflight\`.

- [ ] **Step 3: Write SKILL.md with front matter and intro sections only**

Use the `Write` tool to create `C:\Users\camil\.claude\skills\pr-preflight\SKILL.md` with this exact content:

````markdown
---
name: pr-preflight
description: Use before creating a pull request, opening a PR, pushing a branch up for review, or running `gh pr create` — runs the project's format, analyze/lint, and test checks locally to catch the same failures CI would flag. Auto-detects Dart/Flutter, Rust, Go, Python, and Node projects; honors a per-project `.claude/pr-preflight.sh` override.
---

# PR Preflight

Runs the cheap CI-equivalent checks locally before a PR is opened, so format/analyze/test failures are caught and (where mechanical) fixed before push.

## When to invoke

Invoke this skill when the user (or your own flow) is about to:

- Create a pull request (`gh pr create`, "open a PR", "make a PR", "submit for review")
- Push a feature branch up for review for the first time
- Manually run `/pr-preflight`

Do NOT invoke for:

- Routine pushes to an already-open PR (CI will run anyway)
- Draft PRs intentionally created with broken work-in-progress (the user will say so)
- Any non-PR-creation git operation (commit, fetch, branch, merge, rebase, etc.)

## Flow

1. **Override check.** If `.claude/pr-preflight.sh` exists in the repo root, run it via Bash. Its exit code is the verdict (0 = pass, non-zero = fail). Surface its stdout/stderr to the user. Skip the rest of the flow.

2. **Stack auto-detection.** Check for marker files in the repo root, first match wins:
   - `pubspec.yaml` → Dart/Flutter
   - `Cargo.toml` → Rust
   - `go.mod` → Go
   - `pyproject.toml` → Python
   - `package.json` → Node

   If no marker matches, stop. Report "no preflight recipe detected" and offer to write a stub `.claude/pr-preflight.sh`. Do not block the PR — the caller decides whether to proceed.

3. **Run the stack's checks in sequence**, stopping on the first hard failure:
   1. **Format check.** If clean, continue. If dirty, run the stack's autofix, then re-run the format check to confirm clean. Report which files changed.
   2. **Analyze / lint.** Only errors block — warnings and infos surface but do not fail the preflight.
   3. **Test.** Hard fail on any test failure.

4. **Report.** Use the reporting format below.
````

- [ ] **Step 4: Read back to confirm**

Use the `Read` tool on `C:\Users\camil\.claude\skills\pr-preflight\SKILL.md`. Confirm:
- Front matter has `name: pr-preflight` and the description string.
- "When to invoke" section lists the three trigger cases and three skip cases.
- "Flow" section has 4 numbered steps ending with "Report."
- No "Per-stack commands" or "Reporting format" sections yet — those come in Tasks 2 and 3.

---

### Task 2: Add per-stack command reference

**Files:**
- Modify: `C:\Users\camil\.claude\skills\pr-preflight\SKILL.md` (append after the "Flow" section)

- [ ] **Step 1: Append per-stack reference**

Use the `Edit` tool with `old_string` = the trailing lines of the current file:

```
4. **Report.** Use the reporting format below.
```

and `new_string` = the same lines followed by the new section below:

````markdown
4. **Report.** Use the reporting format below.

## Per-stack command reference

### Dart / Flutter (`pubspec.yaml` present)

Read `pubspec.yaml`. If it contains `flutter:` under `dependencies`, use the `flutter` toolchain. Otherwise use plain `dart` commands.

| Step          | Flutter project                                       | Dart-only project                                    |
|---------------|-------------------------------------------------------|------------------------------------------------------|
| Format check  | `dart format --output=none --set-exit-if-changed .`   | `dart format --output=none --set-exit-if-changed .`  |
| Autofix       | `dart format .`                                       | `dart format .`                                      |
| Analyze       | `flutter analyze --no-fatal-infos`                    | `dart analyze`                                       |
| Test          | `flutter test`                                        | `dart test`                                          |

### Rust (`Cargo.toml` present)

| Step          | Command                              |
|---------------|--------------------------------------|
| Format check  | `cargo fmt --check`                  |
| Autofix       | `cargo fmt`                          |
| Lint          | `cargo clippy -- -D warnings`        |
| Test          | `cargo test`                         |

### Go (`go.mod` present)

| Step          | Command                              |
|---------------|--------------------------------------|
| Format check  | `test -z "$(gofmt -l .)"`            |
| Autofix       | `gofmt -w .`                         |
| Vet           | `go vet ./...`                       |
| Test          | `go test ./...`                      |

### Python (`pyproject.toml` present)

Read `pyproject.toml` to determine which tools are configured. Prefer `ruff` if `[tool.ruff]` exists; fall back to `black` if `[tool.black]` exists.

| Step          | If ruff configured     | If black configured | Notes                                              |
|---------------|------------------------|---------------------|----------------------------------------------------|
| Format check  | `ruff format --check`  | `black --check .`   | Skip if neither configured                         |
| Autofix       | `ruff format`          | `black .`           |                                                    |
| Lint          | `ruff check`           | (skip)              | Skip if `[tool.ruff]` absent                       |
| Test          | `pytest`               | `pytest`            | Skip if `pytest` is not declared as a dependency   |

### Node (`package.json` present)

Read `package.json`'s `scripts` block. Run only scripts that actually exist — do not invent commands.

| Step          | Command                                                    | Condition                                |
|---------------|------------------------------------------------------------|------------------------------------------|
| Format check  | `npm run format:check`                                     | only if `scripts["format:check"]` exists |
| Autofix       | `npm run format`                                           | only if `scripts.format` exists          |
| Lint          | `npm run lint`                                             | only if `scripts.lint` exists            |
| Test          | `npm test`                                                 | only if `scripts.test` exists            |

If a project uses `pnpm` or `yarn` (lockfile present at `pnpm-lock.yaml` or `yarn.lock`), substitute the package manager: `pnpm run format:check`, `yarn format:check`, etc.
````

- [ ] **Step 2: Read back to confirm**

Use the `Read` tool. Confirm "Per-stack command reference" section is present with all five stacks (Dart/Flutter, Rust, Go, Python, Node) and each has its commands table.

---

### Task 3: Add reporting format, edge-case handling, and override-script stub

**Files:**
- Modify: `C:\Users\camil\.claude\skills\pr-preflight\SKILL.md` (append after the per-stack reference)

- [ ] **Step 1: Append reporting + edge cases + stub-script section**

Use the `Edit` tool with `old_string` = the last few lines of the Node section, ending with:

```
If a project uses `pnpm` or `yarn` (lockfile present at `pnpm-lock.yaml` or `yarn.lock`), substitute the package manager: `pnpm run format:check`, `yarn format:check`, etc.
```

and `new_string` = the same lines followed by the new content below:

````markdown
If a project uses `pnpm` or `yarn` (lockfile present at `pnpm-lock.yaml` or `yarn.lock`), substitute the package manager: `pnpm run format:check`, `yarn format:check`, etc.

## Reporting format

Always report in this structure. Use checkmarks for passed steps, `✗` for failed, `~` for auto-fixed.

**On full pass:**

```
PR Preflight — <stack name>
✓ Format clean
✓ Analyze clean
✓ Tests pass (<n> tests)
→ Preflight clean. Safe to `gh pr create`.
```

**On format autofix:**

```
PR Preflight — <stack name>
~ Format: auto-fixed (<count>) file(s):
    <relative path 1>
    <relative path 2>
✓ Format clean (after fix)
✓ Analyze clean
✓ Tests pass (<n> tests)
→ Preflight clean. Note: autofix modified working tree. Decide whether to amend, commit, or stash before `gh pr create`.
```

**On analyze or test failure:**

```
PR Preflight — <stack name>
✓ Format clean
✗ <Analyze | Tests> failed:

<verbatim relevant stderr/stdout, trimmed to the actionable lines>

→ Preflight failed. Do NOT proceed to `gh pr create`. Fix and re-run.
```

**On override script run:**

```
PR Preflight — running .claude/pr-preflight.sh

<script stdout/stderr>

→ Exit code <n>. <Preflight clean | Preflight failed>.
```

**On no recipe detected:**

```
PR Preflight — no recipe detected
No marker file (pubspec.yaml, Cargo.toml, go.mod, pyproject.toml, package.json) found in repo root, and no .claude/pr-preflight.sh override.

Options:
1. Tell me what to run and I'll create a `.claude/pr-preflight.sh` for this project.
2. Proceed without preflight (you're on the hook for CI).
```

## Override script

When `.claude/pr-preflight.sh` exists, the skill defers to it entirely. The script should:

- Use `set -e` so the first failure exits non-zero.
- Run only the project's fast checks (format, lint, test). Skip slow builds.
- Exit 0 on full pass; non-zero on any failure.

Stub template (offer this when "no recipe detected" and the user wants to create one):

```sh
#!/usr/bin/env bash
# .claude/pr-preflight.sh — runs the local equivalent of CI's fast checks.
# Exit 0 = preflight clean. Non-zero = blocks PR creation.
set -e

# Format check
# <command>

# Lint / analyze
# <command>

# Test
# <command>
```

Make the file executable after creating it (`chmod +x .claude/pr-preflight.sh`).

## Edge cases

- **Autofix changes files.** Surface the changed paths explicitly. Do NOT `git add` or commit them. Caller decides whether to amend the current commit, make a new one, or stash.
- **Autofix runs but the second format check still fails.** Treat as hard fail and report. Modified files remain in the working tree.
- **Analyze surfaces warnings only.** Show them in the output but pass the step.
- **Detection picks the wrong stack** (e.g., a `package.json` in a Rust repo for tooling). User creates `.claude/pr-preflight.sh` to override.
- **Cross-platform paths.** On Windows, prefer running commands through Bash (`bash -c "..."`) so `gofmt -l .` and similar work as written.
- **No tests configured.** Skip the test step silently and report `✓ No tests configured`.
````

- [ ] **Step 2: Read back to confirm full file**

Use the `Read` tool. Confirm the file has, in order:
1. Front matter (`name`, `description`)
2. `# PR Preflight` heading + intro line
3. `## When to invoke`
4. `## Flow`
5. `## Per-stack command reference`
6. `## Reporting format`
7. `## Override script`
8. `## Edge cases`

Confirm total line count is roughly 120–150 lines. If under 90, a section is missing.

---

### Task 4: Commit the plan to the project repo

**Files:**
- Add: `docs/superpowers/plans/2026-05-24-pr-preflight-skill.md` (this file)

The skill itself lives outside the repo, but the plan that produced it belongs with the spec. Track this plan in git so the next engineer (or future-me) can find it next to the spec.

- [ ] **Step 1: Confirm only the plan file is unstaged**

Run:
```bash
git status --short
```
Expected: a single `??` or `M` line for `docs/superpowers/plans/2026-05-24-pr-preflight-skill.md`. If other files appear, leave them alone — stage only the plan.

- [ ] **Step 2: Stage and commit**

Run:
```bash
git add docs/superpowers/plans/2026-05-24-pr-preflight-skill.md
git commit -m "$(cat <<'EOF'
docs(superpowers): implementation plan for pr-preflight skill

Tracks the build steps for the skill specified in 8e7abef.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
Expected: commit created on `feature/pre-populate`, working tree clean.

- [ ] **Step 3: Verify**

Run:
```bash
git log -1 --stat
```
Expected: shows the new commit touching only `docs/superpowers/plans/2026-05-24-pr-preflight-skill.md`.

---

### Task 5: End-to-end behavior verification in a fresh Claude Code session

This is the only real "test" for a skill — restart and verify it triggers, detects, runs, and reports correctly.

**Files:** none (verification only)

- [ ] **Step 1: Restart Claude Code**

Exit and reopen the Claude Code session in `C:\Users\camil\projects\ccwmap`. The system-reminder skill list should now include:

> `pr-preflight: Use before creating a pull request, opening a PR, pushing a branch up for review, or running gh pr create — ...`

If it does not appear, the front matter is malformed. Run `Read` on the SKILL.md and check the `---` fences and `name:` / `description:` keys.

- [ ] **Step 2: Verify trigger on PR-creation intent**

In the fresh session, send:

> "I want to open a PR for the current branch. Can you check we're ready first?"

Expected: the model invokes the `pr-preflight` skill (visible in the response or tool calls). If it does not, the description string needs more trigger keywords.

- [ ] **Step 3: Verify clean-path detection on ccwmap**

The current branch (`feature/pre-populate`) should be clean post-merge. Expected behavior:
- Detects Dart/Flutter (via `pubspec.yaml` with `flutter:` dep).
- Runs `dart format --output=none --set-exit-if-changed .` → clean.
- Runs `flutter analyze --no-fatal-infos` → clean.
- Runs `flutter test` → all 109 tests pass.
- Reports the clean-path format (✓ × 3, "Safe to `gh pr create`").

Expected runtime: roughly 60–90 seconds total. If it tries to run an Android or iOS build, the flow section is wrong — those are explicitly out of scope.

- [ ] **Step 4: Verify autofix path**

Introduce a deliberate format violation:

```powershell
$file = "C:\Users\camil\projects\ccwmap\lib\presentation\screens\map_screen.dart"
$original = Get-Content $file -Raw
Set-Content $file -Value ($original -replace "import 'package:flutter/material.dart';", "import   'package:flutter/material.dart';") -NoNewline
```
(Adds extra whitespace inside an import — `dart format` will normalize it.)

Then in the Claude Code session say:

> "Re-run pr-preflight."

Expected:
- First format check fails.
- Skill runs `dart format .`, surfaces `lib/presentation/screens/map_screen.dart` as changed.
- Re-runs format check, clean.
- Analyze + test pass.
- Reports the autofix format (`~ Format: auto-fixed (1) file(s)`, ✓ × 2, note about working-tree modification).

Restore the file:
```powershell
Set-Content $file -Value $original -NoNewline
```
Or `git restore lib/presentation/screens/map_screen.dart`.

- [ ] **Step 5: Verify override-script path**

Create a stub override:
```powershell
New-Item -ItemType Directory -Force C:\Users\camil\projects\ccwmap\.claude
Set-Content -Encoding utf8 C:\Users\camil\projects\ccwmap\.claude\pr-preflight.sh -Value @'
#!/usr/bin/env bash
set -e
echo "running override script"
exit 0
'@
```

In the Claude Code session say:

> "Run pr-preflight."

Expected: skill detects `.claude/pr-preflight.sh`, runs it via `bash .claude/pr-preflight.sh`, reports the override format with `Exit code 0. Preflight clean.` Does NOT run `dart format` or any auto-detected commands.

Clean up:
```powershell
Remove-Item C:\Users\camil\projects\ccwmap\.claude\pr-preflight.sh
Remove-Item C:\Users\camil\projects\ccwmap\.claude -Recurse -ErrorAction SilentlyContinue
```

- [ ] **Step 6: Verify "no recipe" path**

In an unrelated directory (e.g., `C:\Users\camil\temp-empty`) with no marker files:

```powershell
New-Item -ItemType Directory -Force C:\Users\camil\temp-preflight-test
```

Open Claude Code in that directory, say:

> "Run pr-preflight."

Expected: reports `PR Preflight — no recipe detected`, offers the two options (write stub script, or proceed without). Does NOT crash or pick a stack at random.

Clean up:
```powershell
Remove-Item C:\Users\camil\temp-preflight-test -Recurse
```

---

## Self-review

Run this against the spec before declaring done:

**1. Spec coverage:**
- ✓ Skill at `~/.claude/skills/pr-preflight/SKILL.md` → Task 1
- ✓ Description triggers on PR-creation phrases → Task 1 front matter; verified Task 5 Step 2
- ✓ Override-first detection → Task 1 Flow Step 1; verified Task 5 Step 5
- ✓ Auto-detect five stacks → Task 2 per-stack reference; verified Task 5 Step 3 (Dart/Flutter)
- ✓ Autofix format, block on analyze/test → Task 1 Flow Step 3; verified Task 5 Step 4
- ✓ Reporting format → Task 3
- ✓ "No recipe" graceful handling → Task 3; verified Task 5 Step 6
- ✓ Edge cases (autofix-then-fail, Windows paths, no tests) → Task 3 Edge cases section

**2. Placeholder scan:** No TBDs, no "implement later", no "similar to Task N", no "add error handling" — every step shows exact commands or full markdown content.

**3. Type consistency:** Skill name `pr-preflight` used identically in all tasks. Commands match the spec table exactly.

**4. Honest TDD note:** Plan acknowledges that skill authoring doesn't have a useful TDD inner loop; verification is per-chunk file read-back plus an end-to-end smoke test in a fresh session (Task 5). The smoke test exercises all five flow branches.
