# iOS Build Status — MacBook Air 2017

**Date:** 2026-04-04 (last updated)
**Machine:** MacBook Air 2017 (MacBookAir7,2), Intel Core i5, 8GB RAM
**macOS:** 12.7.6 Monterey (hardware-limited, cannot upgrade)
**Disk:** 31 GB free (started), ~29 GB after Flutter download

---

## Phase 1 Status

### 1.1 macOS/Xcode Compatibility ✅ Assessed
- macOS 12.7.6 is the **maximum supported OS** for MacBook Air 2017
- Maximum Xcode for this OS: **Xcode 14.2** (supports iOS 16.2 SDK)
- iPhone 13 Pro Max runs iOS 18.6.2 — requires device support workaround

### 1.2 Tool Installation — ✅ Complete (for certificate purposes)

| Tool | Status | Notes |
|------|--------|-------|
| Command Line Tools | ✅ Installed | At /Library/Developer/CommandLineTools |
| Xcode 14.2 | ✅ Installed | `/Applications/Xcode.app`, license accepted, xcode-select configured |
| Flutter | N/A | Not needed locally — builds run in GitHub Actions |
| CocoaPods | N/A | Not needed locally — builds run in GitHub Actions |

### 1.3 iOS 18 Device Support — Skipped (not building locally)

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

- [x] `SUPABASE_URL`
- [x] `SUPABASE_ANON_KEY`
- [x] `MAPTILER_API_KEY`
- [x] `CERTIFICATES_P12`
- [x] `CERTIFICATES_PASSWORD`
- [x] `PROVISIONING_PROFILE`
- [x] `APP_STORE_CONNECT_API_KEY_ID`
- [x] `APP_STORE_CONNECT_ISSUER_ID`
- [x] `APP_STORE_CONNECT_PRIVATE_KEY`

### Remaining One-Time Setup
- [ ] Create App Record in App Store Connect → My Apps → + → New App
  - Platform: iOS, Name: `CCW Map`, Bundle ID: `com.ccwmap.ccwmap`, SKU: `ccwmap-ios-001`
- [x] App Store Connect API Key created → all 3 secrets added

### Mac Steps Progress
1. ✅ Install Xcode 14.2
2. ✅ Sign in: Xcode → Preferences → Accounts → Apple ID added
3. ✅ Apple Distribution certificate created (Manage Certificates)
4. ✅ `.p12` exported from Keychain Access (password set)
5. ✅ App ID `com.ccwmap.ccwmap` registered in Developer Portal
6. ✅ Distribution provisioning profile `CCW Map App Store` created and downloaded
7. ✅ `.p12` base64 encoded → added as `CERTIFICATES_P12` GitHub secret
8. ✅ `.p12` password added as `CERTIFICATES_PASSWORD` GitHub secret
9. ✅ Provisioning profile base64 encoded → added as `PROVISIONING_PROFILE` GitHub secret
10. ✅ Team ID `DW4GKDYWNP` filled in `ios/ExportOptions.plist`
11. ✅ `PrivacyInfo.xcprivacy` added to Runner target (Build Phases → Copy Bundle Resources)
12. ✅ `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPTILER_API_KEY` added as GitHub secrets

---

## Local Phase 1 Checklist (Updated)

> **Note:** Local builds are not possible on this Mac. Xcode 14.2 is still useful for certificate export only.

- [x] 1.1 macOS version verified
- [x] 1.2 Install Xcode 14.2
  - [x] Downloaded and extracted Xcode_14.2.xip
  - [x] Accept license: `sudo xcodebuild -license accept`
  - [x] `sudo xcode-select -s /Applications/Xcode.app`
  - [x] Sign in to Apple account: Xcode → Preferences → Accounts
  - [x] Apple Distribution certificate created
  - [x] `.p12` exported from Keychain Access
- [x] 1.3 iOS 18 Device Support — skipped (not building locally)
- [ ] 1.4 Verify `.env` file exists at project root with production keys
