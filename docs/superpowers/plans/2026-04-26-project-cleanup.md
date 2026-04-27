# Project Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declutter the repository root and make `docs/` consistent by separating GitHub Pages web content from developer documentation.

**Architecture:** All developer markdown docs move into a new `docs/dev/` subfolder; store screenshots move to a top-level `store-assets/` folder; one misnamed plan file gets renamed to follow the superpowers convention; active cross-references are updated; `pub_upgrade.log` is removed from git tracking (already covered by the `*.log` gitignore rule).

**Tech Stack:** Git (mv for history-preserving moves), Dart/Flutter (one comment update)

---

### Task 1: Create `docs/dev/` and move root dev docs there

**Files:**
- Move: `FUNCTIONAL_SPEC.md` → `docs/dev/FUNCTIONAL_SPEC.md`
- Move: `IMPLEMENTATION_PLAN.md` → `docs/dev/IMPLEMENTATION_PLAN.md`
- Move: `IOS_BUILD_STATUS.md` → `docs/dev/IOS_BUILD_STATUS.md`
- Move: `ITERATION_8_NOTES.md` → `docs/dev/ITERATION_8_NOTES.md`
- Move: `TESTING_GUIDELINES.md` → `docs/dev/TESTING_GUIDELINES.md`
- Move: `APP_STORE_DEPLOYMENT.md` → `docs/dev/APP_STORE_DEPLOYMENT.md`
- Move: `PLAY_STORE_DEPLOYMENT.md` → `docs/dev/PLAY_STORE_DEPLOYMENT.md`

- [ ] **Step 1: Create the target directory**

```bash
mkdir docs/dev
```

- [ ] **Step 2: Move all seven root dev docs**

```bash
git mv FUNCTIONAL_SPEC.md docs/dev/FUNCTIONAL_SPEC.md
git mv IMPLEMENTATION_PLAN.md docs/dev/IMPLEMENTATION_PLAN.md
git mv IOS_BUILD_STATUS.md docs/dev/IOS_BUILD_STATUS.md
git mv ITERATION_8_NOTES.md docs/dev/ITERATION_8_NOTES.md
git mv TESTING_GUIDELINES.md docs/dev/TESTING_GUIDELINES.md
git mv APP_STORE_DEPLOYMENT.md docs/dev/APP_STORE_DEPLOYMENT.md
git mv PLAY_STORE_DEPLOYMENT.md docs/dev/PLAY_STORE_DEPLOYMENT.md
```

- [ ] **Step 3: Verify moves are staged**

```bash
git status
```

Expected: seven `renamed: XXXX.md -> docs/dev/XXXX.md` entries under "Changes to be committed".

---

### Task 2: Move `docs/` markdown files to `docs/dev/`

**Files:**
- Move: `docs/DEPLOY.md` → `docs/dev/DEPLOY.md`
- Move: `docs/GIT_FLOW.md` → `docs/dev/GIT_FLOW.md`
- Move: `docs/MODERATION.md` → `docs/dev/MODERATION.md`
- Move: `docs/RELEASE_NOTES.md` → `docs/dev/RELEASE_NOTES.md`

- [ ] **Step 1: Move the four docs/ markdown files**

```bash
git mv docs/DEPLOY.md docs/dev/DEPLOY.md
git mv docs/GIT_FLOW.md docs/dev/GIT_FLOW.md
git mv docs/MODERATION.md docs/dev/MODERATION.md
git mv docs/RELEASE_NOTES.md docs/dev/RELEASE_NOTES.md
```

- [ ] **Step 2: Verify**

```bash
git status
```

Expected: four additional `renamed: docs/XXXX.md -> docs/dev/XXXX.md` entries.

---

### Task 3: Move and rename the iOS POI tap fix plan

**Files:**
- Move+rename: `docs/ios-poi-tap-fix-plan.md` → `docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md`

- [ ] **Step 1: Move and rename**

```bash
git mv docs/ios-poi-tap-fix-plan.md docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md
```

- [ ] **Step 2: Verify**

```bash
git status
```

Expected: one additional `renamed: docs/ios-poi-tap-fix-plan.md -> docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md` entry.

---

### Task 4: Create `store-assets/` and move root screenshots

**Files:**
- Move: `screenshot-1.png` through `screenshot-5.png` → `store-assets/`
- Move: `ipad-screenshot-1.png` through `ipad-screenshot-5.png` → `store-assets/`

- [ ] **Step 1: Create the target directory**

```bash
mkdir store-assets
```

- [ ] **Step 2: Move Android screenshots**

```bash
git mv screenshot-1.png store-assets/screenshot-1.png
git mv screenshot-2.png store-assets/screenshot-2.png
git mv screenshot-3.png store-assets/screenshot-3.png
git mv screenshot-4.png store-assets/screenshot-4.png
git mv screenshot-5.png store-assets/screenshot-5.png
```

