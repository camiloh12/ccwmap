# CCW Map - Functional Specification

**Version:** 1.0
**Last Updated:** 2025-11-16
**Platform:** Cross-platform (Android/iOS via Flutter)
**Current Implementation:** Not yet started - Flutter will be used for both platforms

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Product Overview](#product-overview)
3. [Core Features](#core-features)
4. [User Flows](#user-flows)
5. [Data Models](#data-models)
6. [Architecture](#architecture)
7. [Authentication System](#authentication-system)
8. [Offline-First Sync Mechanism](#offline-first-sync-mechanism)
9. [UI/UX Specifications](#uiux-specifications)
10. [Third-Party Integrations](#third-party-integrations)
11. [Database Schema](#database-schema)
12. [Configuration & Setup](#configuration--setup)
13. [Testing Strategy](#testing-strategy)
14. [Build & Deployment](#build--deployment)

---

## Executive Summary

**CCW Map** is a mobile application that enables users to collaboratively map and share information about concealed carry weapon (CCW) zones across the United States. The app provides a visual, interactive map where users can create, edit, and view location pins indicating whether firearms are allowed, uncertain, or prohibited at specific establishments.

### Key Capabilities

- **Interactive Mapping**: Pan/zoom map with color-coded location pins
- **User Authentication**: Email/password authentication with session persistence
- **POI Integration**: Points of interest from OpenStreetMap (bars, restaurants, schools, etc.)
- **Offline-First Architecture**: Full functionality without internet connection
- **Cloud Synchronization**: Automatic bidirectional sync with Supabase backend
- **Real-time Collaboration**: Live updates when other users modify pins (infrastructure ready)
- **Geographic Restrictions**: Pins limited to 50 US states + Washington DC

### Technical Highlights

- **Clean Architecture** with strict layer separation (Domain/Data/Presentation)
- **MVVM Pattern** with reactive state management
- **Queue-Based Sync** with automatic retry and conflict resolution
- **Last-Write-Wins** conflict resolution using timestamps
- **Background Sync** via workmanager package (Flutter)
- **Comprehensive Testing** with unit, integration, and widget tests

---

## Product Overview

### Problem Statement

Concealed carry permit holders need to know where they can legally carry firearms. Laws vary by state, locality, and property type. Static resources quickly become outdated, and no collaborative platform exists for real-time, crowd-sourced carry zone information.

### Solution

A mobile app with an interactive map where authenticated users can:
1. **View** color-coded pins showing carry status at locations
2. **Create** new pins at points of interest by selecting from map POIs
3. **Edit** existing pins to update status or add enforcement details
4. **Sync** data across devices automatically
5. **Work offline** with automatic background sync when connectivity returns

### Target Users

- Concealed carry permit holders in the United States
- Travelers visiting unfamiliar areas
- Users seeking crowd-sourced, up-to-date carry zone information

### Platform Requirements

- **Android**: Min SDK 21 (Android 5.0)
- **iOS**: iOS 12.0+
- **Flutter**: 3.0+
- **Internet**: Optional (full offline functionality)
- **Location**: Optional (enhances UX but not required)

---

## Core Features

### 1. Interactive Map Viewing

**Description**: Pan/zoom map with MapLibre showing user's location and carry zone pins.

**Functional Requirements**:
- Display base map tiles from MapTiler (or demo tiles if no API key)
- Show user's current location with blue dot (if permission granted)
- Render color-coded pin markers:
  - **Green (0)**: Firearms allowed
  - **Yellow (1)**: Status uncertain
  - **Red (2)**: No firearms allowed
- Display POI labels from OpenStreetMap (businesses, schools, bars, etc.)
- Support pan, zoom, rotate gestures
- Re-center FAB button to return to user location
- Viewport-based POI loading (fetch POIs when map moves)

**Technical Details**:
- **Map Library**: MapLibre (open-source, no API key required)
- **Tile Source**: MapTiler (optional API key) or demo tiles
- **Camera**: Initial zoom 15.0, user location zoom 16.0
- **POI Refresh**: Fetch on camera idle after 500ms debounce

### 2. Pin Creation via POI Selection

**Description**: Users create pins by tapping POI labels on the map, selecting a status, and adding optional details.

**Functional Requirements**:
- User taps on POI label (e.g., "Starbucks", "City Hall")
- App shows dialog with:
  - POI name as header
  - Status picker (Allowed/Uncertain/No Guns)
  - Restriction tag dropdown (required if status is "No Guns")
  - Security screening checkbox
  - Posted signage checkbox
  - "Create" and "Cancel" buttons
- Validate location is within US boundaries before creation
- Associate pin with authenticated user's ID
- Instant local save + queue for cloud sync

**Validation Rules**:
- Location must be within 50 US states + Washington DC
- If status is "No Guns", restriction tag is required
- POI name must not be empty
- User must be authenticated

**Technical Details**:
- POI names come from Overpass API (OpenStreetMap data)
- US boundary check: `24.396308 <= lat <= 49.384358, -125.0 <= lng <= -66.93457`
- Pin associated with user ID from auth session

### 3. Pin Editing & Deletion

**Description**: Users can edit existing pins to update status or delete them.

**Functional Requirements**:
- User taps existing pin on map
- App shows dialog with:
  - Current status pre-selected
  - Restriction tag (if applicable)
  - Security screening/signage checkboxes
  - "Save", "Delete", and "Cancel" buttons
- Only pin creator can delete a pin
- Any authenticated user can update status (crowd-sourced corrections)
- Changes sync to cloud immediately

**Technical Details**:
- Edit triggers database update with new `last_modified` timestamp
- Delete only allowed if `created_by == current_user_id`
- RLS policy on backend enforces deletion permissions

### 4. User Authentication

**Description**: Email/password authentication with session persistence across app restarts.

**Functional Requirements**:
- **Sign Up**:
  - Email + password input
  - Email format validation
  - Password minimum 6 characters
  - Email confirmation required (sent to inbox)
  - Deep link handling for email confirmation
- **Sign In**:
  - Email + password input
  - Remember session (no re-login on app restart)
  - Error handling for invalid credentials
- **Sign Out**:
  - Clear session and return to login screen
  - Option in map screen menu

**Email Confirmation Flow**:
- User signs up → Supabase sends confirmation email
- **Mobile**: Click link in email → App opens automatically → Auto-login
- **Desktop**: Click link → GitHub Pages fallback → Instructions to open on mobile
- Deep link schemes:
  - Custom: `com.carryzonemap.app://auth/callback`
  - HTTPS: `https://camiloh12.github.io/CarryZoneMap-Android/auth/callback`

**Technical Details**:
- Backend: Supabase Auth
- Session storage: Encrypted secure storage (platform-specific)
- Token refresh: Automatic via SDK
- Password policy: Min 6 chars (configurable in Supabase dashboard)

### 5. Offline-First Synchronization

**Description**: Full app functionality without internet, with automatic bidirectional sync when online.

**Functional Requirements**:
- **Offline Mode**:
  - Create/edit/delete pins without internet
  - All changes saved locally to SQLite database (Drift or sqflite)
  - Operations queued for later upload
  - UI shows instant feedback (no loading spinners)
- **Online Mode**:
  - Automatically detect network connectivity
  - Upload queued operations to Supabase
  - Download remote changes and merge with local data
  - Resolve conflicts using last-write-wins strategy
  - Retry failed operations up to 3 times
- **Background Sync**:
  - Periodic sync every 15 minutes (workmanager package)
  - Sync on app launch
  - Sync on network reconnection
  - Optional: Real-time subscriptions for instant updates

**Conflict Resolution**:
- Compare `last_modified` timestamps
- Newer timestamp wins (local or remote)
- Both sides updated to match winner
- No data loss (last edit always preserved)

**Technical Details**:
- Local DB: Drift or sqflite (Flutter)
- Remote DB: Supabase PostgreSQL
- Network monitor: Reactive stream of connectivity state (connectivity_plus package)
- Sync queue table: Stores pending CREATE/UPDATE/DELETE operations
- Max retries: 3 attempts per operation
- Retry backoff: Exponential (1s, 2s, 4s)

### 6. POI Fetching & Caching

**Description**: Fetch points of interest from OpenStreetMap Overpass API and cache them locally.

**Functional Requirements**:
- Fetch POIs when user moves map to new area
- Cache POIs for 30 minutes to reduce API calls
- Handle Overpass API rate limiting gracefully (return cached data if throttled)
- Display POI labels on map (name, type)
- POI types: Restaurants, bars, schools, government buildings, hospitals, places of worship, stadiums, etc.

**Caching Strategy**:
- **Cache Key**: Rounded viewport bounds (precision: 2 decimal places)
- **Cache Duration**: 30 minutes
- **Cache Size**: 20 most recent viewports
- **Fallback**: Return stale cache if API unavailable

**Technical Details**:
- API: Overpass API (https://overpass-api.de/api/interpreter)
- Query: Overpass QL for amenities, tourism, leisure, building types
- Rate limit: 2 requests/second (enforced by API)
- Cache cleanup: LRU eviction when > 20 entries

### 7. Location Services

**Description**: Access user's current location to center map and enable location-based features.

**Functional Requirements**:
- Request location permission on first launch
- Handle permission denied gracefully (map still works)
- Display user location as blue dot with accuracy circle
- Update location continuously (10-second interval)
- Re-center button to snap map to user location

**Technical Details**:
- **Package**: Geolocator package (Flutter)
- Update interval: 10 seconds
- Min interval: 5 seconds
- Accuracy: High (GPS + network)

### 8. Geographic Restrictions

**Description**: Enforce US-only pin placement to comply with app scope.

**Functional Requirements**:
- Block pin creation outside 50 US states + Washington DC
- Show error message: "Pins can only be placed within the 50 US states and Washington DC"
- Boundary check before showing create dialog
- Defensive check before database save

**Boundary Coordinates**:
- **Latitude**: 24.396308 (southernmost FL Keys) to 49.384358 (northernmost MN)
- **Longitude**: -125.0 (westernmost WA) to -66.93457 (easternmost ME)
- **Exclusions**: Hawaii, Alaska, territories (for simplicity)

**Technical Details**:
- Check in ViewModel before showing dialog
- Double-check in repository before database write
- Logging for attempted violations (security/analytics)

---

## User Flows

### Flow 1: First-Time User Onboarding

1. **App Launch** → User sees login screen
2. **Tap "Sign Up"** → Email/password form appears
3. **Enter credentials** → Validation (email format, password length)
4. **Tap "Sign Up"** → Loading spinner
5. **Success** → Message: "Please check your email to confirm"
6. **Check email** → Click confirmation link
7. **Deep link** → App opens, session auto-imported
8. **Map Screen** → User sees map centered on their location (if permission granted)

### Flow 2: Creating a Pin

1. **User** taps POI label on map (e.g., "Chipotle")
2. **App** queries features at tap point
3. **App** extracts POI name from feature
4. **App** validates location is within US boundaries
5. **App** shows pin creation dialog:
   - Header: "Chipotle" (POI name)
   - Status picker: "Allowed" (default)
   - Restriction tag: Hidden (only shown if status = "No Guns")
   - Checkboxes: Security screening, Posted signage
   - Buttons: "Create", "Cancel"
6. **User** selects "No Guns" → Restriction tag dropdown appears
7. **User** selects "Private Property" from dropdown
8. **User** checks "Posted Signage"
9. **User** taps "Create"
10. **App** creates Pin object:
    - `name = "Chipotle"`
    - `location = {lat, lng}`
    - `status = NO_GUN`
    - `restrictionTag = PRIVATE_PROPERTY`
    - `hasPostedSignage = true`
    - `createdBy = current_user_id`
11. **App** writes to local DB (instant UI update)
12. **App** queues operation for sync
13. **Map** re-renders with new red pin at location
14. **Background** syncs to Supabase when online

### Flow 3: Editing a Pin

1. **User** taps existing pin on map
2. **App** queries features at tap point
3. **App** finds pin by ID
4. **App** shows edit dialog:
   - Current status pre-selected
   - Current restriction tag (if applicable)
   - Current checkbox states
   - Buttons: "Save", "Delete", "Cancel"
5. **User** changes status to "Allowed"
6. **User** taps "Save"
7. **App** updates Pin:
   - `status = ALLOWED`
   - `restrictionTag = null` (cleared)
   - `last_modified = now()`
8. **App** writes to local DB
9. **App** queues update operation
10. **Map** re-renders with green pin
11. **Background** syncs to cloud

### Flow 4: Offline Usage

1. **User** opens app with **no internet**
2. **App** loads pins from local database
3. **User** creates/edits pins normally
4. **App** saves all changes to local DB
5. **App** queues operations in sync queue
6. **User** sees changes instantly on map
7. **Internet** reconnects
8. **Network Monitor** detects connectivity
9. **SyncManager** automatically uploads queued operations
10. **SyncManager** downloads remote changes
11. **App** merges changes (last-write-wins)
12. **Map** updates with latest data

### Flow 5: Multi-Device Sync

1. **User A** creates pin on **Device 1** (Android phone)
2. **Pin** syncs to Supabase cloud
3. **User A** opens app on **Device 2** (iPad)
4. **Device 2** downloads pin from cloud
5. **User B** (different user) edits same pin on **Device 3**
6. **Edit** syncs to cloud with newer `last_modified` timestamp
7. **Device 1** performs background sync
8. **SyncManager** compares timestamps: remote is newer
9. **Device 1** updates local DB with remote version
10. **Map** on Device 1 shows updated pin
11. **(Optional)** Real-time subscription instantly pushes update to all devices without waiting for background sync

---

## Data Models

### 1. Pin (Domain Model)

**Description**: Core entity representing a location pin on the map.

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | String (UUID) | Yes | Auto-generated | Unique identifier |
| `name` | String | Yes | - | POI name (e.g., "Starbucks") |
| `location` | Location | Yes | - | Geographic coordinates |
| `status` | PinStatus | Yes | ALLOWED | Carry zone status |
| `restrictionTag` | RestrictionTag? | No | null | Reason for restriction (required if status = NO_GUN) |
| `hasSecurityScreening` | Boolean | Yes | false | Active security screening present |
| `hasPostedSignage` | Boolean | Yes | false | "No guns" signage visible |
| `metadata` | PinMetadata | Yes | Auto-generated | Creation/modification metadata |

**Business Rules**:
- If `status == NO_GUN`, `restrictionTag` must not be null
- `location` must be within US boundaries
- `id` is immutable after creation
- `metadata.lastModified` auto-updates on any change

**Methods**:
```dart
Pin withNextStatus()  // Cycle to next status
Pin withStatus(PinStatus newStatus)  // Set specific status
Pin withMetadata(PinMetadata newMetadata)  // Update metadata
```

### 2. PinStatus (Enum)

**Description**: Represents carry zone status.

**Values**:

| Value | Display Name | Color Code | Description |
|-------|--------------|------------|-------------|
| `ALLOWED` | "Allowed" | 0 (Green) | Firearms allowed |
| `UNCERTAIN` | "Uncertain" | 1 (Yellow) | Status unknown/unverified |
| `NO_GUN` | "No Guns" | 2 (Red) | Firearms prohibited |

**Methods**:
```dart
PinStatus next()  // ALLOWED -> UNCERTAIN -> NO_GUN -> ALLOWED
PinStatus fromColorCode(int code)  // Convert integer to enum
```

### 3. RestrictionTag (Enum)

**Description**: Reason why firearms carry is restricted (applicable only for NO_GUN status).

**Values**:

| Tag | Display Name | Description |
|-----|--------------|-------------|
| `FEDERAL_PROPERTY` | "Federal Government Property" | Federal building, post office, military base, VA facility, courthouse, tribal land |
| `AIRPORT_SECURE` | "Airport Secure Area" | Past TSA security checkpoint |
| `STATE_LOCAL_GOVT` | "State/Local Government Property" | State/local government building, courthouse, polling place |
| `SCHOOL_K12` | "School (K-12)" | Elementary, middle, or high school campus |
| `COLLEGE_UNIVERSITY` | "College/University" | College or university campus |
| `BAR_ALCOHOL` | "Bar/Alcohol Establishment" | Bar, restaurant, or venue with alcohol restrictions |
| `HEALTHCARE` | "Healthcare Facility" | Hospital, medical clinic, childcare facility |
| `PLACE_OF_WORSHIP` | "Place of Worship" | Church, mosque, temple, religious facility |
| `SPORTS_ENTERTAINMENT` | "Sports/Entertainment Venue" | Sports stadium, arena, concert hall, amusement park |
| `PRIVATE_PROPERTY` | "Private Property" | Private business, workplace, or property restricting carry |

**Methods**:
```dart
RestrictionTag? fromString(String? name)  // Parse from string
```

### 4. Location (Value Object)

**Description**: Geographic coordinates (immutable value object).

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `latitude` | Double | Yes | Latitude (-90 to 90) |
| `longitude` | Double | Yes | Longitude (-180 to 180) |

**Factory Methods**:
```dart
Location fromLngLat(double lng, double lat)
Location fromLatLng(double lat, double lng)
```

**Validation**:
- Latitude: -90 to 90
- Longitude: -180 to 180

### 5. PinMetadata (Data Class)

**Description**: Metadata about pin creation and modification.

**Fields**:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `createdBy` | String? | No | null | User ID who created pin |
| `createdAt` | Long | Yes | Current timestamp | Creation timestamp (epoch millis) |
| `lastModified` | Long | Yes | Current timestamp | Last modification timestamp |
| `photoUri` | String? | No | null | Photo URL (future feature) |
| `notes` | String? | No | null | User notes (future feature) |
| `votes` | Int | Yes | 0 | Voting count (future feature) |

### 6. User (Domain Model)

**Description**: Authenticated user.

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | String (UUID) | Yes | Unique user identifier from auth provider |
| `email` | String? | No | User's email address |

### 7. Poi (Domain Model)

**Description**: Point of Interest from OpenStreetMap.

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | String | Yes | OSM node/way ID |
| `name` | String | Yes | POI name (e.g., "Starbucks") |
| `latitude` | Double | Yes | Latitude |
| `longitude` | Double | Yes | Longitude |
| `type` | String | Yes | POI type (e.g., "restaurant", "bar", "school") |
| `tags` | Map<String, String> | No | Additional OSM tags |

### 8. SyncOperation (Sealed Class)

**Description**: Type of sync operation in queue.

**Values**:
- `CREATE`: Insert new pin to remote
- `UPDATE`: Update existing pin on remote
- `DELETE`: Delete pin from remote

**Database Representation**:
- Stored as string: "CREATE", "UPDATE", "DELETE"

### 9. SyncStatus (Sealed Class)

**Description**: Current sync state.

**Values**:

| State | Properties | Description |
|-------|------------|-------------|
| `Idle` | - | No sync in progress |
| `Syncing` | `pendingCount: Int` | Sync in progress |
| `Success` | `uploadCount: Int, downloadCount: Int` | Sync completed |
| `Error` | `message: String, retryable: Boolean` | Sync failed |

### 10. AuthState (Sealed Class)

**Description**: Current authentication state.

**Values**:

| State | Properties | Description |
|-------|------------|-------------|
| `Loading` | - | Checking auth status |
| `Authenticated` | `user: User` | User logged in |
| `Unauthenticated` | - | User logged out |

---

## Architecture

### Clean Architecture Layers

The app follows **Clean Architecture** with strict dependency rules:

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                       │
│  (UI, ViewModels, State)                                    │
│  - Flutter Widgets                                          │
│  - Stream for reactive updates                              │
│  - Dependency injection via GetIt or Provider               │
└──────────────────────┬──────────────────────────────────────┘
                       │ Depends on
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                     Domain Layer                            │
│  (Business Logic, Models, Repository Interfaces)            │
│  - Pure Dart (no framework dependencies)                    │
│  - Domain models: Pin, User, Location, etc.                 │
│  - Repository interfaces: PinRepository, AuthRepository     │
│  - Business rules and validation logic                      │
└──────────────────────┬──────────────────────────────────────┘
                       │ Depends on
                       ↓
┌─────────────────────────────────────────────────────────────┐
│                      Data Layer                             │
│  (Repository Implementations, Data Sources)                 │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Local DB   │  │ SyncManager  │  │ Remote (Supabase)│   │
│  │ SQLite     │←─│ Queue Ops    │─→│ Auth, Postgrest  │   │
│  │ Instant    │  │ Retry Logic  │  │ Realtime (opt)   │   │
│  │ Reads      │  │ Conflict Res │  │                  │   │
│  └────────────┘  └──────────────┘  └──────────────────┘   │
│                                                             │
│  NetworkMonitor: Reactive connectivity tracking             │
└─────────────────────────────────────────────────────────────┘
```

**Dependency Rule**: Dependencies only flow inward (Presentation → Domain → Data). Domain layer has ZERO framework imports.

### Design Patterns

#### 1. MVVM (Model-View-ViewModel)

**View** (MapScreen):
- StatelessWidget or StatefulWidget
- Listens to Stream from ViewModel
- Renders UI based on state
- Delegates events to ViewModel

**ViewModel** (MapViewModel):
- Owns UI state (MapUiState)
- Exposes Stream
- Handles user events (create pin, edit pin, etc.)
- Calls repository methods
- Updates state immutably

**Model** (Domain models):
- Pure data classes (Pin, User, etc.)
- Business logic methods
- No UI dependencies

#### 2. Repository Pattern

**Interface** (PinRepository):
- Defined in domain layer
- Abstract CRUD operations
- Returns domain models

**Implementation** (PinRepositoryImpl):
- Defined in data layer
- Coordinates local and remote data sources
- Handles sync queue operations
- Maps entities ↔ domain models

#### 3. Offline-First Pattern

**Write Path**:
1. ViewModel calls `repository.addPin(pin)`
2. Repository writes to local DB **immediately**
3. Repository queues operation for sync
4. Local DB emits Stream update
5. ViewModel receives update
6. UI re-renders (instant feedback)
7. Background: SyncManager uploads to cloud

**Read Path**:
1. Repository exposes `Stream<List<Pin>>`
2. Stream sources from local DB
3. ViewModel listens to Stream
4. UI re-renders on each emission
5. Background: SyncManager downloads remote changes → writes to local DB → Stream emits

#### 4. Chain of Responsibility (Click Handling)

**Problem**: MapScreen needs to handle clicks on different feature types (existing pins, Overpass POIs, MapTiler POIs).

**Solution**: Chain of detectors, each checks if it can handle the click:

```dart
abstract class FeatureDetector {
    bool canHandle(map, screenPoint, clickPoint);
    void handle(map, screenPoint, clickPoint);
}

class ExistingPinDetector implements FeatureDetector { ... }
class OverpassPoiDetector implements FeatureDetector { ... }
class MapTilerPoiDetector implements FeatureDetector { ... }

class FeatureClickHandler {
    final List<FeatureDetector> detectors;
    FeatureClickHandler(this.detectors);

    void handleClick(map, screenPoint, clickPoint) {
        detectors.firstWhere((d) => d.canHandle(...))?.handle(...);
    }
}
```

#### 5. Single Responsibility Principle

**MapScreen** delegates responsibilities to helper classes:

- **CameraController**: Camera positioning only
- **MapLayerManager**: POI layer management only
- **LocationComponentManager**: Location component setup only
- **FeatureClickHandler**: Click handling only
- **FeatureLayerManager**: Pin layer rendering only

### Data Flow Example: Creating a Pin

```
User taps POI
    ↓
MapScreen.onMapClick()
    ↓
FeatureClickHandler.handleClick()
    ↓
OverpassPoiDetector.handle()
    ↓
MapViewModel.showCreatePinDialog(name, lng, lat)
    ↓
MapViewModel updates state:
    uiState.copy(pinDialogState = PinDialogState.Creating(...))
    ↓
PinDialog composable re-renders with data
    ↓
User selects status and taps "Create"
    ↓
MapViewModel.confirmPinDialog()
    ↓
MapViewModel calls:
    pinRepository.addPin(pin)
    ↓
PinRepositoryImpl:
    1. pinDao.insertPin(entity)      // Local DB write
    2. syncManager.queuePinForUpload(pin)  // Queue for cloud
    ↓
Database emits Stream<List<PinEntity>>
    ↓
Repository maps to Stream<List<Pin>>
    ↓
MapViewModel listens to Stream, updates state:
    uiState.copy(pins = newPins)
    ↓
MapScreen re-renders with new pin
    ↓
Background: SyncManager uploads to Supabase
```

---

## Authentication System

### Flow: Sign Up

1. **User enters email + password** on LoginScreen
2. **Client validates**:
   - Email format (regex)
   - Password length (min 6 chars)
3. **AuthViewModel calls** `authRepository.signUpWithEmail(email, password)`
4. **SupabaseAuthRepository**:
   - Calls `supabase.auth.signUpWith(Email)`
   - Supabase creates user in `auth.users` table
   - Supabase sends confirmation email
5. **Response handling**:
   - Success with empty user ID → Email confirmation required
   - Success with user ID → Immediate login (if email confirmation disabled)
   - Failure → Error message shown
6. **UI shows**: "Please check your email to confirm your account"

### Flow: Email Confirmation

**Mobile Device**:
1. User clicks link in email
2. Android: Intent filter matches HTTPS deep link
3. MainActivity.handleDeepLink() extracts tokens from URL fragment
4. Calls `auth.importAuthToken(accessToken, refreshToken)`
5. Session imported → AuthState changes to Authenticated
6. MainActivity navigates to MapScreen

**Desktop Browser**:
1. User clicks link in email
2. Browser opens GitHub Pages fallback page
3. Page shows instructions: "Please open this link on your mobile device"
4. User can copy link or scan QR code (future feature)

**Deep Link Schemes**:
- Custom: `com.carryzonemap.app://auth/callback#access_token=...&refresh_token=...`
- HTTPS: `https://camiloh12.github.io/CarryZoneMap-Android/auth/callback#access_token=...&refresh_token=...`

### Flow: Sign In

1. **User enters credentials** on LoginScreen
2. **Client validates** (same as sign up)
3. **AuthViewModel calls** `authRepository.signInWithEmail(email, password)`
4. **SupabaseAuthRepository**:
   - Calls `supabase.auth.signInWith(Email)`
   - Supabase validates credentials
   - Returns session with access token + refresh token
5. **Success**: AuthState changes to Authenticated(user)
6. **MainActivity observes** auth state change
7. **UI navigates** to MapScreen

### Flow: Session Persistence

1. **App launch**: AuthRepository checks for existing session
2. **Supabase SDK** auto-loads session from secure storage
3. **If valid session**: AuthState = Authenticated
4. **If no session**: AuthState = Unauthenticated
5. **Token refresh**: Supabase SDK automatically refreshes expired access tokens using refresh token

### Flow: Sign Out

1. **User taps** "Sign Out" in MapScreen menu
2. **MapViewModel calls** `authRepository.signOut()`
3. **SupabaseAuthRepository**:
   - Calls `supabase.auth.signOut()`
   - Clears session from secure storage
4. **AuthState** changes to Unauthenticated
5. **MainActivity observes** state change
6. **UI navigates** to LoginScreen

### Security

**Password Storage**:
- Never stored locally
- Hashed with bcrypt on Supabase backend
- Only access/refresh tokens stored (encrypted)

**Token Management**:
- Access token: Short-lived (1 hour)
- Refresh token: Long-lived (30 days)
- Auto-refresh handled by SDK
- Tokens stored in platform-specific secure storage:
  - Android: EncryptedSharedPreferences
  - iOS: Keychain

**Row Level Security (RLS)**:
- Enforced at database level
- Users can only delete their own pins (`created_by == auth.uid()`)
- Users can update any pin (crowd-sourced corrections)
- Anyone can read pins (public map data)

---

## Offline-First Sync Mechanism

### Architecture

**Components**:

1. **Local Database** (SQLite via Drift or sqflite):
   - `pins` table: User pins with full schema
   - `sync_queue` table: Pending operations

2. **SyncManager**:
   - Orchestrates upload/download
   - Implements conflict resolution
   - Manages retry logic

3. **NetworkMonitor**:
   - Reactive stream of connectivity state
   - Triggers sync on network reconnection

4. **SyncWorker** (Background Task):
   - Periodic sync every 15 minutes
   - Survives app restarts
   - Only runs when online

5. **Remote Database** (Supabase PostgreSQL):
   - Authoritative source of truth for synced data
   - PostGIS extension for geographic queries

### Sync Operations

#### Create Pin

**Local (Instant)**:
1. Insert into `pins` table
2. Insert into `sync_queue` table:
   - `pin_id = pin.id`
   - `operation_type = "CREATE"`
   - `timestamp = now()`

**Remote (Background)**:
1. SyncManager reads queue
2. For each CREATE operation:
   - Fetch pin from local DB
   - POST to Supabase `/pins` endpoint
   - If success: Delete from queue
   - If failure: Increment retry count, log error

#### Update Pin

**Local (Instant)**:
1. Update `pins` table, set `last_modified = now()`
2. Delete any existing queue operations for this pin
3. Insert UPDATE operation into `sync_queue`

**Remote (Background)**:
1. Fetch pin from local DB
2. PATCH to Supabase `/pins/{id}` endpoint
3. Success: Delete from queue
4. Failure: Retry with backoff

#### Delete Pin

**Local (Instant)**:
1. Delete from `pins` table
2. Delete any existing queue operations for this pin
3. Insert DELETE operation into `sync_queue`

**Remote (Background)**:
1. DELETE to Supabase `/pins/{id}` endpoint
2. Success: Delete from queue
3. Failure: Retry (note: pin already deleted locally)

### Download & Conflict Resolution

**Download Phase** (runs after upload):
1. Fetch all pins from Supabase: `GET /pins`
2. For each remote pin:
   - Check if exists locally
   - **If not exists**: Insert into local DB
   - **If exists**: Compare `last_modified` timestamps
     - Remote newer: Update local with remote data
     - Local newer: Keep local (will upload on next sync)
     - Same: No action

**Last-Write-Wins**:
```kotlin
fun mergeRemotePin(remotePin: Pin): Boolean {
    val localPin = pinDao.getPinById(remotePin.id)

    if (localPin == null) {
        pinDao.insertPin(remotePin)  // New pin, insert
        return true
    }

    if (remotePin.metadata.lastModified > localPin.metadata.lastModified) {
        pinDao.updatePin(remotePin)  // Remote is newer, update
        return true
    }

    // Local is newer, keep local
    return false
}
```

### Retry Logic

**Max Retries**: 3 attempts per operation

**Backoff Strategy**: Exponential
- Retry 1: Immediate
- Retry 2: 2 seconds
- Retry 3: 4 seconds
- After 3 failures: Remove from queue, log error

**Queue Management**:
```sql
-- SyncQueueEntity schema
CREATE TABLE sync_queue (
    id TEXT PRIMARY KEY,
    pin_id TEXT NOT NULL,
    operation_type TEXT NOT NULL,  -- CREATE, UPDATE, DELETE
    timestamp INTEGER NOT NULL,
    retry_count INTEGER DEFAULT 0,
    last_error TEXT
);
```

### Network Monitoring

**Implementation**:
- Package: connectivity_plus (Flutter)
- Reactive stream: `Stream<bool>`
- Distinct emissions (no duplicate events)

**Triggers**:
- Network reconnection → Immediate sync
- App launch → Check connectivity, sync if online
- Background worker → Periodic sync (15 min)

### Real-Time Subscriptions (Optional)

**Infrastructure Ready, Not Enabled by Default**:

```dart
// SyncManager
Stream<String> startRealtimeSubscription() {
    return remoteDataSource.subscribeToChanges()
        .map((event) {
            if (event is PinInsertEvent) return handleRealtimeInsert(event.pin);
            if (event is PinUpdateEvent) return handleRealtimeUpdate(event.pin);
            if (event is PinDeleteEvent) return handleRealtimeDelete(event.pinId);
        });
}
```

**Benefits**:
- Instant updates across devices (no 15-minute delay)
- Live collaboration (see other users' changes immediately)

**Trade-offs**:
- Increased battery usage (WebSocket connection)
- More complex conflict scenarios
- Requires Supabase Realtime enabled ($10/mo)

---

## UI/UX Specifications

**Reference Screenshots**: See `screenshot-1.png`, `screenshot-2.png`, `screenshot-3.png`, and `screenshot-4.png` for current app design.

### Screens

#### 1. LoginScreen

**Layout**:
```
┌──────────────────────────────────────┐
│                                      │
│         [App Logo/Title]             │
│                                      │
│  ┌────────────────────────────────┐ │
│  │ Email                          │ │
│  └────────────────────────────────┘ │
│                                      │
│  ┌────────────────────────────────┐ │
│  │ Password                  [👁] │ │
│  └────────────────────────────────┘ │
│                                      │
│  [ Error/Success Message ]           │
│                                      │
│  ┌────────────────────────────────┐ │
│  │       Sign In / Sign Up        │ │
│  └────────────────────────────────┘ │
│                                      │
│       [Toggle: "Need an account?    │
│        Sign Up" / "Have an account? │
│        Sign In"]                     │
│                                      │
└──────────────────────────────────────┘
```

**Components**:
- Email TextField (keyboard type: email)
- Password TextField (obscureText: true, toggle visibility)
- Submit Button (disabled while loading)
- Loading indicator (shows during auth)
- Error Snackbar (red, dismissible)
- Success message (green, auto-dismiss after 5s)
- Toggle link (switches between Sign In / Sign Up modes)

**State**:
- `isLoading: Boolean`
- `error: String?`
- `successMessage: String?`
- `isSignUpMode: Boolean`

#### 2. MapScreen

**Reference**: `screenshot-1.png`

**Layout**:
- Full-screen map (no traditional AppBar)
- Title "CCW Map" overlaid in top-left corner (dark text on semi-transparent background)
- Sign out/exit icon in top-right corner
- Re-center location FAB in bottom-right corner
- MapLibre attribution in bottom-left corner

**Map Features**:
- Base map tiles showing streets, water bodies, parks (light color scheme)
- User location indicator
- Pin markers (solid colored circles):
  - Green circle: Firearms allowed
  - Yellow/orange circle: Status uncertain
  - Red circle: No firearms allowed
- POI labels from map tiles (business names, landmarks)
- Small red "+" symbols indicating points of interest

**Top Bar** (Overlay, not traditional AppBar):
- Left: "CCW Map" text (dark gray/black)
- Right: Exit/sign out icon (arrow in box icon)
- Background: Semi-transparent or light background
- No bottom border/elevation

**FAB** (Floating Action Button):
- Icon: Circular target/crosshairs icon (location re-center)
- Position: Bottom-right corner
- Style: Circular, light purple/lavender background
- Action: Center map on user location

**Gestures**:
- Pan: Drag to move map
- Zoom: Pinch to zoom in/out
- Rotate: Two-finger rotate
- Tap: Open dialog for creating/editing pin

**State**:
- `pins: List<Pin>`
- `pois: List<Poi>`
- `currentLocation: Location?`
- `isLoading: Boolean`
- `error: String?`
- `hasLocationPermission: Boolean`
- `pinDialogState: PinDialogState`

#### 3. PinDialog (Modal)

**Reference**: `screenshot-2.png` (Create), `screenshot-3.png` (Edit - basic), `screenshot-4.png` (Edit - with restrictions)

**Visual Design**:
- Rounded corners bottom sheet / centered modal dialog
- White/light lavender background
- Appears over dimmed map background
- Padding around all content

**Layout - Creating Mode** (`screenshot-2.png`):
- **Title**: "Create Pin" (large, bold, black text)
- **POI Name**: Display name in purple/indigo color (e.g., "Kohl's")
- **Status Label**: "Select carry zone status:" (gray text)
- **Status Options**: Three bordered boxes with colored circles:
  - Each box: Rounded rectangle with 1-2px border
  - Selected state: Thicker colored border matching the status color
  - Unselected state: Light gray border
  - Layout per box:
    - Left: Colored filled circle (20-24px diameter)
    - Right: Status text ("Allowed", "Uncertain", "No Guns")
  - Colors:
    - Allowed: Green circle (#4CAF50 or similar)
    - Uncertain: Yellow/orange circle (#FFC107 or similar)
    - No Guns: Red circle (#F44336 or similar)
- **Action Buttons** (bottom):
  - Layout: Horizontal, right-aligned
  - "Cancel" button: Text-only, gray/purple text
  - "Create" button: Filled purple/indigo button with white text

**Layout - Editing Mode (Basic)** (`screenshot-3.png`):
- Same as Create mode but:
  - **Title**: "Edit Pin"
  - **POI Name**: "Publix" (in purple)
  - **Delete Button**: Outlined button with red text and trash icon
    - Position: Above action buttons, full width
    - Style: Border with red color, white background
    - Icon: Trash/delete icon on left side
  - **Action Buttons**:
    - "Cancel" (text-only)
    - "Save" (filled purple button)

**Layout - Editing Mode (No Guns Selected)** (`screenshot-4.png`):
- Same as Edit mode plus:
  - **POI Name**: "Tampa General Hospital" (purple)
  - **No Guns Option**: Selected with red border
  - **Restriction Section** (appears when "No Guns" selected):
    - Label: "Why is carry restricted?" (gray text)
    - Dropdown: Full-width rounded button/field
      - Shows selected value (e.g., "Healthcare Facility")
      - Down arrow icon on right
      - Purple text color
      - Light border
  - **Optional Details Section**:
    - Label: "Optional details:" (gray text)
    - Two checkboxes (vertical stack):
      - "Active security screening"
      - "Posted signage visible"
    - Checkboxes: Purple when checked, with checkmark icon
    - Spacing between checkboxes
  - **Delete Button**: Below optional details
  - **Action Buttons**: "Cancel" and "Save" at bottom

**Component Details**:

**Status Selection Buttons**:
- Height: ~56px
- Border radius: 8-12px
- Padding: 12-16px horizontal
- Border: 2px when selected, 1px when unselected
- Spacing: 8-12px between options
- Circle position: Left-aligned with 16px left margin
- Text: Left-aligned, 16px from circle

**Restriction Dropdown**:
- Height: ~56px
- Border radius: 8-12px
- Background: Light purple/white
- Text color: Purple/indigo
- Down arrow: Right-aligned
- Border: 1-2px light purple/gray

**Checkboxes**:
- Size: 24px
- Spacing: 16-20px between items
- Checked color: Purple (#6200EE or similar)
- Unchecked: Light gray border
- Label: 12-16px from checkbox

**Delete Button**:
- Height: ~48px
- Border radius: 24px (pill-shaped)
- Border: 1-2px red
- Text: Red
- Icon: Trash icon, left of text
- Background: White/transparent

**Action Buttons**:
- "Cancel": Text button, gray or purple text, no background
- "Create"/"Save":
  - Height: ~48px
  - Border radius: 24px (pill-shaped)
  - Background: Purple/indigo (#6200EE or similar)
  - Text: White, medium weight
  - Padding: 24-32px horizontal

**Validation**:
- If status = NO_GUN, restriction dropdown is required (disable Create/Save button if not selected)
- Optional details checkboxes are always optional
- All other fields optional

### Theme & Colors

**Material Design** with platform-adaptive widgets (Flutter):

**Color Palette** (based on screenshots):
- **Primary Purple/Indigo**: `#6200EE` or similar (buttons, selected text, checkboxes)
- **Light Purple/Lavender**: `#E8DEF8` or similar (FAB background, dialog tints)
- **Allowed Green**: `#4CAF50` or similar
- **Uncertain Yellow/Orange**: `#FFC107` or `#FFA726`
- **No Guns Red**: `#F44336` or `#E53935`
- **Text Primary**: `#000000` or `#1C1B1F` (titles)
- **Text Secondary**: `#49454F` or gray-700 (labels, descriptions)
- **Border/Outline**: `#79747E` or gray-400 (unselected states)
- **Background**: White or `#FFFBFE` (dialog background)
- **Map Dimmed Background**: Semi-transparent dark overlay when dialog open

**Typography** (Material 3 inspired):
- **Dialog Title**: 24-28px, medium/bold weight
- **POI Name**: 18-20px, medium weight, purple color
- **Section Labels**: 16px, regular weight, gray
- **Status Options**: 16-18px, medium weight
- **Button Text**: 14-16px, medium weight
- **Checkbox Labels**: 14-16px, regular weight

**Map Constants**:
- Default zoom: 15.0
- User location zoom: 16.0
- Min zoom: 5.0
- Max zoom: 20.0

**Pin Markers** (on map):
- Size: 12-16px diameter solid circles
- No border or minimal border
- Colors match status (green, yellow/orange, red)

**Border Radius**:
- Dialog: 28px top corners (bottom sheet) or 24px all corners (centered)
- Status buttons: 8-12px
- Action buttons: 24px (pill-shaped)
- Dropdown: 8-12px
- Checkboxes: 2-4px

**Spacing**:
- Dialog padding: 24px horizontal, 24-32px vertical
- Between elements: 16-24px
- Status options gap: 8-12px
- Button gap: 12-16px

**Fonts**:
- Default system font (platform-adaptive)
- San Francisco (iOS), Roboto (Android)

---

## Third-Party Integrations

### 1. MapLibre (Mapping Library)

**Purpose**: Interactive map rendering

**Package**: `maplibre_gl` (Flutter)

**Configuration**:
- Tile source: MapTiler or demo tiles
- API key: Optional (demo tiles work without key)
- Style URL: `https://api.maptiler.com/maps/streets/style.json?key={API_KEY}`

**Features Used**:
- Map rendering
- Camera control (pan, zoom, rotate)
- Location component (blue dot)
- Symbol layers (pin markers, POI labels)
- Querying features at point (tap handling)

**Pin Layer Setup**:
```dart
// Add GeoJSON source with pin features
await controller.addSource(
    "pins-source",
    GeojsonSourceProperties(data: featureCollection)
);

// Add symbol layer for pin markers
await controller.addLayer(
    "pins-source",
    "pins-layer",
    SymbolLayerProperties(
        iconImage: "pin-{color_code}",  // pin-0, pin-1, pin-2
        iconSize: 1.2,
        iconAllowOverlap: true
    )
);
```

### 2. Supabase (Backend as a Service)

**Purpose**: Authentication, database, real-time sync

**Package**: `supabase_flutter` (Flutter)

**Modules Used**:

#### Supabase Auth
- Email/password authentication
- Session management
- Token refresh
- Email confirmation

**Configuration**:
- Site URL: `https://camiloh12.github.io/ccwmap`
- Redirect URLs:
  - `com.ccwmap.app://auth/callback`
  - `https://camiloh12.github.io/ccwmap/auth/callback`
- Email template: Supabase default with custom Site URL

#### Supabase Postgrest (Database API)
- RESTful API over PostgreSQL
- Automatic CRUD endpoints
- Row Level Security enforcement
- Filtering, sorting, pagination

**Endpoints**:
- `GET /pins` - Fetch all pins
- `POST /pins` - Create pin
- `PATCH /pins?id=eq.{id}` - Update pin
- `DELETE /pins?id=eq.{id}` - Delete pin

**Filters**:
```
GET /pins?longitude=gte.-123&longitude=lte.-122&latitude=gte.37&latitude=lte.38
```

#### Supabase Realtime (Optional)
- WebSocket-based live updates
- Subscribe to table changes (INSERT, UPDATE, DELETE)
- Broadcast messages

**Subscription**:
```dart
supabase.channel('pins')
    .on(RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'pins'),
        (payload, [ref]) {
            // Handle INSERT/UPDATE/DELETE
        })
    .subscribe();
```

### 3. Overpass API (OpenStreetMap POI Data)

**Purpose**: Fetch points of interest for map labels

**API**: `https://overpass-api.de/api/interpreter`

**Query Language**: Overpass QL

**Example Query**:
```
[out:json][timeout:25];
(
  node["amenity"]({{bbox}});
  node["tourism"]({{bbox}});
  node["leisure"]({{bbox}});
  way["amenity"]({{bbox}});
  way["tourism"]({{bbox}});
);
out center;
```

**Rate Limiting**:
- 2 requests per second
- Consider caching to reduce API calls

**Response Handling**:
- Parse JSON response
- Extract name, type, coordinates
- Cache for 30 minutes
- Fallback to cache if API throttled

### 4. Location Services

**Purpose**: Access device location

**Package**: `geolocator` (Flutter)

**Features**:
- High accuracy location (GPS + network)
- Location updates (continuous)
- Permission handling

**Configuration**:
- Update interval: 10 seconds
- Min update interval: 5 seconds
- Priority: High accuracy (GPS + network)

---

## Database Schema

### Local Database (SQLite via Drift or sqflite)

#### Table: `pins`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `name` | TEXT | NOT NULL | POI name |
| `longitude` | REAL | NOT NULL | Longitude |
| `latitude` | REAL | NOT NULL | Latitude |
| `status` | INTEGER | NOT NULL | 0=ALLOWED, 1=UNCERTAIN, 2=NO_GUN |
| `restriction_tag` | TEXT | NULLABLE | Enum name (e.g., "FEDERAL_PROPERTY") |
| `has_security_screening` | INTEGER | NOT NULL DEFAULT 0 | Boolean (0/1) |
| `has_posted_signage` | INTEGER | NOT NULL DEFAULT 0 | Boolean (0/1) |
| `photo_uri` | TEXT | NULLABLE | Photo URL (future) |
| `notes` | TEXT | NULLABLE | User notes (future) |
| `votes` | INTEGER | NOT NULL DEFAULT 0 | Vote count (future) |
| `created_by` | TEXT | NULLABLE | User ID |
| `created_at` | INTEGER | NOT NULL | Epoch milliseconds |
| `last_modified` | INTEGER | NOT NULL | Epoch milliseconds |

**Indexes**:
- `idx_pins_status` on `status`
- `idx_pins_created_at` on `created_at DESC`
- `idx_pins_last_modified` on `last_modified DESC`

#### Table: `sync_queue`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | UUID |
| `pin_id` | TEXT | NOT NULL | Pin ID to sync |
| `operation_type` | TEXT | NOT NULL | CREATE, UPDATE, DELETE |
| `timestamp` | INTEGER | NOT NULL | Queue time (epoch millis) |
| `retry_count` | INTEGER | NOT NULL DEFAULT 0 | Number of attempts |
| `last_error` | TEXT | NULLABLE | Error message from last failure |

**Indexes**:
- `idx_sync_queue_pin_id` on `pin_id`

### Remote Database (Supabase PostgreSQL)

#### Table: `pins`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Pin ID |
| `name` | TEXT | NOT NULL | POI name |
| `longitude` | DOUBLE PRECISION | NOT NULL | Longitude |
| `latitude` | DOUBLE PRECISION | NOT NULL | Latitude |
| `location` | GEOGRAPHY(POINT, 4326) | GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)) STORED | PostGIS geography column |
| `status` | INTEGER | NOT NULL CHECK (status IN (0, 1, 2)) | Pin status |
| `restriction_tag` | restriction_tag_type | NULLABLE | Enum type (see below) |
| `has_security_screening` | BOOLEAN | NOT NULL DEFAULT false | Enforcement detail |
| `has_posted_signage` | BOOLEAN | NOT NULL DEFAULT false | Enforcement detail |
| `photo_uri` | TEXT | NULLABLE | Photo URL |
| `notes` | TEXT | NULLABLE | User notes |
| `votes` | INTEGER | DEFAULT 0 | Vote count |
| `created_by` | UUID | REFERENCES auth.users(id) ON DELETE SET NULL | User ID |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() NOT NULL | Creation timestamp |
| `last_modified` | TIMESTAMPTZ | DEFAULT NOW() NOT NULL | Last modification timestamp |

**Indexes**:
- `idx_pins_status` on `status`
- `idx_pins_restriction_tag` on `restriction_tag`
- `idx_pins_created_by` on `created_by`
- `idx_pins_created_at` on `created_at DESC`
- `idx_pins_last_modified` on `last_modified DESC`
- `idx_pins_location` (GIST index) on `location` (for geographic queries)

**Constraints**:
- `check_red_pin_has_tag`: Ensures `status = 2` pins have a `restriction_tag`

#### Enum: `restriction_tag_type`

```sql
CREATE TYPE restriction_tag_type AS ENUM (
    'FEDERAL_PROPERTY',
    'AIRPORT_SECURE',
    'STATE_LOCAL_GOVT',
    'SCHOOL_K12',
    'COLLEGE_UNIVERSITY',
    'BAR_ALCOHOL',
    'HEALTHCARE',
    'PLACE_OF_WORSHIP',
    'SPORTS_ENTERTAINMENT',
    'PRIVATE_PROPERTY'
);
```

#### Trigger: Auto-update `last_modified`

```sql
CREATE OR REPLACE FUNCTION update_last_modified()
RETURNS TRIGGER AS $$
BEGIN
  NEW.last_modified = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = '';

CREATE TRIGGER set_last_modified
  BEFORE UPDATE ON pins
  FOR EACH ROW
  EXECUTE FUNCTION update_last_modified();
```

#### Row Level Security (RLS) Policies

```sql
-- Enable RLS
ALTER TABLE pins ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can read pins
CREATE POLICY "Pins are viewable by everyone"
  ON pins FOR SELECT
  USING (true);

-- Policy: Authenticated users can insert pins (must match their user ID)
CREATE POLICY "Authenticated users can insert pins"
  ON pins FOR INSERT
  WITH CHECK (auth.uid() = created_by);

-- Policy: Authenticated users can update any pin (crowd-sourced corrections)
CREATE POLICY "Users can update any pin"
  ON pins FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

-- Policy: Users can only delete their own pins
CREATE POLICY "Users can delete own pins"
  ON pins FOR DELETE
  USING (auth.uid() = created_by);
```

---

## Configuration & Setup

### Environment Variables / Build Config

**Flutter (.env file)**:
```properties
# MapTiler (optional - demo tiles work without it)
MAPTILER_API_KEY=get_from_maptiler.com

# Supabase (required)
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Supabase Setup Steps

1. **Create Supabase Project**:
   - Go to https://supabase.com/dashboard
   - Click "New Project"
   - Name: CarryZoneMap
   - Region: Choose closest to users
   - Database password: Save securely

2. **Run Database Migrations**:
   - Go to SQL Editor in Supabase dashboard
   - Execute `001_initial_schema.sql`
   - Execute `002_add_poi_name_to_pins.sql`
   - Execute `003_add_restriction_tags.sql`

3. **Get API Credentials**:
   - Settings → API
   - Copy Project URL
   - Copy anon public key

4. **Configure Authentication**:
   - Authentication → URL Configuration
   - Site URL: `https://camiloh12.github.io/ccwmap` (or your domain)
   - Redirect URLs:
     - `com.ccwmap.app://auth/callback`
     - `https://camiloh12.github.io/ccwmap/auth/callback`

5. **Enable PostGIS** (should be done by migration):
   - Database → Extensions
   - Enable `postgis`

6. **Optional: Enable Realtime**:
   - Database → Replication
   - Enable replication for `pins` table
   - Note: Requires paid plan ($10/mo)

### MapTiler Setup (Optional)

1. Go to https://www.maptiler.com/
2. Create free account
3. Create API key
4. Add to `local.properties` / `.env`

**Note**: App works with demo tiles if no key provided.

### GitHub Pages Fallback (Email Confirmation)

**Setup**:
1. Enable GitHub Pages for repository
2. Create `auth/callback.html` with fallback UI:
   ```html
   <html>
     <body>
       <h1>Email Confirmed!</h1>
       <p>Please open this link on your mobile device to complete sign-in.</p>
       <p>If you're on mobile, the app should open automatically.</p>
     </body>
   </html>
   ```

### Platform-Specific Configuration

**Android (AndroidManifest.xml)**:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- Deep link intent filters -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https"
          android:host="camiloh12.github.io"
          android:pathPrefix="/ccwmap/auth/callback" />
</intent-filter>
```

**iOS (Info.plist)**:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs access to your location to show nearby carry zones on the map.</string>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.ccwmap.app</string>
        </array>
    </dict>
</array>

<key>FlutterDeepLinkingEnabled</key>
<true/>
```

---

## Testing Strategy

### Unit Tests

**Domain Layer**:
- Test all domain model methods (e.g., `Pin.withNextStatus()`)
- Test value object validation (e.g., `Location` coordinate bounds)
- Test enum methods (e.g., `PinStatus.next()`, `RestrictionTag.fromString()`)

**Data Layer**:
- Test mappers (Entity ↔ Domain, DTO ↔ Domain)
- Test repository with fake DAOs and SyncManager
- Test SyncManager logic (upload, download, conflict resolution)
- Test network monitor (simulate online/offline)

**Presentation Layer**:
- Test ViewModels with fake repositories
- Verify state updates on user actions
- Test validation logic (e.g., US boundary check)
- Test dialog state transitions

**Example Test (MapViewModel)**:
```dart
test('creating pin updates state correctly', () async {
    final fakeRepo = FakePinRepository();
    final viewModel = MapViewModel(fakeRepo, ...);

    viewModel.showCreatePinDialog("Starbucks", -122.0, 37.0);
    viewModel.onDialogStatusSelected(PinStatus.NO_GUN);
    viewModel.onDialogRestrictionTagSelected(RestrictionTag.PRIVATE_PROPERTY);
    viewModel.confirmPinDialog();

    final state = await viewModel.uiState.first;
    expect(state.pins.length, 1);
    expect(state.pins[0].name, "Starbucks");
    expect(state.pins[0].status, PinStatus.NO_GUN);
});
```

### Integration Tests

- Test database migrations
- Test Supabase API calls with test project
- Test sync flow end-to-end (local → remote → local)
- Test authentication flow (sign up, confirm, sign in, sign out)

### UI Tests

**Flutter Widget Tests**:
- Test LoginScreen (sign up, sign in, validation)
- Test MapScreen (map loads, pins render)
- Test PinDialog (create, edit, validation)

**Example UI Test**:
```dart
testWidgets('clicking poi shows create dialog', (tester) async {
    await tester.pumpWidget(MapScreen(viewModel: viewModel));

    // Simulate map click on POI
    viewModel.showCreatePinDialog("Test POI", -122.0, 37.0);
    await tester.pump();

    // Verify dialog shown
    expect(find.text("Create Pin: Test POI"), findsOneWidget);
    expect(find.text("Allowed"), findsOneWidget);
});
```

### Test Coverage Goals

- **Domain models**: 100% (pure logic, easy to test)
- **Mappers**: 100% (critical for data consistency)
- **Repositories**: 90%+ (core business logic)
- **ViewModels**: 80%+ (user interactions)
- **UI**: 50%+ (smoke tests for critical flows)

---

## Build & Deployment

### Build Types

**Debug**:
- Debuggable
- No code obfuscation
- Logging enabled
- Fast build time with hot reload

**Release**:
- Code obfuscation
- Logging disabled
- Optimized APK/IPA size
- Signed with release key

### Flutter Build Commands

```bash
# Debug builds
flutter run  # Hot reload during development

# Release APK (Android)
flutter build apk --release

# Release App Bundle (Android)
flutter build appbundle --release

# Release IPA (iOS)
flutter build ios --release

# Run tests
flutter test
```

### Code Quality Tools

**Flutter**:
- **Dart analyzer**: `flutter analyze`
- **Dart formatter**: `dart format .`
- **Coverage**: `flutter test --coverage`
- **Linting**: Use `flutter_lints` or `very_good_analysis` package

### CI/CD Pipeline (GitHub Actions)

**Triggers**:
- Pull requests to `develop` branch
- Pull requests to `master` branch
- Push to `master` (production deployment)

**Jobs**:
1. **Build**: Compile app (debug + release)
2. **Test**: Run all unit tests
3. **Lint**: Run Detekt/KtLint or Dart analyzer
4. **Deploy** (master only): Upload to Google Play / App Store

**Example Workflow** (.github/workflows/ci.yml):
```yaml
name: CI/CD

on:
  pull_request:
    branches: [develop, master]
  push:
    branches: [master]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --release
      - run: flutter build appbundle --release

  deploy:
    if: github.ref == 'refs/heads/master'
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: flutter build appbundle --release
      - uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.SERVICE_ACCOUNT_JSON }}
          packageName: com.ccwmap.app
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: production
```

### Release Process (Git Flow)

1. **Feature Development**:
   ```bash
   git checkout develop
   git checkout -b feature/new-feature
   # Make changes
   git commit -m "feat: Add new feature"
   git push origin feature/new-feature
   # Create PR to develop
   ```

2. **Integration** (develop branch):
   - Merge feature branches via PRs
   - CI runs tests and checks
   - Manual testing on develop

3. **Release Preparation**:
   ```bash
   git checkout develop
   git checkout -b release/v1.0.0
   # Update version numbers
   # Update CHANGELOG.md
   git commit -m "chore: Prepare v1.0.0"
   git push origin release/v1.0.0
   ```

4. **Production Deployment**:
   ```bash
   # Merge release to master
   git checkout master
   git merge release/v1.0.0
   git tag v1.0.0
   git push origin master --tags

   # Merge release back to develop
   git checkout develop
   git merge release/v1.0.0
   git push origin develop

   # Delete release branch
   git branch -d release/v1.0.0
   ```

5. **Automated Deployment**:
   - GitHub Actions detects push to master
   - Runs CI checks
   - Builds release bundle
   - Uploads to Google Play / App Store
   - Creates GitHub release with APK/IPA

### Version Numbering

**Semantic Versioning**: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (e.g., 1.0.0 → 2.0.0)
- **MINOR**: New features (e.g., 1.0.0 → 1.1.0)
- **PATCH**: Bug fixes (e.g., 1.0.0 → 1.0.1)

**Flutter** (pubspec.yaml):
```yaml
version: 1.0.0+1  # version+buildNumber
```

---

## Appendix

### API Endpoints Reference

**Supabase Postgrest**:

```
GET    /pins                     # Fetch all pins
GET    /pins?id=eq.{uuid}        # Fetch pin by ID
POST   /pins                     # Create pin
PATCH  /pins?id=eq.{uuid}        # Update pin
DELETE /pins?id=eq.{uuid}        # Delete pin

# Geographic query (bounding box)
GET /pins?longitude=gte.{west}&longitude=lte.{east}&latitude=gte.{south}&latitude=lte.{north}

# Filter by status
GET /pins?status=eq.2  # Only red (NO_GUN) pins

# Order by timestamp
GET /pins?order=last_modified.desc
```

**Supabase Auth**:

```
POST /auth/v1/signup           # Sign up with email
POST /auth/v1/token?grant_type=password  # Sign in
POST /auth/v1/logout           # Sign out
POST /auth/v1/token?grant_type=refresh_token  # Refresh token
```

### Database Migration Files

**001_initial_schema.sql**: Creates `pins` table with PostGIS, RLS policies, indexes

**002_add_poi_name_to_pins.sql**: Adds `name` column for POI names

**003_add_restriction_tags.sql**: Adds `restriction_tag`, `has_security_screening`, `has_posted_signage` columns, creates enum type, adds constraint

### US Boundary Coordinates

**Continental US Bounding Box**:
- **Min Latitude**: 24.396308 (Key West, FL)
- **Max Latitude**: 49.384358 (Northwest Angle, MN)
- **Min Longitude**: -125.0 (Cape Alava, WA)
- **Max Longitude**: -66.93457 (West Quoddy Head, ME)

**Excluded** (for simplicity):
- Alaska
- Hawaii
- US territories (Puerto Rico, Guam, etc.)

### Key Dependencies (Flutter)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State management
  provider: ^6.1.0

  # Database
  drift: ^2.16.0  # Or sqflite

  # Supabase
  supabase_flutter: ^2.3.0

  # Map
  maplibre_gl: ^0.20.0

  # Location
  geolocator: ^11.0.0

  # Network
  connectivity_plus: ^5.0.0

  # Storage
  shared_preferences: ^2.2.0
  flutter_secure_storage: ^9.0.0

  # Background tasks
  workmanager: ^0.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.0
  integration_test:
    sdk: flutter
```

---

## Summary

This functional specification captures all the requirements, architecture, and implementation details of the CarryZoneMap Android application. It can be used as a comprehensive reference to:

1. **Rebuild the app in Flutter/Dart** for cross-platform Android/iOS deployment
2. **Onboard new developers** to the project
3. **Document product requirements** for stakeholders
4. **Guide testing efforts** with detailed user flows and edge cases
5. **Plan future enhancements** based on the existing foundation

**Key Takeaways**:

- **Clean Architecture** ensures maintainability and testability
- **Offline-first** provides excellent UX regardless of connectivity
- **Queue-based sync** with retry logic guarantees data consistency
- **Last-write-wins** conflict resolution is simple and effective
- **Supabase** provides robust backend with minimal setup
- **MapLibre** offers open-source mapping without API key requirements
- **Comprehensive testing** (98 tests) validates business logic

**Iterative Implementation Plan for Flutter**:

This plan follows an iterative approach, prioritizing early visual feedback with MapLibre integration before implementing complex data management features.

### Iteration 1: Project Setup & Basic Map Display
**Goal**: Get a basic map showing on screen

1. **Initialize Flutter project**
   - Create new Flutter project with proper package naming (`com.ccwmap.app`)
   - Set up folder structure following Clean Architecture (lib/domain, lib/data, lib/presentation)
   - Configure platform-specific files (AndroidManifest.xml, Info.plist)
   - Add initial dependencies to pubspec.yaml

2. **Integrate MapLibre GL**
   - Add `maplibre_gl` package
   - Create basic MapScreen widget with MapLibre map controller
   - Configure map style (use demo tiles initially, no API key required)
   - Implement basic map controls (pan, zoom, rotate)
   - Add "CCW Map" title overlay in top-left corner
   - Test on both Android and iOS

3. **Add basic UI chrome**
   - Add exit/sign out icon placeholder in top-right
   - Add re-center FAB button in bottom-right (purple/lavender styling)
   - Implement basic navigation structure

**Deliverable**: App shows interactive map with basic UI overlay

### Iteration 2: Location Services
**Goal**: Show user's current location on the map

4. **Implement location services**
   - Add `geolocator` package
   - Request location permissions (platform-specific)
   - Get current location and display on map
   - Add blue dot/indicator for user location
   - Implement re-center FAB functionality to move map to user location
   - Handle permission denied scenarios gracefully

**Deliverable**: Map shows user's location and can re-center to it

### Iteration 3: Domain Models & Local Database
**Goal**: Set up data foundation without sync

5. **Create domain models**
   - Implement Pin model with all fields (id, name, location, status, etc.)
   - Implement PinStatus enum (ALLOWED, UNCERTAIN, NO_GUN)
   - Implement RestrictionTag enum with all categories
   - Implement Location value object with validation
   - Implement PinMetadata model
   - Write unit tests for domain models

6. **Set up local database**
   - Add Drift or sqflite package
   - Create database schema for `pins` table
   - Create database schema for `sync_queue` table
   - Implement DAO (Data Access Object) for pins
   - Write database migration scripts
   - Test database CRUD operations

**Deliverable**: Domain models defined and local database operational

### Iteration 4: Display Static Pins on Map
**Goal**: Show hardcoded/sample pins on the map

7. **Implement pin visualization**
   - Create sample pins in local database
   - Implement repository interface (return hard-coded data initially)
   - Add GeoJSON layer to MapLibre for pins
   - Render pins as colored circles (green, yellow, red)
   - Test different pin statuses and colors
   - Implement basic tap detection on map

**Deliverable**: Map displays colored pin markers

### Iteration 5: Authentication
**Goal**: User can sign up, sign in, and sign out

8. **Integrate Supabase Auth**
   - Add `supabase_flutter` package
   - Configure Supabase project and credentials (.env file)
   - Create LoginScreen UI matching design specs
   - Implement sign up flow with email confirmation
   - Implement sign in flow
   - Implement sign out functionality
   - Set up deep linking for email confirmation
   - Add session persistence with `flutter_secure_storage`
   - Implement auth state management (Provider or similar)

9. **Add auth navigation**
   - Show LoginScreen when unauthenticated
   - Show MapScreen when authenticated
   - Add sign out button to map screen
   - Test auth flows end-to-end

**Deliverable**: Complete authentication system with persistent sessions

### Iteration 6: Create & Edit Pin Dialogs (UI Only)
**Goal**: Build pin creation/editing UI without actual data persistence

10. **Build PinDialog widget**
    - Create reusable PinDialog component
    - Implement Create mode UI (screenshot-2.png reference)
    - Implement Edit mode UI (screenshot-3.png reference)
    - Implement restriction dropdown and optional details (screenshot-4.png)
    - Style all components to match design (status buttons, dropdown, checkboxes)
    - Add validation (require restriction tag when "No Guns" selected)
    - Wire up state management within dialog
    - Show/hide dialog on map taps (dummy data for now)

**Deliverable**: Fully styled, interactive pin dialogs (not saving data yet)

### Iteration 7: Pin Creation & Editing (Local Only)
**Goal**: Actually create and edit pins, stored locally

11. **Implement repository pattern**
    - Create PinRepository interface in domain layer
    - Create PinRepositoryImpl in data layer
    - Implement local-only CRUD operations (no sync yet)
    - Use Stream to expose pins from database
    - Implement MapViewModel with pin creation/editing logic

12. **Wire up pin functionality**
    - Implement POI tap detection (use Overpass API or map features)
    - Show Create dialog with POI name on map tap
    - Save new pins to local database
    - Update map to show newly created pins
    - Implement Edit dialog on existing pin tap
    - Update pins in database on edit
    - Implement delete functionality
    - Add US boundary validation

**Deliverable**: Users can create, edit, and delete pins (stored locally only)

### Iteration 8: POI Integration
**Goal**: Fetch and display points of interest from OpenStreetMap

13. **Integrate Overpass API**
    - Implement Overpass API client
    - Fetch POIs based on map viewport
    - Cache POI results (30-minute cache)
    - Display POI labels on map
    - Implement tap detection on POI labels
    - Pre-fill POI name when creating pin from POI

**Deliverable**: Map shows POI labels; tapping POI opens create dialog with name

### Iteration 9: Remote Database & Basic Sync
**Goal**: Pins sync to and from Supabase

14. **Set up Supabase backend**
    - Run database migrations on Supabase (001, 002, 003)
    - Enable PostGIS extension
    - Configure Row Level Security policies
    - Test database access from app

15. **Implement basic sync**
    - Add remote data source (Supabase Postgrest)
    - Implement upload pins to Supabase
    - Implement download pins from Supabase
    - Add sync trigger on app launch
    - Test bidirectional sync
    - Implement conflict resolution (last-write-wins)

**Deliverable**: Pins sync between local database and Supabase

### Iteration 10: Offline-First Sync Queue
**Goal**: Reliable sync that works offline

16. **Implement sync queue**
    - Create SyncQueue database table
    - Queue operations (CREATE, UPDATE, DELETE) on user actions
    - Implement SyncManager with retry logic
    - Add network monitoring with `connectivity_plus`
    - Trigger sync on network reconnection
    - Implement exponential backoff for retries

17. **Test offline scenarios**
    - Test creating pins offline
    - Test editing pins offline
    - Test sync when coming back online
    - Test conflict resolution
    - Handle failed sync gracefully

**Deliverable**: Robust offline-first sync with queue and retry logic

### Iteration 11: Background Sync
**Goal**: Automatic periodic syncing in background

18. **Add background sync**
    - Integrate `workmanager` package
    - Configure periodic sync (15 minutes)
    - Implement background sync task
    - Test background sync on both platforms
    - Add sync status indicators (optional)

**Deliverable**: App syncs automatically in background

### Iteration 12: Polish & Testing
**Goal**: Production-ready app with comprehensive tests

19. **UI polish**
    - Fine-tune all spacing, colors, fonts to match screenshots
    - Add loading states and error messages
    - Implement smooth animations/transitions
    - Add haptic feedback (optional)
    - Test on various screen sizes
    - Accessibility improvements (screen reader support, etc.)

20. **Comprehensive testing**
    - Write unit tests for all domain models
    - Write unit tests for repositories and ViewModels
    - Write widget tests for key UI flows
    - Write integration tests for auth flow
    - Write integration tests for sync flow
    - Test on real devices (Android and iOS)
    - Fix bugs and edge cases

**Deliverable**: Polished, well-tested app

### Iteration 13: CI/CD & Deployment
**Goal**: Deploy to app stores

21. **Set up CI/CD**
    - Create GitHub Actions workflow
    - Configure Flutter build pipeline
    - Add automated testing to pipeline
    - Set up code signing for iOS
    - Set up app signing for Android

22. **Deploy to stores**
    - Prepare store listings (screenshots, descriptions)
    - Submit to Google Play (internal testing first)
    - Submit to App Store (TestFlight first)
    - Gather beta tester feedback
    - Deploy to production

**Deliverable**: App available in Google Play and App Store

### Future Enhancements (Post-Launch)
- Real-time subscriptions for instant updates
- Photo upload for pins
- User notes and voting system
- Advanced filtering and search
- Heat maps for restricted areas
- Push notifications for nearby zone changes

---

**Document Version**: 1.0
**Created By**: Claude Code (AI-assisted)
**Date**: 2025-11-16
**Contact**: camilo@kyberneticlabs.com
