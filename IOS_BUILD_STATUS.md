# iOS Build Status — MacBook Air 2017

**Date:** 2026-03-08 (last updated)
**Machine:** MacBook Air 2017 (MacBookAir7,2), Intel Core i5, 8GB RAM
**macOS:** 12.7.6 Monterey (hardware-limited, cannot upgrade)
**Disk:** 31 GB free (started), ~29 GB after Flutter download

---

## Phase 1 Status

### 1.1 macOS/Xcode Compatibility ✅ Assessed
- macOS 12.7.6 is the **maximum supported OS** for MacBook Air 2017
- Maximum Xcode for this OS: **Xcode 14.2** (supports iOS 16.2 SDK)
- iPhone 13 Pro Max runs iOS 18.6.2 — requires device support workaround

### 1.2 Tool Installation — ⚠️ Partially Blocked

| Tool | Status | Notes |
|------|--------|-------|
| Command Line Tools | ✅ Installed | At /Library/Developer/CommandLineTools |
| Xcode 14.2 | ⏳ Pending | User must download manually from developer.apple.com/download/all |
| Flutter | ⬇️ Downloaded (incompatible) | flutter_macos_3.41.2-stable.zip at ~/development/flutter — **requires macOS 14+, fails on this Mac** |
| CocoaPods | ❌ Blocked | System Ruby 2.6 is too old; CocoaPods needs Ruby 3.0+ |
| Homebrew | ❌ Not installed | Would fix Ruby/CocoaPods issue but requires sudo |

### 1.3 iOS 18 Device Support — ⏳ Pending Xcode install

### 1.4 Clone & Build — ⚠️ Cannot build locally
- Repo is already at `/Users/camiloh/projects/ccwmap`
- `.env` file status: **unknown — needs verification**
- Cannot run `flutter build ipa` on this Mac (Flutter incompatible with macOS 12)

---

## ⚠️ Critical Incompatibilities Found

### 1. Flutter SDK requires macOS 14+
- `pubspec.yaml` requires Dart SDK `^3.9.2`
- Dart 3.9.2 ships with Flutter 3.38+
- Flutter 3.38+ requires macOS 14.0 (Sonoma)
- This Mac is permanently capped at macOS 12.7.6
- **Local Flutter builds are not possible on this machine**

### 2. Xcode 14.2 cannot submit to App Store
- Apple now requires Xcode 16+ for App Store submissions
- Xcode 16 requires macOS 14
- Xcode 14.2 supports iOS 16.2 SDK only
- **Cannot submit to App Store from this Mac**

---

## ✅ What This Mac CAN Do

1. **Xcode 14.2** — install for code signing certificate setup
   - Create Apple Distribution certificate (.p12 export for GitHub Actions)
   - Download provisioning profiles
   - Manage App IDs in Developer Portal via Xcode
2. **Transporter.app** — upload a pre-built `.ipa` to App Store Connect (if needed)
3. **Physical device testing** — run debug builds if a compatible Flutter + Xcode combo is found

---

## ✅ Recommended Build Path: GitHub Actions (Phase 9)

GitHub Actions (`macos-latest`) provides:
- macOS 14+ with Xcode 16
- Flutter 3.41+ with Dart 3.9.2+
- Automated `flutter build ipa --release`
- Optional TestFlight upload via `apple-actions/upload-testflight-build`

---

## Phase 9 Progress — 2026-03-08

### Files Created (from Windows)
| File | Status |
|------|--------|
| `.github/workflows/ios-testflight.yml` | ✅ Created — manual trigger, builds IPA + uploads to TestFlight |
| `ios/ExportOptions.plist` | ✅ Created — `YOUR_TEAM_ID` placeholder, **needs real Team ID** |
| `ios/Runner/PrivacyInfo.xcprivacy` | ✅ Created — required Apple privacy manifest |

### GitHub Secrets Checklist

**Do now (browser: github.com → repo → Settings → Secrets → Actions):**
- [ ] `SUPABASE_URL`
- [ ] `SUPABASE_ANON_KEY`
- [ ] `MAPTILER_API_KEY`

**Requires Mac (Xcode + Keychain Access):**
- [ ] `CERTIFICATES_P12` — export Apple Distribution cert from Keychain, `base64 -i cert.p12`
- [ ] `CERTIFICATES_PASSWORD` — password set during `.p12` export
- [ ] `PROVISIONING_PROFILE` — download from Developer Portal, `base64 -i profile.mobileprovision`
- [ ] `APP_STORE_CONNECT_API_KEY_ID` — from App Store Connect → Integrations → API Keys
- [ ] `APP_STORE_CONNECT_ISSUER_ID` — same page
- [ ] `APP_STORE_CONNECT_PRIVATE_KEY` — contents of `.p8` file (download once only)

### Remaining One-Time Setup (browser, do now)
- [ ] Create App Record in App Store Connect → My Apps → + → New App
  - Platform: iOS, Name: `CCW Map`, Bundle ID: `com.ccwmap.ccwmap`, SKU: `ccwmap-ios-001`
- [ ] Create App Store Connect API Key (Integrations → App Store Connect API → Generate)

### Remaining Mac Steps (one-time, then all future builds via GitHub Actions)
1. Install Xcode 14.2 — only needed for certificate export, not for building
2. Sign in: Xcode → Preferences → Accounts → add Apple ID
3. Download Distribution certificate (Xcode auto-creates it)
4. Export `.p12` from Keychain Access → add as `CERTIFICATES_P12` secret
5. Download provisioning profile from Developer Portal → add as `PROVISIONING_PROFILE` secret
6. Fill in real Team ID in `ios/ExportOptions.plist` (replace `YOUR_TEAM_ID`)
7. Add `PrivacyInfo.xcprivacy` to Runner target in Xcode (Build Phases → Copy Bundle Resources)

---

## Local Phase 1 Checklist (Updated)

> **Note:** Local builds are not possible on this Mac. Xcode 14.2 is still useful for certificate export only.

- [x] 1.1 macOS version verified
- [ ] 1.2 Install Xcode 14.2 — needed **only** for certificate/profile export
  - Download: https://developer.apple.com/download/all/
  - [ ] Accept license: `sudo xcodebuild -license accept`
  - [ ] Sign in to Apple account: Xcode → Preferences → Accounts
  - [ ] CocoaPods NOT needed (builds run in GitHub Actions)
- [ ] 1.3 iOS 18 Device Support — skip (not building locally)
- [ ] 1.4 Verify `.env` file exists at project root with production keys (for local reference only)
