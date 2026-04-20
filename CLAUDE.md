# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Environment

- **Primary machine:** Windows laptop — Flutter installed, all local commands (pub get, code generation, icon generation, etc.) run here
- **Secondary machine:** MacBook Air 2017 (macOS 12.7.6, hardware-limited) — Xcode 14.2 for certificate/provisioning profile management only; cannot run Flutter (requires macOS 14+)
- **iOS builds:** GitHub Actions only (`macos-latest` runner with Xcode 16+)

## Known Bugs (Do Not Fix Without Being Asked)

_No open bugs._

### BUG-004 (FIXED): Tapping a pin on web did not open the edit dialog
- **Platform:** Web only (Android and iOS were unaffected).
- **Original symptom:** Clicking on an existing pin on the web platform did nothing — the edit dialog never opened. This was a regression introduced by the BUG-001 fix (commit `9eb3739`), which removed the geographic-distance fallback that `_onFeatureTapped` used when the feature-id lookup missed.
- **Root cause:** On web, maplibre-gl-js does not automatically surface our GeoJSON string feature ids (UUIDs) to `onFeatureTapped` without an explicit `promoteId`. The lookup `_pins.firstWhere((p) => p.id == id)` always threw, and with no fallback the tap was dropped.
- **Fix:** Two parts in `lib/presentation/screens/map_screen.dart`.
  1. **Pixel-distance fallback restored** in `_onFeatureTapped`: when id-lookup fails, iterate all pins and pick the nearest within `_pinHitPixelThreshold` (30 px). Still honors the BUG-001 guard — taps >30 px from every pin are ignored.
  2. **`promoteId: 'id'`** added to the `addGeoJsonSource('pins-source', ...)` call so maplibre-gl-js maps our property `id` to the feature id, making the ID path work on all platforms.

### BUG-003 (FIXED): iOS did not auto-navigate to user's location on app open
- **Platform:** iOS only (Android and web were unaffected).
- **Original symptom:** On iOS cold-start the map stayed at the continental-US center. Tapping the compass FAB correctly panned to the user — so location permission and `Geolocator` were working — but the automatic initial pan did not.
- **Root cause:** `_enableLocationComponent` called `updateMyLocationTrackingMode(tracking)` → `animateCamera(userLatLng)` → `updateMyLocationTrackingMode(none)` on native. On iOS the tracking-mode animation raced with the explicit `animateCamera`, and the immediate `none` cancelled the in-flight animation before the camera settled. Android tolerated the race; web never ran these calls. Secondary issue: the work could run before the style had loaded, and `_locationComponentEnabled` was set to `true` even when the underlying calls silently no-op'd, preventing any retry.
- **Fix:** In `lib/presentation/screens/map_screen.dart`:
  1. Renamed to `_tryEnableLocationComponent` and gated on four preconditions — controller present, `_styleLoaded` true, `_currentLocation` non-null, not already enabled. Called from three places (`_onMapCreated`, `_onStyleLoadedCallback`, `_requestLocationPermission` completion); whichever satisfies the trio triggers the one-shot pan.
  2. Dropped the tracking-mode toggle entirely. `myLocationEnabled: true` on `MapLibreMap` already shows the puck on native; tracking mode is only needed for continuous follow, which this app does not do. Now just a single `animateCamera` call.
  3. On failure the flag is reset so a retry can succeed later.

