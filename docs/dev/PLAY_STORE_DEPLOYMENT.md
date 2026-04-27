# Google Play Store Deployment Checklist

**App:** CCW Map
**Target Platform:** Android
**Requirements:** Android API 35 (2026 compliance)
**Timeline:** 2-4 hours prep + 1-7 days review

---

## Phase 1: Pre-Deployment Configuration

### 1.1 Update Build Configuration
- [x] Open `android/app/build.gradle` (Note: Using build.gradle.kts - Kotlin DSL)
- [x] Set `compileSdk = 35`
- [x] Set `targetSdk = 35` in `defaultConfig`
- [x] Verify `minSdk = 21`
- [x] Set initial `versionCode = 1` and `versionName = "1.0.0"`
- [x] Verify `applicationId = "com.ccwmap.app"`
- [ ] Save and test build: `flutter build appbundle --release` (test only) - **Requires signing keys from Phase 2**

### 1.2 Verify Environment Variables
- [x] Confirm `.env` file exists with all required keys:
  - [x] `SUPABASE_URL` - Verified (loaded via dotenv)
  - [x] `SUPABASE_ANON_KEY` - Verified (loaded via dotenv)
  - [ ] `MAPTILER_API_KEY` (optional) - **User to verify if needed**
- [x] Verify `.env` is in `.gitignore` - Confirmed on line 46
- [x] Verify no secrets hardcoded in source code - All secrets properly loaded via dotenv.env[]
- [x] Run `grep -r "SUPABASE_URL\|SUPABASE_ANON_KEY" lib/` to check (should be empty) - Only found proper dotenv references in main.dart and background_sync.dart

### 1.3 Update App Metadata
- [x] Open `android/app/src/main/AndroidManifest.xml`
- [x] Verify app name is set correctly - "CCW Map" on line 8
- [x] Verify deep link intent filters are configured:
  - [x] `com.ccwmap.app://auth/callback` - Added custom scheme intent filter
  - [x] `https://camiloh12.github.io/ccwmap/auth/callback` - Added HTTPS fallback intent filter
- [x] Verify `android.permission.INTERNET` is present - Line 2
- [x] Verify `android.permission.ACCESS_FINE_LOCATION` is present - Line 3
- [x] Verify `android.permission.ACCESS_COARSE_LOCATION` is present - Line 4
- [x] Add any other required permissions for your features - ACCESS_NETWORK_STATE also present (line 5)

### 1.4 Test on Physical Device
- [ ] Connect Android device via USB
- [ ] Run: `flutter run --release` on device
- [ ] Test core flows:
  - [ ] User registration
  - [ ] Email verification (deep link)
  - [ ] Pin creation
  - [ ] Pin editing
  - [ ] Pin deletion
  - [ ] Map navigation
  - [ ] Offline functionality (airplane mode)
- [ ] Fix any crashes or bugs

---

## Phase 2: Create App Signing Keys

### 2.1 Generate Upload Keystore
- [x] Open terminal/command prompt
- [x] Run: `keytool -genkey -v -keystore C:\Users\camil\keys\ccwmap-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ccwmap-upload`
- [x] When prompted, fill in:
  - [x] Keystore password: `[REDACTED - Stored securely]`
  - [x] Key password: `[REDACTED - Same as keystore password]`
  - [x] First and last name: Provided
  - [x] Organization unit: Provided
  - [x] Organization: Provided
  - [x] City/locality: Provided
  - [x] State/province: Provided
  - [x] Country code: `US`
