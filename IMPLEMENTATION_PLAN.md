# CCW Map - Implementation Plan & Checklist

**Project**: CCW Map (Flutter)
**Version**: 1.0
**Last Updated**: 2025-11-16
**Platform**: Android & iOS (Flutter)

---

## Overview

This implementation plan provides a detailed, iterative roadmap for building the CCW Map application using Flutter. Each iteration is designed to deliver a working, testable feature set that builds upon the previous iteration.

**Approach**: Start with visual features (map display) early to provide immediate feedback, then progressively add data management, authentication, and sync capabilities.

---

## Progress Tracking

- [x] **Iteration 1**: Project Setup & Basic Map Display ✓
- [ ] **Iteration 2**: Location Services
- [ ] **Iteration 3**: Domain Models & Local Database
- [ ] **Iteration 4**: Display Static Pins on Map
- [ ] **Iteration 5**: Authentication
- [ ] **Iteration 6**: Create & Edit Pin Dialogs (UI Only)
- [ ] **Iteration 7**: Pin Creation & Editing (Local Only)
- [ ] **Iteration 8**: POI Integration
- [ ] **Iteration 9**: Remote Database & Basic Sync
- [ ] **Iteration 10**: Offline-First Sync Queue
- [ ] **Iteration 11**: Background Sync
- [ ] **Iteration 12**: Polish & Testing
- [ ] **Iteration 13**: CI/CD & Deployment

---

## Iteration 1: Project Setup & Basic Map Display

**Goal**: Get a basic map showing on screen
**Estimated Time**: 2-3 days
**Deliverable**: App shows interactive map with basic UI overlay

### Tasks

#### 1.1 Initialize Flutter Project
- [x] Run `flutter create ccwmap` with proper parameters
- [x] Configure package name: `com.ccwmap.app`
- [x] Set up project description and metadata in `pubspec.yaml`
- [x] Verify project runs on both Android and iOS simulators/emulators
- [x] Initialize git repository (if not already done)
- [x] Create `.gitignore` file with Flutter defaults

#### 1.2 Set Up Project Structure
- [x] Create `lib/domain/` directory
  - [x] Create `lib/domain/models/` subdirectory
  - [x] Create `lib/domain/repositories/` subdirectory
- [x] Create `lib/data/` directory
  - [x] Create `lib/data/repositories/` subdirectory
  - [x] Create `lib/data/datasources/` subdirectory
  - [x] Create `lib/data/models/` subdirectory
- [x] Create `lib/presentation/` directory
  - [x] Create `lib/presentation/screens/` subdirectory
  - [x] Create `lib/presentation/widgets/` subdirectory
  - [x] Create `lib/presentation/viewmodels/` subdirectory
- [x] Create `assets/` directory for images/icons
- [x] Create `.env.example` file for configuration template

#### 1.3 Configure Platform-Specific Files

**Android Configuration:**
- [x] Update `android/app/build.gradle`:
  - [x] Set `minSdkVersion` to 21
  - [x] Set `targetSdkVersion` to 34
  - [x] Set `applicationId` to "com.ccwmap.app"
- [x] Update `android/app/src/main/AndroidManifest.xml`:
  - [x] Add INTERNET permission
  - [x] Add ACCESS_FINE_LOCATION permission
  - [x] Add ACCESS_COARSE_LOCATION permission
  - [x] Add ACCESS_NETWORK_STATE permission
  - [x] Configure deep link intent filters for auth callback
  - [x] Set application name to "CCW Map"

**iOS Configuration:**
- [x] Update `ios/Runner/Info.plist`:
  - [x] Add NSLocationWhenInUseUsageDescription
  - [x] Add CFBundleURLTypes for deep linking
  - [x] Add FlutterDeepLinkingEnabled
  - [x] Set CFBundleDisplayName to "CCW Map"
- [x] Update `ios/Runner.xcodeproj/project.pbxproj` if needed

#### 1.4 Add Initial Dependencies
- [x] Add to `pubspec.yaml`:
  ```yaml
  dependencies:
    flutter:
      sdk: flutter
    maplibre_gl: ^0.20.0
    flutter_dotenv: ^5.1.0
  ```
- [x] Run `flutter pub get`
- [x] Verify dependencies resolve correctly

#### 1.5 Integrate MapLibre GL
- [x] Create `lib/presentation/screens/map_screen.dart`
- [x] Import `maplibre_gl` package
- [x] Create `MapScreen` StatefulWidget
- [x] Initialize `MapLibreMapController`
- [x] Set up map widget in build method
- [x] Configure initial camera position (center of US)
  - [x] Latitude: 39.8283, Longitude: -98.5795, Zoom: 4.0
- [x] Use demo tiles (no API key required initially)
  - [x] Style URL: `https://demotiles.maplibre.org/style.json`
- [x] Implement `onMapCreated` callback
- [x] Test pan gesture
- [x] Test zoom gesture (pinch)
- [x] Test rotate gesture (two-finger rotation)

#### 1.6 Add Basic UI Chrome
- [x] Create overlaid title bar (not AppBar)
  - [x] Position "CCW Map" text in top-left
  - [x] Style: Dark text, semi-transparent background
  - [x] Add padding: 16px horizontal, 12px vertical
- [x] Add exit/sign out icon placeholder in top-right
  - [x] Use `Icons.exit_to_app` or similar
  - [x] Position with `Positioned` widget
  - [x] Add tap handler (show dialog for now)
- [x] Add re-center FAB in bottom-right
  - [x] Use `FloatingActionButton`
  - [x] Icon: `Icons.my_location`
  - [x] Background: Light purple/lavender (`Color(0xFFE8DEF8)`)
  - [x] Position: 16px from bottom, 16px from right
  - [x] Add tap handler (placeholder for now)

#### 1.7 Test on Both Platforms
- [x] Run app on Android emulator
  - [x] Verify map loads
  - [x] Test all gestures
  - [x] Check UI overlay positioning
- [x] Run app on iOS simulator
  - [x] Verify map loads
  - [x] Test all gestures
  - [x] Check UI overlay positioning
- [x] Fix any platform-specific issues

#### 1.8 Update Main.dart
- [x] Create `MaterialApp` with proper theme
- [x] Set `MapScreen` as home
- [x] Configure app title: "CCW Map"
- [x] Add basic theme colors (purple primary)
- [x] Test app launches correctly

**Iteration 1 Complete** ✓ ✓ ✓

---

## Iteration 2: Location Services

**Goal**: Show user's current location on the map
**Estimated Time**: 1-2 days
**Deliverable**: Map shows user's location and can re-center to it

### Tasks

#### 2.1 Add Geolocator Package
- [ ] Add `geolocator: ^11.0.0` to `pubspec.yaml`
- [ ] Run `flutter pub get`

#### 2.2 Configure Platform Permissions

**Android:**
- [ ] Verify location permissions in AndroidManifest.xml (should be done in Iteration 1)
- [ ] Add `permission_handler` package if needed for runtime permissions

**iOS:**
- [ ] Verify NSLocationWhenInUseUsageDescription in Info.plist (should be done in Iteration 1)

#### 2.3 Implement Location Service Class
- [ ] Create `lib/data/services/location_service.dart`
- [ ] Implement `checkPermission()` method
- [ ] Implement `requestPermission()` method
- [ ] Implement `getCurrentLocation()` method
- [ ] Implement `getLocationStream()` method (for continuous updates)
- [ ] Handle permission denied scenario
- [ ] Handle location services disabled scenario
- [ ] Add error handling and logging

#### 2.4 Integrate Location into MapScreen
- [ ] Create state variable for current location
- [ ] Request location permission on screen init
- [ ] Call `getCurrentLocation()` on map created
- [ ] Store location in state
- [ ] Enable location component on MapLibre map
  - [ ] Call `mapController.setMyLocationTrackingMode()`
  - [ ] Configure location indicator style (blue dot)
- [ ] Add location update listener
- [ ] Update map camera when location changes (optional)

#### 2.5 Implement Re-center Functionality
- [ ] Wire up FAB tap handler
- [ ] Get current location when FAB tapped
- [ ] Animate map camera to user location
  - [ ] Target: User's lat/lng
  - [ ] Zoom: 16.0
  - [ ] Duration: 1000ms
- [ ] Handle case when location is unavailable
- [ ] Show snackbar if location permission denied

#### 2.6 Handle Permission Denied Gracefully
- [ ] Create permission denied dialog
- [ ] Explain why location is needed
- [ ] Provide option to open app settings
- [ ] Allow app to work without location (map still functional)

#### 2.7 Test Location Features
- [ ] Test on Android device/emulator
  - [ ] Grant location permission
  - [ ] Verify blue dot appears at current location
  - [ ] Test re-center button
  - [ ] Deny permission and verify graceful handling
- [ ] Test on iOS device/simulator
  - [ ] Grant location permission
  - [ ] Verify blue dot appears
  - [ ] Test re-center button
  - [ ] Deny permission and verify graceful handling
- [ ] Test permission flow (allow → deny → allow again)

**Iteration 2 Complete** ✓

---

## Iteration 3: Domain Models & Local Database

**Goal**: Set up data foundation without sync
**Estimated Time**: 2-3 days
**Deliverable**: Domain models defined and local database operational

### Tasks

#### 3.1 Create Domain Models

**Location Value Object:**
- [ ] Create `lib/domain/models/location.dart`
- [ ] Implement `Location` class
  - [ ] Fields: `double latitude`, `double longitude`
  - [ ] Constructor with validation (-90 to 90 lat, -180 to 180 lng)
  - [ ] Factory: `Location.fromLatLng(lat, lng)`
  - [ ] Factory: `Location.fromLngLat(lng, lat)`
  - [ ] Override `==` and `hashCode`
  - [ ] Add `toString()` method
- [ ] Write unit tests for Location
  - [ ] Test valid coordinates
  - [ ] Test invalid latitude (out of range)
  - [ ] Test invalid longitude (out of range)
  - [ ] Test equality

**PinStatus Enum:**
- [ ] Create `lib/domain/models/pin_status.dart`
- [ ] Define enum values: `ALLOWED`, `UNCERTAIN`, `NO_GUN`
- [ ] Add `colorCode` getter (0, 1, 2)
- [ ] Add `displayName` getter
- [ ] Add `next()` method (cycle through statuses)
- [ ] Add `fromColorCode(int)` factory
- [ ] Write unit tests for PinStatus
  - [ ] Test colorCode mapping
  - [ ] Test next() cycling
  - [ ] Test fromColorCode conversion

**RestrictionTag Enum:**
- [ ] Create `lib/domain/models/restriction_tag.dart`
- [ ] Define all enum values (10 categories):
  - [ ] FEDERAL_PROPERTY
  - [ ] AIRPORT_SECURE
  - [ ] STATE_LOCAL_GOVT
  - [ ] SCHOOL_K12
  - [ ] COLLEGE_UNIVERSITY
  - [ ] BAR_ALCOHOL
  - [ ] HEALTHCARE
  - [ ] PLACE_OF_WORSHIP
  - [ ] SPORTS_ENTERTAINMENT
  - [ ] PRIVATE_PROPERTY
- [ ] Add `displayName` getter for each
- [ ] Add `fromString(String?)` factory
- [ ] Write unit tests for RestrictionTag
  - [ ] Test displayName for each value
  - [ ] Test fromString conversion

**PinMetadata Model:**
- [ ] Create `lib/domain/models/pin_metadata.dart`
- [ ] Implement `PinMetadata` class
  - [ ] Field: `String? createdBy`
  - [ ] Field: `DateTime createdAt`
  - [ ] Field: `DateTime lastModified`
  - [ ] Field: `String? photoUri`
  - [ ] Field: `String? notes`
  - [ ] Field: `int votes` (default 0)
