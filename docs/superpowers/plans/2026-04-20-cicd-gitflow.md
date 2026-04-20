# CI/CD Pipeline & Git Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a full PR-gated CI pipeline and two-stage CD pipeline (release branch → TestFlight + Play Internal; `v*.*.*` tag → App Store + Play Production) for this Flutter iOS + Android app.

**Architecture:** Trunk-based branching (`master` only, with short-lived `feature/*`, `release/v*`, `hotfix/v*`). Five parallel blocking PR checks. Release workflow fires on `release/v*` / `hotfix/v*` push; production workflow fires on `v*.*.*` tag push. One shared composite action handles Flutter setup.

**Tech Stack:** GitHub Actions, `subosito/flutter-action`, `apple-actions/import-codesign-certs`, `apple-actions/upload-testflight-build`, `r0adkll/upload-google-play`, `gitleaks/gitleaks-action`, `google/osv-scanner-action`, `github/codeql-action`.

**Design spec:** `docs/superpowers/specs/2026-04-20-cicd-gitflow-design.md` — refer back to it for rationale behind any decision below.

---

## Prerequisites (Human Actions)

These must be completed by the repo owner before any task below runs successfully. The plan itself does not perform these — it assumes they are done.

### P1. Generate Android release keystore

Run locally on the Windows dev machine (Git Bash):

```bash
keytool -genkey -v -keystore ccwmap-release.jks -alias ccwmap -keyalg RSA -keysize 2048 -validity 10000
```

Answer the prompts. Pick a strong password. **Store the `.jks` file outside the repo.** This is the app's identity in the Play Store — losing it means a new app listing.

Base64-encode for the GitHub secret:

```bash
base64 -w 0 ccwmap-release.jks > ccwmap-release.jks.b64
```

### P2. Create Google Play Console service account

1. In Google Cloud Console, create a service account (any name, e.g. `ccwmap-ci`).
2. Download its JSON key.
3. In Play Console → Users and permissions, invite the service account email; grant app-level permissions for `com.ccwmap.app`: **Release apps to testing tracks**, **Release apps to production**, **View app information**.

### P3. Add the following GitHub Actions secrets

Repo → Settings → Secrets and variables → Actions:

| Secret name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Contents of `ccwmap-release.jks.b64` (one line, no trailing newline) |
| `ANDROID_KEYSTORE_PASSWORD` | Password chosen in P1 |
| `ANDROID_KEY_ALIAS` | `ccwmap` |
| `ANDROID_KEY_PASSWORD` | Password chosen in P1 (same as keystore password unless you set a separate key password) |
| `PLAY_SERVICE_ACCOUNT_JSON` | Full contents of the JSON downloaded in P2 |

(Existing iOS and Supabase/MapTiler secrets are already present. Do not modify them.)

### P4. Opt the Android app into Internal testing track

Play Console → Testing → Internal testing → Create new release → add at least one tester email. Required before `r0adkll/upload-google-play` can push to the `internal` track.

### P5. Ensure App Store Connect app record exists

If not already created: App Store Connect → My Apps → + → New App. Fill out minimum required metadata. Bundle ID must match the iOS project bundle identifier.

---

## File Structure

**Created:**

```
.github/actions/setup-flutter/action.yml   # Reusable Flutter setup
.github/workflows/pr-checks.yml            # PR-gated checks
.github/workflows/release.yml              # TestFlight + Play Internal
.github/workflows/production.yml           # App Store + Play Production
.github/workflows/weekly-scans.yml         # OSV + CodeQL
android/key.properties.template            # Documentation for local signing
docs/GIT_FLOW.md                           # Branching + release playbook
```

**Modified:**

```
android/app/build.gradle.kts               # CI-aware signing config
CLAUDE.md                                   # CI/CD & Build Flags section updated
```

**Deleted (superseded):**

```
.github/workflows/ios.yml                  # replaced by pr-checks.yml
.github/workflows/ios-testflight.yml       # replaced by release.yml
```

---

## Task 1: Shared Composite Action `setup-flutter`

**Files:**
- Create: `.github/actions/setup-flutter/action.yml`

- [ ] **Step 1: Create the composite action**

Create `.github/actions/setup-flutter/action.yml` with this exact content:

```yaml
name: Setup Flutter
description: Install Flutter, cache pub deps, write .env, run pub get.
inputs:
  supabase-url:
    description: Supabase URL
    required: true
  supabase-anon-key:
    description: Supabase anon key
    required: true
  maptiler-api-key:
    description: MapTiler API key
    required: true
  flutter-version:
    description: Optional Flutter version override. Empty uses channel latest.
    required: false
    default: ''
runs:
  using: composite
  steps:
    - name: Install Flutter
      uses: subosito/flutter-action@v2
      with:
        channel: stable
        flutter-version: ${{ inputs.flutter-version }}
    - name: Cache pub dependencies
      uses: actions/cache@v4
      with:
        path: |
          ~/.pub-cache
          .dart_tool
        key: pub-${{ runner.os }}-${{ hashFiles('pubspec.lock') }}
        restore-keys: |
          pub-${{ runner.os }}-
    - name: Write .env
      shell: bash
      run: |
        cat > .env <<EOF
        SUPABASE_URL=${{ inputs.supabase-url }}
        SUPABASE_ANON_KEY=${{ inputs.supabase-anon-key }}
        MAPTILER_API_KEY=${{ inputs.maptiler-api-key }}
        EOF
    - name: flutter pub get
      shell: bash
      run: flutter pub get
```

