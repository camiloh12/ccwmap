# Apple App Store Deployment Checklist

**App:** CCW Map
**Target Platform:** iOS
**Requirements:** iOS 13.0+ minimum deployment target
**Timeline:** 1-2 days prep + 1-3 days review
**Current Bundle ID:** `com.ccwmap.ccwmap`
**Hardware Available:** MacBook Air 2017 (macOS 12.7.6), iPhone 13 Pro Max (iOS 18.6.2)

---

## Phase 0: Apple Developer Account Enrollment

### 0.1 Choose Account Type
- [ ] **Individual Account** ($99/year) - Recommended for solo developer
  - No D-U-N-S number required
  - Your personal name appears as developer on App Store
  - Faster enrollment (24-48 hours)
- [x] Organization Account ($99/year) - For company/LLC
  - Requires D-U-N-S number (free but takes ~1 week)
  - Company name appears as developer on App Store

### 0.2 Prerequisites
- [x] Apple ID with two-factor authentication enabled
  - If you don't have one: [appleid.apple.com](https://appleid.apple.com)
  - Enable 2FA: Settings → [Your Name] → Password & Security → Two-Factor Authentication
- [x] Valid credit/debit card for $99 annual fee
- [x] Government-issued photo ID (may be requested for identity verification)

### 0.3 Enroll in Apple Developer Program
- [x] Go to [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/)
- [x] Sign in with your Apple ID
- [x] Select **Individual** (or Organization)
- [x] Fill in personal information:
  - [x] Legal first name
  - [x] Legal last name
  - [x] Phone number
  - [x] Address
- [x] Agree to Apple Developer Program License Agreement
- [x] Pay $99 USD annual fee
- [x] Wait for enrollment approval (typically 24-48 hours)
- [x] Confirmation email received: `_________________________________`

