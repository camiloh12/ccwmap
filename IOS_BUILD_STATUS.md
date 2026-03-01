# iOS Build Status — MacBook Air 2017

**Date:** 2026-03-01
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

**Next steps for GitHub Actions:**
1. Add GitHub Secrets: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPTILER_API_KEY`
2. Create App Store Connect API Key (App Store Connect → Integrations)
3. Export Distribution Certificate as `.p12` (needs Xcode on any Mac)
4. Export Provisioning Profile as base64
5. Add remaining secrets: `CERTIFICATES_P12`, `CERTIFICATES_PASSWORD`, `PROVISIONING_PROFILE`, etc.
6. Create `.github/workflows/ios-testflight.yml`

---

## Local Phase 1 Checklist (Updated)

- [x] 1.1 macOS version verified
- [ ] 1.2 Install Xcode 14.2 — download from https://developer.apple.com/download/all/
  - [ ] Accept license: `sudo xcodebuild -license accept`
  - [ ] Verify Command Line Tools point to Xcode: `sudo xcode-select -s /Applications/Xcode.app`
  - [ ] Install CocoaPods — **requires sudo for Ruby fix or Homebrew**
- [ ] 1.3 iOS 18 Device Support — after Xcode installed
- [ ] 1.4 Verify `.env` file exists at project root with production keys