- [ ] Add `copyWith()` method
- [ ] Add JSON serialization methods
- [ ] Write unit tests for PinMetadata

**Pin Model:**
- [ ] Create `lib/domain/models/pin.dart`
- [ ] Implement `Pin` class
  - [ ] Field: `String id` (UUID)
  - [ ] Field: `String name`
  - [ ] Field: `Location location`
  - [ ] Field: `PinStatus status`
  - [ ] Field: `RestrictionTag? restrictionTag`
  - [ ] Field: `bool hasSecurityScreening`
  - [ ] Field: `bool hasPostedSignage`
  - [ ] Field: `PinMetadata metadata`
- [ ] Add business rule validation
  - [ ] If status == NO_GUN, restrictionTag must not be null
- [ ] Add methods:
  - [ ] `Pin withNextStatus()`
  - [ ] `Pin withStatus(PinStatus)`
  - [ ] `Pin withMetadata(PinMetadata)`
  - [ ] `Pin copyWith(...)`
- [ ] Add JSON serialization
- [ ] Write unit tests for Pin
  - [ ] Test withNextStatus()
  - [ ] Test validation (NO_GUN requires restrictionTag)
  - [ ] Test immutability (copyWith creates new instance)

**User Model:**
- [ ] Create `lib/domain/models/user.dart`
- [ ] Implement `User` class
  - [ ] Field: `String id`
  - [ ] Field: `String? email`
- [ ] Write unit tests

#### 3.2 Set Up Local Database (Drift)

**Note**: Choose Drift for type-safe SQL generation. Alternative: sqflite.

- [ ] Add dependencies:
  ```yaml
  dependencies:
    drift: ^2.16.0
    sqlite3_flutter_libs: ^0.5.0
    path_provider: ^2.1.0
    path: ^1.8.0

  dev_dependencies:
    drift_dev: ^2.16.0
    build_runner: ^2.4.0
  ```
- [ ] Run `flutter pub get`

**Create Database Schema:**
- [ ] Create `lib/data/database/database.dart`
- [ ] Define `@DataClassName('PinEntity')` table
  - [ ] Column: `id` (text, primary key)
  - [ ] Column: `name` (text)
  - [ ] Column: `latitude` (real)
  - [ ] Column: `longitude` (real)
  - [ ] Column: `status` (int)
  - [ ] Column: `restrictionTag` (text, nullable)
  - [ ] Column: `hasSecurityScreening` (boolean)
  - [ ] Column: `hasPostedSignage` (boolean)
  - [ ] Column: `createdBy` (text, nullable)
  - [ ] Column: `createdAt` (int, milliseconds since epoch)
  - [ ] Column: `lastModified` (int)
  - [ ] Column: `photoUri` (text, nullable)
  - [ ] Column: `notes` (text, nullable)
  - [ ] Column: `votes` (int)

- [ ] Define `@DataClassName('SyncQueueEntity')` table
  - [ ] Column: `id` (text, primary key)
  - [ ] Column: `pinId` (text)
  - [ ] Column: `operationType` (text) // CREATE, UPDATE, DELETE
  - [ ] Column: `timestamp` (int)
  - [ ] Column: `retryCount` (int, default 0)
  - [ ] Column: `lastError` (text, nullable)

- [ ] Create `AppDatabase` class extending `_$AppDatabase`
- [ ] Override `schemaVersion` (start with 1)
- [ ] Run build runner: `flutter pub run build_runner build`
- [ ] Fix any generated code errors

**Create DAOs:**
- [ ] Create `lib/data/database/pin_dao.dart`
- [ ] Define `@DriftAccessor` for PinDao
- [ ] Implement CRUD methods:
  - [ ] `Future<void> insertPin(PinEntity)`
  - [ ] `Future<void> updatePin(PinEntity)`
  - [ ] `Future<void> deletePin(String id)`
  - [ ] `Future<PinEntity?> getPinById(String id)`
  - [ ] `Stream<List<PinEntity>> watchAllPins()`
  - [ ] `Future<List<PinEntity>> getAllPins()`

- [ ] Create `lib/data/database/sync_queue_dao.dart`
- [ ] Define `@DriftAccessor` for SyncQueueDao
- [ ] Implement methods:
  - [ ] `Future<void> enqueue(SyncQueueEntity)`
  - [ ] `Future<void> dequeue(String id)`
  - [ ] `Future<List<SyncQueueEntity>> getPendingOperations()`
  - [ ] `Future<void> incrementRetryCount(String id, String error)`

- [ ] Run build runner again
- [ ] Verify DAOs compile correctly

#### 3.3 Create Database Mappers
- [ ] Create `lib/data/mappers/pin_mapper.dart`
- [ ] Implement `PinEntity toEntity(Pin)` function
- [ ] Implement `Pin fromEntity(PinEntity)` function
- [ ] Handle Location conversion
- [ ] Handle enum conversions (PinStatus, RestrictionTag)
- [ ] Handle DateTime to int conversions
- [ ] Write unit tests for mappers
  - [ ] Test round-trip conversion (Pin → Entity → Pin)
  - [ ] Test null handling for optional fields

#### 3.4 Initialize Database
- [ ] Create singleton instance of AppDatabase
- [ ] Initialize database on app startup in `main.dart`
- [ ] Add database close on app dispose (if needed)

#### 3.5 Test Database Operations
- [ ] Write integration tests for database
- [ ] Test insert pin
- [ ] Test update pin
- [ ] Test delete pin
- [ ] Test query pins
- [ ] Test Stream updates (watchAllPins)
- [ ] Test sync queue operations
- [ ] Verify database file is created on device

**Iteration 3 Complete** ✓

---

## Iteration 4: Display Static Pins on Map

**Goal**: Show hardcoded/sample pins on the map
**Estimated Time**: 2 days
**Deliverable**: Map displays colored pin markers

### Tasks

#### 4.1 Create Sample Pins
- [ ] Create `lib/data/sample_data.dart`
- [ ] Define 5-10 sample pins with variety:
  - [ ] Mix of ALLOWED, UNCERTAIN, NO_GUN statuses
  - [ ] Different locations across US
  - [ ] Various restriction tags
  - [ ] Sample names (e.g., "Starbucks", "City Hall", etc.)
- [ ] Create method to insert sample pins into database

#### 4.2 Create Repository Interface
- [ ] Create `lib/domain/repositories/pin_repository.dart`
- [ ] Define `PinRepository` abstract class
- [ ] Declare methods:
  - [ ] `Stream<List<Pin>> watchPins()`
  - [ ] `Future<List<Pin>> getPins()`
  - [ ] `Future<Pin?> getPinById(String id)`
  - [ ] `Future<void> addPin(Pin pin)`
  - [ ] `Future<void> updatePin(Pin pin)`
  - [ ] `Future<void> deletePin(String id)`

#### 4.3 Implement Repository (Local Only)
- [ ] Create `lib/data/repositories/pin_repository_impl.dart`
- [ ] Implement `PinRepository` interface
- [ ] Inject `PinDao` dependency
- [ ] Implement `watchPins()`:
  - [ ] Call `pinDao.watchAllPins()`
  - [ ] Map Stream<List<PinEntity>> to Stream<List<Pin>>
  - [ ] Use pin mapper
- [ ] Implement `addPin()`:
  - [ ] Convert Pin to PinEntity
  - [ ] Call `pinDao.insertPin()`
- [ ] Implement other methods similarly
- [ ] Don't worry about sync queue yet (Iteration 10)

#### 4.4 Create MapViewModel
- [ ] Create `lib/presentation/viewmodels/map_viewmodel.dart`
- [ ] Use ChangeNotifier or Riverpod/Provider
- [ ] Inject PinRepository
- [ ] Expose `Stream<List<Pin>>` for UI to listen to
- [ ] Create `loadPins()` method
- [ ] Add sample pins on first launch
- [ ] Handle loading state
- [ ] Handle error state

#### 4.5 Add GeoJSON Layer to Map
- [ ] In MapScreen, listen to pins stream
- [ ] Convert List<Pin> to GeoJSON FeatureCollection
  - [ ] Each pin becomes a Feature
  - [ ] Geometry: Point with [longitude, latitude]
  - [ ] Properties: Include `color_code` (0, 1, 2) based on status
- [ ] Create method `_updatePinLayer(List<Pin> pins)`
- [ ] Add GeoJSON source to map:
  ```dart
  await mapController.addSource(
    'pins-source',
    GeojsonSourceProperties(data: featureCollection)
  );
  ```
- [ ] Add symbol layer for pin markers:
  ```dart
  await mapController.addSymbolLayer(
    'pins-source',
    'pins-layer',
    SymbolLayerProperties(
      iconImage: 'pin-{color_code}',
      iconSize: 1.2,
      iconAllowOverlap: true,
    )
  );
  ```

#### 4.6 Create Pin Marker Icons
- [ ] Create pin icons as images (or use built-in symbols)
  - [ ] Option 1: Use colored circles with `CircleLayerProperties` instead
  - [ ] Option 2: Add custom PNG icons to assets
- [ ] If using CircleLayerProperties:
  ```dart
  await mapController.addCircleLayer(
    'pins-source',
    'pins-layer',
    CircleLayerProperties(
      circleRadius: 8.0,
      circleColor: [
        'match',
        ['get', 'color_code'],
        0, '#4CAF50', // Green
        1, '#FFC107', // Yellow
        2, '#F44336', // Red
        '#999999' // Default gray
      ]
    )
  );
  ```
- [ ] Test different approaches and choose best one

#### 4.7 Update Pin Layer When Data Changes
- [ ] Listen to pins stream in MapScreen
- [ ] Call `_updatePinLayer()` whenever pins change
- [ ] Update GeoJSON source data:
  ```dart
  await mapController.setGeoJsonSource('pins-source', featureCollection);
  ```
- [ ] Verify map updates reactively

#### 4.8 Implement Basic Tap Detection
- [ ] Add `onMapClick` callback to MapLibreMap widget
- [ ] Query features at tap point:
  ```dart
  final features = await mapController.queryRenderedFeatures(
    point: point,
    layerIds: ['pins-layer'],
  );
  ```
- [ ] If feature found, show pin details in console (for now)
- [ ] Log pin ID and name

#### 4.9 Test Pin Display
- [ ] Verify sample pins appear on map
- [ ] Check all three colors display correctly (green, yellow, red)
- [ ] Test tap detection (console logs correct pin)
- [ ] Pan map to different areas
- [ ] Zoom in/out and verify pins scale appropriately
- [ ] Test on both Android and iOS

**Iteration 4 Complete** ✓

---

## Iteration 5: Authentication

**Goal**: User can sign up, sign in, and sign out
**Estimated Time**: 3-4 days
**Deliverable**: Complete authentication system with persistent sessions

### Tasks

#### 5.1 Set Up Supabase Project
- [ ] Go to https://supabase.com/dashboard
- [ ] Create new project: "ccwmap"
- [ ] Choose region (closest to target users)
- [ ] Set strong database password (save securely)
- [ ] Wait for project provisioning (~2 minutes)
- [ ] Navigate to Settings → API
- [ ] Copy Project URL
- [ ] Copy anon public key

#### 5.2 Configure Supabase in Flutter
- [ ] Create `.env` file in project root (add to .gitignore)
- [ ] Add credentials:
  ```
  SUPABASE_URL=https://xxxxx.supabase.co
  SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  ```
- [ ] Add dependencies:
  ```yaml
  dependencies:
    supabase_flutter: ^2.3.0
    flutter_secure_storage: ^9.0.0
    flutter_dotenv: ^5.1.0
  ```
- [ ] Run `flutter pub get`
- [ ] Load .env file in main.dart:
  ```dart
  await dotenv.load(fileName: ".env");
  ```
- [ ] Initialize Supabase:
  ```dart
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  ```