- [ ] **Step 3: Move iPad screenshots**

```bash
git mv ipad-screenshot-1.png store-assets/ipad-screenshot-1.png
git mv ipad-screenshot-2.png store-assets/ipad-screenshot-2.png
git mv ipad-screenshot-3.png store-assets/ipad-screenshot-3.png
git mv ipad-screenshot-4.png store-assets/ipad-screenshot-4.png
git mv ipad-screenshot-5.png store-assets/ipad-screenshot-5.png
```

- [ ] **Step 4: Verify**

```bash
git status
```

Expected: ten additional `renamed: XXXX.png -> store-assets/XXXX.png` entries.

---

### Task 5: Commit all file moves

- [ ] **Step 1: Confirm full staged diff looks right (no content changes — only renames)**

```bash
git diff --cached --stat
```

Expected: 22 lines of renames, 0 insertions, 0 deletions.

- [ ] **Step 2: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore: move dev docs to docs/dev/ and screenshots to store-assets/

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Update references in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

Four references need updating.

- [ ] **Step 1: Update FUNCTIONAL_SPEC.md reference (line ~57)**

In `CLAUDE.md`, find and replace:

```
Spec updated in `FUNCTIONAL_SPEC.md` (sections 3, Data Model, and Row Level Security).
```

With:

```
Spec updated in `docs/dev/FUNCTIONAL_SPEC.md` (sections 3, Data Model, and Row Level Security).
```

- [ ] **Step 2: Update GIT_FLOW.md reference (line ~89)**

In `CLAUDE.md`, find and replace:

```
See `docs/GIT_FLOW.md` for the full release playbook.
```

With:

```
See `docs/dev/GIT_FLOW.md` for the full release playbook.
```

- [ ] **Step 3: Update MODERATION.md and DEPLOY.md references (lines ~199–200)**

In `CLAUDE.md`, find and replace:

```
  plaintext email via Resend. See `docs/MODERATION.md` and
  `docs/DEPLOY.md`.
```

With:

```
  plaintext email via Resend. See `docs/dev/MODERATION.md` and
  `docs/dev/DEPLOY.md`.
```

- [ ] **Step 4: Verify no old paths remain**

```bash
grep -n "FUNCTIONAL_SPEC\.md\|docs/GIT_FLOW\|docs/MODERATION\|docs/DEPLOY" CLAUDE.md
```

Expected: zero matches.

---

### Task 7: Update references in `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update first IMPLEMENTATION_PLAN reference (line ~21)**

In `README.md`, find and replace:

```
See `IMPLEMENTATION_PLAN.md` for detailed development roadmap.
```

With:

```
See `docs/dev/IMPLEMENTATION_PLAN.md` for detailed development roadmap.
```

- [ ] **Step 2: Update second IMPLEMENTATION_PLAN reference (line ~149)**

In `README.md`, find and replace:

```
- **Implementation Plan**: See `IMPLEMENTATION_PLAN.md` for roadmap
```

With:

```
- **Implementation Plan**: See `docs/dev/IMPLEMENTATION_PLAN.md` for roadmap
```

- [ ] **Step 3: Verify no old path remains**

```bash
grep -n "IMPLEMENTATION_PLAN" README.md
```

Expected: two matches, both showing `docs/dev/IMPLEMENTATION_PLAN.md`.

---

### Task 8: Update screenshot references in `docs/dev/FUNCTIONAL_SPEC.md`

**Files:**
- Modify: `docs/dev/FUNCTIONAL_SPEC.md`

The file references `screenshot-1.png` through `screenshot-4.png` in multiple places. Each bare filename gets a `store-assets/` prefix. Replace all occurrences of each filename throughout the file.

- [ ] **Step 1: Replace all occurrences of `screenshot-1.png`**

In `docs/dev/FUNCTIONAL_SPEC.md`, replace all instances of:

```
screenshot-1.png
```

With:

```
store-assets/screenshot-1.png
```

- [ ] **Step 2: Replace all occurrences of `screenshot-2.png`**

In `docs/dev/FUNCTIONAL_SPEC.md`, replace all instances of:

```
screenshot-2.png
```

With:

```
store-assets/screenshot-2.png
```

- [ ] **Step 3: Replace all occurrences of `screenshot-3.png`**

In `docs/dev/FUNCTIONAL_SPEC.md`, replace all instances of:

```
screenshot-3.png
```

With:

```
store-assets/screenshot-3.png
```

- [ ] **Step 4: Replace all occurrences of `screenshot-4.png`**

In `docs/dev/FUNCTIONAL_SPEC.md`, replace all instances of:

```
screenshot-4.png
```

With:

```
store-assets/screenshot-4.png
```

- [ ] **Step 5: Verify no bare screenshot filenames remain**

```bash
grep -n "screenshot-[1-4]\.png" docs/dev/FUNCTIONAL_SPEC.md
```