- [x] Verify `ccwmap-upload.jks` was created at `C:\Users\camil\keys\` - **Confirmed (2.8 KB)**
- [x] **BACKUP keystore file to secure location** (external drive, cloud storage) - **COMPLETED**
- [x] **Document passwords securely** (password manager) - **COMPLETED**

### 2.2 Configure Signing in Flutter
- [x] Create `android/key.properties` file
- [x] Add content:
  ```properties
  storePassword=[YOUR_KEYSTORE_PASSWORD]
  keyPassword=[YOUR_KEY_PASSWORD]
  keyAlias=ccwmap-upload
  storeFile=C:\\Users\\camil\\keys\\ccwmap-upload.jks
  ```
- [x] File created at: `C:\Users\camil\projects\ccwmap\android\key.properties`
- [x] **IMMEDIATELY** add `android/key.properties` to `.gitignore` - **Added (lines 49-52)**
- [x] Verify file is not committed: `git status` shows clean - **Confirmed**
- [x] **NOTE:** Actual passwords stored in `key.properties` file (gitignored) and password manager

### 2.3 Update build.gradle for Signing
- [x] Open `android/app/build.gradle.kts` (Kotlin DSL)
- [x] Add imports at top:
  ```kotlin
  import java.util.Properties
  import java.io.FileInputStream
  import java.io.File
  ```
- [x] Load keystore properties (before `android {}`):
  ```kotlin
  val keystorePropertiesFile = rootProject.file("key.properties")
  val keystoreProperties = Properties()
  if (keystorePropertiesFile.exists()) {
      FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
  }
  ```
- [x] Add `signingConfigs` block inside `android { ... }`:
  ```kotlin
  signingConfigs {
      create("release") {
          keyAlias = keystoreProperties.getProperty("keyAlias")
          keyPassword = keystoreProperties.getProperty("keyPassword")
          storeFile = keystoreProperties.getProperty("storeFile")?.let { File(it) }
          storePassword = keystoreProperties.getProperty("storePassword")
      }
  }
  ```
- [x] Update `buildTypes { release { ... } }`:
  ```kotlin
  release {
      signingConfig = signingConfigs.getByName("release")
      isMinifyEnabled = true
      isShrinkResources = true
      proguardFiles(
          getDefaultProguardFile("proguard-android-optimize.txt"),
          "proguard-rules.pro"
      )
  }
  ```
- [x] Create `android/app/proguard-rules.pro` file with Flutter rules
- [x] Save files
- [x] Test compile: `flutter pub get` - **SUCCESS**
- [x] Verify signing config: `./gradlew signingReport` - **SUCCESS**
  - Store: `C:\Users\camil\keys\ccwmap-upload.jks`
  - Alias: `ccwmap-upload`
  - Valid until: June 28, 2053
  - SHA-256: `9E:6E:D7:D8:38:75:3F:02:4E:D8:61:2A:FB:08:82:9F:03:79:A2:99:98:6A:8F:4D:62:E1:D9:05:8A:9A:02:35`

---

## Phase 3: Build Release Bundle

### 3.1 Clean and Build
- [x] Run: `flutter clean` - **Completed**
- [x] Run: `flutter pub get` - **Completed**
- [x] Run: `flutter build appbundle --release` - **Completed**
- [x] Wait for completion (may take 2-5 minutes) - **Took 1m 16s**
- [x] Verify no errors in output - **Gradle BUILD SUCCESSFUL**
- [x] Note: Debug symbol stripping warning is non-critical (cmdline-tools issue)
- [x] Updated `compileSdk` to 36 (required by androidx dependencies)

### 3.2 Verify Build Output
- [x] Check file exists: `build/app/outputs/bundle/release/app-release.aab` - **Confirmed**
- [x] Check file size: `ls -lh build/app/outputs/bundle/release/app-release.aab` - **59 MB**
- [x] Verify size is under 150MB - **✓ Well under limit (59 MB / 150 MB)**
- [x] Verify AAB is signed - **✓ Signed with upload keystore (SHA384withRSA)**
  - Signer: CN=Camilo Hurtado, O=Kybernetic Labs, L=Tampa, ST=Florida, C=US
  - Valid: 2/10/26 to 6/28/53
  - MD5: `bf3be1bd77602376dda2e3a4cea515e5`
- [ ] **BACKUP** `app-release.aab` file to secure location - **ACTION REQUIRED**
- [x] Note the exact file path: `C:\Users\camil\projects\ccwmap\build\app\outputs\bundle\release\app-release.aab`

---

## Phase 4: Play Console Setup

### 4.1 Create App in Play Console
- [x] Go to [Play Console](https://play.google.com/console)
- [x] Sign in with your developer account
- [x] Click **Create app**
- [x] Fill in form:
  - [x] App name: `CCW Map`
  - [x] Default language: `English (United States)`
  - [x] App or game: Select `App`
  - [x] Free or paid: Select `Free`
  - [x] Declarations: Check all required boxes
- [x] Click **Create app** button
- [x] Wait for app to be created
- [x] Note your App ID: `com.ccwmap.app` (Package name / Application ID)

### 4.2 Enable Play App Signing
- [ ] Navigate to **Release > Setup > App signing**
- [ ] Read the information about Play App Signing
- [ ] Check box accepting the terms: `☐ I understand and accept`
- [ ] Click **Enable** or confirm enrollment
- [ ] If prompted, upload your upload key certificate
- [ ] **Status should show:** "Managed by Google Play"

### 4.3 Complete Data Safety Form (CRITICAL FOR 2026)
- [x] Navigate to **App content > Data safety**
- [x] Click **Start** or **Edit**
- [x] Answer questions about data collection:
  - [x] **Location data:** Yes - Precise location (for pin mapping)
  - [x] **User account information:** Yes - Email addresses (authentication)
  - [x] **Photos/videos/audio:** No
  - [x] **Calendar:** No
  - [x] **Contacts:** No
  - [x] **SMS:** No
  - [x] **Payment information:** No
  - [x] **Health/fitness:** No
  - [x] **Other personal info:** No
- [x] For each selected data type, answer:
  - [x] Is collection optional? No (required for functionality)
  - [x] Data usage: `App functionality`
  - [x] Shared with third parties? No
  - [x] Encrypted in transit? Yes
  - [x] Users can request deletion? Yes
- [x] Complete security practices section:
  - [x] Data encrypted in transit: Yes
  - [x] Committed to compliance: Checked
  - [x] Authorized to bind by terms: Checked
- [x] Click **Save and continue**
- [x] Verify form shows as complete with checkmark

### 4.4 Set Content Rating
- [x] Go to **App content > Content rating**
- [x] If first time: Click **Fill out questionnaire**
- [x] Answer questions (CCW Map is informational, not violent):
  - [x] Violence: `None`
  - [x] Profanity: `None`
  - [x] Sexual content: `None`
  - [x] Substance abuse: `None`
  - [x] Gambling: `None`
  - [x] Other: `None`
- [x] Click **Submit questionnaire**
- [x] View assigned rating:
  - [x] Rating received (informational app)
- [x] Note rating: **Completed**

### 4.5 Add Privacy Policy URL
- [x] Go to **App content > Privacy policy**
- [x] Enter hosted URL: `https://camiloh12.github.io/ccwmap/privacy-policy.html`
- [x] Click **Save**
- [x] Verify status shows as complete
- [x] Test URL in browser to confirm it's accessible