### BUG-002 (FIXED): Deleted pin reappeared after screen re-render
- **Platform:** Android, iOS, web.
- **Original symptom:** Tapping delete showed "deletion successful" and the pin vanished, but after any other pin action (or re-render that triggered a sync) the deleted pin came back.
- **Root cause:** The original Supabase RLS delete policy was `USING (auth.uid() = created_by)` — only the pin's creator could delete it. Supabase Postgrest's `delete().eq('id', pinId)` does **not** throw when the RLS policy silently filters the row; it returns 200 with 0 rows affected. So deleting a pin the current user didn't create (including pins created under a previous account, or pre-auth pins stored as `'anonymous'`) looked like success on the client but the row survived on the server, and the next sync-download re-inserted it locally.
- **Fix:** Three parts.
  1. **RLS policy changed** from "only creators delete" to "any authenticated user deletes" — matches the existing UPDATE policy and the spec's crowd-sourced model. User runs in Supabase SQL editor:
     ```sql
     DROP POLICY IF EXISTS "Users can delete own pins" ON pins;
     CREATE POLICY "Authenticated users can delete any pin"
       ON pins FOR DELETE
       USING (auth.role() = 'authenticated');
     ```
     Spec updated in `FUNCTIONAL_SPEC.md` (sections 3, Data Model, and Row Level Security).
  2. **`SupabaseRemoteDataSource.deletePin`** performs a follow-up `select('id').eq('id', pinId).maybeSingle()` and throws if the row survived the delete. Belt-and-suspenders: surfaces any unexpected server rejection (network glitch, future policy changes, race where another client recreated the row) as a real error through `SyncManager`'s normal retry path.
  3. **`PinTombstones` table** (`lib/data/database/database.dart`, schema v2; DAO in `lib/data/database/pin_tombstone_dao.dart`) is kept as defense-in-depth. `SyncManager._downloadRemoteChanges` consults it alongside current queue DELETEs and just-processed IDs. With the new RLS policy, tombstones are no longer load-bearing for the primary bug, but they make offline-delete-then-sync bulletproof against mid-cycle failures.
- **Tests:** `test/data/database/database_test.dart` adds four tests for `PinTombstoneDao` (insert/retrieve, idempotent insert, isTombstoned, remove).
- **Web note:** The web build uses `DriftWebStorage.volatile()` (in-memory SQLite) per `lib/data/database/database_connection_web.dart`. Tombstones don't survive a page refresh on web. With the new RLS policy this no longer matters for correctness — the remote DELETE actually removes the row, so refresh sees a remote table without the pin — but do not rely on tombstones persisting across refreshes in the web build.

### BUG-001 (FIXED): Tapping POI label on iOS opened edit dialog instead of create dialog
- **Platform:** iOS only (Android was already working correctly).
- **Original symptom:** Tapping a POI label opened the edit dialog for the nearest existing pin — often a pin far off-screen — instead of a create-pin dialog with the POI name. If no pin was nearby, nothing happened.
- **Root cause:** `queryRenderedFeatures` on iOS does not return features from base map symbol layers (MapTiler POI labels). Because `_detectPoiAtPoint` returned null, taps fell through to PRIORITY 3 (nearest-pin proximity search), which used a meter-based threshold that expanded at low zoom levels — so distant pins matched.
- **Fix:** Two parts.
  1. **POI detection fallback (iOS):** When `queryRenderedFeatures` returns nothing on iOS, `_detectPoiAtPoint` calls MapTiler's reverse-geocoding API at the tap coordinates, filters for `place_type == "poi"`, and accepts the result only if the POI anchor is within 60 screen pixels of the tap. See `lib/data/datasources/maptiler_geocoding_client.dart` and `_reverseGeocodePoiAtPoint` in `lib/presentation/screens/map_screen.dart`.
  2. **Pixel-based pin hit detection:** `_onFeatureTapped` and the PRIORITY 3 nearest-pin branch now use `mapController.toScreenLocation` and a 30-pixel threshold (`_pinHitPixelThreshold`, `_nearPinPixelThreshold`) rather than meters. Prevents distant pins from being matched when empty space is tapped.