Expected: all matches now show `store-assets/screenshot-N.png` prefixes.

---

### Task 9: Update `TESTING_GUIDELINES.md` reference in `docs/dev/IMPLEMENTATION_PLAN.md`

**Files:**
- Modify: `docs/dev/IMPLEMENTATION_PLAN.md`

- [ ] **Step 1: Update the reference (line ~480)**

In `docs/dev/IMPLEMENTATION_PLAN.md`, find and replace:

```
- `TESTING_GUIDELINES.md`
```

With:

```
- `docs/dev/TESTING_GUIDELINES.md`
```

- [ ] **Step 2: Verify**

```bash
grep -n "TESTING_GUIDELINES" docs/dev/IMPLEMENTATION_PLAN.md
```

Expected: one match showing `docs/dev/TESTING_GUIDELINES.md`.

---

### Task 10: Update dart comment in `maptiler_geocoding_client.dart`

**Files:**
- Modify: `lib/data/datasources/maptiler_geocoding_client.dart:30`

- [ ] **Step 1: Update the comment (line 30)**

In `lib/data/datasources/maptiler_geocoding_client.dart`, find and replace:

```
/// base map POI labels. See docs/ios-poi-tap-fix-plan.md.
```

With:

```
/// base map POI labels. See docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md.
```

- [ ] **Step 2: Verify**

```bash
grep -n "ios-poi-tap-fix" lib/data/datasources/maptiler_geocoding_client.dart
```

Expected: one match showing the new path `docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md`.

---

### Task 11: Commit all reference updates

- [ ] **Step 1: Check what's staged**

```bash
git diff --stat
```

Expected: `CLAUDE.md`, `README.md`, `docs/dev/FUNCTIONAL_SPEC.md`, `docs/dev/IMPLEMENTATION_PLAN.md`, `lib/data/datasources/maptiler_geocoding_client.dart` — all modified.

- [ ] **Step 2: Stage and commit**

```bash
git add CLAUDE.md README.md docs/dev/FUNCTIONAL_SPEC.md docs/dev/IMPLEMENTATION_PLAN.md lib/data/datasources/maptiler_geocoding_client.dart
git commit -m "$(cat <<'EOF'
chore: update doc cross-references to new paths

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Remove `pub_upgrade.log` from git tracking

`*.log` is already in `.gitignore`, but `pub_upgrade.log` was committed before that rule took effect, so git still tracks it. Remove it from the index; the existing `*.log` rule will prevent re-tracking.

**Files:**
- Remove from git: `pub_upgrade.log`

- [ ] **Step 1: Remove from git index (leaves file on disk initially)**

```bash
git rm --cached pub_upgrade.log
```

Expected output: `rm 'pub_upgrade.log'`

- [ ] **Step 2: Delete the file from disk**

```bash
rm pub_upgrade.log
```

- [ ] **Step 3: Confirm .gitignore already covers *.log (no edit needed)**

```bash
grep "\.log" .gitignore
```

Expected: `*.log` entry present.

- [ ] **Step 4: Commit**

`git rm --cached` already staged the deletion. Commit it directly — no additional staging needed.

```bash
git commit -m "$(cat <<'EOF'
chore: stop tracking pub_upgrade.log (covered by *.log gitignore rule)

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Final verification

- [ ] **Step 1: Confirm root is clean**

```bash
ls *.md *.png *.log 2>/dev/null
```

Expected: only `CLAUDE.md` and `README.md` match `*.md`. No `*.png` or `*.log` files.

- [ ] **Step 2: Confirm docs/ root has only web content and subdirs**

```bash
ls docs/
```

Expected: `auth/`, `data-deletion.html`, `dev/`, `index.html`, `privacy-policy.html`, `superpowers/`, `terms/`. No loose `.md` files.

- [ ] **Step 3: Confirm docs/dev/ has all eleven markdown files**

```bash
ls docs/dev/
```

Expected: `APP_STORE_DEPLOYMENT.md`, `DEPLOY.md`, `FUNCTIONAL_SPEC.md`, `GIT_FLOW.md`, `IOS_BUILD_STATUS.md`, `IMPLEMENTATION_PLAN.md`, `ITERATION_8_NOTES.md`, `MODERATION.md`, `PLAY_STORE_DEPLOYMENT.md`, `RELEASE_NOTES.md`, `TESTING_GUIDELINES.md`

- [ ] **Step 4: Confirm store-assets/ has all ten screenshots**

```bash
ls store-assets/
```

Expected: ten `.png` files (`screenshot-1..5.png` and `ipad-screenshot-1..5.png`).

- [ ] **Step 5: Confirm renamed plan exists**

```bash
ls docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md
```

Expected: file exists.

- [ ] **Step 6: Run flutter analyze to confirm no dart errors**

```bash
flutter analyze
```

Expected: no issues (the single dart comment change should not introduce any analysis errors).