### 4.6 Set Target Audience and Content
- [x] Go to **App content > Target audience**
- [x] Select primary target age: `18+` (firearm-related content)
- [x] For content guidelines:
  - [x] Content rating: Verified (from 4.4)
  - [x] Apps for kids: `No`
  - [x] Advertisements: `No`
  - [x] User-generated content: `Yes` (pins are user-generated)
  - [x] Financial transactions: `No`
  - [x] Sensitive information: `Yes` (location data collected)
- [x] Click **Save**

---

## Phase 5: Create Store Listing

### 5.1 Main Store Listing Setup
- [x] Go to **Main store listing** or **Manage > Main store listing**
- [x] Fill in basic information:
  - [x] **App name:** `CCW Map` (max 50 chars)
  - [x] **Short description:** (max 80 chars)
    ```
    Collaborative map of concealed carry weapon zones across the United States
    ```
  - [x] Short description: "Collaborative map of concealed carry weapon zones across the United States"

### 5.2 Full Description
- [x] In **Full description** field (max 4000 chars), paste:
  ```
  CCW Map helps responsible gun owners navigate concealed carry laws by crowdsourcing information about CCW-friendly and restricted zones.

  Features:
  • Interactive map with color-coded pins (green=allowed, yellow=uncertain, red=restricted)
  • Offline-first design - works without internet connection
  • Detailed restriction tags (federal property, schools, airports, etc.)
  • Community-driven data - contribute and update locations
  • US boundary coverage with precise location tracking

  Whether you're traveling, commuting, or exploring new areas, CCW Map provides essential information to help you stay compliant with local regulations.

  Privacy & Security:
  • Secure authentication with email verification
  • Data synchronized across devices
  • Your contributions help the community stay informed

  Note: This app provides user-contributed information and should not be considered legal advice. Always verify local laws and regulations.
  ```
