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