### 0.4 Verify Account Access
- [x] Sign in to [App Store Connect](https://appstoreconnect.apple.com)
- [x] Sign in to [Apple Developer Portal](https://developer.apple.com/account)
- [x] Note your **Team ID** (visible in Membership section): `_________________________________`
- [x] Note your **Apple ID** used for enrollment: `_________________________________`

---

## Phase 1: MacBook Setup

### 1.1 Check macOS and Xcode Compatibility
- [x] Current macOS version: 12.7.6 (Monterey)
- [x] Maximum Xcode version on Monterey: **Xcode 14.2**
- [x] Xcode 14.2 supports building for iOS 16.2 SDK
- [x] **NOTE:** Local builds not possible (Flutter requires macOS 14+) — using GitHub Actions instead

### 1.2 Install Development Tools
- [x] Install Xcode 14.2 (downloaded Xcode_14.2.xip, extracted to /Applications)
- [x] Accept Xcode license: `sudo xcodebuild -license accept`
- [x] `sudo xcode-select -s /Applications/Xcode.app`
- [x] CocoaPods — N/A (builds run in GitHub Actions)
- [ ] Install Flutter SDK: — N/A locally
  - [ ] Download from [docs.flutter.dev/get-started/install/macos](https://docs.flutter.dev/get-started/install/macos)
  - [ ] Extract to `~/development/flutter`
  - [ ] Add to PATH: `export PATH="$PATH:$HOME/development/flutter/bin"` (add to `~/.zshrc`)
  - [ ] Run `flutter doctor` and resolve any issues
- [ ] Verify setup:
  ```
  flutter doctor
  ```
  - [ ] Flutter: ✓
  - [ ] Xcode: ✓
  - [ ] CocoaPods: ✓
  - [ ] Connected device: ✓ (after Phase 1.3)

### 1.3 iOS 18 Device Support Workaround
Your MacBook's Xcode 14.2 does not natively support iOS 18 devices. Apply this workaround:

- [ ] On the MacBook, find Xcode's DeviceSupport directory:
  ```
  /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/
  ```
- [ ] Download iOS 18 DeviceSupport files:
  - [ ] Search GitHub for "iPhoneOSDeviceSupport" or "iOS-DeviceSupport"
  - [ ] Download the iOS 18.x folder
  - [ ] Copy it into the DeviceSupport directory above
- [ ] Restart Xcode
- [ ] Connect iPhone via USB and trust the computer
- [ ] Check if device appears in Xcode: Window → Devices and Simulators
- [ ] **If this workaround fails:** Use GitHub Actions for builds (see Phase 8)

### 1.4 Clone and Build Project
- [ ] Clone the repository:
  ```
  git clone https://github.com/camiloh12/ccwmap.git
  cd ccwmap
  ```
- [ ] Create `.env` file with required keys:
  ```
  SUPABASE_URL=https://xxxxx.supabase.co
  SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  MAPTILER_API_KEY=your_key_here
  ```
- [ ] Install dependencies:
  ```
  flutter pub get
  cd ios && pod install && cd ..
  ```
- [ ] Run tests to verify:
  ```
  flutter test
  ```
- [ ] All 74 tests passing: ✓

---

## Phase 2: iOS Project Configuration

### 2.1 Verify Bundle Identifier
- [ ] Open `ios/Runner.xcworkspace` in Xcode (NOT `.xcodeproj`)
- [ ] Select Runner project → Runner target → **General** tab
- [ ] Verify **Bundle Identifier:** `com.ccwmap.ccwmap`
  - [ ] **Decision:** Keep `com.ccwmap.ccwmap` or change to `com.ccwmap.app` to match Android?
  - [ ] If changing, update in Xcode AND `project.pbxproj` (all 3 occurrences)
  - [ ] Note: Once published, bundle ID **cannot be changed**
- [ ] Verify **Display Name:** `CCW Map`
- [ ] Verify **Deployment Target:** `13.0`
- [ ] Verify **Device:** iPhone (uncheck iPad if not tested)

### 2.2 Configure Code Signing
- [ ] In Xcode: Runner target → **Signing & Capabilities** tab
- [ ] Check **Automatically manage signing**
- [ ] Select your **Team** (your Apple Developer account)
- [ ] Xcode will automatically:
  - [ ] Create a signing certificate
  - [ ] Create an App ID
  - [ ] Create a provisioning profile
- [ ] Verify no errors appear in the Signing section
- [ ] Status should show: "Signing certificate and provisioning profile OK"

### 2.3 Verify Info.plist Configuration
- [ ] Open `ios/Runner/Info.plist`
- [ ] Verify required entries:
  - [ ] `CFBundleDisplayName`: `CCW Map`
  - [ ] `NSLocationWhenInUseUsageDescription`: Present (location permission)
  - [ ] `FlutterDeepLinkingEnabled`: `true`
  - [ ] `CFBundleURLSchemes`: Contains `com.ccwmap.app`
- [ ] **Add if missing** — Privacy descriptions for any additional permissions:
  ```xml
  <!-- Only add if using camera in future -->
  <key>NSCameraUsageDescription</key>
  <string>CCW Map needs camera access to take photos of locations.</string>
  ```

### 2.4 Add Privacy Manifest (Required 2024+)
- [x] Create `ios/Runner/PrivacyInfo.xcprivacy` if it doesn't exist ✅ Created 2026-03-08
- [ ] Add the following content:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>NSPrivacyCollectedDataTypes</key>
      <array>
          <dict>
              <key>NSPrivacyCollectedDataType</key>
              <string>NSPrivacyCollectedDataTypePreciseLocation</string>
              <key>NSPrivacyCollectedDataTypeLinked</key>
              <true/>
              <key>NSPrivacyCollectedDataTypeTracking</key>
              <false/>
              <key>NSPrivacyCollectedDataTypePurposes</key>
              <array>
                  <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
              </array>
          </dict>
          <dict>
              <key>NSPrivacyCollectedDataType</key>
              <string>NSPrivacyCollectedDataTypeEmailAddress</string>
              <key>NSPrivacyCollectedDataTypeLinked</key>
              <true/>
              <key>NSPrivacyCollectedDataTypeTracking</key>
              <false/>
              <key>NSPrivacyCollectedDataTypePurposes</key>
              <array>
                  <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
              </array>
          </dict>
      </array>
      <key>NSPrivacyAccessedAPITypes</key>
      <array>
          <dict>
              <key>NSPrivacyAccessedAPIType</key>
              <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
              <key>NSPrivacyAccessedAPITypeReasons</key>
              <array>
                  <string>CA92.1</string>
              </array>
          </dict>
      </array>
      <key>NSPrivacyTrackingDomains</key>
      <array/>
      <key>NSPrivacyTracking</key>
      <false/>
  </dict>
  </plist>
  ```
- [ ] In Xcode: Add `PrivacyInfo.xcprivacy` to the Runner target if not auto-included
- [ ] Verify it appears in Build Phases → Copy Bundle Resources
> **Note:** File is committed to repo. Must be added to Xcode target manually on MacBook.

### 2.5 Configure App Icons
- [ ] Verify `ios/Runner/Assets.xcassets/AppIcon.appiconset/` contains all required sizes
- [ ] If icons are missing, generate them:
  - [ ] Use your `assets/icon/app_icon.png` as source
  - [ ] Update `pubspec.yaml` to enable iOS icons:
    ```yaml
    flutter_launcher_icons:
      android: true
      ios: true  # Change from false to true
      image_path: "assets/icon/app_icon.png"
    ```
  - [ ] Run: `flutter pub run flutter_launcher_icons`
- [ ] Verify `Contents.json` in AppIcon.appiconset references all icon sizes
- [ ] Required sizes: 20pt, 29pt, 40pt, 58pt, 60pt, 76pt, 80pt, 87pt, 120pt, 152pt, 167pt, 180pt, 1024pt

### 2.6 Test on Physical Device
- [ ] Connect iPhone 13 Pro Max via USB to MacBook
- [ ] Trust the computer on iPhone (popup will appear)
- [ ] In Xcode: Select your iPhone as the run destination
- [ ] Run: `flutter run` (or press Play in Xcode)
- [ ] **If using free Apple ID (no $99 account yet):**
  - [ ] On iPhone: Settings → General → VPN & Device Management → Trust your developer certificate
  - [ ] Build will expire after 7 days
- [ ] Test core flows:
  - [ ] App launches without crash
  - [ ] Map displays correctly
  - [ ] Location permission prompt appears and works
  - [ ] User registration
  - [ ] Email verification (deep link: `com.ccwmap.app://auth/callback`)
  - [ ] Pin creation
  - [ ] Pin editing
  - [ ] Pin deletion
  - [ ] Offline functionality (airplane mode)
- [ ] Fix any crashes or bugs before proceeding

---

## Phase 3: Build Release Archive

### 3.1 Prepare for Release Build
- [ ] Update version in `pubspec.yaml`:
  ```yaml
  version: 1.0.0+1
  ```
  - Format: `versionName+buildNumber`
  - `buildNumber` must increment with every App Store submission
- [ ] Ensure `.env` file is present with production keys
- [ ] Run: `flutter clean`
- [ ] Run: `flutter pub get`

### 3.2 Build IPA
**Option A: Using Flutter CLI (Recommended)**
- [ ] Run:
  ```
  flutter build ipa --release
  ```
- [ ] Wait for build to complete (2-5 minutes)
- [ ] Output location: `build/ios/ipa/ccwmap.ipa`
- [ ] Note: This creates an unsigned archive; signing happens during distribution

**Option B: Using Xcode**
- [ ] Open `ios/Runner.xcworkspace` in Xcode
- [ ] Select **Any iOS Device (arm64)** as destination (not a simulator)
- [ ] Menu: **Product → Archive**
- [ ] Wait for archive to complete
- [ ] Xcode Organizer window opens automatically

### 3.3 Validate Build
- [ ] In Xcode Organizer (Window → Organizer):
  - [ ] Select your archive
  - [ ] Click **Validate App**
  - [ ] Select your distribution certificate and profile
  - [ ] Wait for validation to complete
  - [ ] Resolve any validation errors
- [ ] Common validation errors:
  - Missing icon sizes → Fix in Assets.xcassets
  - Invalid bundle ID → Fix in Xcode project settings
  - Missing privacy manifest → Add PrivacyInfo.xcprivacy
  - Code signing issues → Re-select team in Signing & Capabilities

### 3.4 Upload to App Store Connect

**Option A: Xcode Organizer (Recommended)**
- [ ] In Xcode Organizer, select your validated archive
- [ ] Click **Distribute App**
- [ ] Select **App Store Connect**
- [ ] Select **Upload**
- [ ] Follow prompts (accept defaults for symbol upload, bitcode)
- [ ] Wait for upload to complete
- [ ] Status: "Upload Successful"

**Option B: Transporter App**
- [ ] Download [Transporter](https://apps.apple.com/app/transporter/id1450874784) from Mac App Store
- [ ] Sign in with your Apple ID
- [ ] Drag and drop the `.ipa` file
- [ ] Click **Deliver**
- [ ] Wait for upload and processing

- [ ] After upload, wait for processing email from Apple (typically < 30 minutes)
- [ ] Build will appear in App Store Connect → TestFlight tab

---

## Phase 4: App Store Connect Setup

### 4.1 Create App Record
- [x] Go to App Store Connect
- [x] Click **My Apps** → **+** → **New App**
- [x] **Platforms:** iOS, **Name:** `CCW Map`, **Primary Language:** English (U.S.)
- [x] **Bundle ID:** `com.ccwmap.ccwmap`, **SKU:** `ccwmap-ios-001`
- [x] App record created ✅

### 4.2 Set Pricing and Availability
- [x] Go to **Pricing and Availability**
- [x] **Price:** Free
- [x] **Availability:** United States (add other countries as desired)
- [x] Click **Save**

### 4.3 Set Age Rating
- [x] Go to **App Information** → **Age Rating**
- [x] Click **Edit** next to Age Rating
- [x] Answer questionnaire:
  - [x] Cartoon or Fantasy Violence: None
  - [x] Realistic Violence: None
  - [x] Prolonged Graphic or Sadistic Realistic Violence: No
  - [x] Profanity or Crude Humor: None
  - [x] Mature/Suggestive Themes: None
  - [x] Horror/Fear Themes: None
  - [x] Medical/Treatment Information: No
  - [x] Alcohol, Tobacco, or Drug Use: None
  - [x] Simulated Gambling: No
  - [x] Sexual Content and Nudity: None
  - [x] Unrestricted Web Access: No
  - [x] Gambling with Real Money: No
  - [x] **Made for Kids:** No
  - [x] **Contains firearms information:** Technically yes — mark accordingly
    - [x] If prompted about violence context, clarify: "Informational/legal reference only, no violent content"
- [x] Click **Save**
- [x] Expected rating: **17+** (due to firearms reference) or **12+** (informational only)
- [x] Note assigned rating: `_________________________________`

### 4.4 App Privacy (Privacy Nutrition Labels)
- [x] Go to **App Privacy**
- [x] Click **Get Started** or **Edit**
- [x] **Data Collection:**
  - [x] "Does your app collect data?" → **Yes**
- [x] **Data Types Collected:**
  - [x] **Location** → Precise Location
    - [x] Usage: App Functionality
    - [x] Linked to user: Yes
    - [x] Used for tracking: No
  - [x] **Contact Info** → Email Address
    - [x] Usage: App Functionality (authentication)
    - [x] Linked to user: Yes
    - [x] Used for tracking: No
  - [x] **Identifiers** → User ID
    - [x] Usage: App Functionality
    - [x] Linked to user: Yes
    - [x] Used for tracking: No
- [x] **Third-party data sharing:** No
- [x] Click **Publish**
- [x] Verify privacy labels appear correctly on app page preview

### 4.5 Add Privacy Policy URL
- [x] Go to **App Information** → **Privacy Policy URL**
- [x] Enter: `https://camiloh12.github.io/ccwmap/privacy-policy.html`
- [x] Click **Save**
- [x] Test URL in browser to confirm it's accessible

### 4.6 App Category
- [x] Go to **App Information**
- [x] **Primary Category:** Navigation
- [x] **Secondary Category:** Travel (optional)
- [x] Click **Save**

---

## Phase 5: Store Listing

### 5.1 App Description
- [x] Go to your app version (e.g., "1.0 Prepare for Submission")
- [x] Fill in **Promotional Text** (max 170 chars, can be updated without new version):
  ```
  Navigate concealed carry laws with community-sourced CCW zone information across the United States.
  ```
- [x] Fill in **Description** (max 4000 chars):
  ```
  CCW Map helps responsible gun owners navigate concealed carry laws by crowdsourcing information about CCW-friendly and restricted zones.

  Features:
  - Interactive map with color-coded pins (green=allowed, yellow=uncertain, red=restricted)
  - Offline-first design - works without internet connection
  - Detailed restriction tags (federal property, schools, airports, etc.)
  - Community-driven data - contribute and update locations
  - US boundary coverage with precise location tracking

  Whether you're traveling, commuting, or exploring new areas, CCW Map provides essential information to help you stay compliant with local regulations.

  Privacy & Security:
  - Secure authentication with email verification
  - Data synchronized across devices
  - Your contributions help the community stay informed

  Note: This app provides user-contributed information and should not be considered legal advice. Always verify local laws and regulations.
  ```
- [x] Fill in **Keywords** (max 100 chars, comma-separated):
  ```
  ccw,concealed carry,gun zones,firearm,map,second amendment,restriction,permit,weapon
  ```
- [x] Fill in **Support URL:**
  ```
  https://github.com/camiloh12/ccwmap
  ```
- [x] Fill in **Marketing URL** (optional):
  ```
  https://github.com/camiloh12/ccwmap
  ```

### 5.2 What's New (Release Notes)
- [ ] Fill in **What's New in This Version:**
  ```
  CCW Map v1.0.0 - Initial Release

  - Interactive map showing concealed carry weapon zone information
  - Create and update pins with detailed restriction tags
  - Color-coded status indicators (allowed, uncertain, restricted)
  - Offline-first design - works without internet connection
  - Secure user authentication with email verification
  - Community-driven data to help users stay compliant

  Disclaimer: This app provides user-contributed information and should not be considered legal advice.
  ```

### 5.3 Upload Screenshots

**Required Sizes (2026 simplified — Apple auto-scales to other devices):**

**iPhone 6.9" Display (Required):** 1320 x 2868 px
- [ ] Screenshot 1: Sign In / Authentication screen
- [ ] Screenshot 2: Map view with multiple pins (green/yellow/red)
- [ ] Screenshot 3: Create Pin dialog
- [ ] Screenshot 4: Edit Pin dialog (Allowed status)
- [ ] Screenshot 5: Edit Pin dialog (Restricted status with tags)
- [ ] Optional: Up to 10 total screenshots

**iPad 13" Display (Optional, if supporting iPad):** 2064 x 2752 px
- [ ] Same set of screenshots at iPad resolution
- [ ] Note: For first release, iPhone screenshots are sufficient

**How to capture screenshots:**
- [ ] Run app on iPhone 13 Pro Max
- [ ] Take screenshots using: Side button + Volume Up
- [ ] Transfer photos to MacBook via AirDrop or USB
- [ ] Resize to 1320 x 2868 px if needed (use Preview or Figma)
- [ ] Upload in App Store Connect → App Previews and Screenshots

**Tips:**
- First screenshot is most important (shown in search results)
- Show actual app content, not mockups
- Ensure text is legible at small sizes
- Don't include status bar with personal info

### 5.4 App Icon (1024x1024)
- [ ] App Store icon is automatically pulled from your asset catalog
- [ ] Verify `ios/Runner/Assets.xcassets/AppIcon.appiconset/` contains 1024x1024 icon
- [ ] Icon requirements:
  - [ ] PNG format, no alpha channel (no transparency)
  - [ ] No rounded corners (Apple adds them automatically)
  - [ ] No overlay text or badges

### 5.5 Contact Information
- [ ] **Contact email:** `_________________________________`
- [ ] **Phone** (optional): Not required
- [ ] **Support URL:** `https://github.com/camiloh12/ccwmap`
- [ ] Click **Save**

### 5.6 App Review Information
- [ ] Go to **App Review Information** section
- [ ] **Contact Information:**
  - [ ] First name: `_________________________________`
  - [ ] Last name: `_________________________________`
  - [ ] Phone: `_________________________________`
  - [ ] Email: `_________________________________`
- [ ] **Demo Account** (if app requires login):
  - [ ] Username: `_________________________________` (create a test account)
  - [ ] Password: `_________________________________`
- [ ] **Notes for Reviewer:**
  ```
  CCW Map is an informational mapping application that helps users identify
  concealed carry weapon zones across the United States. The app contains
  no violent content — it provides legal/regulatory information only.

  To test the app:
  1. Create an account or use the demo credentials provided
  2. Allow location access when prompted
  3. Tap on the map to create pins with CCW zone information
  4. Pins are color-coded: green (allowed), yellow (uncertain), red (restricted)

  The app uses Supabase for authentication and data storage.
  Location access is required for core map functionality.
  ```

---

## Phase 6: TestFlight Beta Testing

### 6.1 Internal Testing (Immediate, No Review)
- [ ] Go to **TestFlight** tab in App Store Connect
- [ ] Your uploaded build should appear (wait for processing if needed)
- [ ] Click on the build version
- [ ] **Export Compliance:**
  - [ ] "Does your app use encryption?" → **Yes** (HTTPS/TLS)
  - [ ] "Does your app qualify for any exemptions?" → **Yes**
  - [ ] Select: "Uses encryption exempt from EAR" (standard HTTPS)
- [ ] **Add Internal Testers:**
  - [ ] Click **App Store Connect Users**
  - [ ] Add your own account
  - [ ] Add up to 100 internal testers (same team)
- [ ] Testers receive email invitation
- [ ] On iPhone: Download **TestFlight** app from App Store
- [ ] Open TestFlight → Accept invitation → Install CCW Map
- [ ] Test the app thoroughly

### 6.2 External Testing (Requires Beta App Review)
- [ ] Create a new external testing group:
  - [ ] Click **+** next to External Testing
  - [ ] Name: `CCW Map Beta Testers`
- [ ] Add testers by email (up to 10,000)
  - [ ] Add email addresses of friends, family, or beta community
- [ ] Select your build for this group
- [ ] Fill in **Test Information:**
  - [ ] What to test: "Test all core flows: account creation, map navigation, pin creation/editing/deletion, offline mode"
  - [ ] Beta App Description: Same as store description
  - [ ] Email: Your contact email
  - [ ] Privacy policy URL: `https://camiloh12.github.io/ccwmap/privacy-policy.html`
- [ ] Click **Submit for Review**
- [ ] Wait for Beta App Review (typically 24-48 hours)
- [ ] Once approved, testers receive invitation

### 6.3 TestFlight Testing Checklist
- [ ] App installs successfully via TestFlight
- [ ] App launches without crash
- [ ] Location permission works
- [ ] Map renders correctly on iOS
- [ ] Can create account and sign in
- [ ] Email verification deep link works
- [ ] Pin creation works
- [ ] Pin editing works
- [ ] Pin deletion works
- [ ] Offline mode works (airplane mode)
- [ ] App handles network reconnection
- [ ] No memory leaks or excessive battery drain
- [ ] UI looks correct on iPhone 13 Pro Max screen

---

## Phase 7: Submit for App Store Review

### 7.1 Pre-Submission Checklist
- [ ] All TestFlight issues resolved
- [ ] Privacy policy URL is live and accessible
- [ ] Screenshots match current app version
- [ ] App description is accurate
- [ ] Demo account credentials work
- [ ] Privacy nutrition labels completed
- [ ] Age rating questionnaire completed
- [ ] All required metadata filled in

### 7.2 Select Build for Submission
- [ ] Go to your app version in App Store Connect
- [ ] Under **Build**, click **+** or **Select a Build**
- [ ] Choose your latest uploaded build
- [ ] Verify version number matches

### 7.3 Set Release Options
- [ ] Scroll to **Version Release**
- [ ] Choose release option:
  - [ ] **Manually release this version** (recommended for first release)
    - Gives you control over exact release timing
  - [ ] **Automatically release this version** (after approval)
  - [ ] **Automatically release on a specific date**
- [ ] Click **Save**

### 7.4 Submit for Review
- [ ] Click **Add for Review** button (top right)
- [ ] Review all information one final time
- [ ] Click **Submit to App Review**
- [ ] **RECORD SUBMISSION DETAILS:**
  - [ ] Submission date: `_________________________________`
  - [ ] Submission time: `_________________________________`
  - [ ] Version submitted: `1.0.0`
  - [ ] Build number: `_________________________________`

### 7.5 Monitor Review Status
- [ ] Status in App Store Connect will show: **Waiting for Review**
- [ ] Typical review timeline:
  - [ ] Day 1: Waiting for Review → In Review
  - [ ] Day 1-3: In Review (automated + human review)
  - [ ] Day 1-3: Decision made
- [ ] Check status daily in App Store Connect
- [ ] Watch for emails from App Review
- [ ] **If reviewer asks questions:** Respond quickly via Resolution Center

---

## Phase 8: Common Rejection Reasons & Fixes

### 8.1 Most Likely Rejection Reasons for CCW Map

**Guideline 1.1 - Objectionable Content:**
- [ ] Firearms content may trigger extra scrutiny
- [ ] **Mitigation:** Emphasize informational/legal nature in reviewer notes
- [ ] Ensure no violent imagery, no weapon sales, no illegal activity promotion

**Guideline 2.1 - Performance (Crashes):**
- [ ] App must not crash during review
- [ ] Test thoroughly on iPhone before submission

**Guideline 5.1.1 - Data Collection:**
- [ ] All data collection must be disclosed in privacy labels
- [ ] Privacy policy must be accessible and accurate

**Guideline 2.3.1 - Accurate Metadata:**
- [ ] Screenshots must match actual app
- [ ] Description must be accurate

**Guideline 4.0 - Design:**
- [ ] App must provide enough value/functionality
- [ ] Must not be a thin wrapper around a website

### 8.2 If Rejected
- [ ] Read rejection message carefully in **Resolution Center**
- [ ] Identify specific guideline violated
- [ ] Fix the issue:
  - [ ] If code issue: Fix, rebuild, upload new build
  - [ ] If metadata issue: Update in App Store Connect, no rebuild needed
- [ ] **Increment build number** (version name can stay the same):
  ```yaml
  # pubspec.yaml
  version: 1.0.0+2  # Changed +1 to +2
  ```
- [ ] Rebuild: `flutter build ipa --release`
- [ ] Upload new build
- [ ] Select new build in App Store Connect
- [ ] Reply in Resolution Center explaining fixes
- [ ] Resubmit for review
- [ ] Note: Resubmission reviews are typically faster

### 8.3 If Approved
- [ ] Status changes to **Pending Developer Release** (if manual) or **Ready for Distribution** (if automatic)
- [ ] If manual release: Click **Release This Version** when ready
- [ ] App typically appears in App Store within 24 hours of release

---

## Phase 9: GitHub Actions for iOS CI/CD (Alternative to MacBook Builds)

### 9.1 Why Use GitHub Actions
- Your MacBook Air 2017 is limited to Xcode 14.2
- GitHub Actions runs `macos-latest` with latest Xcode
- Automates builds, tests, and optionally TestFlight uploads
- Free for public repos (2,000 min/month for private)

### 9.2 Basic Build Workflow (Already Created)
- [x] File: `.github/workflows/ios.yml` — verifies code compiles ✅ Already existed
- [ ] Add GitHub Secrets (do in browser: github.com → repo → Settings → Secrets → Actions):
  - [ ] `SUPABASE_URL`
  - [ ] `SUPABASE_ANON_KEY`
  - [ ] `MAPTILER_API_KEY`

### 9.3 TestFlight Upload Workflow (Requires Paid Developer Account)
To automatically upload to TestFlight from GitHub Actions:

**Step 1: Create App Store Connect API Key**
- [x] Go to App Store Connect → Users and Access → Integrations → App Store Connect API
- [x] Generated API Key — Name: `GitHub Actions`, Access: `App Manager`
- [x] Downloaded `.p8` file
- [x] Noted Key ID and Issuer ID
- [x] Added `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY` secrets

**Step 2: Export Signing Certificate**
- [x] On MacBook: Open Keychain Access
- [x] Find your Apple Distribution certificate
- [x] Right-click → Export → Save as `.p12` file
- [x] Set an export password
- [ ] Base64 encode it: `base64 -i distribution.p12 | pbcopy` → add as `CERTIFICATES_P12` secret

**Step 3: Export Provisioning Profile**
- [x] App ID `com.ccwmap.ccwmap` registered in Developer Portal
- [x] Distribution profile `CCW Map App Store` created and downloaded
- [x] Base64 encoded: `base64 -i CCW_Map_App_Store.mobileprovision | pbcopy`

**Step 4: Add GitHub Secrets**
- [ ] `APP_STORE_CONNECT_API_KEY_ID`: Key ID from Step 1
- [ ] `APP_STORE_CONNECT_ISSUER_ID`: Issuer ID from Step 1
- [ ] `APP_STORE_CONNECT_PRIVATE_KEY`: Contents of `.p8` file
- [x] `CERTIFICATES_P12`: Base64-encoded `.p12` certificate
- [x] `CERTIFICATES_PASSWORD`: Password for `.p12` file
- [x] `PROVISIONING_PROFILE`: Base64-encoded provisioning profile
- [x] `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPTILER_API_KEY`

**Step 5: Create TestFlight Upload Workflow**
- [x] Create `.github/workflows/ios-testflight.yml` ✅ Created 2026-03-08
  > See `.github/workflows/ios-testflight.yml` in the repo.

**Step 6: Create ExportOptions.plist**
- [x] Create `ios/ExportOptions.plist` ✅ Created 2026-03-08
- [x] Team ID `DW4GKDYWNP` filled in, provisioning profile name `CCW Map App Store` set

---

## Phase 10: Post-Approval Actions

### 10.1 App Published
- [ ] Verify app is visible in App Store:
  - [ ] Search "CCW Map" in App Store
  - [ ] Verify listing looks correct (icon, screenshots, description)
  - [ ] Download and test on a fresh device
- [ ] Share app link: `https://apps.apple.com/app/idXXXXXXXXXX`
- [ ] Note App Store ID: `_________________________________`

### 10.2 Monitor After Launch
- [ ] App Store Connect → **App Analytics:**
  - [ ] Impressions and product page views
  - [ ] Downloads
  - [ ] Crashes
- [ ] **Xcode Organizer → Crashes:**
  - [ ] Monitor for crash reports from users
  - [ ] Symbolicate crash logs for debugging
- [ ] **App Store Connect → Ratings and Reviews:**
  - [ ] Read and respond to reviews
  - [ ] Address negative feedback promptly
- [ ] **Monitor Supabase logs** for API errors from iOS clients

### 10.3 Hotfix Process (If Needed)
- [ ] Fix bug in code
- [ ] Increment build number in `pubspec.yaml`:
  ```yaml
  version: 1.0.1+2
  ```
- [ ] Rebuild: `flutter build ipa --release`
- [ ] Upload new build to App Store Connect
- [ ] Submit for expedited review if critical:
  - [ ] In App Store Connect, request expedited review
  - [ ] Explain the critical issue
- [ ] Typical expedited review: 24 hours

---

## Phase 11: Updates and Maintenance

### 11.1 Releasing Updates
For each new version:
- [ ] Make code changes
- [ ] Update version in `pubspec.yaml`:
  ```yaml
  version: 1.1.0+3  # Increment both version and build number
  ```
- [ ] **Build number must always increase** (App Store rejects same or lower)
- [ ] Test on physical device
- [ ] Build IPA: `flutter build ipa --release`
- [ ] Upload to App Store Connect
- [ ] Update release notes ("What's New")
- [ ] Update screenshots if UI changed
- [ ] Submit for review

### 11.2 Annual Requirements
- [ ] **Renew Apple Developer membership** ($99/year)
  - If membership lapses, app is removed from App Store
- [ ] **Update privacy labels** if data practices change
- [ ] **Update SDK** when Apple announces new requirements
  - Apple typically requires latest SDK within ~1 year of release
- [ ] **Review age rating** if content changes

### 11.3 Certificate Renewal
- [ ] Distribution certificates expire after 1 year
- [ ] Xcode automatic signing handles renewal
- [ ] If using GitHub Actions: Re-export and update secrets when certificate renews
- [ ] Provisioning profiles expire after 1 year — regenerate in Developer Portal

---

## Emergency Contacts & Resources

### Important Links
- [ ] [App Store Connect](https://appstoreconnect.apple.com)
- [ ] [Apple Developer Portal](https://developer.apple.com/account)
- [ ] [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [ ] [Flutter iOS Deployment Docs](https://docs.flutter.dev/deployment/ios)
- [ ] [Apple Developer Forums](https://developer.apple.com/forums/)
- [ ] [CCW Map GitHub](https://github.com/camiloh12/ccwmap)

### Account Information
- [ ] Apple ID: `_________________________________`
- [ ] Team ID: `_________________________________`
- [ ] Bundle ID: `com.ccwmap.ccwmap`
- [ ] SKU: `_________________________________`
- [ ] App Store ID: `_________________________________`

### Key File Locations (MacBook)
- [ ] Xcode project: `ios/Runner.xcworkspace`
- [ ] Info.plist: `ios/Runner/Info.plist`
- [ ] Privacy manifest: `ios/Runner/PrivacyInfo.xcprivacy`
- [ ] Export options: `ios/ExportOptions.plist`
- [ ] Signing certificates: Keychain Access
- [ ] Provisioning profiles: `~/Library/MobileDevice/Provisioning Profiles/`

---

## Cost Summary

| Item | Cost | Frequency |
|------|------|-----------|
| Apple Developer Program | $99 | Annual |
| GitHub Actions (public repo) | Free | - |
| GitHub Actions (private repo) | Free tier: 2,000 min/month | Monthly |
| **Total minimum** | **$99/year** | |

---

## Sign-Off

- [ ] **All phases completed:** Date: `_________________________________`
- [ ] **App published to App Store:** Yes/No
- [ ] **App Store URL:** `_________________________________`

---

**Notes for Future Reference:**

```
[Space for additional notes, lessons learned, or issues encountered]



```