- **On-device debug aid:** Tap the bug icon (top-right, left of the exit button) to toggle a debug overlay showing the last tap's screen/geo coordinates and how `_detectPoiAtPoint` resolved it (QRF hit, geocode hit, fallback to nearest pin, or ignored). Gated on `kShowDebugUI` (see "CI/CD & Build Flags" below) so it ships to TestFlight but is tree-shaken out of App Store builds.
- **Known limitation:** Tapping empty space within 60 px of a POI anchor opens a create dialog for that POI. This is a strictly better failure mode than the original bug, and the user can cancel out.
- **Previous failed approach (removed):** Overpass API was used to render a custom symbol layer on iOS, but the Overpass data never loaded (`pois:0`). That code has been removed.

## CI/CD & Build Flags

### `SHOW_DEBUG_UI` compile-time flag
- **Defined in:** `lib/core/build_flags.dart` as `kShowDebugUI = !kReleaseMode || bool.fromEnvironment('SHOW_DEBUG_UI')`.
- **What it controls:** The in-app bug-icon toggle (top-right of map) and the tap-detection debug overlay. Both are invaluable for diagnosing map behavior on physical devices without a Mac + Xcode.
- **Resolution:**
  - `flutter run` (debug) or `--profile` → `true` automatically (not release mode).
  - `flutter build ... --release --dart-define=SHOW_DEBUG_UI=true` → `true`.
  - `flutter build ... --release` (no flag) → `false`. Dart's compiler tree-shakes the gated widgets out entirely — no bytecode for the debug UI ships.
- **Current workflow state:**
  - `.github/workflows/ios-testflight.yml` — **includes** `--dart-define=SHOW_DEBUG_UI=true` (manual trigger, internal TestFlight only).
  - `.github/workflows/ios.yml` — build validation only (no deployment), flag not needed.
- **TODO when wiring full production CI/CD:**
  - Any workflow that uploads to **App Store Connect for public release** (as opposed to internal TestFlight) must **OMIT** `--dart-define=SHOW_DEBUG_UI=true` so the debug UI does not ship to end users.
  - Same rule for Play Store production workflows.
  - Reasonable convention: keep the flag on `workflow_dispatch` / internal-tester workflows, omit it on any workflow triggered by a release tag or release branch merge.

## Project Overview

CCW Map is a mobile application that enables users to collaboratively map and share information about concealed carry weapon (CCW) zones across the United States. The app uses an offline-first architecture with cloud synchronization.

**Current Status:** Iteration 7 Complete - Local CRUD operations fully functional
**Target Platforms:** Android and iOS (production), Web (development/testing)
**Backend:** Supabase (PostgreSQL + Auth + Realtime)

### What's Implemented (Iterations 1-7)
- ✅ Clean Architecture setup (Domain, Data, Presentation layers)
- ✅ Local SQLite database with Drift ORM (native) + in-memory (web)
- ✅ MapLibre integration with circle-based pin markers
- ✅ Location services and user positioning
- ✅ Supabase authentication (email/password) with secure session storage
- ✅ Deep linking support for email confirmation
- ✅ Complete Pin CRUD operations (Create, Read, Update, Delete)
- ✅ US boundary validation
- ✅ Pin dialogs with color-coded status and restriction tags
- ✅ Web pin click detection (dual-detection system)
- ✅ 74/74 tests passing (100% success rate)

## Architecture

The application follows **Clean Architecture** with strict layer separation:

### Layer Dependency Rules
- **Presentation Layer** (UI, ViewModels) → depends on Domain Layer
- **Domain Layer** (Business logic, models, repository interfaces) → no external dependencies
- **Data Layer** (Repository implementations, DAOs, API clients) → depends on Domain Layer

Dependencies flow **inward only**. The Domain layer must remain pure Dart with zero framework imports.

### Key Design Patterns

**MVVM (Model-View-ViewModel):**
- Views are stateless and reactive (Flutter Widgets)
- ViewModels expose Stream and handle user events
- Models are pure domain objects with business logic

**Offline-First Pattern:**
- All writes go to local DB immediately (instant UI feedback)
- Operations queued for cloud sync in background
- Reads always from local DB (single source of truth for UI)
- SyncManager handles bidirectional sync with conflict resolution