- [x] Click **Save**
- [x] Verify character count is under 4000

### 5.3 Upload App Icon
- [x] Create or obtain 512 x 512 PNG app icon with alpha channel
- [x] Icon should be square with rounded corners
- [x] Go to **App icon** section
- [x] Click **Upload image**
- [x] Select your 512x512 PNG file
- [x] Verify preview looks correct
- [x] Icon should be memorable and clear at small sizes
- [x] File uploaded and verified

### 5.4 Upload Feature Graphic
- [x] Create or obtain 1024 x 500 feature graphic (JPG or PNG)
- [x] Should showcase app key features (map with pins)
- [x] Go to **Feature graphic** section
- [x] Click **Upload image**
- [x] Select your 1024x500 file
- [x] Verify preview looks good
- [x] File uploaded and verified

### 5.5 Upload Phone Screenshots (MINIMUM 2, MAXIMUM 8)
- [x] Create 2-8 screenshots showing app interface - **5 screenshots created**
- [x] Each screenshot must be:
  - [x] 9:16 aspect ratio (portrait)
  - [x] PNG format
  - [x] Minimum 320px on shortest side
- [x] Screenshots captured:
  - [x] Screenshot 1: Sign In / Authentication screen
  - [x] Screenshot 2: Map view with multiple pins (green/red)
  - [x] Screenshot 3: Create Pin dialog
  - [x] Screenshot 4: Edit Pin dialog (Allowed - Publix)
  - [x] Screenshot 5: Edit Pin dialog (Restricted - Hospital with tags)
- [x] Go to **Phone screenshots** section
- [x] Click **Add screenshot** (5 times)
- [x] Upload each screenshot in order
- [x] Add optional captions:
  - "Secure authentication with email verification"
  - "Interactive map showing CCW-friendly and restricted zones"
  - "Easy pin creation with color-coded status indicators"
  - "Edit locations with detailed information"
  - "Specify restriction reasons for no-carry zones"
- [x] Verify all uploads completed
- [x] **Screenshots saved in:** `assets/screenshots/` (version controlled)

### 5.6 Optional: Upload Tablet Screenshots
- [ ] If tablet layout is significantly different, consider tablet screenshots
- [ ] Each tablet screenshot should be:
  - [ ] 7" or 10" tablet aspect ratio
  - [ ] JPG or PNG format
  - [ ] Minimum 320px on shortest side
- [ ] Go to **Tablet screenshots** section (if available)
- [ ] Upload 1-8 tablet-specific screenshots
- [ ] Note: For first release, phone screenshots are sufficient

### 5.7 Set Category
- [x] Go to **Category** section
- [x] Select: `Maps & Navigation`
- [x] Optional tags (space-separated):
  - [x] Add: `travel safety location firearm concealed-carry`
- [x] Save

### 5.8 Contact Details
- [x] Go to **Contact details** section
- [x] **Email:** Provided
- [x] **Phone:** (optional) Not provided
- [x] **Website:** `https://github.com/camiloh12/ccwmap`
- [x] Save

### 5.9 Verify Complete Store Listing
- [x] Check all sections marked with green checkmark:
  - [x] ✓ Short description
  - [x] ✓ Full description
  - [x] ✓ App icon (512x512)
  - [x] ✓ Feature graphic (1024x500)
  - [x] ✓ Phone screenshots (5 screenshots uploaded)
  - [x] ✓ Category (Maps & Navigation)
  - [x] ✓ Contact details
- [x] Preview how listing will appear in Play Store

---

## Phase 6: Testing Track (REQUIRED FOR NEW ACCOUNTS)

### 6.1 Check Account Age
- [ ] Was your Play developer account created after November 2023?
  - [ ] Yes → Must complete 6.2 (Closed Testing with 20 testers for 14 days)
  - [ ] No → Can skip to 6.2 (internal) or go directly to Phase 7