#### 5.3 Configure Supabase Auth Settings
- [ ] In Supabase Dashboard → Authentication → URL Configuration
- [ ] Set Site URL: `https://camiloh12.github.io/ccwmap`
- [ ] Add Redirect URLs:
  - [ ] `com.ccwmap.app://auth/callback`
  - [ ] `https://camiloh12.github.io/ccwmap/auth/callback`
- [ ] Save settings

#### 5.4 Set Up Deep Linking

**Android:**
- [ ] Verify intent filters in AndroidManifest.xml (should be done in Iteration 1)
- [ ] Test deep link with: `adb shell am start -W -a android.intent.action.VIEW -d "com.ccwmap.app://auth/callback"`

**iOS:**
- [ ] Verify URL types in Info.plist (should be done in Iteration 1)
- [ ] Test deep link in simulator

#### 5.5 Create Auth Repository
- [ ] Create `lib/domain/repositories/auth_repository.dart`
- [ ] Define interface:
  - [ ] `Future<User?> getCurrentUser()`
  - [ ] `Stream<User?> authStateChanges()`
  - [ ] `Future<void> signUpWithEmail(String email, String password)`
  - [ ] `Future<void> signInWithEmail(String email, String password)`
  - [ ] `Future<void> signOut()`
  - [ ] `Future<void> handleDeepLink(Uri uri)`

- [ ] Create `lib/data/repositories/supabase_auth_repository.dart`
- [ ] Implement AuthRepository using Supabase client
- [ ] Implement `signUpWithEmail()`:
  - [ ] Call `supabase.auth.signUp(email: email, password: password)`
  - [ ] Handle response
  - [ ] Return user or throw error
- [ ] Implement `signInWithEmail()`:
  - [ ] Call `supabase.auth.signInWithPassword()`
  - [ ] Return user
- [ ] Implement `signOut()`:
  - [ ] Call `supabase.auth.signOut()`
- [ ] Implement `authStateChanges()`:
  - [ ] Return stream from `supabase.auth.onAuthStateChange`
  - [ ] Map to User model
- [ ] Implement `getCurrentUser()`:
  - [ ] Return `supabase.auth.currentUser`
- [ ] Implement `handleDeepLink()`:
  - [ ] Extract tokens from URI fragment
  - [ ] Call `supabase.auth.setSession()` with tokens
- [ ] Add error handling for all methods

#### 5.6 Create LoginScreen UI
- [ ] Create `lib/presentation/screens/login_screen.dart`
- [ ] Create StatefulWidget
- [ ] Add form fields:
  - [ ] Email TextField with email keyboard type
  - [ ] Password TextField with obscureText
  - [ ] Password visibility toggle icon
- [ ] Add validation:
  - [ ] Email format validation
  - [ ] Password minimum 6 characters
- [ ] Add sign up/sign in toggle
  - [ ] Text button: "Need an account? Sign Up" / "Have an account? Sign In"
  - [ ] Toggles between modes
- [ ] Add submit button
  - [ ] Text changes based on mode: "Sign Up" / "Sign In"
  - [ ] Disabled while loading
- [ ] Add loading indicator (circular progress during auth)
- [ ] Style to match Material Design

#### 5.7 Create AuthViewModel
- [ ] Create `lib/presentation/viewmodels/auth_viewmodel.dart`
- [ ] Use ChangeNotifier
- [ ] Inject AuthRepository
- [ ] Expose state:
  - [ ] `bool isLoading`
  - [ ] `String? error`
  - [ ] `String? successMessage`
  - [ ] `User? currentUser`
- [ ] Implement `signUp(email, password)` method
  - [ ] Set isLoading = true
  - [ ] Call repository.signUpWithEmail()
  - [ ] On success: set successMessage
  - [ ] On error: set error message
  - [ ] Set isLoading = false
- [ ] Implement `signIn(email, password)` method
- [ ] Implement `signOut()` method
- [ ] Listen to auth state changes
- [ ] Update currentUser when auth state changes

#### 5.8 Wire Up LoginScreen
- [ ] Connect LoginScreen to AuthViewModel
- [ ] Handle form submission
  - [ ] Validate inputs
  - [ ] Call viewModel.signUp() or signIn()
- [ ] Show loading indicator when isLoading = true
- [ ] Display error in Snackbar when error != null
- [ ] Display success message when successMessage != null
- [ ] Handle sign up success:
  - [ ] Show message: "Please check your email to confirm your account"
  - [ ] Auto-dismiss after 5 seconds

#### 5.9 Add Navigation Based on Auth State
- [ ] In `main.dart`, listen to auth state stream
- [ ] Show LoginScreen when user == null
- [ ] Show MapScreen when user != null
- [ ] Handle deep link when app opened via email confirmation
  - [ ] In main.dart, check for incoming link
  - [ ] Call authRepository.handleDeepLink(uri)
  - [ ] Navigate to MapScreen on success

#### 5.10 Add Sign Out to MapScreen
- [ ] Add sign out button to map screen (top-right icon)
- [ ] Wire up to AuthViewModel.signOut()
- [ ] Show confirmation dialog before sign out
- [ ] Navigate to LoginScreen on sign out

#### 5.11 Test Authentication Flows

**Sign Up Flow:**
- [ ] Open app (shows LoginScreen)
- [ ] Enter email and password
- [ ] Tap "Sign Up"
- [ ] Verify success message appears
- [ ] Check email inbox for confirmation
- [ ] Click confirmation link
- [ ] Verify app opens and shows MapScreen
- [ ] Verify user remains signed in after app restart

**Sign In Flow:**
- [ ] Sign out if signed in
- [ ] Enter email and password
- [ ] Tap "Sign In"
- [ ] Verify MapScreen appears
- [ ] Restart app
- [ ] Verify still signed in

**Sign Out Flow:**
- [ ] From MapScreen, tap sign out icon
- [ ] Confirm sign out
- [ ] Verify navigates to LoginScreen
- [ ] Verify cannot access MapScreen without signing in

**Error Cases:**
- [ ] Test invalid email format
- [ ] Test password too short
- [ ] Test incorrect credentials on sign in
- [ ] Test network error handling

**Deep Linking:**
- [ ] Test email confirmation link on device
- [ ] Test email confirmation link in desktop browser (should show fallback page)

#### 5.12 Test on Both Platforms
- [ ] Test all flows on Android
- [ ] Test all flows on iOS
- [ ] Fix any platform-specific issues

**Iteration 5 Complete** ✓

---

## Iteration 6: Create & Edit Pin Dialogs (UI Only)

**Goal**: Build pin creation/editing UI without actual data persistence
**Estimated Time**: 2-3 days
**Deliverable**: Fully styled, interactive pin dialogs (not saving data yet)

### Tasks

#### 6.1 Create PinDialog Widget
- [ ] Create `lib/presentation/widgets/pin_dialog.dart`
- [ ] Create StatefulWidget
- [ ] Add parameters:
  - [ ] `bool isEditMode`
  - [ ] `String poiName`
  - [ ] `PinStatus? initialStatus`
  - [ ] `RestrictionTag? initialRestrictionTag`
  - [ ] `bool initialHasSecurityScreening`
  - [ ] `bool initialHasPostedSignage`
  - [ ] `VoidCallback onConfirm`
  - [ ] `VoidCallback? onDelete` (optional, only in edit mode)
  - [ ] `VoidCallback onCancel`

#### 6.2 Implement Dialog Layout
- [ ] Use `Dialog` or `showModalBottomSheet`
- [ ] Add rounded corners (28px top for bottom sheet, 24px all for dialog)
- [ ] White/light lavender background
- [ ] Padding: 24px horizontal, 24-32px vertical
- [ ] Title: "Create Pin" or "Edit Pin" (24-28px, bold)
- [ ] POI name display in purple (18-20px, medium weight)

#### 6.3 Build Status Selection Section
- [ ] Add label: "Select carry zone status:" (16px, gray)
- [ ] Create three status option buttons
- [ ] For each status option:
  - [ ] Container with rounded border (8-12px radius)
  - [ ] Height: ~56px
  - [ ] Padding: 12-16px horizontal
  - [ ] Border: 1px light gray (unselected), 2px colored (selected)
  - [ ] Row layout:
    - [ ] Circle icon (20-24px diameter, filled with status color)
    - [ ] Spacing: 16px
    - [ ] Status text ("Allowed", "Uncertain", "No Guns")
  - [ ] Tap to select (update state)
- [ ] Apply colors:
  - [ ] Allowed: Green #4CAF50
  - [ ] Uncertain: Yellow/Orange #FFC107
  - [ ] No Guns: Red #F44336
- [ ] Selected state: thicker border matching status color
- [ ] Spacing between options: 8-12px

#### 6.4 Build Restriction Section (Conditional)
- [ ] Show only when status == NO_GUN
- [ ] Add label: "Why is carry restricted?" (16px, gray)
- [ ] Create dropdown button:
  - [ ] Height: ~56px
  - [ ] Rounded border (8-12px radius)
  - [ ] Light purple/white background
  - [ ] Purple text color
  - [ ] Down arrow icon on right
  - [ ] Show selected RestrictionTag value
- [ ] Populate dropdown with all RestrictionTag values
- [ ] Use displayName for each option
- [ ] Update state on selection

#### 6.5 Build Optional Details Section
- [ ] Add label: "Optional details:" (16px, gray)
- [ ] Create two checkboxes (vertical stack):
  - [ ] "Active security screening"
  - [ ] "Posted signage visible"
