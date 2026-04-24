# Release Notes Playbook

Single source of truth for user-facing release notes across TestFlight,
App Store, and Google Play. CI pipes the same text into both stores.

## Where to edit

```
release_notes/whatsnew-en-US
```

Plain text. No markdown, no trailing headline/version — stores render
this verbatim. When you change it, commit it on the `release/v*` or
tag branch that will ship.

## Constraints

- **Hard cap:** 500 characters (Google Play's per-locale limit; the
  stricter of the two). iOS tolerates up to 4000.
- **Brief:** 3–5 short bullets, each a single user-facing outcome.
- **Voice:** imperative or user-outcome ("Browse the map without
  signing in"). Don't reference internal terms (SP-1, migrations,
  edge functions, etc.).
- **No version prefix.** The store already shows the version; don't
  repeat it in the body.

Keep it brief.

## How CI picks it up

Both `.github/workflows/release.yml` (TestFlight + Play Internal) and
`.github/workflows/production.yml` (App Store + Play Production) read
from the same file:

**iOS (`apple-actions/upload-testflight-build@v3`):**
A `Read release notes (en-US) for TestFlight` step `cat`s the file
into a step output, then passes it to the upload action's
`release-notes:` input. This becomes the TestFlight build's
"What to Test" text.

**Android (`r0adkll/upload-google-play@v1`):**
The upload action reads `release_notes/` directly via its
`whatsNewDirectory:` input. Any file matching `whatsnew-<LOCALE>` is
uploaded as that locale's release notes. Play's 500-char cap applies
per locale.

## App Store "What's New" (production only)

The iOS `release-notes` input sets **TestFlight's** "What to Test"
text — visible to beta testers only. App Store's public "What's New"
field (shown to customers on the store listing) is a separate
property on the App Store Version resource.

For v0.4.0 and until we automate it, paste the same text manually
when submitting the version for App Store review:

1. App Store Connect → App → App Store → `<Version>` → "What's New
   in This Version".
2. Paste the contents of `release_notes/whatsnew-en-US`.
3. Save.

Automation path (future): add a step that calls the App Store
Connect API's `POST /v1/appStoreVersionLocalizations` (or `PATCH` if
it exists) with the `whatsNew` field. Needs the same JWT we already
mint for upload.

## Adding a new locale

Drop another file into `release_notes/`:

```
release_notes/whatsnew-en-US
release_notes/whatsnew-es-ES
release_notes/whatsnew-ja-JP
```

Android picks them all up automatically (one per locale). iOS
currently only pipes the `en-US` file — the `Read release notes`
step hardcodes the path. If you need iOS localization, extend that
step to read each file and pass it via the appropriate App Store
Connect API call (the simple `release-notes:` input only accepts one
string).

## Verifying after a deploy

- **TestFlight:** App Store Connect → TestFlight → `<build>` →
  "Test Details" → "What to Test".
- **Play Internal/Production:** Play Console → Release → `<track>` →
  select the release → "What's new in this release".

Both should match the committed file within a minute or two of the
CI run finishing.

## When asked to "generate release notes"

The assistant overwrites `release_notes/whatsnew-en-US` with brief
user-facing bullets based on the PR/commits since the last release
tag. It does **not** touch any other file unless asked — the CI
wiring is one-time and lives in `release.yml` / `production.yml`.
