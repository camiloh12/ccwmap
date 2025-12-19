# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CCW Map is a mobile application that enables users to collaboratively map and share information about concealed carry weapon (CCW) zones across the United States. The app uses an offline-first architecture with cloud synchronization.

**Current Status:** Planning/specification phase - implementation not yet started
**Target Platforms:** Android and iOS (production), Web (development/testing)
**Backend:** Supabase (PostgreSQL + Auth + Realtime)

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
- RLS policies enforce: anyone read, authenticated users create/update, only creators delete
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

### Supabase (Backend)
- **Auth:** Email/password, session persistence, deep links
- **Postgrest:** RESTful API over PostgreSQL with RLS
- **Realtime:** Optional WebSocket subscriptions for live updates

### Overpass API (POI Data)
- Fetches OpenStreetMap points of interest (restaurants, schools, etc.)
- Rate limit: 2 req/second
- Caching: 30 minutes, LRU eviction (20 viewports max)

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