### 6.2 Create Internal Testing Release (Recommended)
- [ ] Go to **Release > Testing > Internal testing**
- [ ] Click **Create new release**
- [ ] In **Select bundle**:
  - [ ] Click **Browse files** or **Upload**
  - [ ] Select `build/app/outputs/bundle/release/app-release.aab`
  - [ ] Wait for upload and validation
- [ ] In **Release notes** (what's new):
  ```
  Initial beta release - v0.1.0

  Features:
  - Interactive map of concealed carry zones
  - Create, edit, and delete pins with restrictions
  - Offline-first functionality
  - Secure user authentication
  - US-wide coverage
  ```
- [ ] Click **Save**
- [ ] Under **Testers**, add emails of internal testers:
  - [ ] Add your own email
  - [ ] Add 1-2 trusted testers (optional)
- [ ] Click **Review release**
- [ ] Verify:
  - [ ] AAB file uploaded successfully
  - [ ] No validation errors
  - [ ] Release notes present
- [ ] Click **Start rollout to Internal testing**
- [ ] Status should show **In review** or **Submitted**
- [ ] Wait for email indicating release is ready
- [ ] Test app via link sent to your email
- [ ] Verify functionality:
  - [ ] [ ] App installs and launches
  - [ ] [ ] No immediate crashes
  - [ ] [ ] Can create account
  - [ ] [ ] Can create pins
  - [ ] [ ] Map displays correctly
  - [ ] [ ] Offline mode works

### 6.3 Create Closed Testing Release (REQUIRED IF ACCOUNT CREATED AFTER NOV 2023)
- [ ] Go to **Release > Testing > Closed testing**
- [ ] Click **Create new release**
- [ ] First, create tester list:
  - [ ] Click **Manage closed testing track**
  - [ ] Click **Create email list**
  - [ ] Name: `CCW Map Beta Testers`
  - [ ] Add **minimum 20 email addresses** of people willing to test:
    - [ ] `_________________________________`
    - [ ] `_________________________________`
    - [ ] `_________________________________`
    - [ ] `_________________________________`
    - [ ] `_________________________________`
    - [ ] (add 15 more)
  - [ ] Click **Save**
- [ ] Now create release:
  - [ ] Go back to **Release > Testing > Closed testing**
  - [ ] Click **Create new release**
  - [ ] Upload AAB file (same as internal)
  - [ ] Add release notes (same as internal)
  - [ ] Add tester email list created above
- [ ] Click **Review release**
- [ ] Click **Start rollout to Closed testing**
- [ ] **IMPORTANT:** This track must run for **14 continuous days minimum**
- [ ] **Calendar reminder:** Set reminder for 14 days from today: `_________________________________`
- [ ] Collect feedback from testers during 14 days
- [ ] Monitor for crashes in Play Console > Quality
- [ ] Fix critical bugs if found (rebuild AAB and create new release)
- [ ] After 14 days, proceed to Phase 7

### 6.4 Optional: Create Open Testing Release
- [ ] Go to **Release > Testing > Open testing**
- [ ] Click **Create new release**
- [ ] Upload same AAB file
- [ ] Add release notes
- [ ] This allows unlimited users to opt-in to beta
- [ ] Good for gathering broader feedback
- [ ] Can do this in parallel with closed testing or after
- [ ] Click **Start rollout to Open testing**

---

## Phase 7: Production Release

### 7.1 Create Production Release
- [ ] Navigate to **Release > Production**
- [ ] Click **Create new release**
- [ ] In **Select bundle**:
  - [ ] Click **Browse files** or **Upload**
  - [ ] Select `build/app/outputs/bundle/release/app-release.aab`
  - [ ] Wait for upload and validation (should be fast - same AAB)
  - [ ] Verify no validation errors
- [ ] Click **Next** or **Continue**

### 7.2 Add Release Notes for Production
- [ ] In **Release notes** (what's new), paste:
  ```
  CCW Map v1.0.0 - Initial Release

  We're excited to launch CCW Map, a collaborative tool for navigating concealed carry laws across the United States!

  Features:
  • Interactive map showing concealed carry weapon zone information
  • Create and update pins with detailed restriction tags
  • Color-coded status indicators (allowed, uncertain, restricted)
  • Offline-first design - works without internet connection
  • Secure user authentication
  • Community-driven data to help users stay compliant

  Privacy & Security:
  • Your location data is used only for mapping
  • Secure authentication with encrypted connections
  • Your contributions remain associated with your account

  Disclaimer: This app provides user-contributed information and should not be considered legal advice. Always verify local laws and regulations before carrying.
  ```
- [ ] Click **Next**

### 7.3 Set Countries and Regions
- [ ] Select **United States** as primary market
- [ ] Add other countries (optional):
  - [ ] You can target specific countries or regions
  - [ ] For initial release, US only is fine
  - [ ] Can add more countries in future updates
- [ ] Click **Next** or **Continue**

### 7.4 Set Rollout Strategy
- [ ] Choose rollout type:
  - [ ] **Full rollout:** Release to 100% of users immediately
    - [ ] Recommended: **NO** for first release (higher risk)
  - [ ] **Staged rollout:** Release to increasing percentage over time
    - [ ] Recommended: **YES**
- [ ] If staged rollout selected:
  - [ ] Set initial rollout: `5%` (or 10%)
  - [ ] Plan next stages:
    - [ ] Day 1: 5%
    - [ ] Day 3: 10%
    - [ ] Day 5: 20%
    - [ ] Day 7: 50%
    - [ ] Day 10: 100%
  - [ ] **NOTE:** Can manually increase percentages in Play Console anytime
- [ ] Click **Next**

### 7.5 Review Release Before Publishing
- [ ] Verify **ALL** sections have green checkmarks:
  - [ ] ✓ Release bundle (AAB uploaded)
  - [ ] ✓ Release notes (added)
  - [ ] ✓ Countries & regions (US selected)
  - [ ] ✓ Rollout schedule (staged or full)
- [ ] Verify **Store listing complete:**
  - [ ] ✓ App access (configured in 4.6)
  - [ ] ✓ Content rating (set in 4.4)
  - [ ] ✓ Data safety (completed in 4.3)
  - [ ] ✓ Privacy policy (added in 4.5)
  - [ ] ✓ Target audience (configured in 4.6)
  - [ ] ✓ Store listing (completed in Phase 5)
  - [ ] ✓ Pricing (free)
- [ ] Review app icon, screenshots, descriptions one more time
- [ ] Check for any typos or errors

### 7.6 Submit for Review
- [ ] Click **Review release** button
- [ ] Read final confirmation message
- [ ] Click **Start rollout to Production**
- [ ] **Confirmation:** App will now be submitted for Google Play review
- [ ] **RECORD SUBMISSION DETAILS:**
  - [ ] Submission time: `_________________________________`
  - [ ] Submission date: `_________________________________`
  - [ ] Version code submitted: `1`
  - [ ] Initial rollout percentage: `_____`%

### 7.7 Monitor Submission Status
- [ ] Go to **Release > Production**
- [ ] Check release status:
  - [ ] Expected status: **Pending review**
  - [ ] Time estimate: 1-7 days
- [ ] **Email notifications:** Google will send updates to developer account email
- [ ] Monitor in Play Console daily:
  - [ ] Go to **Release > Production**
  - [ ] Check status column
  - [ ] Look for any action required messages
- [ ] **EXPECTED TIMELINE:**
  - [ ] Day 1-2: Pending review (usually sent to review team quickly)
  - [ ] Day 2-5: Under review (automated + human review)
  - [ ] Day 5-7: Usually decision made
  - [ ] If approved: Status changes to **Ready to publish** or **Published**
  - [ ] If rejected: Status changes to **Rejected** with reason

---

## Phase 8: Post-Submission Actions

### 8.1 While App is Under Review
- [ ] Do NOT make changes to release while under review
- [ ] Do NOT change store listing drastically
- [ ] Do monitor email for status updates
- [ ] Document your submission date and expected review date:
  - [ ] Submitted: `_________________________________`
  - [ ] Expected decision: `_________________________________`
- [ ] Continue monitoring for crashes:
  - [ ] Go to **Quality > Crashes & ANRs**
  - [ ] Check for any crashes from testers (from testing track)
  - [ ] If critical crash found, prepare fix for post-launch

### 8.2 Common Rejection Reasons (2026)
If your app is rejected, check these common issues:
- [ ] Missing data safety declaration (completed in Phase 4.3)
- [ ] Privacy policy not accessible or complete
- [ ] targetSdk below 35 (should be 35)
- [ ] Missing or incomplete content rating
- [ ] App crashes on startup
- [ ] Deep links not working (test in 8.4)
- [ ] Insufficient testing (new account without 14-day closed test)
- [ ] Policy violations (read rejection email carefully)

### 8.3 If App is Rejected
- [ ] Read rejection email carefully and thoroughly
- [ ] Identify root cause(s)
- [ ] Fix issues:
  - [ ] If code issue: Fix, rebuild, new AAB
  - [ ] If Play Console issue: Fix configuration, no rebuild needed
- [ ] **IMPORTANT:** Increment version code
  - [ ] Open `android/app/build.gradle`
  - [ ] Change `versionCode = 1` to `versionCode = 2`
  - [ ] Change `versionName = "1.0.0"` to `versionName = "1.0.1"`
  - [ ] If only Play Console issue (no code change): Still increment versionCode
- [ ] If code changed:
  - [ ] Run `flutter build appbundle --release`
  - [ ] New AAB created
- [ ] Create new release:
  - [ ] Go to **Release > Production**
  - [ ] Click **Create new release**
  - [ ] Upload updated AAB (or same if only Play Console fixes)
  - [ ] Add release notes explaining fixes:
    ```
    v1.0.1 - Resubmission

    Fixed issues from initial review:
    - [Describe fixes made]
    ```
  - [ ] Submit again
  - [ ] Wait for new review
- [ ] **Note:** Resubmission review usually faster than initial review

### 8.4 Test Deep Links Before Approval
- [ ] Install app from testing track on physical device
- [ ] Test email verification deep link:
  - [ ] Create account in app
  - [ ] Check email for verification link
  - [ ] Click link - should open app to confirmation page
  - [ ] If not working: Fix in `AndroidManifest.xml` and redeploy to testing
- [ ] Verify link schemes:
  - [ ] `com.ccwmap.app://auth/callback` (deep link scheme)
  - [ ] `https://camiloh12.github.io/ccwmap/auth/callback` (fallback URL)

---

## Phase 9: Post-Approval Actions

### 9.1 App Approved! 🎉
- [ ] Status changes to **Published** or **Ready to publish**
- [ ] If "Ready to publish": Click **Publish** button to go live immediately
- [ ] Verify app is visible in Play Store:
  - [ ] Go to Google Play Store app or web
  - [ ] Search for "CCW Map"
  - [ ] Verify your app appears
  - [ ] Check listing looks correct (screenshots, description, icon)

### 9.2 Monitor After Launch
- [ ] Set up monitoring dashboard:
  - [ ] Go to **Quality > Overview**
  - [ ] Check crashes, ANRs, vital metrics
  - [ ] Crashes should be near 0% for first days
  - [ ] Monitor daily for first week
- [ ] Check analytics:
  - [ ] Go to **Statistics > Overview**
  - [ ] Check install count
  - [ ] Check uninstall trends
  - [ ] Set up alerts for unusual activity
- [ ] Respond to user reviews:
  - [ ] Go to **Reviews**
  - [ ] Read all 5-star and 1-star reviews
  - [ ] Reply to negative reviews with helpful tone
  - [ ] Thank users for positive feedback
- [ ] Check for critical issues:
  - [ ] If crash rate > 1%: Prepare hotfix
  - [ ] If multiple similar issues: Create bug report
  - [ ] Monitor Supabase logs for API errors

### 9.3 Build Hotfix (If Needed)
- [ ] If critical crash detected:
  - [ ] Fix bug in code
  - [ ] Increment version:
    - [ ] `versionCode = 2` → `3`
    - [ ] `versionName = "1.0.1"` → `"1.0.2"`
  - [ ] Run `flutter build appbundle --release`
  - [ ] Create new release in **Production**
  - [ ] Add release notes: "v1.0.2 - Critical fix for [issue]"
  - [ ] Use full rollout (100%) for urgent fixes
  - [ ] Submit for review

### 9.4 Manage Staged Rollout (If Applied)
- [ ] Go to **Release > Production**
- [ ] Under staged rollout, see current percentage
- [ ] Monitor crashes/issues at current percentage for 2-3 days
- [ ] If all good, manually increase percentage:
  - [ ] Click **Increase rollout**
  - [ ] Set new percentage (10%, 25%, 50%, 100%)
  - [ ] Confirm
  - [ ] Monitor again
- [ ] Only increase to 100% once confident

### 9.5 Verify App in Play Store
- [ ] Check your app page:
  - [ ] `https://play.google.com/store/apps/details?id=com.ccwmap.app`
  - [ ] (Replace with actual app ID)
- [ ] Verify all information displays correctly
- [ ] Download and test on new device
- [ ] Check play store listing matches your configured store listing

---

## Phase 10: Updates and Maintenance

### 10.1 Creating Updates for Future Releases
For each new version you release:

- [ ] Make code changes needed
- [ ] Update version in `pubspec.yaml`:
  - [ ] Increment version: `1.0.0` → `1.1.0` (or `1.0.1` for patch)
- [ ] Update version in `android/app/build.gradle`:
  - [ ] `versionCode = 1` → `versionCode = 2` (increment by 1)
  - [ ] `versionName = "1.0.0"` → `versionName = "1.1.0"`
  - [ ] **Rule:** versionCode must always increase, versionName can be any format
- [ ] Test on physical device: `flutter run --release`
- [ ] Verify all new features work
- [ ] Build AAB: `flutter build appbundle --release`
- [ ] Create release in **Production**
- [ ] Write detailed release notes
- [ ] Submit for review

### 10.2 Required Annual Actions (IMPORTANT FOR 2026+)
- [ ] **Every 12 months:**
  - [ ] Re-verify data safety declaration
  - [ ] Update privacy policy if features changed
  - [ ] Check target SDK requirement (must be within 1 year of latest Android)
  - [ ] Update compliance documents
- [ ] **Review checklist quarterly:**
  - [ ] Verify store listing is up-to-date
  - [ ] Check all screenshots still relevant
  - [ ] Review and respond to user feedback
  - [ ] Monitor crash rates and fix critical issues

### 10.3 Monitor App Health Continuously
- [ ] Set calendar reminders for:
  - [ ] Weekly: Check crash reports
  - [ ] Weekly: Review new user feedback
  - [ ] Monthly: Check install trends
  - [ ] Quarterly: Update metadata if needed
  - [ ] Annually: Verify compliance requirements
- [ ] Use Play Console dashboard:
  - [ ] **Quality > Overview:** Crash trends
  - [ ] **Quality > Vitals:** Performance metrics
  - [ ] **Statistics > Overview:** Install/uninstall rates
  - [ ] **Reviews:** User feedback
  - [ ] **Crashes & ANRs:** Detailed crash logs

### 10.4 End-of-Life Plan
- [ ] If app discontinuation decided:
  - [ ] [ ] Set app to "Inactive" (will be removed from Play Store)
  - [ ] [ ] Respond to users about alternative apps
  - [ ] [ ] Archive all code and documentation
  - [ ] [ ] Preserve keystore and signing credentials

---

## Emergency Contacts & Resources

### Important Links
- [ ] [Play Console](https://play.google.com/console)
- [ ] [Flutter Android Deployment Docs](https://docs.flutter.dev/deployment/android)
- [ ] [Android Developer Docs](https://developer.android.com/studio/publish/app-signing)
- [ ] [Play Console Help Center](https://support.google.com/googleplay/android-developer)
- [ ] [CCW Map GitHub](https://github.com/camiloh12/ccwmap)

### Support Contacts
- [ ] Personal email: `_________________________________`
- [ ] Developer account email: `_________________________________`
- [ ] Play Console recovery email: `_________________________________`

### Backup Information
- [ ] Keystore file backed up at: `_________________________________`
- [ ] Keystore password stored in: `_________________________________`
- [ ] App signing key fingerprint: `_________________________________`

---

## Sign-Off

- [ ] **All phases completed:** Date: `_________________________________`
- [ ] **App published to Play Store:** Yes/No
- [ ] **Celebration:** 🎉 (Congratulations on your launch!)

---

**Notes for Future Reference:**

```
[Space for additional notes, lessons learned, or issues encountered]




```
