# CI/CD Pipeline & Git Flow — Design Spec

**Date:** 2026-04-20
**Status:** Approved
**Scope:** Define the branching model, PR quality gates, release/production deployment flows, and supporting infrastructure for ccwmap (a Flutter iOS + Android app).

## 1. Goals & Non-Goals

### Goals
- Enforce PR-based changes to `master` with blocking quality checks.
- Automate deployment to iOS TestFlight + Android Play Console Internal track from a `release/*` branch push.
- Automate promotion to iOS App Store + Android Play Production from a `v*.*.*` tag push.
- Keep the pipeline intelligible for a solo / small-team project — no ceremony that doesn't pay rent.
- Preserve the existing `SHOW_DEBUG_UI` compile-time flag convention (on for beta, off for production).

### Non-Goals
- No permanent `develop` integration branch (simpler trunk-based model).
- No Fastlane (keep parity with the existing minimal-deps GitHub Actions style).
- No realtime Slack/email notifications (solo; GitHub's own notifications are enough).
- No automated version bumping of `pubspec.yaml` — semver is a judgment call; humans own it.

## 2. Branching Model

```
master (protected, production)
  ↑
  ├── feature/*       (new features)
  ├── bugfix/*        (non-critical fixes)
  ├── chore/*         (tooling, deps, docs — e.g. chore/deps-upgrade-2026-04)
  ├── refactor/*
  ├── release/vX.Y.Z  (cut off master; version bump; merges back to master)
  └── hotfix/vX.Y.Z   (cut off a production tag; patches prod; merges back to master)
```

### Branch rules
- **`master`** is the only long-lived branch. Always deployable. Protected: require PR, require all status checks green, require branch up-to-date with base, no force-push, no direct commits.
- **`feature/*` / `bugfix/*` / `chore/*` / `refactor/*`** → PR to `master`. **Squash-merge** for clean history.
- **`release/vX.Y.Z`** → cut off `master` when a version is ready for beta. Version bump lives here. PR back to `master` uses **merge commit** (preserves release point). Tagging `vX.Y.Z` on `master` triggers production deploy.
- **`hotfix/vX.Y.Z`** → cut off the production tag being patched (`git checkout -b hotfix/v0.3.1 v0.3.0`). Reuses the release workflow for beta testing, then merges to `master` via merge commit, then tagged.

### Branch protection configuration (applied via repo settings, not committed code)
- Require a pull request before merging to `master`.
- Require status checks to pass: `format`, `analyze-test`, `build-android`, `build-ios`, `secret-scan`.
- Require branches to be up to date before merging.
- Do not allow bypassing (including admins — keeps me honest).
- Disallow force-pushes to `master` and to all `release/*` / `hotfix/*` branches (a branch-protection rule matching the glob `{master,release/**,hotfix/**}`).

## 3. PR Pipeline — `.github/workflows/pr-checks.yml`

**Trigger:** `pull_request` to `master`.

**Five parallel required jobs:**

| Job | Runner | Purpose | Command |
|---|---|---|---|
| `format` | ubuntu-latest | Enforce Dart formatting | `dart format --output=none --set-exit-if-changed .` |
| `analyze-test` | ubuntu-latest | Static analysis + unit tests | `flutter pub get` → `flutter analyze --no-fatal-infos` → `flutter test` |
| `build-android` | ubuntu-latest | Catch Android build breakage early | `flutter build apk --debug` |
| `build-ios` | macos-latest | Catch iOS build breakage early | `flutter build ios --release --no-codesign` |
| `secret-scan` | ubuntu-latest | Block committed credentials | `gitleaks/gitleaks-action@v2` against the PR diff |

All jobs use the shared `.github/actions/setup-flutter` composite action (checkout → flutter-action → pub cache → write `.env` from secrets).

**Supersedes** the existing `.github/workflows/ios.yml`. That file is deleted as part of migration.

## 4. Weekly Scans — `.github/workflows/weekly-scans.yml`

**Trigger:** `schedule: cron '0 13 * * 1'` (Mondays 13:00 UTC = 09:00 ET) + `workflow_dispatch`.

**Two jobs, non-blocking (run on `master`, not PRs):**

| Job | Tool | What it checks |
|---|---|---|
| `dep-vuln-scan` | `google/osv-scanner-action@v1` | `pubspec.lock` + `android/app/build.gradle.kts` + `ios/Podfile.lock` against the OSV vulnerability database |
| `codeql` | `github/codeql-action/init@v3` + `analyze@v3` | Swift + Kotlin + JS static analysis. Dart is skipped (no official CodeQL support) — covered by `flutter analyze` in PR pipeline. |

**On failure:** `actions/github-script` opens a GitHub issue tagged `security` linking to the failing run. Subsequent failures de-duplicate by searching for an open issue with the same title.

## 5. Release Flow — `.github/workflows/release.yml`

**Trigger:** `push` to branches matching `release/v*` **or** `hotfix/v*`.

**Two parallel jobs:**

| Job | Runner | Output |
|---|---|---|
| `deploy-ios-testflight` | macos-latest | Builds IPA → uploads to TestFlight internal testing |
| `deploy-android-internal` | ubuntu-latest | Builds AAB → uploads to Play Console `internal` track |

### Version-stamp step (both jobs, before `flutter build`)

```bash
SEMVER=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1)
BUILD=${{ github.run_number }}
sed -i.bak "s/^version:.*/version: ${SEMVER}+${BUILD}/" pubspec.yaml
```

- **Semver** comes from `pubspec.yaml` (manually edited on the release branch).
- **Build number** comes from `github.run_number` — monotonic, never repeats across workflow runs in the repo.

### Build flags
Both jobs pass `--dart-define=SHOW_DEBUG_UI=true`. This matches the existing CLAUDE.md contract: debug UI ships to beta / internal testers, tree-shaken out of production.

### iOS deploy specifics
- Xcode 26 selected explicitly (`sudo xcode-select -s $(ls -d /Applications/Xcode_26*.app | head -1)`).
- `apple-actions/import-codesign-certs@v3` imports the distribution cert from `CERTIFICATES_P12`.
- Provisioning profile decoded from `PROVISIONING_PROFILE` into `~/Library/MobileDevice/Provisioning Profiles/`.
- `flutter build ipa --release --dart-define=SHOW_DEBUG_UI=true --export-options-plist=ios/ExportOptions.plist`.
- `apple-actions/upload-testflight-build@v3` pushes the IPA using the App Store Connect API key.

### Android deploy specifics
- Decode `ANDROID_KEYSTORE_BASE64` into `android/app/release.jks`.
- Set env vars consumed by `android/app/build.gradle.kts` signing config: `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEYSTORE_PATH=app/release.jks`.
- `flutter build appbundle --release --dart-define=SHOW_DEBUG_UI=true`.
- `r0adkll/upload-google-play@v1` uploads `build/app/outputs/bundle/release/app-release.aab` to track `internal` using `PLAY_SERVICE_ACCOUNT_JSON`.

### Post-deploy step
Creates or updates a **draft GitHub Release** named `vX.Y.Z` pointing at the release branch HEAD, with body template:

> Testing in TestFlight (build {run_number}) and Play Internal (build {run_number}). Tag this commit `vX.Y.Z` after beta verification to promote to production.

## 6. Production Flow — `.github/workflows/production.yml`

**Trigger:** `push` to tags matching `v*.*.*`.

**Two parallel jobs** — same structure as release, different outputs:

| Job | Output |
|---|---|
| `deploy-ios-appstore` | Builds IPA **without** `SHOW_DEBUG_UI` → uploads to App Store Connect for App Store review |
| `deploy-android-production` | Builds AAB **without** `SHOW_DEBUG_UI` → uploads to Play Console `production` track |

### Version-stamp step differs

```bash
SEMVER=${GITHUB_REF_NAME#v}   # v0.3.0 → 0.3.0
BUILD=${{ github.run_number }}
sed -i.bak "s/^version:.*/version: ${SEMVER}+${BUILD}/" pubspec.yaml
```

The tag is authoritative — `pubspec.yaml` in `master` can lag the tag without harm.

### Critical guard
**No `--dart-define=SHOW_DEBUG_UI=true`.** The debug UI is tree-shaken out. This is the guard behind the TODO in CLAUDE.md's "CI/CD & Build Flags" section.

### Post-deploy step
1. Promotes the draft GitHub Release to published.
2. Attaches the IPA and AAB as release assets for forensic reference.

### Store-side manual steps (intentionally not automated)
- App Store: the IPA lands in App Store Connect in "Processing" state. You manually submit for review in the App Store Connect UI when ready — this preserves the human checkpoint on what actually ships to end users.
- Play: the AAB lands in the `production` track, rollout is **halted at 0%** via the `changesNotSentForReview: true` and `status: draft` options. You manually set the rollout percentage in the Play Console UI.

## 7. Hotfix Flow

Rare, manual, no separate workflow file.

1. Production has a P0 bug at `v0.3.0`. Cut the branch: `git checkout -b hotfix/v0.3.1 v0.3.0`.
2. Fix the bug. Bump `pubspec.yaml` to `0.3.1`. Commit. Push.
3. The branch name pattern `hotfix/v*` triggers `release.yml` → the hotfix is beta-tested on TestFlight + Play Internal just like a regular release.
4. Once verified, open PR `hotfix/v0.3.1` → `master`, merge-commit.
5. Tag `v0.3.1` on the merge commit. `production.yml` fires → public stores.

Hotfixes reuse the release workflow entirely. No duplication.

## 8. Shared Composite Action — `.github/actions/setup-flutter/action.yml`

Reusable steps consolidated:

- `actions/checkout@v4`
- `subosito/flutter-action@v2` (pinned to `channel: stable`; optional `flutter-version` input if a workflow needs to override)
- Cache `~/.pub-cache` keyed on `pubspec.lock` hash
- Write `.env` from `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPTILER_API_KEY` secrets (all three passed as inputs)
- Run `flutter pub get`

Consumed by all five workflows. Cuts ~40 lines of duplication per workflow.

## 9. Android Signing Configuration

`android/app/build.gradle.kts` `android { signingConfigs { release { ... } } }` block is refactored to read from env vars when `System.getenv("CI")` is set, falling back to a local `android/key.properties` file for developer builds:

```kotlin
signingConfigs {
    create("release") {
        if (System.getenv("CI") == "true") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH") ?: "app/release.jks")
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        } else {
            val props = Properties().apply {
                val f = rootProject.file("key.properties")
                if (f.exists()) load(f.inputStream())
            }
            storeFile = props["storeFile"]?.let { file(it as String) }
            storePassword = props["storePassword"] as String?
            keyAlias = props["keyAlias"] as String?
            keyPassword = props["keyPassword"] as String?
        }
    }
}
```

A `android/key.properties.template` is committed (values blanked) as documentation. Actual `key.properties` stays gitignored.

## 10. Secrets Inventory (GitHub Actions)

### Already present — unchanged
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPTILER_API_KEY` — injected into `.env` at build time.
- `CERTIFICATES_P12`, `CERTIFICATES_PASSWORD` — iOS distribution cert.
- `PROVISIONING_PROFILE` — base64-encoded iOS provisioning profile.
- `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_PRIVATE_KEY` — App Store Connect API key (works for both TestFlight and App Store upload).

### New — must be added before Android workflows will function
- `ANDROID_KEYSTORE_BASE64` — base64-encoded `.jks` release keystore.
- `ANDROID_KEYSTORE_PASSWORD` — keystore password.
- `ANDROID_KEY_ALIAS` — key alias within the keystore.
- `ANDROID_KEY_PASSWORD` — key password.
- `PLAY_SERVICE_ACCOUNT_JSON` — Google Play Console service account JSON. Service account must have "Release manager" role for the app in Play Console.

## 11. Files Touched

```
CREATED:
  .github/workflows/pr-checks.yml
  .github/workflows/weekly-scans.yml
  .github/workflows/release.yml
  .github/workflows/production.yml
  .github/actions/setup-flutter/action.yml
  android/key.properties.template
  docs/GIT_FLOW.md

DELETED:
  .github/workflows/ios.yml            (absorbed into pr-checks.yml)
  .github/workflows/ios-testflight.yml (absorbed into release.yml)

MODIFIED:
  android/app/build.gradle.kts  — CI-aware signing config
  .gitignore                    — ensure android/key.properties stays ignored
  CLAUDE.md                     — update "CI/CD & Build Flags" section with new
                                  workflow names and the production.yml guarantee
                                  that SHOW_DEBUG_UI is omitted
```

## 12. Migration Plan (execution order)

1. Configure all new GitHub Secrets. (Nothing runs yet — no-op if unset.)
2. Generate Android release keystore (one-time; procedure is captured in step 12's GIT_FLOW.md so future-us doesn't have to re-derive it).
3. Refactor `android/app/build.gradle.kts` signing config + commit `key.properties.template`. Verify local `flutter build appbundle --release` still works using local `key.properties`.
4. Create `.github/actions/setup-flutter` composite action. Low-risk, reusable.
5. Add `pr-checks.yml`. Open a throwaway PR with a deliberate formatting error to confirm the `format` job fails; push a fix to confirm it recovers.
6. Delete `.github/workflows/ios.yml` once `pr-checks.yml` is proven on two consecutive PRs.
7. Add `release.yml`. Smoke-test by cutting `release/v0.2.1` (patch bump off current master). Verify: TestFlight receives build N, Play Internal receives build N. **Do not** merge the release branch to `master` on first run — treat first run as proof the workflow works.
8. Delete `.github/workflows/ios-testflight.yml` (the manual one).
9. Add `production.yml`. Merge the smoke-test `release/v0.2.1` to `master`, tag `v0.2.1`, verify: App Store Connect receives the IPA in "Processing" (do not submit for review), Play production receives the AAB with 0% rollout. Roll back if anything looks off — neither store auto-publishes.
10. Add `weekly-scans.yml`. Trigger manually via `workflow_dispatch` once to verify both jobs run; assess first-run findings before leaving them on cron.
11. Configure branch protection on `master` last, requiring all five `pr-checks.yml` jobs as required status checks.
12. Write `docs/GIT_FLOW.md` (ccwmap-specific version of the reference doc) and update CLAUDE.md.

## 13. Risk Register

| Risk | Mitigation |
|---|---|
| First Android CI build fails on signing config | Validate local `flutter build appbundle --release` first; budget an hour of fiddling. |
| App Store Connect rejects first upload because bundle ID / app record doesn't exist | One-time manual setup in App Store Connect web UI before production.yml runs (Xcode 14 on the secondary Mac isn't needed — it's all web-UI). |
| Play Console rejects first upload because app isn't opted into internal track | One-time manual setup: opt in to Internal testing, add at least one tester email. |
| `github.run_number` gets reset if the repo is recreated | Acceptable: if that ever happens, manually upload a one-off build with a higher build number to re-seed monotonicity. |
| A developer pushes `release/v*` prematurely and burns a build number | No real harm — build numbers can skip, just not repeat. TestFlight/Play won't reject skips. |
| `production.yml` runs on a tag that doesn't match a clean master commit | Git tag moves require explicit `--force` + push; branch protection doesn't guard tags. Mitigation: convention-only — tag only merge commits from release branches. Future enhancement could add a workflow step that verifies the tagged commit is reachable from `master` HEAD. |
| Secret scanner false positive blocks legit PR | Add `.gitleaksignore` file for documented exceptions; reviewer can override by amending the commit, not by disabling the check. |

## 14. Open Questions (deliberately left to implementation)

- Exact Xcode version pinning strategy (currently glob-matched to `Xcode_26*` in `ios-testflight.yml`). Implementation plan will decide whether to pin to a specific minor or keep the glob.
- Whether to add a pre-merge `concurrency:` group so a second push to the same PR cancels in-flight PR checks (probably yes — saves minutes, decided at implementation time).
- Retention policy for uploaded build artifacts (current `ios.yml` uses 14 days; may tighten for the new workflows).
- Whether to add iOS simulator tests (`flutter test integration_test`) to PR pipeline. Currently no integration tests exist in the repo — out of scope for this spec.