Note: the composite does NOT include `actions/checkout` — the calling workflow must run that first (otherwise the composite file wouldn't even be on disk).

- [ ] **Step 2: Validate YAML locally**

Run (in Git Bash):

```bash
docker run --rm -v "$(pwd):/repo" -w /repo rhysd/actionlint:latest .github/actions/setup-flutter/action.yml || echo "actionlint not available — will rely on CI validation"
```

Expected: no output (success) OR the fallback message. The composite action is too small to have real errors but this catches typos.

- [ ] **Step 3: Commit**

```bash
git add .github/actions/setup-flutter/action.yml
git commit -m "ci: add shared setup-flutter composite action

Consolidates flutter-action + pub cache + .env write + pub get so
every workflow calls one step instead of five."
```

---

## Task 2: PR Checks Workflow

**Files:**
- Create: `.github/workflows/pr-checks.yml`

- [ ] **Step 1: Create the PR checks workflow**

Create `.github/workflows/pr-checks.yml` with this exact content:

```yaml
name: PR Checks

on:
  pull_request:
    branches: [master]

concurrency:
  group: pr-${{ github.ref }}
  cancel-in-progress: true

jobs:
  format:
    name: Format
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}
      - name: dart format check
        run: dart format --output=none --set-exit-if-changed .

  analyze-test:
    name: Analyze + Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}
      - name: flutter analyze
        run: flutter analyze --no-fatal-infos
      - name: flutter test
        run: flutter test

  build-android:
    name: Build Android (debug APK)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}
      - name: flutter build apk --debug
        run: flutter build apk --debug

  build-ios:
    name: Build iOS (no codesign)
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}
      - name: flutter build ios --release --no-codesign
        run: flutter build ios --release --no-codesign

  secret-scan:
    name: Secret scan (gitleaks)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Commit on a throwaway branch to smoke-test**

```bash
git add .github/workflows/pr-checks.yml
git commit -m "ci: add PR checks workflow (format, analyze+test, android, ios, secret-scan)"
```

- [ ] **Step 3: Push the current branch and open a test PR against master**

```bash
git push origin feature/cicd
```

Open a draft PR on GitHub: `feature/cicd` → `master`. All five jobs must fire.

Expected: all five jobs pass. If any fail, fix the underlying issue (not the workflow) before proceeding. Likely candidates:
- `format` fails → run `dart format .` locally and commit.
- `build-android` fails → run `flutter build apk --debug` locally to reproduce.

- [ ] **Step 4: Delete the legacy ios.yml**

Once pr-checks has run at least one fully-green pass:

```bash
git rm .github/workflows/ios.yml
git commit -m "ci: remove legacy ios.yml (absorbed into pr-checks.yml)"
```

---

## Task 3: Android Signing — CI-Aware Config

**Files:**
- Modify: `android/app/build.gradle.kts` (lines 12-17 and lines 37-44)
- Create: `android/key.properties.template`

- [ ] **Step 1: Refactor the signing config to read from env vars in CI**

In `android/app/build.gradle.kts`, replace lines 12-17:

```kotlin
// Load keystore properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
```

with:

```kotlin
// Load keystore properties from local file for dev builds. CI overrides
// these at runtime via environment variables (see release.yml / production.yml).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val isCi = System.getenv("CI") == "true"
```

And replace lines 37-44 (the `signingConfigs { create("release") { ... } }` block):

```kotlin
    signingConfigs {
        create("release") {
            if (isCi) {
                val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH") ?: "app/release.jks"
                storeFile = rootProject.file(keystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            } else {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { File(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }
```

- [ ] **Step 2: Create `android/key.properties.template`**

Create `android/key.properties.template` with this exact content:

```properties
# Copy this file to `android/key.properties` and fill in real values for local
# signed builds. The real key.properties is gitignored.
#
# CI builds ignore this file — they read signing config from environment
# variables set in .github/workflows/release.yml and production.yml.

storeFile=/absolute/path/to/your-release-key.jks
storePassword=YOUR_KEYSTORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

- [ ] **Step 3: Verify local release build still works**

Make sure `android/key.properties` exists and points at your local keystore (from Prerequisite P1). Run:

```bash
flutter build appbundle --release
```

Expected: Build succeeds. Output at `build/app/outputs/bundle/release/app-release.aab`.

If it fails with a signing error: verify `android/key.properties` has the four keys (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) and the `storeFile` path is absolute.

- [ ] **Step 4: Commit**

```bash
git add android/app/build.gradle.kts android/key.properties.template
git commit -m "build(android): make signing config CI-aware

Signing config now reads from env vars when CI=true, falls back to
local key.properties for dev builds. key.properties.template documents
the local workflow for future contributors."
```

---

## Task 4: Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the release workflow**

Create `.github/workflows/release.yml` with this exact content:

```yaml
name: Release (Beta)

on:
  push:
    branches:
      - 'release/v*'
      - 'hotfix/v*'

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  deploy-ios-testflight:
    name: iOS → TestFlight
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 26
        run: sudo xcode-select -s $(ls -d /Applications/Xcode_26*.app | head -1)

      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}

      - name: Stamp version (semver from pubspec + run_number build)
        run: |
          SEMVER=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1 | tr -d ' ')
          BUILD=${{ github.run_number }}
          sed -i.bak "s/^version:.*/version: ${SEMVER}+${BUILD}/" pubspec.yaml
          echo "Stamped: $(grep '^version:' pubspec.yaml)"

      - name: Import code signing certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.CERTIFICATES_P12 }}
          p12-password: ${{ secrets.CERTIFICATES_PASSWORD }}

      - name: Import provisioning profile
        run: |
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          echo "${{ secrets.PROVISIONING_PROFILE }}" | \
            base64 --decode > ~/Library/MobileDevice/Provisioning\ Profiles/profile.mobileprovision

      - name: Build IPA (SHOW_DEBUG_UI=true for beta)
        run: flutter build ipa --release --dart-define=SHOW_DEBUG_UI=true --export-options-plist=ios/ExportOptions.plist

      - name: Upload to TestFlight
        uses: apple-actions/upload-testflight-build@v3
        with:
          app-path: build/ios/ipa/ccwmap.ipa
          issuer-id: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
          api-key-id: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          api-private-key: ${{ secrets.APP_STORE_CONNECT_PRIVATE_KEY }}

  deploy-android-internal:
    name: Android → Play Internal
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'

      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}

      - name: Stamp version (semver from pubspec + run_number build)
        run: |
          SEMVER=$(grep '^version:' pubspec.yaml | sed 's/version: //' | cut -d'+' -f1 | tr -d ' ')
          BUILD=${{ github.run_number }}
          sed -i.bak "s/^version:.*/version: ${SEMVER}+${BUILD}/" pubspec.yaml
          echo "Stamped: $(grep '^version:' pubspec.yaml)"

      - name: Decode keystore
        run: |
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > android/app/release.jks

      - name: Build AAB (SHOW_DEBUG_UI=true for beta)
        env:
          ANDROID_KEYSTORE_PATH: app/release.jks
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: flutter build appbundle --release --dart-define=SHOW_DEBUG_UI=true

      - name: Upload to Play Internal
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: com.ccwmap.app
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: internal
          status: completed

  create-draft-release:
    name: Create/update draft GitHub Release
    needs: [deploy-ios-testflight, deploy-android-internal]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Extract version tag from branch name
        id: ver
        run: |
          # release/v0.3.0 -> v0.3.0 ; hotfix/v0.3.1 -> v0.3.1
          TAG="${GITHUB_REF_NAME#release/}"
          TAG="${TAG#hotfix/}"
          echo "tag=${TAG}" >> "$GITHUB_OUTPUT"
      - name: Create or update draft release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ steps.ver.outputs.tag }}
          BUILD: ${{ github.run_number }}
          SHA: ${{ github.sha }}
        run: |
          BODY="Testing in TestFlight (build ${BUILD}) and Play Internal (build ${BUILD}). Tag this commit \`${TAG}\` after beta verification to promote to production."
          if gh release view "$TAG" >/dev/null 2>&1; then
            gh release edit "$TAG" --notes "$BODY" --target "$SHA" --draft=true
          else
            gh release create "$TAG" --draft --title "$TAG" --notes "$BODY" --target "$SHA"
          fi
```

- [ ] **Step 2: Commit the workflow**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow (TestFlight + Play Internal on release/v* push)"
```

- [ ] **Step 3: Smoke-test with a throwaway release branch**

Pick a patch version not yet used (check current `pubspec.yaml`: `version: 0.2.0+4`; use `0.2.1`).

```bash
git checkout master
git pull origin master
git checkout -b release/v0.2.1
sed -i.bak "s/^version:.*/version: 0.2.1+0/" pubspec.yaml
rm -f pubspec.yaml.bak
git add pubspec.yaml
git commit -m "chore: bump version to 0.2.1 (CI smoke test)"
git push origin release/v0.2.1
```

Watch the Actions tab. Expected result:
- `deploy-ios-testflight` completes; build shows up in App Store Connect → TestFlight as "Processing".
- `deploy-android-internal` completes; build shows up in Play Console → Internal testing.
- `create-draft-release` creates a draft release named `v0.2.1` on GitHub.

**If any job fails:** do NOT merge the release branch. Diagnose and fix. Common failures:
- iOS code signing → verify `CERTIFICATES_P12`, `PROVISIONING_PROFILE` secrets haven't expired.
- Play upload "Package not found" → Prerequisite P4 (opt into Internal testing track) not done.
- AAB signing failure → verify `ANDROID_KEY_ALIAS` matches what's in the keystore: `keytool -list -v -keystore ccwmap-release.jks | grep Alias`.

- [ ] **Step 4: Clean up the smoke-test release**

Once verified working:

```bash
git checkout master
git branch -D release/v0.2.1
git push origin --delete release/v0.2.1
```

Delete the `v0.2.1` draft release on GitHub (UI: Releases → draft → Delete).
Delete the TestFlight and Play Internal builds from their respective consoles (optional cleanup — they'll expire on their own).

- [ ] **Step 5: Delete the legacy ios-testflight.yml**

```bash
git rm .github/workflows/ios-testflight.yml
git commit -m "ci: remove legacy ios-testflight.yml (absorbed into release.yml)"
```

---

## Task 5: Production Workflow

**Files:**
- Create: `.github/workflows/production.yml`

- [ ] **Step 1: Create the production workflow**

Create `.github/workflows/production.yml` with this exact content:

```yaml
name: Production

on:
  push:
    tags:
      - 'v*.*.*'

concurrency:
  group: production-${{ github.ref }}
  cancel-in-progress: false

jobs:
  deploy-ios-appstore:
    name: iOS → App Store
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 26
        run: sudo xcode-select -s $(ls -d /Applications/Xcode_26*.app | head -1)

      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}

      - name: Stamp version (semver from tag + run_number build)
        run: |
          SEMVER="${GITHUB_REF_NAME#v}"
          BUILD=${{ github.run_number }}
          sed -i.bak "s/^version:.*/version: ${SEMVER}+${BUILD}/" pubspec.yaml
          echo "Stamped: $(grep '^version:' pubspec.yaml)"

      - name: Import code signing certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.CERTIFICATES_P12 }}
          p12-password: ${{ secrets.CERTIFICATES_PASSWORD }}

      - name: Import provisioning profile
        run: |
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          echo "${{ secrets.PROVISIONING_PROFILE }}" | \
            base64 --decode > ~/Library/MobileDevice/Provisioning\ Profiles/profile.mobileprovision

      - name: Build IPA (NO SHOW_DEBUG_UI — production)
        run: flutter build ipa --release --export-options-plist=ios/ExportOptions.plist

      - name: Upload to App Store Connect
        uses: apple-actions/upload-testflight-build@v3
        with:
          app-path: build/ios/ipa/ccwmap.ipa
          issuer-id: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
          api-key-id: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          api-private-key: ${{ secrets.APP_STORE_CONNECT_PRIVATE_KEY }}

      - name: Upload IPA as run artifact
        uses: actions/upload-artifact@v4
        with:
          name: ios-ipa-${{ github.ref_name }}
          path: build/ios/ipa/ccwmap.ipa
          retention-days: 90

  deploy-android-production:
    name: Android → Play Production
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'

      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}

      - name: Stamp version (semver from tag + run_number build)
        run: |
          SEMVER="${GITHUB_REF_NAME#v}"
          BUILD=${{ github.run_number }}
          sed -i.bak "s/^version:.*/version: ${SEMVER}+${BUILD}/" pubspec.yaml
          echo "Stamped: $(grep '^version:' pubspec.yaml)"

      - name: Decode keystore
        run: |
          echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 --decode > android/app/release.jks

      - name: Build AAB (NO SHOW_DEBUG_UI — production)
        env:
          ANDROID_KEYSTORE_PATH: app/release.jks
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
        run: flutter build appbundle --release

      - name: Upload to Play Production (halted rollout)
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: com.ccwmap.app
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: production
          status: draft

      - name: Upload AAB as run artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-aab-${{ github.ref_name }}
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 90

  publish-release:
    name: Publish GitHub Release
    needs: [deploy-ios-appstore, deploy-android-production]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: ios-ipa-${{ github.ref_name }}
          path: ./artifacts
      - uses: actions/download-artifact@v4
        with:
          name: android-aab-${{ github.ref_name }}
          path: ./artifacts
      - name: Publish release + attach artifacts
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ github.ref_name }}
          BUILD: ${{ github.run_number }}
        run: |
          if gh release view "$TAG" >/dev/null 2>&1; then
            gh release edit "$TAG" --draft=false
          else
            gh release create "$TAG" --title "$TAG" --notes "Production release $TAG (build $BUILD)."
          fi
          gh release upload "$TAG" ./artifacts/ccwmap.ipa ./artifacts/app-release.aab --clobber
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/production.yml
git commit -m "ci: add production workflow (App Store + Play Production on v*.*.* tag push)"
```

- [ ] **Step 3: Smoke-test — end-to-end release-then-tag**

Walk through a full release flow with a test patch version (but this time, merge it).

```bash
git checkout master
git pull origin master
git checkout -b release/v0.2.1
sed -i.bak "s/^version:.*/version: 0.2.1+0/" pubspec.yaml
rm -f pubspec.yaml.bak
git add pubspec.yaml
git commit -m "chore: bump version to 0.2.1"
git push origin release/v0.2.1
```

Wait for `release.yml` to finish green. Verify TestFlight + Play Internal received the build. Then:

```bash
# Open PR release/v0.2.1 -> master on GitHub, MERGE COMMIT (not squash).
git checkout master
git pull origin master
git tag v0.2.1
git push origin v0.2.1
```

Watch Actions. Expected:
- `deploy-ios-appstore` completes; build appears in App Store Connect → TestFlight (iOS always routes uploads there first; you'd submit for App Store review from the TestFlight tab).
- `deploy-android-production` completes; draft release appears in Play Console → Production with rollout **not started**.
- `publish-release` promotes the GitHub Release from draft to published, attaches `ccwmap.ipa` and `app-release.aab`.

**Do NOT click "Submit for Review" in App Store Connect or start Play rollout during the smoke test.** Leave them in draft — this proves the pipeline works without shipping anything to users.

- [ ] **Step 4: Document any store-side observations**

If either store shows unexpected state (e.g., Play flags export compliance, App Store requires encryption declaration), note it in `docs/GIT_FLOW.md` under a "Store submission checklist" section. This is the one-time "first upload" friction the spec warned about.

---

## Task 6: Weekly Scans Workflow

**Files:**
- Create: `.github/workflows/weekly-scans.yml`

- [ ] **Step 1: Create the weekly scans workflow**

Create `.github/workflows/weekly-scans.yml` with this exact content:

```yaml
name: Weekly Scans

