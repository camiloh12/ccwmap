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

### Mac Steps Progress
1. ✅ Install Xcode 14.2
2. ✅ Sign in: Xcode → Preferences → Accounts → Apple ID added
3. ✅ Apple Distribution certificate created (Manage Certificates)
4. ✅ `.p12` exported from Keychain Access (password set)
5. ⏳ Open `ios/Runner.xcworkspace` → configure Team → provisioning profile auto-created → download
6. ⏳ Base64 encode `.p12`: `base64 -i distribution.p12 | pbcopy` → add as `CERTIFICATES_P12` secret
7. ⏳ Base64 encode provisioning profile → add as `PROVISIONING_PROFILE` secret
8. ⏳ Fill in real Team ID in `ios/ExportOptions.plist` (replace `YOUR_TEAM_ID`)
9. ⏳ Add `PrivacyInfo.xcprivacy` to Runner target in Xcode (Build Phases → Copy Bundle Resources)

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