- [ ] Checkbox styling:
  - [ ] Size: 24px
  - [ ] Purple when checked (#6200EE)
  - [ ] Light gray border when unchecked
  - [ ] Checkmark icon when checked
  - [ ] Spacing: 16-20px between items
  - [ ] Label 12-16px from checkbox
- [ ] Update state on tap

#### 6.6 Build Delete Button (Edit Mode Only)
- [ ] Show only when `isEditMode == true`
- [ ] Outlined button:
  - [ ] Height: ~48px
  - [ ] Border radius: 24px (pill-shaped)
  - [ ] Border: 1-2px red
  - [ ] Background: white/transparent
  - [ ] Text color: red
- [ ] Add trash icon on left side of text
- [ ] Text: "Delete Pin"
- [ ] Position: Below optional details, above action buttons
- [ ] Tap to call onDelete callback

#### 6.7 Build Action Buttons
- [ ] Horizontal row, right-aligned
- [ ] Spacing: 12-16px between buttons

**Cancel Button:**
- [ ] TextButton (no background)
- [ ] Gray or purple text
- [ ] Text: "Cancel"
- [ ] Tap to call onCancel callback

**Confirm Button (Create/Save):**
- [ ] ElevatedButton
- [ ] Height: ~48px
- [ ] Border radius: 24px (pill-shaped)
- [ ] Background: Purple/indigo (#6200EE)
- [ ] Text: White, medium weight
- [ ] Padding: 24-32px horizontal
- [ ] Text: "Create" (create mode) or "Save" (edit mode)
- [ ] Disabled if validation fails
- [ ] Tap to call onConfirm callback

#### 6.8 Implement Validation
- [ ] If status == NO_GUN and restrictionTag == null:
  - [ ] Disable confirm button
  - [ ] Show error hint (optional)
- [ ] Otherwise: enable confirm button

#### 6.9 Add State Management
- [ ] Create state variables:
  - [ ] `PinStatus selectedStatus`
  - [ ] `RestrictionTag? selectedRestrictionTag`
  - [ ] `bool hasSecurityScreening`
  - [ ] `bool hasPostedSignage`
- [ ] Initialize from parameters
- [ ] Update on user interaction
- [ ] Pass values back via callback (use a result object)

#### 6.10 Test Dialog Interactions
- [ ] Show dialog on button press
- [ ] Test status selection (all three options)
- [ ] Test restriction dropdown (appears/disappears based on status)
- [ ] Test selecting each restriction tag
- [ ] Test checkboxes (toggle on/off)
- [ ] Test validation (confirm button disabled when NO_GUN without tag)
- [ ] Test cancel button (closes dialog)
- [ ] Test confirm button (logs values for now)
- [ ] Test delete button (edit mode only, logs for now)

#### 6.11 Wire Up to MapScreen (Dummy Data)
- [ ] Add tap handler to MapScreen
- [ ] On map tap, show PinDialog with dummy POI name
- [ ] Pass dummy initial values
- [ ] Log confirmed values to console
- [ ] On confirm, close dialog
- [ ] On cancel, close dialog
- [ ] On delete, close dialog and log

#### 6.12 Test on Both Platforms
- [ ] Test all dialog features on Android
- [ ] Test all dialog features on iOS
- [ ] Verify styling matches screenshots
- [ ] Adjust spacing, colors, sizes as needed
- [ ] Test keyboard behavior (dialog should resize)

**Iteration 6 Complete** ✓

---

## Iteration 7: Pin Creation & Editing (Local Only)

**Goal**: Actually create and edit pins, stored locally
**Estimated Time**: 3-4 days
**Deliverable**: Users can create, edit, and delete pins (stored locally only)

### Tasks

#### 7.1 Update MapViewModel for Pin Operations
- [ ] Add method: `createPin(Pin pin)`
  - [ ] Validate pin (location within US, etc.)
  - [ ] Call `repository.addPin(pin)`
  - [ ] Update UI state
- [ ] Add method: `updatePin(Pin pin)`
  - [ ] Call `repository.updatePin(pin)`
- [ ] Add method: `deletePin(String id)`
  - [ ] Call `repository.deletePin(id)`
- [ ] Add state for selected pin (for editing)
- [ ] Add method: `selectPin(Pin pin)`

#### 7.2 Implement US Boundary Validation
- [ ] Create `lib/domain/validators/location_validator.dart`
- [ ] Implement `isWithinUSBounds(double lat, double lng)` function:
  - [ ] Check: 24.396308 <= lat <= 49.384358
  - [ ] Check: -125.0 <= lng <= -66.93457
  - [ ] Return true if both conditions met
- [ ] Write unit tests for boundary validation
  - [ ] Test valid locations (within US)
  - [ ] Test invalid locations (outside US)
  - [ ] Test edge cases (exactly on boundary)

#### 7.3 Implement POI Tap Detection
- [ ] In MapScreen, improve onMapClick handler
- [ ] Query rendered features at tap point:
  ```dart
  final features = await mapController.queryRenderedFeatures(
    point: screenPoint,
    layerIds: ['pins-layer'],  // Existing pins
  );
  ```
- [ ] If existing pin tapped:
  - [ ] Extract pin ID from feature properties
  - [ ] Look up full Pin object from repository
  - [ ] Show edit dialog
- [ ] If no pin tapped:
  - [ ] Assume POI tap (for now, use dummy name)
  - [ ] Validate location is within US bounds
  - [ ] If valid: show create dialog
  - [ ] If invalid: show error snackbar

#### 7.4 Wire Up Create Pin Dialog
- [ ] When create dialog confirmed:
  - [ ] Get selected values from dialog
  - [ ] Create Pin object:
    - [ ] id: Generate UUID (use `uuid` package)
    - [ ] name: POI name from dialog
    - [ ] location: Location from tap coordinates
    - [ ] status: Selected status
    - [ ] restrictionTag: Selected tag (if applicable)
    - [ ] hasSecurityScreening: Checkbox value
    - [ ] hasPostedSignage: Checkbox value
    - [ ] metadata: PinMetadata with current user, current timestamp
- [ ] Call `viewModel.createPin(pin)`
- [ ] Close dialog
- [ ] Show success snackbar (optional)

#### 7.5 Wire Up Edit Pin Dialog
- [ ] When existing pin tapped:
  - [ ] Get pin from repository by ID
  - [ ] Show edit dialog with pre-filled values:
    - [ ] isEditMode: true
    - [ ] poiName: pin.name
    - [ ] initialStatus: pin.status
    - [ ] initialRestrictionTag: pin.restrictionTag
    - [ ] initialHasSecurityScreening: pin.hasSecurityScreening
    - [ ] initialHasPostedSignage: pin.hasPostedSignage
- [ ] When edit dialog confirmed:
  - [ ] Get selected values
  - [ ] Create updated Pin (use pin.copyWith())
  - [ ] Update metadata.lastModified to current timestamp
  - [ ] Call `viewModel.updatePin(pin)`
  - [ ] Close dialog
  - [ ] Show success snackbar (optional)

#### 7.6 Wire Up Delete Pin
- [ ] When delete button tapped in edit dialog:
  - [ ] Show confirmation dialog:
    - [ ] Title: "Delete Pin?"
    - [ ] Message: "Are you sure you want to delete this pin?"
    - [ ] Buttons: "Cancel", "Delete"
  - [ ] If user confirms:
    - [ ] Call `viewModel.deletePin(pin.id)`
    - [ ] Close dialogs
    - [ ] Show snackbar: "Pin deleted"

#### 7.7 Update Repository to Actually Save
- [ ] In `PinRepositoryImpl`, implement full CRUD:
  - [ ] `addPin()`: Convert to entity, insert to database
  - [ ] `updatePin()`: Convert to entity, update in database
  - [ ] `deletePin()`: Delete from database by ID
- [ ] Verify Stream updates automatically (Drift should handle this)

#### 7.8 Test Pin Creation
- [ ] Tap on map at various locations
- [ ] Create pins with different statuses
- [ ] Create NO_GUN pins with various restriction tags
- [ ] Toggle optional details checkboxes
- [ ] Verify pins appear on map immediately
- [ ] Verify pins persist after app restart
- [ ] Test boundary validation:
  - [ ] Try creating pin outside US (should show error)
  - [ ] Create pin just inside US boundary (should work)

#### 7.9 Test Pin Editing
- [ ] Tap on existing pin
- [ ] Verify edit dialog shows correct pre-filled values
- [ ] Change status to different value
- [ ] Save changes
- [ ] Verify pin color updates on map
- [ ] Tap pin again, verify new values persist
- [ ] Change status to NO_GUN
- [ ] Select restriction tag
- [ ] Save
- [ ] Verify updates persist

#### 7.10 Test Pin Deletion
- [ ] Tap on existing pin
- [ ] Tap "Delete Pin"
- [ ] Cancel deletion
- [ ] Verify pin still exists
- [ ] Tap "Delete Pin" again
- [ ] Confirm deletion
- [ ] Verify pin disappears from map
- [ ] Verify pin no longer in database (restart app and check)

#### 7.11 Handle Edge Cases
- [ ] Test creating many pins (50+)
- [ ] Test editing pin immediately after creation
- [ ] Test deleting pin immediately after creation
- [ ] Test tapping between pins (close together)
- [ ] Handle null/empty POI names gracefully
- [ ] Test permission checks (if only creator can delete - implement later)

#### 7.12 Test on Both Platforms
- [ ] Full testing on Android device
- [ ] Full testing on iOS device
- [ ] Fix any platform-specific issues

**Iteration 7 Complete** ✓

---

## Iteration 8: POI Integration

**Goal**: Fetch and display points of interest from OpenStreetMap
**Estimated Time**: 2-3 days
**Deliverable**: Map shows POI labels; tapping POI opens create dialog with name

### Tasks

#### 8.1 Add HTTP Client
- [ ] Add `http: ^1.1.0` to pubspec.yaml
- [ ] Run `flutter pub get`

#### 8.2 Create Overpass API Client
- [ ] Create `lib/data/datasources/overpass_api_client.dart`
- [ ] Define Overpass API URL: `https://overpass-api.de/api/interpreter`
- [ ] Implement `fetchPOIs(LatLngBounds bounds)` method
  - [ ] Build Overpass QL query:
    ```
    [out:json][timeout:25];
    (
      node["amenity"](south,west,north,east);
      node["tourism"](south,west,north,east);
      node["leisure"](south,west,north,east);
      way["amenity"](south,west,north,east);
      way["tourism"](south,west,north,east);
    );
    out center;
    ```
  - [ ] Replace (south,west,north,east) with actual bounds
  - [ ] Make POST request to Overpass API
  - [ ] Parse JSON response
  - [ ] Extract elements array
  - [ ] Convert to List<Poi> model
- [ ] Add error handling:
  - [ ] Handle network errors
  - [ ] Handle rate limiting (429 status)
  - [ ] Handle malformed responses
- [ ] Add timeout: 25 seconds

#### 8.3 Create Poi Model
- [ ] Create `lib/domain/models/poi.dart`
- [ ] Define Poi class:
  - [ ] `String id` (OSM ID)
  - [ ] `String name`
  - [ ] `double latitude`
  - [ ] `double longitude`
  - [ ] `String type` (e.g., "restaurant", "school")
  - [ ] `Map<String, String>? tags` (optional OSM tags)
- [ ] Add JSON deserialization from Overpass response
- [ ] Handle missing names (use type or "Unknown")
- [ ] Handle center coordinates for ways

#### 8.4 Implement POI Caching
- [ ] Create `lib/data/datasources/poi_cache.dart`
- [ ] Use in-memory cache (Map<String, CachedPOIs>)
- [ ] Cache key: Rounded bounds (2 decimal places precision)
- [ ] Cache value:
  - [ ] List<Poi> pois
  - [ ] DateTime cachedAt
- [ ] Implement cache methods:
  - [ ] `List<Poi>? getCached(LatLngBounds bounds)`
    - [ ] Check if key exists
    - [ ] Check if cache is still valid (< 30 minutes old)
    - [ ] Return cached POIs or null
  - [ ] `void cache(LatLngBounds bounds, List<Poi> pois)`
    - [ ] Store pois with current timestamp
  - [ ] `void clearOld()`
    - [ ] Remove entries older than 30 minutes
    - [ ] Keep only 20 most recent entries (LRU)

#### 8.5 Create POI Repository
- [ ] Create `lib/domain/repositories/poi_repository.dart`
- [ ] Define interface:
  - [ ] `Future<List<Poi>> getPOIs(LatLngBounds bounds)`

- [ ] Create `lib/data/repositories/poi_repository_impl.dart`
- [ ] Implement repository:
  - [ ] Inject OverpassApiClient and PoiCache
  - [ ] In `getPOIs()`:
    - [ ] Check cache first
    - [ ] If cached and valid: return cached
    - [ ] If not cached: fetch from API
    - [ ] Cache results
    - [ ] Return POIs
  - [ ] On API error: return cached data (even if stale) or empty list
  - [ ] Log errors but don't crash

#### 8.6 Integrate POI Fetching in MapScreen
- [ ] Add debounced camera change listener
  - [ ] Use timer to debounce (500ms)
  - [ ] On camera idle, fetch POIs for current viewport
- [ ] Create method `_fetchPOIsForViewport()`
  - [ ] Get current visible bounds from map controller
  - [ ] Call `poiRepository.getPOIs(bounds)`
  - [ ] Update state with POIs
- [ ] Handle loading state (optional: show progress indicator)

#### 8.7 Display POI Labels on Map
- [ ] Convert POIs to GeoJSON features
- [ ] Add POI GeoJSON source:
  ```dart
  await mapController.addSource(
    'pois-source',
    GeojsonSourceProperties(data: poiFeatureCollection)
  );
  ```
- [ ] Add symbol layer for POI labels:
  ```dart
  await mapController.addSymbolLayer(
    'pois-source',
    'pois-layer',
    SymbolLayerProperties(
      textField: ['get', 'name'],
      textSize: 12.0,
      textColor: '#333333',
      textHaloColor: '#FFFFFF',
      textHaloWidth: 2.0,
      textOffset: [0, 1.5],
    )
  );
  ```
- [ ] Update POI layer when POIs change

#### 8.8 Implement POI Tap Detection
- [ ] Update onMapClick handler
- [ ] Query both pins and POIs:
  ```dart
  final poiFeatures = await mapController.queryRenderedFeatures(
    point: screenPoint,
    layerIds: ['pois-layer'],
  );
  ```
- [ ] Check pin features first (priority)
- [ ] If no pin, check POI features
- [ ] If POI found:
  - [ ] Extract POI name from feature properties
  - [ ] Extract coordinates
  - [ ] Validate location is within US
  - [ ] Show create pin dialog with POI name pre-filled

#### 8.9 Test POI Features
- [ ] Pan map to different areas
- [ ] Verify POIs load after 500ms debounce
- [ ] Check console for Overpass API calls (should be throttled)
- [ ] Verify POI labels appear on map
- [ ] Tap on POI label
- [ ] Verify create dialog opens with POI name
- [ ] Create pin from POI
- [ ] Verify pin appears at POI location with POI name

#### 8.10 Test POI Caching
- [ ] Pan to area A, wait for POIs to load
- [ ] Pan to area B
- [ ] Pan back to area A
- [ ] Verify POIs load instantly (from cache, no API call)
- [ ] Wait 30+ minutes (or manually clear cache)
- [ ] Pan to area A again
- [ ] Verify POIs reload from API (cache expired)

#### 8.11 Test Edge Cases
- [ ] Test areas with many POIs (city centers)
- [ ] Test areas with no POIs (rural areas)
- [ ] Test API rate limiting (rapid panning)
  - [ ] Verify fallback to cached data
  - [ ] Verify no crashes
- [ ] Test network offline
  - [ ] Verify returns cached data
  - [ ] Verify graceful failure when no cache
- [ ] Test POIs with missing names
  - [ ] Verify fallback to type or "Unknown"

#### 8.12 Optimize Performance
- [ ] Limit POI fetching to reasonable zoom levels (e.g., zoom >= 12)
- [ ] Consider reducing POI query complexity if too slow
- [ ] Add loading indicator for POI fetching (optional)

#### 8.13 Test on Both Platforms
- [ ] Full testing on Android
- [ ] Full testing on iOS
- [ ] Fix platform-specific issues

**Iteration 8 Complete** ✓

---

## Iteration 9: Remote Database & Basic Sync

**Goal**: Pins sync to and from Supabase
**Estimated Time**: 3-4 days
**Deliverable**: Pins sync between local database and Supabase

### Tasks

#### 9.1 Run Database Migrations on Supabase
- [ ] In Supabase Dashboard → SQL Editor
- [ ] Create and run migration: `001_initial_schema.sql`
  - [ ] Create `pins` table with all columns
  - [ ] Add indexes
  - [ ] Enable PostGIS extension
  - [ ] Create `location` geography column
  - [ ] Add CHECK constraint for status values
  - [ ] Add trigger to auto-update `last_modified`
- [ ] Create and run migration: `002_add_poi_name_to_pins.sql` (if needed)
- [ ] Create and run migration: `003_add_restriction_tags.sql`
  - [ ] Create `restriction_tag_type` enum
  - [ ] Add restriction tag column
  - [ ] Add enforcement detail columns
  - [ ] Add constraint: NO_GUN pins require restriction tag
- [ ] Verify tables created successfully in Dashboard → Table Editor

#### 9.2 Configure Row Level Security (RLS)
- [ ] In Table Editor → pins table → Settings
- [ ] Enable RLS
- [ ] Create policies:

**SELECT Policy** (anyone can read):
```sql
CREATE POLICY "Pins are viewable by everyone"
  ON pins FOR SELECT
  USING (true);
```

**INSERT Policy** (authenticated users, must match their user ID):
```sql
CREATE POLICY "Authenticated users can insert pins"
  ON pins FOR INSERT
  WITH CHECK (auth.uid() = created_by);
```

**UPDATE Policy** (authenticated users can update any pin):
```sql
CREATE POLICY "Users can update any pin"
  ON pins FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');
```

**DELETE Policy** (users can only delete their own pins):
```sql
CREATE POLICY "Users can delete own pins"
  ON pins FOR DELETE
  USING (auth.uid() = created_by);
```

- [ ] Test policies using SQL Editor or API

#### 9.3 Create Supabase Data Models
- [ ] Create `lib/data/models/supabase_pin_dto.dart`
- [ ] Define DTO (Data Transfer Object) class matching Supabase schema
  - [ ] All fields matching database columns
  - [ ] JSON serialization (toJson, fromJson)
  - [ ] Handle enum conversions (string <-> enum)
  - [ ] Handle DateTime <-> String conversions
- [ ] Create mapper: DTO ↔ Domain Pin model

#### 9.4 Create Supabase Data Source
- [ ] Create `lib/data/datasources/supabase_remote_data_source.dart`
- [ ] Inject Supabase client
- [ ] Implement methods:
  - [ ] `Future<List<SupabasePinDto>> getAllPins()`
    - [ ] Query: `supabase.from('pins').select()`
    - [ ] Return list of DTOs
  - [ ] `Future<void> insertPin(SupabasePinDto pin)`
    - [ ] Insert: `supabase.from('pins').insert(pin.toJson())`
  - [ ] `Future<void> updatePin(SupabasePinDto pin)`
    - [ ] Update: `supabase.from('pins').update(pin.toJson()).eq('id', pin.id)`
  - [ ] `Future<void> deletePin(String id)`
    - [ ] Delete: `supabase.from('pins').delete().eq('id', id)`
- [ ] Add error handling for each method
- [ ] Log API calls for debugging

#### 9.5 Update PinRepository for Sync

**Add Remote Sync Methods:**
- [ ] In PinRepositoryImpl, inject SupabaseRemoteDataSource
- [ ] Create `Future<void> syncWithRemote()` method:
  - [ ] Upload local changes (to be implemented in Iteration 10)
  - [ ] Download remote changes
  - [ ] Merge with local database
- [ ] Create `Future<void> downloadRemotePins()` method:
  - [ ] Fetch all pins from Supabase
  - [ ] For each remote pin:
    - [ ] Check if exists locally (by ID)
    - [ ] If not exists: insert to local DB
    - [ ] If exists: compare `last_modified` timestamps
      - [ ] If remote newer: update local
      - [ ] If local newer: skip (will upload later)
      - [ ] If same: skip
- [ ] Create `Future<void> uploadLocalPins()` method (for now, upload all):
  - [ ] Get all pins from local database
  - [ ] For each local pin:
    - [ ] Check if exists on remote (query by ID)
    - [ ] If not exists: insert to remote
    - [ ] If exists: compare timestamps
      - [ ] If local newer: update remote
      - [ ] If remote newer: skip (already downloaded)

#### 9.6 Implement Conflict Resolution
- [ ] Create `Pin _mergeRemotePin(Pin remotePin)` method:
  ```dart
  Future<Pin> _mergeRemotePin(Pin remotePin) async {
    final localPin = await pinDao.getPinById(remotePin.id);

    if (localPin == null) {
      await pinDao.insertPin(remotePin.toEntity());
      return remotePin;
    }

    if (remotePin.metadata.lastModified > localPin.metadata.lastModified) {
      await pinDao.updatePin(remotePin.toEntity());
      return remotePin;
    }

    return localPin.toDomain(); // Keep local
  }
  ```
- [ ] Use this method when downloading remote pins
- [ ] Log conflicts for debugging

#### 9.7 Add Sync Trigger on App Launch
- [ ] In main.dart or MapViewModel, trigger sync on app start
- [ ] Call `pinRepository.syncWithRemote()`
- [ ] Handle sync errors gracefully (don't block UI)
- [ ] Show loading indicator during initial sync (optional)
- [ ] Log sync results (uploaded X, downloaded Y)

#### 9.8 Test Basic Sync

**Device A:**
- [ ] Create 3 pins with different statuses
- [ ] Verify pins appear on map
- [ ] Check Supabase dashboard → Table Editor → pins
- [ ] Verify 3 pins uploaded to Supabase

**Device B (or clear app data):**
- [ ] Sign in with same account
- [ ] Wait for sync to complete
- [ ] Verify 3 pins downloaded and appear on map

**Edit on Device A:**
- [ ] Edit one pin (change status)
- [ ] Trigger sync (restart app or manual sync)
- [ ] Check Supabase → verify update

**View on Device B:**
- [ ] Trigger sync
- [ ] Verify pin status updated

**Delete on Device A:**
- [ ] Delete one pin
- [ ] Trigger sync
- [ ] Verify deleted from Supabase

**View on Device B:**
- [ ] Trigger sync
- [ ] Verify pin removed from map

#### 9.9 Test Conflict Resolution

**Simultaneous Edits:**
- [ ] On Device A: Edit pin X at time T
- [ ] On Device B: Edit pin X at time T+1 (later)
- [ ] On Device A: Sync (uploads changes)
- [ ] On Device B: Sync (should receive Device A's changes, then upload newer version)
- [ ] On Device A: Sync again
- [ ] Verify Device B's newer changes are on both devices (last-write-wins)

**Create with Same ID (edge case):**
- [ ] This shouldn't happen with UUIDs, but handle gracefully
- [ ] Test by manually creating pin with same ID on both devices
- [ ] Verify conflict resolved (last-write-wins based on timestamp)

#### 9.10 Handle Sync Errors
- [ ] Test sync with no network connection
  - [ ] Should fail gracefully
  - [ ] Should not crash app
  - [ ] Should log error
- [ ] Test sync with Supabase down
  - [ ] Should timeout gracefully
  - [ ] Should retry later (Iteration 10)
- [ ] Test authentication expired during sync
  - [ ] Should redirect to login
  - [ ] Should preserve local data

#### 9.11 Add Sync Status Indicator (Optional)
- [ ] Show sync status in UI (syncing, success, error)
- [ ] Small indicator in map screen
- [ ] Snackbar on sync completion

#### 9.12 Test on Both Platforms
- [ ] Full testing on Android
- [ ] Full testing on iOS
- [ ] Test cross-platform sync (Android <-> iOS)

**Iteration 9 Complete** ✓

---

## Iteration 10: Offline-First Sync Queue

**Goal**: Reliable sync that works offline
**Estimated Time**: 4-5 days
**Deliverable**: Robust offline-first sync with queue and retry logic

### Tasks

#### 10.1 Create SyncOperation Model
- [ ] Create `lib/domain/models/sync_operation.dart`
- [ ] Define enum `SyncOperationType`: CREATE, UPDATE, DELETE
- [ ] Create SyncOperation class:
  - [ ] `String id` (UUID)
  - [ ] `String pinId`
  - [ ] `SyncOperationType operationType`
  - [ ] `DateTime timestamp`
  - [ ] `int retryCount`
  - [ ] `String? lastError`

#### 10.2 Update Sync Queue DAO
- [ ] Review SyncQueueDao created in Iteration 3
- [ ] Ensure methods exist:
  - [ ] `enqueue(SyncQueueEntity)`
  - [ ] `dequeue(String id)`
  - [ ] `getPendingOperations()`
  - [ ] `incrementRetryCount(String id, String error)`
  - [ ] `clearCompleted()`

#### 10.3 Update PinRepository for Queueing

**Modify addPin():**
- [ ] Insert pin to local database (immediate)
- [ ] Queue CREATE operation:
  ```dart
  await syncQueueDao.enqueue(SyncQueueEntity(
    id: generateUuid(),
    pinId: pin.id,
    operationType: 'CREATE',
    timestamp: DateTime.now().millisecondsSinceEpoch,
    retryCount: 0,
  ));
  ```

**Modify updatePin():**
- [ ] Update pin in local database (immediate)
- [ ] Delete any existing queue operations for this pin
- [ ] Queue UPDATE operation

**Modify deletePin():**
- [ ] Delete pin from local database (immediate)
- [ ] Delete any existing queue operations for this pin
- [ ] Queue DELETE operation

- [ ] Verify Stream<List<Pin>> still emits correctly after changes

#### 10.4 Create Network Monitor
- [ ] Add `connectivity_plus: ^5.0.0` to pubspec.yaml
- [ ] Run `flutter pub get`
- [ ] Create `lib/data/services/network_monitor.dart`
- [ ] Implement NetworkMonitor class:
  - [ ] `Stream<bool> get isOnline`
  - [ ] Listen to Connectivity().onConnectivityChanged
  - [ ] Convert ConnectivityResult to bool (true if not none)
  - [ ] Use distinct() to avoid duplicate events
- [ ] Test network monitor (airplane mode on/off)

#### 10.5 Create SyncManager
- [ ] Create `lib/data/sync/sync_manager.dart`
- [ ] Inject dependencies:
  - [ ] SyncQueueDao
  - [ ] PinDao
  - [ ] SupabaseRemoteDataSource
  - [ ] NetworkMonitor
- [ ] Create `Future<SyncResult> sync()` method:
  - [ ] Check if online (return early if offline)
  - [ ] Get pending operations from queue
  - [ ] Process each operation:
    - [ ] Get pin from local DB (if needed)
    - [ ] Convert to DTO
    - [ ] Upload to Supabase based on operation type
    - [ ] On success: dequeue operation
    - [ ] On error: increment retry count, log error
    - [ ] If retry count > 3: dequeue and log failure
  - [ ] After upload, download remote changes
  - [ ] Merge with local database (conflict resolution)
  - [ ] Return SyncResult (uploaded count, downloaded count, errors)

#### 10.6 Implement Retry Logic

**Exponential Backoff:**
- [ ] Create retry delay calculation:
  ```dart
  Duration getRetryDelay(int retryCount) {
    if (retryCount == 0) return Duration.zero;
    if (retryCount == 1) return Duration(seconds: 2);
    if (retryCount == 2) return Duration(seconds: 4);
    return Duration(seconds: 8);
  }
  ```
- [ ] In sync(), check retry count before processing
- [ ] If retry count > 0, check if enough time has passed since last attempt
- [ ] Skip operation if retry delay not yet elapsed

**Max Retries:**
- [ ] Define MAX_RETRIES = 3
- [ ] After 3 failed attempts, remove from queue
- [ ] Log permanently failed operations
- [ ] Consider notifying user (optional)

#### 10.7 Handle Operation Types

**CREATE:**
- [ ] Get pin from local DB by pinId
- [ ] Convert to DTO
- [ ] Call `remoteDataSource.insertPin(dto)`
- [ ] On success: dequeue
- [ ] On error (e.g., already exists): dequeue anyway (idempotent)

**UPDATE:**
- [ ] Get pin from local DB
- [ ] Convert to DTO
- [ ] Call `remoteDataSource.updatePin(dto)`
- [ ] On success: dequeue
- [ ] On error (e.g., not found): dequeue anyway

**DELETE:**
- [ ] Call `remoteDataSource.deletePin(pinId)`
- [ ] On success: dequeue
- [ ] On error (e.g., not found): dequeue anyway

#### 10.8 Trigger Sync on Network Reconnection
- [ ] In app startup (main.dart or MapViewModel):
  - [ ] Listen to NetworkMonitor.isOnline stream
  - [ ] When transitions from offline → online:
    - [ ] Trigger SyncManager.sync()
  - [ ] Debounce to avoid multiple rapid syncs

#### 10.9 Trigger Sync on App Launch
- [ ] In MapViewModel or repository initialization:
  - [ ] Check if online
  - [ ] If online: trigger sync immediately
  - [ ] If offline: wait for network reconnection

#### 10.10 Test Offline Pin Creation
- [ ] Turn on airplane mode
- [ ] Create 3 pins
- [ ] Verify pins appear on map (from local DB)
- [ ] Check sync queue (should have 3 CREATE operations)
- [ ] Turn off airplane mode
- [ ] Wait for auto-sync
- [ ] Verify pins uploaded to Supabase
- [ ] Verify queue emptied

#### 10.11 Test Offline Pin Editing
- [ ] Create pin while online (synced)
- [ ] Turn on airplane mode
- [ ] Edit pin (change status)
- [ ] Verify change appears on map
- [ ] Check sync queue (should have UPDATE operation)
- [ ] Turn off airplane mode
- [ ] Verify update synced
- [ ] Verify queue emptied

#### 10.12 Test Offline Pin Deletion
- [ ] Create pin while online
- [ ] Turn on airplane mode
- [ ] Delete pin
- [ ] Verify pin removed from map
- [ ] Check sync queue (should have DELETE operation)
- [ ] Turn off airplane mode
- [ ] Verify deletion synced to Supabase
- [ ] Verify queue emptied

#### 10.13 Test Conflict Resolution in Offline Mode

**Scenario: Edit same pin offline on two devices**
- [ ] Device A: Edit pin X, change status to NO_GUN (offline)
- [ ] Device B: Edit pin X, change status to ALLOWED (offline)
- [ ] Device A: Come online, sync
  - [ ] Should upload Device A's changes
- [ ] Device B: Come online, sync
  - [ ] Should download Device A's changes first
  - [ ] Compare timestamps
  - [ ] Upload Device B's changes if newer
  - [ ] Or keep Device A's changes if newer
- [ ] Verify last-write-wins based on timestamp

#### 10.14 Test Retry Logic
- [ ] Simulate network error during sync:
  - [ ] Turn off WiFi mid-sync
  - [ ] Or use mocking to force API error
- [ ] Verify operation remains in queue
- [ ] Verify retry count incremented
- [ ] Wait for retry delay
- [ ] Restore network
- [ ] Verify operation retried and succeeds

#### 10.15 Test Max Retries
- [ ] Create pin
- [ ] Force sync to fail 3 times (mock API errors)
- [ ] Verify operation retried 3 times
- [ ] Verify operation removed from queue after 3 failures
- [ ] Verify error logged
- [ ] Verify app doesn't crash

#### 10.16 Test Queue Ordering
- [ ] Create pin A (offline)
- [ ] Edit pin A (offline)
- [ ] Delete pin A (offline)
- [ ] Come online, sync
- [ ] Verify operations processed in order:
  - [ ] CREATE, then UPDATE, then DELETE
  - [ ] Or: Optimize to skip CREATE and UPDATE, just DELETE

#### 10.17 Optimize Queue Processing
- [ ] Implement queue optimization:
  - [ ] If DELETE operation exists for a pin:
    - [ ] Remove any earlier CREATE or UPDATE operations for same pin
  - [ ] If UPDATE operation exists:
    - [ ] Remove any earlier UPDATE operations for same pin (keep latest)
- [ ] Test optimization reduces unnecessary API calls

#### 10.18 Add Sync Progress Indicator
- [ ] Show sync status in UI:
  - [ ] "Syncing..." with progress (X of Y operations)
  - [ ] "Sync complete" on success
  - [ ] "Sync failed, will retry" on error
- [ ] Use Snackbar or inline indicator
- [ ] Test user experience

#### 10.19 Handle Edge Cases
- [ ] Test sync with 100+ queued operations
- [ ] Test sync with slow network (high latency)
- [ ] Test sync interrupted mid-way (app closed)
  - [ ] Should resume on next launch
- [ ] Test authentication expired during sync
  - [ ] Should redirect to login
  - [ ] Should preserve queue for later

#### 10.20 Test on Both Platforms
- [ ] Full offline testing on Android
- [ ] Full offline testing on iOS
- [ ] Test cross-platform offline sync

**Iteration 10 Complete** ✓

---

## Iteration 11: Background Sync

**Goal**: Automatic periodic syncing in background
**Estimated Time**: 2-3 days
**Deliverable**: App syncs automatically in background

### Tasks

#### 11.1 Add WorkManager Package
- [ ] Add `workmanager: ^0.5.0` to pubspec.yaml
- [ ] Run `flutter pub get`

#### 11.2 Configure WorkManager for Android
- [ ] In `android/app/src/main/AndroidManifest.xml`:
  - [ ] Verify WAKE_LOCK permission (may be needed)
- [ ] WorkManager should work out-of-box on Android

#### 11.3 Configure WorkManager for iOS
- [ ] In `ios/Runner/AppDelegate.swift`:
  - [ ] Import WorkManager
  - [ ] Enable background fetch
- [ ] Configure background modes in Xcode:
  - [ ] Enable "Background fetch"
  - [ ] Enable "Background processing"
- [ ] Set minimum background fetch interval

#### 11.4 Initialize WorkManager
- [ ] In `main.dart`, initialize WorkManager:
  ```dart
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: kDebugMode,
  );
  ```
- [ ] Create top-level callback dispatcher:
  ```dart
  @pragma('vm:entry-point')
  void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      // Background sync logic
      return Future.value(true);
    });
  }
  ```

#### 11.5 Register Periodic Sync Task
- [ ] After WorkManager initialization:
  ```dart
  await Workmanager().registerPeriodicTask(
    'sync-pins',
    'syncPinsTask',
    frequency: Duration(minutes: 15),
    initialDelay: Duration(minutes: 1),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
  );
  ```
- [ ] Task runs every 15 minutes when connected to network

#### 11.6 Implement Background Sync Logic
- [ ] In callback dispatcher:
  - [ ] Initialize dependencies (database, Supabase, etc.)
  - [ ] Create SyncManager instance
  - [ ] Call `await syncManager.sync()`
  - [ ] Log result
  - [ ] Return true on success, false on failure
- [ ] Handle errors gracefully
- [ ] Ensure task completes within time limit (iOS: 30s)

#### 11.7 Handle Dependency Injection in Background
- [ ] Background tasks run in separate isolate
- [ ] Cannot access singleton instances from main isolate
- [ ] Reinitialize required services:
  - [ ] AppDatabase
  - [ ] Supabase client
  - [ ] SyncManager
  - [ ] Repositories, DAOs
- [ ] Test that background task can access database

#### 11.8 Add Sync Status Tracking
- [ ] Store last sync time in shared preferences
- [ ] Update on each successful sync
- [ ] Display in UI (optional):
  - [ ] "Last synced: 5 minutes ago"
  - [ ] Refresh indicator

#### 11.9 Test Background Sync on Android
- [ ] Install app on Android device
- [ ] Let app run in background (close but don't force stop)
- [ ] Create pin on another device
- [ ] Wait 15+ minutes
- [ ] Open app on first device
- [ ] Verify new pin appears (synced in background)
- [ ] Check logs for background task execution

#### 11.10 Test Background Sync on iOS
- [ ] Install app on iOS device
- [ ] Enable background app refresh in Settings
- [ ] Let app run in background
- [ ] Create pin on another device
- [ ] Wait for background fetch (may take longer than 15 min on iOS)
- [ ] Open app
- [ ] Verify new pin appears
- [ ] Note: iOS background fetch is opportunistic, not guaranteed

#### 11.11 Test Battery Constraints
- [ ] On Android, set battery to low
- [ ] Verify background sync pauses
- [ ] Charge battery
- [ ] Verify background sync resumes

#### 11.12 Test Network Constraints
- [ ] Turn off network
- [ ] Verify background sync doesn't run
- [ ] Turn on network
- [ ] Verify background sync runs

#### 11.13 Add Manual Sync Trigger (Optional)
- [ ] Add pull-to-refresh on map screen
- [ ] Trigger manual sync
- [ ] Show loading indicator
- [ ] Show result (success/failure)
- [ ] Update last sync time

#### 11.14 Handle Sync Conflicts
- [ ] Test scenario:
  - [ ] Device A offline, creates pin
  - [ ] Device B online, creates different pin
  - [ ] Device B's pin syncs in background
  - [ ] Device A comes online
  - [ ] Both pins should exist (no conflict)
- [ ] Test edit conflicts handled by last-write-wins

#### 11.15 Optimize Background Sync
- [ ] Limit sync to when necessary (check queue first)
- [ ] If queue is empty and last download was recent, skip
- [ ] Add incremental sync (download only new/updated pins)
  - [ ] Track last sync timestamp
  - [ ] Query: `pins.select().gte('last_modified', lastSyncTime)`
- [ ] Reduce battery and data usage

#### 11.16 Test on Both Platforms
- [ ] Full background sync testing on Android
- [ ] Full background sync testing on iOS
- [ ] Test app in background for extended period (hours)
- [ ] Verify periodic sync continues

#### 11.17 Handle App Updates
- [ ] Test background sync persists after app update
- [ ] Verify WorkManager tasks re-registered on upgrade

**Iteration 11 Complete** ✓

---

## Iteration 12: Polish & Testing

**Goal**: Production-ready app with comprehensive tests
**Estimated Time**: 5-7 days
**Deliverable**: Polished, well-tested app

### Tasks

#### 12.1 UI Polish - MapScreen
- [ ] Fine-tune title overlay positioning and padding
- [ ] Adjust sign out icon size and color
- [ ] Perfect FAB styling (match screenshots exactly)
  - [ ] Background color: #E8DEF8
  - [ ] Icon color and size
  - [ ] Shadow/elevation
- [ ] Verify MapLibre attribution positioning
- [ ] Add smooth camera animations
- [ ] Test on various screen sizes (small phones, tablets)
- [ ] Ensure UI doesn't overlap map controls

#### 12.2 UI Polish - PinDialog
- [ ] Match dialog styling to screenshots pixel-perfect:
  - [ ] Border radius: 24-28px
  - [ ] Padding: 24px
  - [ ] POI name color: #6200EE
  - [ ] Status button heights: 56px
  - [ ] Button border radius: 8-12px
  - [ ] Selected border width: 2px
- [ ] Verify colors match:
  - [ ] Green: #4CAF50
  - [ ] Yellow: #FFC107
  - [ ] Red: #F44336
  - [ ] Purple: #6200EE
- [ ] Test restriction dropdown styling
- [ ] Test checkbox styling (purple when checked)
- [ ] Test delete button styling (red border, pill shape)
- [ ] Test action buttons (purple filled, text-only cancel)
- [ ] Ensure spacing matches (8-12px between elements)

#### 12.3 Add Loading States
- [ ] Add loading indicator for initial map load
- [ ] Add shimmer or skeleton for pin loading
- [ ] Add progress indicator during sync
  - [ ] Show "Syncing X of Y pins..."
- [ ] Add loading state for POI fetching (subtle)
- [ ] Disable interactions during operations
- [ ] Test all loading states

#### 12.4 Add Error Handling & Messages
- [ ] Create user-friendly error messages
- [ ] Location permission denied:
  - [ ] Show dialog explaining need
  - [ ] Offer to open settings
- [ ] Network error:
  - [ ] Show Snackbar: "No connection, changes will sync later"
- [ ] Sync error:
  - [ ] Show: "Sync failed, will retry automatically"
- [ ] Invalid location (outside US):
  - [ ] Show: "Pins can only be created within the US"
- [ ] Authentication error:
  - [ ] Redirect to login
  - [ ] Show: "Session expired, please sign in again"
- [ ] Generic error:
  - [ ] Show: "Something went wrong, please try again"
- [ ] Test all error scenarios

#### 12.5 Add Success Feedback
- [ ] Pin created: Snackbar "Pin created"
- [ ] Pin updated: Snackbar "Pin updated"
- [ ] Pin deleted: Snackbar "Pin deleted"
- [ ] Sync completed: Snackbar "Sync complete" (optional)
- [ ] Use green color for success messages
- [ ] Auto-dismiss after 3 seconds

#### 12.6 Implement Smooth Animations
- [ ] Map camera animations (when re-centering)
- [ ] Dialog slide-in animation (bottom to top)
- [ ] Fade-in for POI labels
- [ ] Ripple effect on buttons
- [ ] Smooth pin addition/removal from map
- [ ] Page transitions (login → map)
- [ ] Test animations on both platforms
- [ ] Ensure animations are not too slow or fast

#### 12.7 Add Haptic Feedback (Optional)
- [ ] Vibrate on pin created
- [ ] Light haptic on button press
- [ ] Use `HapticFeedback.lightImpact()`
- [ ] Make optional (user can disable)

#### 12.8 Test on Various Screen Sizes

**Android:**
- [ ] Small phone (4.5")
- [ ] Medium phone (6")
- [ ] Large phone (6.7")
- [ ] Tablet (10")
- [ ] Foldable device

**iOS:**
- [ ] iPhone SE (small)
- [ ] iPhone 14 (medium)
- [ ] iPhone 14 Pro Max (large)
- [ ] iPad (tablet)

- [ ] Verify all UI elements visible and accessible
- [ ] Adjust layout if needed for edge cases

#### 12.9 Accessibility Improvements
- [ ] Add semantic labels to all interactive elements
- [ ] Ensure sufficient color contrast (WCAG AA)
- [ ] Add screen reader support:
  - [ ] Map: "Interactive map showing CCW zones"
  - [ ] Pins: "Pin at [location], status: [allowed/uncertain/no guns]"
  - [ ] Buttons: Clear descriptions
- [ ] Test with TalkBack (Android) and VoiceOver (iOS)
- [ ] Ensure keyboard navigation works (for external keyboards)
- [ ] Add focus indicators

#### 12.10 Performance Optimization
- [ ] Profile app with DevTools
- [ ] Optimize pin rendering (use CircleLayer instead of SymbolLayer if faster)
- [ ] Lazy load POIs (only fetch when zoomed in enough)
- [ ] Optimize database queries (add indexes if needed)
- [ ] Reduce widget rebuilds (use const constructors)
- [ ] Optimize map layer updates (only update when data changes)
- [ ] Test with 1000+ pins on map
- [ ] Ensure smooth 60 FPS on map interactions

#### 12.11 Write Unit Tests

**Domain Models:**
- [ ] Test Pin.withNextStatus() cycles correctly
- [ ] Test Pin validation (NO_GUN requires restrictionTag)
- [ ] Test Location validation (lat/lng bounds)
- [ ] Test PinStatus.fromColorCode() conversion
- [ ] Test RestrictionTag.fromString() conversion
- [ ] Test PinMetadata creation and updates
- [ ] Aim for 100% coverage on domain models

**Mappers:**
- [ ] Test PinEntity ↔ Pin conversion
- [ ] Test SupabasePinDto ↔ Pin conversion
- [ ] Test round-trip conversions (no data loss)
- [ ] Test null handling
- [ ] Test enum conversions
- [ ] Test DateTime conversions
- [ ] Aim for 100% coverage on mappers

**Validators:**
- [ ] Test US boundary validation with various coordinates
- [ ] Test edge cases (exactly on boundary)

#### 12.12 Write Repository Tests

**PinRepository:**
- [ ] Test addPin() saves to local DB
- [ ] Test updatePin() updates local DB
- [ ] Test deletePin() removes from local DB
- [ ] Test watchPins() emits Stream correctly
- [ ] Test sync queue operations enqueued
- [ ] Use mock DAOs
- [ ] Test error handling

**AuthRepository:**
- [ ] Test signUp() calls Supabase correctly
- [ ] Test signIn() calls Supabase correctly
- [ ] Test signOut() clears session
- [ ] Test authStateChanges() stream
- [ ] Test error handling (invalid credentials, network errors)
- [ ] Use mock Supabase client

**SyncManager:**
- [ ] Test sync() uploads queued operations
- [ ] Test sync() downloads remote changes
- [ ] Test conflict resolution (last-write-wins)
- [ ] Test retry logic (increments retry count)
- [ ] Test max retries (removes after 3 failures)
- [ ] Use mocks for all dependencies

#### 12.13 Write ViewModel Tests

**MapViewModel:**
- [ ] Test loadPins() populates state
- [ ] Test createPin() validates and saves
- [ ] Test updatePin() saves changes
- [ ] Test deletePin() removes pin
- [ ] Test selectPin() updates selection
- [ ] Test error handling
- [ ] Test loading states
- [ ] Use fake repositories

**AuthViewModel:**
- [ ] Test signUp() updates state correctly
- [ ] Test signIn() updates state correctly
- [ ] Test signOut() clears user
- [ ] Test error handling (sets error message)
- [ ] Test loading states

#### 12.14 Write Widget Tests

**LoginScreen:**
- [ ] Test email field validation
- [ ] Test password field validation
- [ ] Test sign up/sign in toggle
- [ ] Test form submission
- [ ] Test error display
- [ ] Test loading indicator

**PinDialog:**
- [ ] Test status selection updates state
- [ ] Test restriction dropdown visibility (only when NO_GUN)
- [ ] Test restriction dropdown selection
- [ ] Test checkboxes toggle
- [ ] Test confirm button disabled when invalid
- [ ] Test delete button (edit mode only)
- [ ] Test cancel button closes dialog

**MapScreen:**
- [ ] Test map renders
- [ ] Test FAB click
- [ ] Test sign out button
- [ ] Test pin display
- [ ] Test dialog shows on pin tap

#### 12.15 Write Integration Tests

**Auth Flow:**
- [ ] Test complete sign up flow (mock email confirmation)
- [ ] Test complete sign in flow
- [ ] Test sign out flow
- [ ] Test session persistence

**Pin CRUD Flow:**
- [ ] Test create pin end-to-end (tap map → dialog → save → appears on map)
- [ ] Test edit pin end-to-end
- [ ] Test delete pin end-to-end

**Sync Flow:**
- [ ] Test offline pin creation → online sync
- [ ] Test offline edit → online sync
- [ ] Test bidirectional sync (two devices)
- [ ] Test conflict resolution

#### 12.16 Test on Real Devices

**Android:**
- [ ] Test on low-end device (Android 8.0, 2GB RAM)
- [ ] Test on mid-range device (Android 12, 4GB RAM)
- [ ] Test on high-end device (Android 14, 8GB+ RAM)

**iOS:**
- [ ] Test on iPhone SE (A13 chip)
- [ ] Test on iPhone 12 (A14 chip)
- [ ] Test on iPhone 14 Pro (A16 chip)

- [ ] Test all major features on each device
- [ ] Identify and fix performance issues
- [ ] Test battery usage (should be minimal)

#### 12.17 Test Edge Cases
- [ ] Test with 1000+ pins on map (performance)
- [ ] Test with very long POI names (truncation)
- [ ] Test with special characters in pin names
- [ ] Test rapid pin creation/deletion
- [ ] Test sync with large number of queued operations (100+)
- [ ] Test app in low memory conditions
- [ ] Test app with restricted background data (Android)
- [ ] Test app with Background App Refresh disabled (iOS)

#### 12.18 Fix Bugs and Issues
- [ ] Create bug tracker (GitHub Issues or similar)
- [ ] Document all bugs found during testing
- [ ] Prioritize critical bugs (crash, data loss)
- [ ] Fix critical bugs first
- [ ] Fix medium priority bugs
- [ ] Fix low priority bugs (nice-to-have)
- [ ] Retest after each fix

#### 12.19 Code Quality Review
- [ ] Run `flutter analyze` and fix all warnings
- [ ] Run `dart format .` to format code
- [ ] Review code for TODO comments and address them
- [ ] Remove debug print statements
- [ ] Remove unused imports
- [ ] Remove commented-out code
- [ ] Ensure consistent naming conventions
- [ ] Add documentation comments to public APIs

#### 12.20 Security Review
- [ ] Verify .env file is in .gitignore
- [ ] Ensure no API keys committed to git
- [ ] Review RLS policies (correct permissions)
- [ ] Test that users can only delete their own pins
- [ ] Test that users cannot access others' sessions
- [ ] Verify secure storage used for tokens
- [ ] Check for SQL injection vulnerabilities (should be none with Drift/Supabase)
- [ ] Review network requests (HTTPS only)

**Iteration 12 Complete** ✓

---

## Iteration 13: CI/CD & Deployment

**Goal**: Deploy to app stores
**Estimated Time**: 3-5 days
**Deliverable**: App available in Google Play and App Store

### Tasks

#### 13.1 Prepare for Release

**Update Version:**
- [ ] Update version in `pubspec.yaml`:
  ```yaml
  version: 1.0.0+1  # version+buildNumber
  ```

**Update App Metadata:**
- [ ] Set app name: "CCW Map"
- [ ] Set app description
- [ ] Create app icon (1024x1024 PNG)
  - [ ] Use launcher icon generator
  - [ ] Update for both Android and iOS
- [ ] Create splash screen (optional)

#### 13.2 Configure Code Signing (iOS)

**In Xcode:**
- [ ] Open `ios/Runner.xcworkspace` in Xcode
- [ ] Select Runner project
- [ ] Select Signing & Capabilities tab
- [ ] Select Team (Apple Developer account)
- [ ] Enable "Automatically manage signing"
- [ ] Verify bundle identifier: `com.ccwmap.app`
- [ ] Create provisioning profile
- [ ] Archive app to verify signing works

#### 13.3 Configure App Signing (Android)

**Create Keystore:**
- [ ] Generate keystore:
  ```bash
  keytool -genkey -v -keystore ~/ccwmap-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ccwmap
  ```
- [ ] Save keystore password securely
- [ ] Save alias password securely

**Configure Gradle:**
- [ ] Create `android/key.properties`:
  ```properties
  storePassword=your_store_password
  keyPassword=your_key_password
  keyAlias=ccwmap
  storeFile=/path/to/ccwmap-release-key.jks
  ```
- [ ] Add `key.properties` to `.gitignore`
- [ ] Update `android/app/build.gradle`:
  - [ ] Load key.properties
  - [ ] Configure signingConfigs
  - [ ] Use signingConfig in release buildType

**Test Release Build:**
- [ ] Run `flutter build appbundle --release`
- [ ] Verify APK is signed
- [ ] Test installation on device

#### 13.4 Create Store Listings

**Google Play Console:**
- [ ] Create app in Play Console
- [ ] Set up app details:
  - [ ] App name: "CCW Map"
  - [ ] Short description (80 chars)
  - [ ] Full description (4000 chars max)
  - [ ] Category: Maps & Navigation
  - [ ] Content rating: Mature 17+ (firearm-related)
  - [ ] Privacy policy URL (if required)
- [ ] Upload screenshots (see next task)
- [ ] Upload app icon (512x512 PNG)
- [ ] Upload feature graphic (1024x500 PNG)

**App Store Connect:**
- [ ] Create app in App Store Connect
- [ ] Set up app information:
  - [ ] App name: "CCW Map"
  - [ ] Subtitle (30 chars)
  - [ ] Description (4000 chars max)
  - [ ] Category: Navigation
  - [ ] Age rating: 17+ (firearm-related content)
  - [ ] Privacy policy URL (if required)
- [ ] Upload screenshots (see next task)
- [ ] Upload app icon (1024x1024 PNG)

#### 13.5 Create Screenshots

**Required Sizes:**

**Android:**
- [ ] Phone: 1080x1920 (portrait)
- [ ] 7-inch tablet: 1920x1200 (landscape)
- [ ] 10-inch tablet: 2560x1800 (landscape)

**iOS:**
- [ ] 6.7" (iPhone 14 Pro Max): 1290x2796
- [ ] 6.5" (iPhone 14 Plus): 1284x2778
- [ ] 5.5" (iPhone 8 Plus): 1242x2208
- [ ] 12.9" iPad Pro: 2048x2732

**Screenshot Content:**
- [ ] Screenshot 1: Map view with pins
- [ ] Screenshot 2: Create pin dialog
- [ ] Screenshot 3: Edit pin dialog with restrictions
- [ ] Screenshot 4: Login screen (optional)
- [ ] Add text overlays highlighting features (optional)

#### 13.6 Write Privacy Policy
- [ ] Create privacy policy document
- [ ] Include:
  - [ ] Data collected (email, location, pins created)
  - [ ] How data is used
  - [ ] Third-party services (Supabase, MapLibre)
  - [ ] Data retention policy
  - [ ] User rights (delete account, data export)
  - [ ] Contact information
- [ ] Host on GitHub Pages or website
- [ ] Update URLs in store listings

#### 13.7 Set Up CI/CD Pipeline (GitHub Actions)

**Create Workflow File:**
- [ ] Create `.github/workflows/main.yml`

**Build Job:**
```yaml
name: Build and Test

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test

  build-android:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v3
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk

  build-ios:
    needs: test
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build ios --release --no-codesign
```

**Secrets Configuration:**
- [ ] Add GitHub secrets:
  - [ ] `SUPABASE_URL`
  - [ ] `SUPABASE_ANON_KEY`
  - [ ] Android keystore (base64 encoded)
  - [ ] Android keystore password
  - [ ] iOS certificates (for advanced CI)

**Test CI Pipeline:**
- [ ] Push code to trigger workflow
- [ ] Verify tests run
- [ ] Verify builds succeed
- [ ] Fix any CI-specific issues

#### 13.8 Deploy to Internal Testing (Android)

**Upload to Play Console:**
- [ ] Build release bundle: `flutter build appbundle --release`
- [ ] Go to Play Console → Internal testing
- [ ] Upload app bundle
- [ ] Complete release notes
- [ ] Submit for review

**Create Test Track:**
- [ ] Add tester emails
- [ ] Send invite to testers
- [ ] Testers install and test app

**Gather Feedback:**
- [ ] Fix critical bugs found by testers
- [ ] Upload new build if needed
- [ ] Get approval from testers

#### 13.9 Deploy to TestFlight (iOS)

**Upload to App Store Connect:**
- [ ] Archive app in Xcode:
  - [ ] Product → Archive
  - [ ] Validate archive
  - [ ] Distribute to App Store Connect
- [ ] Or use `flutter build ipa` and upload via Transporter app

**Configure TestFlight:**
- [ ] In App Store Connect → TestFlight
- [ ] Add internal testers
- [ ] Add external testers (optional)
- [ ] Complete beta app information
- [ ] Submit for Beta App Review (if using external testing)

**Gather Feedback:**
- [ ] Testers install via TestFlight
- [ ] Collect feedback
- [ ] Fix bugs
- [ ] Upload new build if needed

#### 13.10 Submit to Production (Android)

**In Play Console:**
- [ ] Go to Production release
- [ ] Create new release
- [ ] Upload release app bundle
- [ ] Write release notes (user-facing)
- [ ] Set rollout percentage (e.g., 20% initially)
- [ ] Review and confirm
- [ ] Submit for review

**Review Process:**
- [ ] Wait for Google review (typically 1-3 days)
- [ ] Address any issues if rejected
- [ ] Resubmit if needed

**Post-Launch:**
- [ ] Monitor reviews and ratings
- [ ] Monitor crash reports (Play Console)
- [ ] Gradually increase rollout to 100%

#### 13.11 Submit to Production (iOS)

**In App Store Connect:**
- [ ] Select app version
- [ ] Complete all required fields:
  - [ ] App Review Information
  - [ ] Version Information
  - [ ] Age Rating
  - [ ] Copyright
- [ ] Add build from TestFlight
- [ ] Set pricing (free)
- [ ] Set availability (all countries or selected)
- [ ] Submit for App Review

**Review Process:**
- [ ] Wait for Apple review (typically 1-3 days)
- [ ] Address any issues if rejected
  - [ ] Common issues: privacy policy, content rating, in-app purchases
- [ ] Resubmit if needed

**Post-Launch:**
- [ ] Monitor reviews and ratings
- [ ] Monitor crash reports (App Store Connect)
- [ ] Respond to user reviews

#### 13.12 Set Up Analytics (Optional)

**Firebase Analytics:**
- [ ] Add Firebase to project
- [ ] Track key events:
  - [ ] Pin created
  - [ ] Pin edited
  - [ ] Pin deleted
  - [ ] Sync completed
  - [ ] User signed up
- [ ] Set up dashboards in Firebase Console

**Crashlytics:**
- [ ] Add Firebase Crashlytics
- [ ] Configure crash reporting
- [ ] Test crash reporting
- [ ] Monitor for crashes post-launch

#### 13.13 Plan for Post-Launch Support

**Monitor:**
- [ ] User reviews (respond within 24 hours)
- [ ] Crash reports (fix critical crashes ASAP)
- [ ] Performance metrics (ANR, slow frames)
- [ ] Server costs (Supabase usage)

**Plan Updates:**
- [ ] Bug fix releases (as needed)
- [ ] Feature releases (monthly/quarterly)
- [ ] OS version updates (new Android/iOS releases)

#### 13.14 Create Release Checklist for Future Updates
- [ ] Update version number
- [ ] Update CHANGELOG.md
- [ ] Run full test suite
- [ ] Test on real devices
- [ ] Build release artifacts
- [ ] Upload to stores
- [ ] Update release notes
- [ ] Monitor release

#### 13.15 Documentation

**User Documentation:**
- [ ] Create user guide (optional)
- [ ] Create FAQ page
- [ ] Add help section in app (optional)

**Developer Documentation:**
- [ ] Update README.md with:
  - [ ] Project description
  - [ ] Setup instructions
  - [ ] Build instructions
  - [ ] Contribution guidelines
- [ ] Document API integrations
- [ ] Document database schema

**Iteration 13 Complete** ✓

---

## Post-Launch: Future Enhancements

**Priority: Low** (After initial release)

### Real-Time Subscriptions
- [ ] Enable Supabase Realtime on pins table
- [ ] Subscribe to INSERT/UPDATE/DELETE events
- [ ] Update local database on real-time changes
- [ ] Show live indicators when other users edit pins

### Photo Upload
- [ ] Add image picker
- [ ] Implement photo upload to Supabase Storage
- [ ] Display photos in pin dialog
- [ ] Add photo gallery view

### User Notes
- [ ] Add notes field to pin dialog
- [ ] Store in database
- [ ] Display notes in pin details view

### Voting System
- [ ] Add upvote/downvote buttons
- [ ] Track votes in database
- [ ] Display vote count on pins
- [ ] Sort pins by votes (most trusted)

### Advanced Filtering
- [ ] Filter by restriction type
- [ ] Filter by date range (recent updates)
- [ ] Filter by distance from user
- [ ] Save filter preferences

### Heat Maps
- [ ] Aggregate pins by area
- [ ] Display heat map overlay
- [ ] Color intensity based on restriction density
- [ ] Toggle heat map on/off

### Push Notifications
- [ ] Notify users when near restricted zone
- [ ] Notify when pin status changes nearby
- [ ] Implement geofencing
- [ ] Add notification preferences

---

## Completion Checklist

- [ ] All 13 iterations completed
- [ ] App deployed to Google Play
- [ ] App deployed to App Store
- [ ] All critical bugs fixed
- [ ] Documentation complete
- [ ] CI/CD pipeline operational
- [ ] Post-launch monitoring in place

---

**End of Implementation Plan**

**Total Estimated Time**: 30-40 days (6-8 weeks)
**Team Size**: 1-2 developers
**Complexity**: Medium to High

**Good luck with the implementation!** 🚀