on:
  schedule:
    - cron: '0 13 * * 1'  # Mondays 13:00 UTC = 09:00 ET
  workflow_dispatch: {}

concurrency:
  group: weekly-scans
  cancel-in-progress: false

jobs:
  dep-vuln-scan:
    name: OSV dependency scan
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
      actions: read
    steps:
      - uses: actions/checkout@v4
      - name: OSV scanner
        id: scan
        uses: google/osv-scanner-action/osv-scanner-action@v1
        with:
          scan-args: |-
            --lockfile=pubspec.lock
            --lockfile=ios/Podfile.lock
            -r .
        continue-on-error: true
      - name: Open GitHub issue on failure
        if: steps.scan.outcome == 'failure'
        uses: actions/github-script@v7
        with:
          script: |
            const titlePrefix = 'Weekly dep-vuln-scan failed';
            const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
            // Dedupe: only open a new issue if there's no existing open one
            const existing = await github.rest.search.issuesAndPullRequests({
              q: `repo:${context.repo.owner}/${context.repo.repo} is:issue is:open label:security "${titlePrefix}"`,
            });
            if (existing.data.total_count > 0) {
              core.info(`Existing open security issue found (#${existing.data.items[0].number}); skipping duplicate.`);
              return;
            }
            const title = `${titlePrefix} (${new Date().toISOString().slice(0,10)})`;
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title,
              labels: ['security'],
              body: `OSV scanner reported vulnerabilities in pubspec.lock or Podfile.lock.\n\nFailing run: ${runUrl}\n\nTriage:\n1. Click the run link above and open the "OSV scanner" step log.\n2. Identify affected packages and severity.\n3. Bump the affected dep via a \`chore/deps-*\` branch, or document why we're deferring.`,
            });

  codeql-kotlin:
    name: CodeQL (Kotlin)
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
      actions: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: github/codeql-action/init@v3
        with:
          languages: java-kotlin
      - uses: ./.github/actions/setup-flutter
        with:
          supabase-url: ${{ secrets.SUPABASE_URL }}
          supabase-anon-key: ${{ secrets.SUPABASE_ANON_KEY }}
          maptiler-api-key: ${{ secrets.MAPTILER_API_KEY }}
      - name: Build Android (for CodeQL to observe)
        run: flutter build apk --debug
      - uses: github/codeql-action/analyze@v3
        with:
          category: '/language:java-kotlin'