**Repository Pattern:**
- Interfaces defined in domain layer
- Implementations in data layer coordinate local/remote sources
- Return domain models (never entities/DTOs)

**Chain of Responsibility:**
- Used for map click handling (existing pins → Overpass POIs → MapTiler POIs)
- Each detector checks if it can handle the click and delegates if not

## Data Synchronization

### Sync Architecture
- **Local DB:** Drift or sqflite (Flutter)
- **Remote DB:** Supabase PostgreSQL with PostGIS extension
- **Sync Queue:** Tracks pending CREATE/UPDATE/DELETE operations
- **Conflict Resolution:** Last-write-wins using `last_modified` timestamps
- **Retry Logic:** Max 3 attempts with exponential backoff (1s, 2s, 4s)

### Sync Flow
1. User creates/edits pin → Write to local DB immediately
2. Queue operation in `sync_queue` table
3. UI updates instantly from local DB (offline-first)
4. Background: SyncManager uploads queued operations
5. Download remote changes and merge using timestamp comparison
6. Local DB updates trigger UI refresh via Stream

## Database Schema

### Local Tables

**pins:**
- Primary key: `id` (UUID as TEXT)
- Coordinates: `latitude`, `longitude` (REAL)
- Status: `status` (INTEGER: 0=ALLOWED, 1=UNCERTAIN, 2=NO_GUN)
- Metadata: `created_by`, `created_at`, `last_modified`
- Enforcement: `restriction_tag`, `has_security_screening`, `has_posted_signage`

**sync_queue:**
- Tracks pending operations for cloud sync
- Fields: `pin_id`, `operation_type`, `timestamp`, `retry_count`, `last_error`

### Remote Database (Supabase)

- Same schema as local with PostgreSQL types (UUID, DOUBLE PRECISION, TIMESTAMPTZ)
- Additional: `location` column (PostGIS GEOGRAPHY for spatial queries)
- RLS policies enforce: anyone read, authenticated users create/update/delete (any authenticated user can delete any pin — crowd-sourced cleanup, matches the update policy)
- Automatic `last_modified` trigger on updates

## Authentication

**Provider:** Supabase Auth (email/password)

**Deep Link Schemes:**
- Custom: `com.ccwmap.app://auth/callback`
- HTTPS: `https://camiloh12.github.io/ccwmap/auth/callback`

**Email Confirmation Flow:**
- Mobile: Deep link opens app automatically
- Desktop: GitHub Pages fallback shows instructions

**Token Storage:**
- Secure storage via flutter_secure_storage package
- Auto-refresh handled by Supabase SDK

## Third-Party Integrations

### MapLibre (Mapping)
- Open-source, no API key required
- Tile source: MapTiler (optional) or demo tiles
- Features: Pan/zoom, location component, symbol layers, feature queries

**Web-Specific Behavior:**
- Circle/symbol layers block `onMapClick` events on web platform
- Solution: Dual-detection system using `onFeatureTapped` (direct clicks) + geographic distance (nearby clicks)
- See `BUILD_STATUS.md` section 2 for detailed technical explanation

### Supabase (Backend)
- **Auth:** Email/password, session persistence, deep links
- **Postgrest:** RESTful API over PostgreSQL with RLS
- **Realtime:** Optional WebSocket subscriptions for live updates

### Overpass API (POI Data) — NOT CURRENTLY USED
- Code exists in `lib/data/` but is not wired into the app
- Was previously used to fetch OpenStreetMap POIs but removed because MapTiler base map already provides POI labels
- May be re-evaluated if needed for iOS POI tap detection

## Geographic Restrictions

**US Boundary Check (Continental US only):**
- Latitude: 24.396308 to 49.384358
- Longitude: -125.0 to -66.93457
- Excludes: Alaska, Hawaii, territories