```

Scope note: initial CodeQL implementation covers Kotlin only. Swift and JS/TS (which the spec mentioned) are deferred — Swift CodeQL needs a separate macOS runner and autobuild reliability is mixed with Flutter; JS is not meaningfully present in this repo. If swift/js analysis is wanted later, add additional jobs in a follow-up PR.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/weekly-scans.yml
git commit -m "ci: add weekly scans (OSV deps + CodeQL Kotlin)"
```

- [ ] **Step 3: Trigger manually to smoke-test**

On GitHub: Actions → Weekly Scans → Run workflow → from `master`. (Requires merging the branch first, or temporarily changing the trigger to also fire on the current branch. Simpler: wait until this branch is merged to master, then trigger.)

Expected:
- `dep-vuln-scan` completes. If vulnerabilities are found, an issue labeled `security` opens automatically. If not, no issue.
- `codeql-kotlin` completes. Findings (if any) appear in the repo's Security → Code scanning tab.

If `codeql-kotlin` fails at build time, check the log for the Gradle error — usually a missing env var or Java version mismatch. Fix and re-trigger.

---

## Task 7: Documentation — `docs/GIT_FLOW.md` + `CLAUDE.md` Update

**Files:**
- Create: `docs/GIT_FLOW.md`
- Modify: `CLAUDE.md` (CI/CD & Build Flags section)

- [ ] **Step 1: Create `docs/GIT_FLOW.md`**

Create `docs/GIT_FLOW.md` with this exact content:

````markdown
# Git Flow & Release Playbook

This document describes the branching strategy, CI/CD pipelines, and release
procedure for ccwmap. The design rationale lives in
`docs/superpowers/specs/2026-04-20-cicd-gitflow-design.md` — refer there for
the "why". This doc is the "how".

## Branching Model

```
master (protected, production)
  ↑
  ├── feature/*       (new features)
  ├── bugfix/*        (non-critical fixes)
  ├── chore/*         (tooling, deps, docs)
  ├── refactor/*
  ├── release/vX.Y.Z  (version bumped, beta-tested, merges to master)
  └── hotfix/vX.Y.Z   (cut off a production tag, patches prod)
```

`master` is the only long-lived branch. Do not push directly to it.

## PR Workflow (feature / bugfix / chore)

```bash
git checkout master
git pull origin master
git checkout -b feature/your-feature

# ... work, commit ...

git push origin feature/your-feature
# Open PR to master on GitHub
```

PR must pass all five checks before merging:
- `Format` — `dart format` clean
- `Analyze + Test` — `flutter analyze` + `flutter test` pass
- `Build Android (debug APK)` — compiles
- `Build iOS (no codesign)` — compiles
- `Secret scan (gitleaks)` — no committed secrets

Merge strategy: **Squash and merge** (keeps master history clean).

## Release Workflow (beta)

### 1. Cut the release branch

```bash
git checkout master
git pull origin master
git checkout -b release/v0.3.0
```

### 2. Bump the version in `pubspec.yaml`

Edit `pubspec.yaml`:

```yaml
version: 0.3.0+0   # CI will overwrite the +N with github.run_number
```