Validation occurs in ViewModel before showing create dialog AND in repository before database write.

## Domain Models

### Pin
- Immutable data class with methods: `withNextStatus()`, `withStatus()`, `withMetadata()`
- Business rule: If `status == NO_GUN`, `restrictionTag` must not be null
- All coordinates validated at construction

### PinStatus (Enum)
- ALLOWED (0, Green), UNCERTAIN (1, Yellow), NO_GUN (2, Red)
- Method: `next()` cycles through states

### RestrictionTag (Enum)
- 10 categories: FEDERAL_PROPERTY, AIRPORT_SECURE, STATE_LOCAL_GOVT, SCHOOL_K12, etc.
- Only applicable when status is NO_GUN

### Location (Value Object)
- Immutable coordinates with validation (-90 to 90 lat, -180 to 180 lng)

## Testing Strategy

### Target Coverage
- Domain models: 100% (pure logic)
- Mappers: 100% (critical for consistency)
- Repositories: 90%+
- ViewModels: 80%+
- UI: 50%+ (smoke tests)

### Test Structure
- Unit tests: Use fakes for repositories, DAOs, SyncManager
- Integration tests: Database migrations, Supabase API, end-to-end sync
- UI tests: Flutter widget tests for critical flows

## Configuration

### Environment Variables

Required in `.env` file:
```properties
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
MAPTILER_API_KEY=your_key_here  # Optional - demo tiles work without
```

### Supabase Setup Steps
1. Create project, run migrations (001, 002, 003)
2. Enable PostGIS extension
3. Configure Auth redirect URLs
4. Optional: Enable Realtime for live updates (requires paid plan)

## Code Organization

### Single Responsibility Principle

MapScreen delegates to specialized components:
- **CameraController:** Camera positioning
- **MapLayerManager:** POI layer management
- **LocationComponentManager:** Location component setup
- **FeatureClickHandler:** Click event routing
- **FeatureLayerManager:** Pin marker rendering

### Mappers

Critical for Clean Architecture:
- **Entity ↔ Domain:** Database entities to domain models
- **DTO ↔ Domain:** Supabase responses to domain models
- All mappers must be 100% tested

## Key Implementation Details

### Pin Creation Flow
1. User taps POI → FeatureClickHandler routes to OverpassPoiDetector
2. Detector extracts POI name, validates US boundary
3. MapViewModel shows dialog: `showCreatePinDialog(name, lng, lat)`
4. User selects status/tags → `confirmPinDialog()`
5. ViewModel calls `repository.addPin(pin)`
6. Repository writes to local DB + queues sync operation
7. Database emits Stream → ViewModel updates state → UI re-renders
8. Background: SyncManager uploads to Supabase

### Conflict Resolution
```dart
Future<bool> mergeRemotePin(Pin remotePin) async {
    final localPin = await pinDao.getPinById(remotePin.id);

    if (localPin == null) {
        await pinDao.insertPin(remotePin);  // New pin
        return true;
    }

    if (remotePin.metadata.lastModified > localPin.metadata.lastModified) {
        await pinDao.updatePin(remotePin);  // Remote newer
        return true;
    }

    // Local newer, keep local
    return false;
}
```

## Development Notes

- **Never store sensitive data** (API keys, tokens) in version control
- **Validate inputs** at ViewModel level before repository calls
- **Update last_modified** timestamp on every pin modification
- **Queue operations** atomically with database writes (use transactions)
- **Handle null POI names** gracefully (Overpass API sometimes returns empty names)
- **Test offline scenarios** thoroughly (airplane mode, poor connectivity)

## Future Enhancements (Documented in Spec)

- Real-time subscriptions for instant multi-device updates
- Photo upload for pins (`photo_uri` field ready)
- User notes for additional context
- Voting system for crowd-sourced accuracy (`votes` field ready)
- Advanced filtering (by restriction type, date range)
- Heat maps for high-restriction areas