### 3. Push — CI fires automatically

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 0.3.0"
git push origin release/v0.3.0
```

GitHub Actions runs `release.yml`:
- Builds signed iOS IPA with `SHOW_DEBUG_UI=true` → uploads to TestFlight
- Builds signed Android AAB with `SHOW_DEBUG_UI=true` → uploads to Play Internal
- Creates a draft GitHub Release named `v0.3.0`

### 4. Beta-test on device

Install the TestFlight build on an iPhone. Install the Play Internal build on
an Android device. Verify the core flows still work.

### 5. Merge the release branch to master

Open PR `release/v0.3.0` → `master`. Merge strategy: **Create a merge
commit** (preserves the release point). All PR checks must pass (they will
— the code is the same as the latest master when you branched, plus a
version bump).

### 6. Tag the merge commit — triggers production

```bash
git checkout master
git pull origin master
git tag v0.3.0
git push origin v0.3.0
```

GitHub Actions runs `production.yml`:
- Builds signed iOS IPA **without** `SHOW_DEBUG_UI` → uploads to App Store
  Connect (lands in "Processing" state for App Store review)
- Builds signed Android AAB **without** `SHOW_DEBUG_UI` → uploads to Play
  Production in **draft** state (rollout halted at 0%)
- Publishes the draft GitHub Release, attaches IPA + AAB as assets

### 7. Manual store-side steps

**App Store:**
1. App Store Connect → TestFlight → wait for "Processing" to finish (~10-30 min).
2. App Store Connect → My Apps → ccwmap → your version → "+ Version" if not
   already present.
3. Attach the uploaded build. Fill in "What's New in This Version". Submit
   for Review.

**Play Console:**
1. Play Console → Production → draft release → Review release.
2. Set rollout percentage (start at 20%, monitor crash-free rate, ramp to
   100% over a few days).
3. Publish.

### 8. Clean up

```bash
git branch -d release/v0.3.0
git push origin --delete release/v0.3.0
```

## Hotfix Workflow

Same as release, but branch off a production tag and use `hotfix/v*`:

```bash
git checkout -b hotfix/v0.3.1 v0.3.0
# ... fix ...
# Bump pubspec.yaml to 0.3.1+0
git push origin hotfix/v0.3.1
```

`release.yml` fires on `hotfix/v*` too — hotfixes are beta-tested before
promoting. Then PR to master, tag `v0.3.1`, and production.yml fires.

## Weekly Scans

`weekly-scans.yml` runs Mondays 09:00 ET. Opens a GitHub issue tagged
`security` if OSV finds a vulnerable dep, or CodeQL flags something. To run
on demand: Actions → Weekly Scans → Run workflow.

## First-Time Setup (Prerequisites)

If setting up a new clone or reviving the project:

1. Generate Android release keystore (one-time; back up the `.jks` securely):
   ```bash
   keytool -genkey -v -keystore ccwmap-release.jks -alias ccwmap \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Create `android/key.properties` (gitignored) from
   `android/key.properties.template`, pointing `storeFile` at the local
   `.jks` path.
3. Ensure all secrets listed in
   `docs/superpowers/specs/2026-04-20-cicd-gitflow-design.md` §10 are
   configured in repo Settings → Secrets and variables → Actions.
4. Play Console: grant the service account "Release manager" on the app.
   Opt the app into Internal testing with at least one tester email.
5. App Store Connect: ensure the app record exists with a matching bundle ID.

## Troubleshooting

**"Cannot push to protected branch master"**
Expected. Use a feature branch and a PR.

**PR check `format` fails**
```bash
dart format .
git add -A
git commit -m "chore: format"
git push
```

**`build-android` fails on PR**
Reproduce locally: `flutter build apk --debug`. Likely a Gradle or
signing-config error.

**`release.yml` fails at "Upload to TestFlight" with 401**
App Store Connect API key has expired. Regenerate and update
`APP_STORE_CONNECT_PRIVATE_KEY` secret.

**`release.yml` fails at "Upload to Play Internal" with "Package not found"**
Service account hasn't been granted permission, or the Internal testing
track hasn't been opted into. See "First-Time Setup" steps 4 above.

**`production.yml` fires on an unexpected tag**
The trigger pattern is `v*.*.*`. Don't push arbitrary `v`-prefixed tags
(e.g. `vnext`, `v-temp`). If you did, delete the tag on GitHub and locally:
`git push origin --delete v-temp && git tag -d v-temp`.

## Version Numbering

Semantic versioning: `MAJOR.MINOR.PATCH`.

- **MAJOR**: breaking user-visible changes.
- **MINOR**: new features, backwards-compatible.
- **PATCH**: bug fixes.

Build number (the `+N` after the semver in `pubspec.yaml`) is overwritten
by CI to `github.run_number`. Both stores require a strictly-increasing
build number. Never manually reset it.
````

- [ ] **Step 2: Update `CLAUDE.md` CI/CD & Build Flags section**

Read the current content of the "## CI/CD & Build Flags" section in `CLAUDE.md`. Replace the "Current workflow state" subsection and the "TODO when wiring full production CI/CD" subsection with this:

```markdown
- **Current workflow state:**
  - `.github/workflows/pr-checks.yml` — PR-gated checks (format, analyze+test, android build, ios build, gitleaks secret scan). Flag not applicable (no deploy).
  - `.github/workflows/release.yml` — fires on push to `release/v*` or `hotfix/v*`. **Includes** `--dart-define=SHOW_DEBUG_UI=true` for both iOS TestFlight and Android Play Internal.
  - `.github/workflows/production.yml` — fires on push of `v*.*.*` tag. **Omits** the flag entirely. Debug UI is tree-shaken out of every public-store build by construction.
  - `.github/workflows/weekly-scans.yml` — scheduled OSV dep scan + CodeQL Kotlin. Flag not applicable.

- **Production guarantee:** The only trigger for a public-store build is a `v*.*.*` tag push, which can only run `production.yml`, which does not pass `SHOW_DEBUG_UI`. There is no path from developer action to a public build that carries the debug UI. See `docs/GIT_FLOW.md` for the full release playbook.
```

- [ ] **Step 3: Commit the docs**

```bash
git add docs/GIT_FLOW.md CLAUDE.md
git commit -m "docs: add GIT_FLOW.md and update CLAUDE.md CI/CD section"
```

---

## Task 8: Branch Protection Configuration (Manual)

This is a repo-settings change, not a code change. Cannot be committed to git.

- [ ] **Step 1: Enable branch protection on `master`**

GitHub → Settings → Branches → Add branch ruleset (or edit existing) for `master`:

- [x] Require a pull request before merging
  - [x] Require approvals: 0 (solo project; change to 1+ if team grows)
  - [x] Dismiss stale pull request approvals when new commits are pushed
- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Required status checks (search and add each):
    - [x] `Format`
    - [x] `Analyze + Test`
    - [x] `Build Android (debug APK)`
    - [x] `Build iOS (no codesign)`
    - [x] `Secret scan (gitleaks)`
- [x] Do not allow bypassing the above settings (includes admins)
- [x] Restrict pushes that create matching refs (no one bypasses)

- [ ] **Step 2: Add branch protection for `release/*` and `hotfix/*`**

Add a second ruleset matching the glob `{release/**,hotfix/**}`:

- [x] Restrict force-pushes
- [x] Restrict deletions

No PR requirement (these are short-lived and the release workflow reads them directly), but no rewriting history either.

- [ ] **Step 3: Verify by attempting a direct push to master**

From a clean clone:

```bash
git checkout master
git commit --allow-empty -m "direct push test"
git push origin master
```

Expected: push rejected by GitHub with "protected branch" error. Clean up:

```bash
git reset --hard origin/master
```

---

## Final Integration: Merge the CI/CD Branch

Once all tasks above are complete on `feature/cicd`:

- [ ] **Step 1: Final push**

```bash
git push origin feature/cicd
```

- [ ] **Step 2: Open PR feature/cicd → master**

All five PR checks must pass on the CI/CD branch itself (including the new checks). This is the true smoke test — the pipeline is validating its own source.

- [ ] **Step 3: Merge (squash)**

Squash merge to master. Delete the branch.

- [ ] **Step 4: Retire Prerequisites scratch files**

```bash
rm -f ccwmap-release.jks.b64   # (on your local machine, if still present)
```

The `.jks` itself stays on your local machine, backed up externally. Never commit it.

---

## Self-Review

After the plan is complete, verify against the spec:

1. **Spec §2 Branching Model** → Task 8 enforces it; Task 7 documents it.
2. **Spec §3 PR Pipeline** → Task 2 implements the five jobs.
3. **Spec §4 Weekly Scans** → Task 6 implements OSV + CodeQL (Kotlin only initially, documented as deferred scope for Swift+JS).
4. **Spec §5 Release Flow** → Task 4 implements iOS TestFlight + Android Play Internal + draft GitHub Release.
5. **Spec §6 Production Flow** → Task 5 implements iOS App Store + Android Play Production (halted) + published GitHub Release with artifacts.
6. **Spec §7 Hotfix Flow** → Task 4's release workflow triggers on `hotfix/v*` too; Task 7 documents the procedure.
7. **Spec §8 Composite Action** → Task 1.
8. **Spec §9 Android Signing** → Task 3.
9. **Spec §10 Secrets Inventory** → Prerequisites P3.
10. **Spec §11 Files Touched** → matches File Structure section above.
11. **Spec §12 Migration Plan** → task ordering mirrors spec §12 ordering (secrets → keystore → setup-flutter → pr-checks → delete ios.yml → Android signing → release.yml → delete ios-testflight.yml → production.yml → weekly-scans.yml → branch protection → GIT_FLOW.md). Minor reorder: Android signing is Task 3 (before release.yml needs it) rather than between step 2 and step 5 of the spec; this is strictly before first need.
12. **Spec §13 Risk Register** → Task 4 Step 3 and Task 5 Step 3 enumerate the common first-run failures from the risk register as "if-then" diagnostics.

Coverage: complete. No placeholder text. Types and names consistent across tasks (`release.yml`, `production.yml`, `setup-flutter`, `ANDROID_KEYSTORE_PATH`, etc.).
