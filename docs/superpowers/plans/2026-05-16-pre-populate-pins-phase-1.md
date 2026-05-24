# Pre-Populate Pins — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing "sync every pin to every device" model with the tiered sync described in §5 of [the spec](../specs/2026-05-10-pre-populate-pins-design.md), so the app can scale to the 25–50k pilot dataset (Phase 4–6) without first-launch sync regressions on Android, iOS, or web.

**Architecture:** Split the current `SyncManager` into two cooperating components: `MyPinsSync` owns the existing offline-first flow restricted to `created_by = auth.uid()` (write queue upload + delta download of my pins + mirroring of server-side tombstones for my pins). `ViewportPinsManager` owns bbox-on-demand reads via the `get_pins_in_view` RPC (added in Phase 0's migration 008), persisting non-mine results into a "visited" cache that LRU-evicts at ~20k rows. The map screen drives `ViewportPinsManager` from a 500 ms-debounced `onCameraIdle` hook, renders individual pins through the existing layer, and renders server-side clusters through a new layer. Anonymous users see the map (bbox fetches are unauthenticated); `MyPinsSync` is a no-op for them.

**Tech Stack:** Flutter 3.41.7 / Dart 3.11.5, Drift ORM (schema v4 bump), `maplibre_gl` 0.24.1 (`onCameraIdle`, `getVisibleRegion`, `LatLngBounds`), Supabase Postgrest RPC, `shared_preferences` for the per-user `last_synced_at`.

**Out of scope (deferred):**
- Pre-populated pin data itself — Phases 2–6.
- Pin dialog UI changes for source/citation/badge — Phase 4.
- Saving/starring individual non-mine pins to force-cache them — future enhancement called out in spec §5 "Subtleties."
- Realtime subscriptions scoped to viewport — future, per spec §5.
- Persistent web SQLite (IndexedDB) — explicitly deferred in spec §scope.

---

## Pre-flight checklist (do these once, before Task 1)

These confirm Phase 0 is in the state Phase 1 depends on. They are read-only checks; no migrations or writes happen here.

- [ ] **Confirm migration 008 is applied to staging.** Open Supabase dashboard for project `miihmfhnsfmwgrvgayns` (the `ccwmap-staging` project, per memory `reference_supabase_staging.md`) → Database → Migrations and verify `008_provenance_and_view_rpc` shows applied. If not, apply it via dashboard SQL Editor by pasting `supabase/migrations/008_provenance_and_view_rpc.sql`. Production stays unmigrated for now per the deferral commit (`4cf91d6`).
- [ ] **Confirm `get_pins_in_view` exists in staging.** In staging SQL Editor:
  ```sql
  SELECT proname FROM pg_proc WHERE proname = 'get_pins_in_view';
  ```
  Expected: one row. If empty, migration 008 has not been applied — fix that first.
- [ ] **Confirm `kSystemUserId` is wired.** `grep -n kSystemUserId lib/core/system_constants.dart` should show the constant set to a real UUID, not the `REPLACE-WITH-YOUR-PRE-GENERATED-UUID` placeholder.
- [ ] **Confirm local Drift schema is at v3** so the v4 bump in Task 1 is a single-step migration: `grep schemaVersion lib/data/database/database.dart` should report `int get schemaVersion => 3;`.
- [ ] **Sanity-call the RPC from staging dashboard.** Run in staging SQL Editor:
  ```sql
  SELECT count(*) FROM get_pins_in_view(24.0, -125.0, 49.5, -66.0, 12);
  ```
  Expected: a number ≥ 0 returned without error. The whole-of-CONUS at zoom 12 will land in the density-fallback cluster branch (≤200 candidate rows in staging, but cluster cells will still come back).

---

## File map

**Create:**
- `lib/domain/models/map_item.dart` — sealed `MapItem` hierarchy (`MapItemPin` + `MapItemCluster`) returned by `get_pins_in_view`.
- `lib/data/models/get_pins_in_view_row.dart` — DTO + parser for one row of RPC output (kind discriminator + nullable fields).
- `lib/data/models/server_pin_deletion_dto.dart` — DTO for `pin_deletions` SELECT rows used by `MyPinsSync`.
- `lib/data/database/fetched_bbox_dao.dart` — DAO over the new `FetchedBboxes` table (eviction bookkeeping).
- `lib/data/database/server_pin_deletion_dao.dart` — DAO over the new `ServerPinDeletions` table (my-pin tombstones mirrored from server).
- `lib/data/sync/last_synced_at_store.dart` — thin wrapper over `SharedPreferences` for per-user `last_synced_at` and `last_deletion_synced_at` ISO timestamps.
- `lib/data/sync/my_pins_sync.dart` — full delta sync for `created_by = auth.uid()` (write queue upload + my-pins-modified-since download + my-pin-tombstones-since mirroring).
- `lib/data/sync/viewport_pins_manager.dart` — bbox fetch + cache + LRU eviction.
- `lib/data/sync/bbox_request_debouncer.dart` — 500 ms debounce with in-flight cancellation.
- Tests:
  - `test/data/database/database_v4_migration_test.dart` — Drift v3→v4 migration.
  - `test/data/database/fetched_bbox_dao_test.dart`
  - `test/data/database/server_pin_deletion_dao_test.dart`
  - `test/data/database/pin_dao_cached_test.dart` — new `cached_at`-aware methods on `PinDao`.
  - `test/data/models/get_pins_in_view_row_test.dart`
  - `test/data/sync/last_synced_at_store_test.dart`
  - `test/data/sync/my_pins_sync_test.dart`
  - `test/data/sync/viewport_pins_manager_test.dart`
  - `test/data/sync/bbox_request_debouncer_test.dart`
  - `test/presentation/viewmodels/map_viewmodel_viewport_test.dart`

**Modify:**
- `lib/data/database/database.dart` — bump `schemaVersion` to 4; add `cachedAt` column on `Pins`; add `FetchedBboxes` and `ServerPinDeletions` tables; register new DAOs; extend `onUpgrade`.
- `lib/data/database/pin_dao.dart` — add `countNonMinePins`, `evictOldestCachedNonMine`, `upsertCachedPins`, `deleteAllCachedNonMinePins`, `markAsCached` helpers; `getPinsModifiedSinceForUser` for tests/sync verification.
- `lib/data/models/supabase_pin_dto.dart` — add `source`, `confidence`, `legalCitation`, `legalCitationVerifiedDate`, `sourceExternalId` fields; refresh `fromJson`/`toJson`/`toJsonForUpdate`.
- `lib/data/mappers/supabase_pin_mapper.dart` — propagate provenance fields onto the domain `Pin` (`Pin.metadata` already carries `createdBy`; provenance lives in the entity layer for now since UI doesn't surface it until Phase 4 — see Task 2 note).
- `lib/data/mappers/pin_mapper.dart` — carry provenance fields through Pin↔PinEntity round-trip; add `toCachedEntity(Pin, DateTime cachedAt)` for bbox cache writes.
- `lib/data/datasources/remote_data_source_interface.dart` — replace `getAllPins()` with `getMyPinsModifiedSince(String userId, DateTime since)`; add `getPinsInView({required sw, ne, zoom, currentUserId})`; add `getMyPinDeletionsSince(String userId, DateTime since)`.
- `lib/data/datasources/supabase_remote_data_source.dart` — implement the three new methods; delete `getAllPins`.
- `lib/data/sync/sync_manager.dart` — **delete this file**. Its responsibilities split into `MyPinsSync` (upload queue + my-pin download) and `ViewportPinsManager` (bbox fetch).
- `lib/data/sync/background_sync.dart` — wire `MyPinsSync` instead of `SyncManager`.
- `lib/data/repositories/pin_repository_impl.dart` — accept `MyPinsSync` instead of `SyncManager`; `syncWithRemote` delegates to `MyPinsSync.sync`.
- `lib/data/repositories/supabase_auth_repository.dart` — replace `SyncManager` ctor field with `MyPinsSync` (used to clear local data on sign-out — verify the call path).
- `lib/main.dart` — DI updates: build `LastSyncedAtStore`, `MyPinsSync`, `BboxRequestDebouncer`, `ViewportPinsManager`; pass `ViewportPinsManager` to `MapViewModel`.
- `lib/presentation/viewmodels/map_viewmodel.dart` — accept `ViewportPinsManager`; expose `viewportClusters` (`ValueListenable<List<MapItemCluster>>`); add `onCameraIdle(LatLngBounds, double zoom)`; add `onAuthChanged(String? userId)` so `MyPinsSync` knows whose pins to sync.
- `lib/presentation/screens/map_screen.dart` — wire `onCameraIdle` on `MapLibreMap`; debounce + dispatch to `MapViewModel.onCameraIdle`; render cluster GeoJSON in a new `clusters-layer`; toggle pin-layer visibility against cluster presence; cluster-tap zooms into cluster cell.

**Touch (regenerate):**
- `lib/data/database/database.g.dart` — regenerated by `flutter pub run build_runner build --delete-conflicting-outputs` after the v4 schema bump.

---

## Task 1: Drift schema v4 — `cached_at`, `FetchedBboxes`, `ServerPinDeletions`

**Files:**
- Modify: `lib/data/database/database.dart`
- Touch: `lib/data/database/database.g.dart` (regenerated)
- Test: `test/data/database/database_v4_migration_test.dart`

The local DB has to track which pins are bbox-cache rows (so we can LRU-evict them) and mirror the server-side tombstones for my pins (so `MyPinsSync` can apply remote deletes locally). It also needs a `fetched_bboxes` log for eviction bookkeeping per spec §5.

- [ ] **Step 1: Write the failing migration test**

`test/data/database/database_v4_migration_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
// `hide isNull` is load-bearing — without it Drift's query helper
// `isNull` shadows the flutter_test matcher and `expect(x, isNull)` calls
// stop compiling. The analyzer can't see the directive as "using" the
// package, hence the ignore.
// ignore: unused_import
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase schemaVersion 4', () {
    test('reports schemaVersion == 4', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, 4);
    });

    test('pins table has nullable cachedAt column', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.into(db.pins).insert(
            PinsCompanion.insert(
              id: 'pin-1',
              name: 'Test',
              latitude: 30.0,
              longitude: -95.0,
              status: 0,
              createdAt: 1,
              lastModified: 1,
            ),
          );

      final row = await (db.select(db.pins)
            ..where((t) => t.id.equals('pin-1')))
          .getSingle();
      expect(row.cachedAt, isNull);
    });

    test('fetched_bboxes table exists and accepts inserts', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.into(db.fetchedBboxes).insert(
            FetchedBboxesCompanion.insert(
              swLat: 30.0,
              swLng: -95.5,
              neLat: 30.5,
              neLng: -95.0,
              zoom: 12,
              fetchedAt: 1,
              pinCount: 42,
            ),
          );

      final rows = await db.select(db.fetchedBboxes).get();
      expect(rows, hasLength(1));
      expect(rows.first.pinCount, 42);
    });

    test('server_pin_deletions table exists and accepts inserts', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await db.into(db.serverPinDeletions).insert(
            ServerPinDeletionsCompanion.insert(
              pinId: 'pin-1',
              deletedAt: 1,
            ),
          );

      final rows = await db.select(db.serverPinDeletions).get();
      expect(rows.single.pinId, 'pin-1');
    });
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/database/database_v4_migration_test.dart
```

Expected: compile error — `FetchedBboxes`/`ServerPinDeletions` types not defined; `cachedAt` not a member of `Pins`.

- [ ] **Step 3: Modify `lib/data/database/database.dart`**

Add the `cachedAt` column to `Pins`:

```dart
  /// Milliseconds since epoch — when this pin was last fetched via the
  /// bbox cache. NULL for user-created pins (the "mine" tier never evicts).
  /// Used by ViewportPinsManager for LRU eviction.
  IntColumn get cachedAt => integer().nullable()();
```

Add new tables (after the existing `PinTombstones`):

```dart
/// Log of bbox queries the client has performed.
///
/// Used for eviction bookkeeping per spec §5. Not load-bearing for
/// correctness — the LRU eviction operates on `pins.cached_at` directly.
/// This table exists to make "did I already cache this area" debugging and
/// future cache-warming heuristics tractable.
@DataClassName('FetchedBboxEntity')
class FetchedBboxes extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get swLat => real()();
  RealColumn get swLng => real()();
  RealColumn get neLat => real()();
  RealColumn get neLng => real()();
  IntColumn get zoom => integer()();
  IntColumn get fetchedAt => integer()(); // milliseconds since epoch
  IntColumn get pinCount => integer()();
}

/// Mirror of the server-side `pin_deletions` table, filtered to deletions of
/// pins the current user created (server RLS enforces that filter; we just
/// store what the SELECT returns). Consulted by MyPinsSync to apply remote
/// "another device deleted my pin" deletes locally.
///
/// Distinct from `PinTombstones`, which records *locally-initiated* deletes
/// for defense-in-depth against the bbox cache re-inserting a pin the user
/// deleted while anonymous.
@DataClassName('ServerPinDeletionEntity')
class ServerPinDeletions extends Table {
  TextColumn get pinId => text()();
  IntColumn get deletedAt => integer()(); // milliseconds since epoch

  @override
  Set<Column> get primaryKey => {pinId};
}
```

Register the new tables and DAOs in `@DriftDatabase`:

```dart
@DriftDatabase(
  tables: [Pins, SyncQueue, PinTombstones, FetchedBboxes, ServerPinDeletions],
  daos: [
    PinDao,
    SyncQueueDao,
    PinTombstoneDao,
    FetchedBboxDao,
    ServerPinDeletionDao,
  ],
)
```

Bump the version and add an `onUpgrade` branch:

```dart
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(pinTombstones);
          }
          if (from < 3) {
            await m.addColumn(pins, pins.source);
            await m.addColumn(pins, pins.sourceExternalId);
            await m.addColumn(pins, pins.sourceDatasetVersion);
            await m.addColumn(pins, pins.importedAt);
            await m.addColumn(pins, pins.userModified);
            await m.addColumn(pins, pins.confidence);
            await m.addColumn(pins, pins.legalCitation);
            await m.addColumn(pins, pins.legalCitationVerifiedDate);
            await m.addColumn(pins, pins.sourceOrphanedAt);
          }
          if (from < 4) {
            await m.addColumn(pins, pins.cachedAt);
            await m.createTable(fetchedBboxes);
            await m.createTable(serverPinDeletions);
          }
        },
      );
```

Add empty stub DAO files referenced by `daos:` so the part directive compiles. Append to `database.dart`:

```dart
part 'fetched_bbox_dao.dart';
part 'server_pin_deletion_dao.dart';
```

Then create empty placeholder files (will be filled in Tasks 8/9):

`lib/data/database/fetched_bbox_dao.dart`:
```dart
part of 'database.dart';

@DriftAccessor(tables: [FetchedBboxes])
class FetchedBboxDao extends DatabaseAccessor<AppDatabase>
    with _$FetchedBboxDaoMixin {
  FetchedBboxDao(super.db);
}
```

`lib/data/database/server_pin_deletion_dao.dart`:
```dart
part of 'database.dart';

@DriftAccessor(tables: [ServerPinDeletions])
class ServerPinDeletionDao extends DatabaseAccessor<AppDatabase>
    with _$ServerPinDeletionDaoMixin {
  ServerPinDeletionDao(super.db);
}
```

- [ ] **Step 4: Regenerate Drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: build succeeds; `lib/data/database/database.g.dart` now defines `FetchedBboxesCompanion`, `ServerPinDeletionsCompanion`, `FetchedBboxEntity`, `ServerPinDeletionEntity`, `_$FetchedBboxDaoMixin`, `_$ServerPinDeletionDaoMixin`.

- [ ] **Step 5: Run the migration test and confirm it passes**

```bash
flutter test test/data/database/database_v4_migration_test.dart
```

Expected: all four tests pass.

- [ ] **Step 6: Run the full database test suite to confirm no regressions**

```bash
flutter test test/data/database/
```

Expected: all tests pass (the v2 and v3 tests as well as the new v4 test).

- [ ] **Step 7: Commit**

```bash
git add lib/data/database/database.dart \
        lib/data/database/database.g.dart \
        lib/data/database/fetched_bbox_dao.dart \
        lib/data/database/server_pin_deletion_dao.dart \
        test/data/database/database_v4_migration_test.dart
git commit -m "feat(db): schema v4 — cached_at, fetched_bboxes, server_pin_deletions"
```

---

## Task 2: Provenance fields on `SupabasePinDto` + mappers

**Files:**
- Modify: `lib/data/models/supabase_pin_dto.dart`
- Modify: `lib/data/mappers/supabase_pin_mapper.dart`
- Modify: `lib/data/mappers/pin_mapper.dart`
- Test: `test/data/mappers/supabase_pin_mapper_test.dart` (extend existing if present, else create)
- Test: `test/data/mappers/pin_mapper_test.dart` (extend existing if present, else create)

The Phase 0 migration added provenance columns server-side; the local DB has them too. `MyPinsSync` and `ViewportPinsManager` both need to round-trip these fields cleanly so Phase 4's pin dialog can read them without a second fetch. Since the domain `Pin` doesn't surface them yet (Phase 4 will add `Pin.source`, `Pin.confidence`, `Pin.legalCitation`), we map them through `PinEntity` directly and leave `Pin.metadata` untouched.

- [ ] **Step 1: Inspect existing tests in `test/data/mappers/`**

```bash
ls test/data/mappers/
```

Confirm whether `pin_mapper_test.dart` and `supabase_pin_mapper_test.dart` already exist. If they do, extend them; if not, create them following the pattern in `test/data/mappers/sync_operation_mapper_test.dart`.

- [ ] **Step 2: Write the failing test for SupabasePinDto round-trip with provenance**

Append to (or create) `test/data/mappers/supabase_pin_mapper_test.dart`:

```dart
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupabasePinDto provenance round-trip', () {
    test('fromJson reads source/confidence/legal_citation', () {
      final dto = SupabasePinDto.fromJson({
        'id': 'pin-1',
        'name': 'Federal Courthouse',
        'latitude': 30.0,
        'longitude': -95.0,
        'status': 2,
        'restriction_tag': 'FEDERAL_PROPERTY',
        'has_security_screening': true,
        'has_posted_signage': true,
        'created_by': '81775f8b-1a6a-47d6-b793-e9ab7e38634e',
        'created_at': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
        'photo_uri': null,
        'notes': null,
        'votes': 0,
        'source': 'hifld_courts',
        'source_external_id': 'HIFLD-COURT-12345',
        'confidence': 'high',
        'legal_citation': '18 USC 930(a)',
        'legal_citation_verified_date': '2026-01-15',
      });

      expect(dto.source, 'hifld_courts');
      expect(dto.sourceExternalId, 'HIFLD-COURT-12345');
      expect(dto.confidence, 'high');
      expect(dto.legalCitation, '18 USC 930(a)');
      expect(dto.legalCitationVerifiedDate, '2026-01-15');
    });

    test('fromJson defaults source to "user" when absent', () {
      final dto = SupabasePinDto.fromJson({
        'id': 'pin-1',
        'name': 'My pin',
        'latitude': 30.0,
        'longitude': -95.0,
        'status': 0,
        'restriction_tag': null,
        'has_security_screening': false,
        'has_posted_signage': false,
        'created_by': null,
        'created_at': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
        'photo_uri': null,
        'notes': null,
        'votes': 0,
        // no source key at all — server omitted it
      });

      expect(dto.source, 'user');
      expect(dto.sourceExternalId, isNull);
      expect(dto.confidence, isNull);
    });

    test('toJsonForUpdate omits provenance fields '
         '(authenticated users have no GRANT on them)', () {
      final dto = SupabasePinDto(
        id: 'pin-1',
        name: 'x',
        latitude: 30,
        longitude: -95,
        status: 0,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        createdBy: null,
        createdAt: '2026-01-01T00:00:00Z',
        lastModified: '2026-01-01T00:00:00Z',
        photoUri: null,
        notes: null,
        votes: 0,
        source: 'osm',
        sourceExternalId: 'OSM-NODE-42',
        confidence: 'medium',
        legalCitation: 'TX Penal Code §46.035(b)(1)',
        legalCitationVerifiedDate: '2026-01-15',
      );

      final json = dto.toJsonForUpdate();
      expect(json.containsKey('source'), isFalse);
      expect(json.containsKey('source_external_id'), isFalse);
      expect(json.containsKey('confidence'), isFalse);
      expect(json.containsKey('legal_citation'), isFalse);
      expect(json.containsKey('legal_citation_verified_date'), isFalse);
    });
  });
}
```

- [ ] **Step 3: Run the test and confirm it fails**

```bash
flutter test test/data/mappers/supabase_pin_mapper_test.dart
```

Expected: fails — `SupabasePinDto` constructor lacks the new named params.

- [ ] **Step 4: Add fields to `lib/data/models/supabase_pin_dto.dart`**

Add the five new fields after `votes`:

```dart
  final String source;                       // 'user' | 'nces' | 'osm' | ...
  final String? sourceExternalId;
  final String? confidence;                  // 'high' | 'medium' | 'low'
  final String? legalCitation;
  final String? legalCitationVerifiedDate;   // ISO date string (YYYY-MM-DD)
```

Update the constructor — keep all five as named params; `source` defaults to `'user'`, the others default to null:

```dart
  const SupabasePinDto({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.restrictionTag,
    required this.hasSecurityScreening,
    required this.hasPostedSignage,
    this.createdBy,
    required this.createdAt,
    required this.lastModified,
    this.photoUri,
    this.notes,
    required this.votes,
    this.source = 'user',
    this.sourceExternalId,
    this.confidence,
    this.legalCitation,
    this.legalCitationVerifiedDate,
  });
```

Extend `fromJson`:

```dart
      source: (json['source'] as String?) ?? 'user',
      sourceExternalId: json['source_external_id'] as String?,
      confidence: json['confidence'] as String?,
      legalCitation: json['legal_citation'] as String?,
      legalCitationVerifiedDate: json['legal_citation_verified_date'] as String?,
```

Extend `toJson` (used for insert; server allows provenance on insert when service-role, no-op for clients):

```dart
      'source': source,
      'source_external_id': sourceExternalId,
      'confidence': confidence,
      'legal_citation': legalCitation,
      'legal_citation_verified_date': legalCitationVerifiedDate,
```

Do **not** extend `toJsonForUpdate` — migration 008 § 8 explicitly REVOKEs UPDATE on these from `authenticated`. Adding them to the payload would 403.

- [ ] **Step 5: Run the DTO test and confirm it passes**

```bash
flutter test test/data/mappers/supabase_pin_mapper_test.dart
```

Expected: all three tests pass.

- [ ] **Step 6: Write the failing test for PinMapper provenance round-trip**

Append to (or create) `test/data/mappers/pin_mapper_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinMapper.toCachedEntity', () {
    test('writes cachedAt and preserves provenance fields from PinEntity', () {
      final cachedAt = DateTime.utc(2026, 5, 16, 12, 0, 0);
      final pin = Pin(
        id: 'pin-1',
        name: 'Cached Pin',
        location: Location.fromLatLng(30.0, -95.0),
        status: PinStatus.uncertain,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'other-user',
          createdAt: DateTime.utc(2026, 1, 1),
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      );

      final entity = PinMapper.toCachedEntity(pin, cachedAt: cachedAt);

      expect(entity.cachedAt, cachedAt.millisecondsSinceEpoch);
      expect(entity.source, 'user'); // default; non-user only set via toEntityWithProvenance
    });
  });
}
```

- [ ] **Step 7: Run the test and confirm it fails**

```bash
flutter test test/data/mappers/pin_mapper_test.dart
```

Expected: compile error — `PinMapper.toCachedEntity` not defined.

- [ ] **Step 8: Extend `lib/data/mappers/pin_mapper.dart`**

`toEntity` needs to carry `cachedAt` through (default null). Add to the `PinEntity(...)` constructor call: `cachedAt: null`.

Add a new static method:

```dart
  /// Build a [PinEntity] for the bbox-cache flow. Sets `cachedAt` so the LRU
  /// eviction in [ViewportPinsManager] can find this row. `source` is left
  /// at the default `'user'` — Phase 1 callers should overwrite from the RPC
  /// row before insert when provenance is known.
  static PinEntity toCachedEntity(Pin pin, {required DateTime cachedAt}) {
    final base = toEntity(pin);
    return base.copyWith(cachedAt: Value(cachedAt.millisecondsSinceEpoch));
  }
```

Note: `copyWith` with a nullable `Value<...>` lift requires `import 'package:drift/drift.dart' show Value;`. Add that import.

- [ ] **Step 9: Run the mapper test and confirm it passes**

```bash
flutter test test/data/mappers/pin_mapper_test.dart
```

Expected: pass.

- [ ] **Step 10: Run the full mapper suite and the database suite**

```bash
flutter test test/data/mappers/ test/data/database/
```

Expected: all green.

- [ ] **Step 11: Commit**

```bash
git add lib/data/models/supabase_pin_dto.dart \
        lib/data/mappers/supabase_pin_mapper.dart \
        lib/data/mappers/pin_mapper.dart \
        test/data/mappers/supabase_pin_mapper_test.dart \
        test/data/mappers/pin_mapper_test.dart
git commit -m "feat(mappers): carry provenance + cachedAt through DTO/entity round-trip"
```

---

## Task 3: `MapItem` domain model + `GetPinsInViewRow` DTO

**Files:**
- Create: `lib/domain/models/map_item.dart`
- Create: `lib/data/models/get_pins_in_view_row.dart`
- Test: `test/domain/models/map_item_test.dart`
- Test: `test/data/models/get_pins_in_view_row_test.dart`

The RPC returns heterogeneous rows (`kind = 'pin'` vs `kind = 'cluster'`). A sealed `MapItem` hierarchy keeps the call sites type-safe without checking nullable fields manually.

- [ ] **Step 1: Write the failing test for MapItem**

`test/domain/models/map_item_test.dart`:

```dart
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapItem', () {
    test('MapItemPin wraps a Pin', () {
      final pin = Pin(
        id: 'p1',
        name: 'x',
        location: Location.fromLatLng(30, -95),
        status: PinStatus.allowed,
        restrictionTag: null,
        hasSecurityScreening: false,
        hasPostedSignage: false,
        metadata: PinMetadata(
          createdBy: 'me',
          createdAt: DateTime.utc(2026, 1, 1),
          lastModified: DateTime.utc(2026, 1, 1),
        ),
      );
      final item = MapItemPin(pin);
      expect(item.pin, same(pin));
    });

    test('MapItemCluster carries centroid + count + dominant tags', () {
      const cluster = MapItemCluster(
        centroidLat: 30.5,
        centroidLng: -95.25,
        count: 42,
        dominantStatus: PinStatus.noGun,
        dominantRestrictionTag: RestrictionTag.SCHOOL_K12,
      );
      expect(cluster.count, 42);
      expect(cluster.dominantStatus, PinStatus.noGun);
      expect(cluster.dominantRestrictionTag, RestrictionTag.SCHOOL_K12);
    });
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/domain/models/map_item_test.dart
```

Expected: missing-file error.

- [ ] **Step 3: Create `lib/domain/models/map_item.dart`**

```dart
import 'pin.dart';
import 'pin_status.dart';
import 'restriction_tag.dart';

/// A single result row from `get_pins_in_view`. Either an individual pin
/// (street-level zoom) or a server-side cluster (regional/national zoom).
sealed class MapItem {
  const MapItem();
}

/// Individual pin — the client persists the wrapped [Pin] to the local
/// bbox cache.
class MapItemPin extends MapItem {
  final Pin pin;
  const MapItemPin(this.pin);
}

/// Server-aggregated cluster — never persisted to local DB. Rendered as a
/// numbered circle by the map layer. Tapping zooms into the cluster's cell.
class MapItemCluster extends MapItem {
  final double centroidLat;
  final double centroidLng;
  final int count;
  final PinStatus dominantStatus;
  final RestrictionTag? dominantRestrictionTag;

  const MapItemCluster({
    required this.centroidLat,
    required this.centroidLng,
    required this.count,
    required this.dominantStatus,
    required this.dominantRestrictionTag,
  });
}
```

- [ ] **Step 4: Run the MapItem test and confirm it passes**

```bash
flutter test test/domain/models/map_item_test.dart
```

Expected: pass.

- [ ] **Step 5: Write the failing test for GetPinsInViewRow**

`test/data/models/get_pins_in_view_row_test.dart`:

```dart
import 'package:ccwmap/data/models/get_pins_in_view_row.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GetPinsInViewRow.parse', () {
    test('parses a pin row into MapItemPin with provenance', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'pin',
        'pin_id': 'pin-1',
        'latitude': 30.0,
        'longitude': -95.0,
        'name': 'Federal Courthouse',
        'status': 2,
        'restriction_tag': 'FEDERAL_PROPERTY',
        'has_security_screening': true,
        'has_posted_signage': true,
        'created_by': '81775f8b-1a6a-47d6-b793-e9ab7e38634e',
        'created_at': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-01T00:00:00Z',
        'source': 'hifld_courts',
        'source_external_id': 'HIFLD-COURT-12345',
        'confidence': 'high',
        'legal_citation': '18 USC 930(a)',
        'legal_citation_verified_date': '2026-01-15',
        'cluster_count': null,
        'dominant_status': null,
        'dominant_restriction_tag': null,
      });

      expect(item, isA<MapItemPin>());
      final mip = item as MapItemPin;
      expect(mip.pin.id, 'pin-1');
      expect(mip.pin.status, PinStatus.noGun);
      expect(mip.pin.restrictionTag, RestrictionTag.FEDERAL_PROPERTY);
    });

    test('parses a cluster row into MapItemCluster', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'cluster',
        'pin_id': null,
        'latitude': 30.5,
        'longitude': -95.25,
        'name': null,
        'status': null,
        'restriction_tag': null,
        'has_security_screening': null,
        'has_posted_signage': null,
        'created_by': null,
        'created_at': null,
        'last_modified': null,
        'source': null,
        'source_external_id': null,
        'confidence': null,
        'legal_citation': null,
        'legal_citation_verified_date': null,
        'cluster_count': 42,
        'dominant_status': 2,
        'dominant_restriction_tag': 'SCHOOL_K12',
      });

      expect(item, isA<MapItemCluster>());
      final c = item as MapItemCluster;
      expect(c.centroidLat, 30.5);
      expect(c.centroidLng, -95.25);
      expect(c.count, 42);
      expect(c.dominantStatus, PinStatus.noGun);
      expect(c.dominantRestrictionTag, RestrictionTag.SCHOOL_K12);
    });

    test('cluster row with null dominant_restriction_tag yields null', () {
      final item = GetPinsInViewRow.parse({
        'kind': 'cluster',
        'pin_id': null,
        'latitude': 30.5,
        'longitude': -95.25,
        'name': null,
        'status': null,
        'restriction_tag': null,
        'has_security_screening': null,
        'has_posted_signage': null,
        'created_by': null,
        'created_at': null,
        'last_modified': null,
        'source': null,
        'source_external_id': null,
        'confidence': null,
        'legal_citation': null,
        'legal_citation_verified_date': null,
        'cluster_count': 3,
        'dominant_status': 0,
        'dominant_restriction_tag': null,
      });

      final c = item as MapItemCluster;
      expect(c.dominantRestrictionTag, isNull);
    });

    test('throws on unknown kind', () {
      expect(
        () => GetPinsInViewRow.parse({'kind': 'meteor'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 6: Run the test and confirm it fails**

```bash
flutter test test/data/models/get_pins_in_view_row_test.dart
```

Expected: missing-file error.

- [ ] **Step 7: Create `lib/data/models/get_pins_in_view_row.dart`**

```dart
import '../../domain/models/location.dart';
import '../../domain/models/map_item.dart';
import '../../domain/models/pin.dart';
import '../../domain/models/pin_metadata.dart';
import '../../domain/models/pin_status.dart';
import '../../domain/models/restriction_tag.dart';

/// Parses one row of `get_pins_in_view` RPC output into a [MapItem].
///
/// The RPC returns a UNION-ALL of pin rows and cluster rows; the `kind`
/// column discriminates. Non-applicable columns are NULL.
class GetPinsInViewRow {
  GetPinsInViewRow._();

  static MapItem parse(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'pin':
        return MapItemPin(_parsePin(json));
      case 'cluster':
        return _parseCluster(json);
      default:
        throw FormatException('Unknown get_pins_in_view kind: $kind');
    }
  }

  static Pin _parsePin(Map<String, dynamic> j) {
    return Pin(
      id: j['pin_id'] as String,
      name: j['name'] as String,
      location: Location.fromLatLng(
        (j['latitude'] as num).toDouble(),
        (j['longitude'] as num).toDouble(),
      ),
      status: PinStatus.fromColorCode(j['status'] as int),
      restrictionTag: RestrictionTag.fromString(j['restriction_tag'] as String?),
      hasSecurityScreening: (j['has_security_screening'] as bool?) ?? false,
      hasPostedSignage: (j['has_posted_signage'] as bool?) ?? false,
      metadata: PinMetadata(
        createdBy: j['created_by'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        lastModified: DateTime.parse(j['last_modified'] as String),
      ),
    );
  }

  static MapItemCluster _parseCluster(Map<String, dynamic> j) {
    return MapItemCluster(
      centroidLat: (j['latitude'] as num).toDouble(),
      centroidLng: (j['longitude'] as num).toDouble(),
      count: j['cluster_count'] as int,
      dominantStatus: PinStatus.fromColorCode(j['dominant_status'] as int),
      dominantRestrictionTag:
          RestrictionTag.fromString(j['dominant_restriction_tag'] as String?),
    );
  }
}
```

- [ ] **Step 8: Run the GetPinsInViewRow test and confirm it passes**

```bash
flutter test test/data/models/get_pins_in_view_row_test.dart
```

Expected: all four tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/domain/models/map_item.dart \
        lib/data/models/get_pins_in_view_row.dart \
        test/domain/models/map_item_test.dart \
        test/data/models/get_pins_in_view_row_test.dart
git commit -m "feat(models): MapItem sealed hierarchy + GetPinsInViewRow parser"
```

---

## Task 4: `PinDao` cached-pin helpers

**Files:**
- Modify: `lib/data/database/pin_dao.dart`
- Test: `test/data/database/pin_dao_cached_test.dart`

`ViewportPinsManager` needs to count non-mine cached pins (for the eviction trigger), evict the oldest ones, and upsert RPC results in bulk. Hard-fallback flow (Task 17) also needs `deleteAllCachedNonMinePins`.

- [ ] **Step 1: Write the failing tests**

`test/data/database/pin_dao_cached_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  PinEntity _pin({
    required String id,
    String? createdBy,
    int? cachedAt,
  }) {
    return PinEntity(
      id: id,
      name: 'p',
      latitude: 30.0,
      longitude: -95.0,
      status: 0,
      restrictionTag: null,
      hasSecurityScreening: false,
      hasPostedSignage: false,
      createdBy: createdBy,
      createdAt: 1,
      lastModified: 1,
      photoUri: null,
      notes: null,
      votes: 0,
      source: 'user',
      userModified: false,
      cachedAt: cachedAt,
    );
  }

  group('PinDao cached-pin helpers', () {
    test('countNonMinePins excludes my pins', () async {
      await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
      await db.pinDao.insertPin(
        _pin(id: 'other-1', createdBy: 'other', cachedAt: 100),
      );
      await db.pinDao.insertPin(
        _pin(id: 'anon-cached', createdBy: null, cachedAt: 100),
      );

      final count = await db.pinDao.countNonMinePins('me');
      expect(count, 2); // other-1 and anon-cached
    });

    test('evictOldestCachedNonMine keeps my pins and newer cached entries',
        () async {
      await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
      await db.pinDao
          .insertPin(_pin(id: 'old', createdBy: 'x', cachedAt: 100));
      await db.pinDao
          .insertPin(_pin(id: 'mid', createdBy: 'x', cachedAt: 200));
      await db.pinDao
          .insertPin(_pin(id: 'new', createdBy: 'x', cachedAt: 300));

      // Cap at 2: should evict 'old' first.
      await db.pinDao.evictOldestCachedNonMine(myUserId: 'me', maxRows: 2);

      final remaining = await db.pinDao.getAllPins();
      final ids = remaining.map((p) => p.id).toSet();
      expect(ids, {'mine', 'mid', 'new'});
    });

    test('evictOldestCachedNonMine never touches pins with cachedAt = null',
        () async {
      await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
      // Pin created by another user but NOT via bbox cache (e.g. older
      // sync model leftover) — cachedAt is null. Eviction must skip it.
      await db.pinDao
          .insertPin(_pin(id: 'legacy-other', createdBy: 'x', cachedAt: null));
      await db.pinDao
          .insertPin(_pin(id: 'cached-other', createdBy: 'x', cachedAt: 100));

      await db.pinDao.evictOldestCachedNonMine(myUserId: 'me', maxRows: 1);

      final remaining = await db.pinDao.getAllPins();
      expect(
        remaining.map((p) => p.id).toSet(),
        {'mine', 'legacy-other'},
      );
    });

    test('upsertCachedPins inserts new rows and updates existing ones', () async {
      await db.pinDao
          .insertPin(_pin(id: 'existing', createdBy: 'x', cachedAt: 100));

      final updated = _pin(id: 'existing', createdBy: 'x', cachedAt: 200)
          .copyWith(name: 'updated name');
      final inserted = _pin(id: 'new', createdBy: 'x', cachedAt: 200);

      await db.pinDao.upsertCachedPins([updated, inserted]);

      final all = await db.pinDao.getAllPins();
      expect(all.length, 2);
      expect(
        all.firstWhere((p) => p.id == 'existing').name,
        'updated name',
      );
      expect(
        all.firstWhere((p) => p.id == 'existing').cachedAt,
        200,
      );
    });

    test('deleteAllCachedNonMinePins removes only cached non-mine rows',
        () async {
      await db.pinDao.insertPin(_pin(id: 'mine', createdBy: 'me'));
      await db.pinDao
          .insertPin(_pin(id: 'legacy', createdBy: 'x', cachedAt: null));
      await db.pinDao
          .insertPin(_pin(id: 'cached', createdBy: 'x', cachedAt: 100));

      await db.pinDao.deleteAllCachedNonMinePins('me');

      final remaining = await db.pinDao.getAllPins();
      expect(remaining.map((p) => p.id).toSet(), {'mine', 'legacy'});
    });
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
flutter test test/data/database/pin_dao_cached_test.dart
```

Expected: compile error — `countNonMinePins`, `evictOldestCachedNonMine`, `upsertCachedPins`, `deleteAllCachedNonMinePins` not defined.

- [ ] **Step 3: Add the helpers to `lib/data/database/pin_dao.dart`**

Append inside the class:

```dart
  /// Count pins not created by [myUserId] (anonymous-cached pins with
  /// `createdBy IS NULL` count too). Used by ViewportPinsManager to decide
  /// when to LRU-evict.
  Future<int> countNonMinePins(String myUserId) async {
    final query = selectOnly(pins)
      ..addColumns([pins.id.count()])
      ..where(pins.createdBy.equals(myUserId).not() | pins.createdBy.isNull());
    final row = await query.getSingle();
    return row.read(pins.id.count()) ?? 0;
  }

  /// Evict the oldest cached non-mine pins until row count ≤ [maxRows].
  /// Pins with `cachedAt IS NULL` are never evicted (they're not bbox-cache
  /// rows — either user-created or pre-Phase-1 legacy data).
  Future<void> evictOldestCachedNonMine({
    required String myUserId,
    required int maxRows,
  }) async {
    final excess = await countNonMinePins(myUserId) - maxRows;
    if (excess <= 0) return;

    final victims = await (select(pins)
          ..where((t) =>
              t.cachedAt.isNotNull() &
              (t.createdBy.equals(myUserId).not() | t.createdBy.isNull()))
          ..orderBy([(t) => OrderingTerm.asc(t.cachedAt)])
          ..limit(excess))
        .get();

    if (victims.isEmpty) return;

    await batch((b) {
      for (final v in victims) {
        b.deleteWhere(pins, (t) => t.id.equals(v.id));
      }
    });
  }

  /// Bulk upsert cached pins from a bbox fetch. Single transaction → single
  /// stream emission to the UI.
  Future<void> upsertCachedPins(List<PinEntity> entities) async {
    if (entities.isEmpty) return;
    await batch((b) {
      for (final e in entities) {
        b.insert(pins, e, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// Drop every cached non-mine pin. Used by the pathological-cache fallback
  /// on app start (spec §6: "if cached count > 2× soft limit, drop all
  /// created_by != me rows, rebuild via bbox").
  Future<void> deleteAllCachedNonMinePins(String myUserId) async {
    await (delete(pins)
          ..where((t) =>
              t.cachedAt.isNotNull() &
              (t.createdBy.equals(myUserId).not() | t.createdBy.isNull())))
        .go();
  }
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
flutter test test/data/database/pin_dao_cached_test.dart
```

Expected: all five tests pass.

- [ ] **Step 5: Run the full database suite**

```bash
flutter test test/data/database/
```

Expected: all green, including the v4 migration test from Task 1.

- [ ] **Step 6: Commit**

```bash
git add lib/data/database/pin_dao.dart \
        test/data/database/pin_dao_cached_test.dart
git commit -m "feat(pin_dao): cached-pin helpers (count, evict, upsert, drop)"
```

---

## Task 5: `FetchedBboxDao` + `ServerPinDeletionDao`

**Files:**
- Modify: `lib/data/database/fetched_bbox_dao.dart` (placeholder from Task 1)
- Modify: `lib/data/database/server_pin_deletion_dao.dart` (placeholder from Task 1)
- Test: `test/data/database/fetched_bbox_dao_test.dart`
- Test: `test/data/database/server_pin_deletion_dao_test.dart`

- [ ] **Step 1: Write the failing tests for FetchedBboxDao**

`test/data/database/fetched_bbox_dao_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('FetchedBboxDao', () {
    test('recordFetch inserts a row', () async {
      await db.fetchedBboxDao.recordFetch(
        swLat: 30.0,
        swLng: -95.5,
        neLat: 30.5,
        neLng: -95.0,
        zoom: 12,
        fetchedAt: DateTime.utc(2026, 5, 16, 12),
        pinCount: 42,
      );

      final rows = await db.fetchedBboxDao.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.pinCount, 42);
    });

    test('pruneOlderThan removes rows older than threshold', () async {
      await db.fetchedBboxDao.recordFetch(
        swLat: 0, swLng: 0, neLat: 1, neLng: 1, zoom: 10,
        fetchedAt: DateTime.utc(2026, 1, 1), pinCount: 1,
      );
      await db.fetchedBboxDao.recordFetch(
        swLat: 0, swLng: 0, neLat: 1, neLng: 1, zoom: 10,
        fetchedAt: DateTime.utc(2026, 5, 1), pinCount: 1,
      );

      await db.fetchedBboxDao.pruneOlderThan(DateTime.utc(2026, 3, 1));

      final rows = await db.fetchedBboxDao.getAll();
      expect(rows, hasLength(1));
      expect(
        rows.single.fetchedAt,
        DateTime.utc(2026, 5, 1).millisecondsSinceEpoch,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/database/fetched_bbox_dao_test.dart
```

Expected: compile error — `recordFetch`, `getAll`, `pruneOlderThan` not defined.

- [ ] **Step 3: Flesh out `lib/data/database/fetched_bbox_dao.dart`**

```dart
part of 'database.dart';

@DriftAccessor(tables: [FetchedBboxes])
class FetchedBboxDao extends DatabaseAccessor<AppDatabase>
    with _$FetchedBboxDaoMixin {
  FetchedBboxDao(super.db);

  Future<void> recordFetch({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required DateTime fetchedAt,
    required int pinCount,
  }) async {
    await into(fetchedBboxes).insert(
      FetchedBboxesCompanion.insert(
        swLat: swLat,
        swLng: swLng,
        neLat: neLat,
        neLng: neLng,
        zoom: zoom,
        fetchedAt: fetchedAt.millisecondsSinceEpoch,
        pinCount: pinCount,
      ),
    );
  }

  Future<List<FetchedBboxEntity>> getAll() => select(fetchedBboxes).get();

  Future<void> pruneOlderThan(DateTime threshold) async {
    await (delete(fetchedBboxes)
          ..where((t) =>
              t.fetchedAt.isSmallerThanValue(threshold.millisecondsSinceEpoch)))
        .go();
  }
}
```

- [ ] **Step 4: Run the FetchedBboxDao test and confirm it passes**

```bash
flutter test test/data/database/fetched_bbox_dao_test.dart
```

Expected: pass.

- [ ] **Step 5: Write the failing test for ServerPinDeletionDao**

`test/data/database/server_pin_deletion_dao_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('ServerPinDeletionDao', () {
    test('upsert + getPinIdsDeletedSince', () async {
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-1',
        deletedAt: DateTime.utc(2026, 5, 15),
      );
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-2',
        deletedAt: DateTime.utc(2026, 5, 16),
      );

      final ids = await db.serverPinDeletionDao
          .getPinIdsDeletedSince(DateTime.utc(2026, 5, 15, 23));

      expect(ids, {'pin-2'});
    });

    test('upsert is idempotent — re-inserting the same pin_id replaces',
        () async {
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-1',
        deletedAt: DateTime.utc(2026, 5, 15),
      );
      await db.serverPinDeletionDao.upsert(
        pinId: 'pin-1',
        deletedAt: DateTime.utc(2026, 5, 16),
      );

      final all = await db.serverPinDeletionDao.getAll();
      expect(all, hasLength(1));
      expect(
        all.single.deletedAt,
        DateTime.utc(2026, 5, 16).millisecondsSinceEpoch,
      );
    });
  });
}
```

- [ ] **Step 6: Run the test and confirm it fails**

```bash
flutter test test/data/database/server_pin_deletion_dao_test.dart
```

Expected: missing methods.

- [ ] **Step 7: Flesh out `lib/data/database/server_pin_deletion_dao.dart`**

```dart
part of 'database.dart';

@DriftAccessor(tables: [ServerPinDeletions])
class ServerPinDeletionDao extends DatabaseAccessor<AppDatabase>
    with _$ServerPinDeletionDaoMixin {
  ServerPinDeletionDao(super.db);

  Future<void> upsert({
    required String pinId,
    required DateTime deletedAt,
  }) async {
    await into(serverPinDeletions).insert(
      ServerPinDeletionEntity(
        pinId: pinId,
        deletedAt: deletedAt.millisecondsSinceEpoch,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<Set<String>> getPinIdsDeletedSince(DateTime since) async {
    final rows = await (select(serverPinDeletions)
          ..where((t) =>
              t.deletedAt.isBiggerThanValue(since.millisecondsSinceEpoch)))
        .get();
    return rows.map((r) => r.pinId).toSet();
  }

  Future<List<ServerPinDeletionEntity>> getAll() =>
      select(serverPinDeletions).get();
}
```

- [ ] **Step 8: Run the ServerPinDeletionDao test and confirm it passes**

```bash
flutter test test/data/database/server_pin_deletion_dao_test.dart
```

Expected: both tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/data/database/fetched_bbox_dao.dart \
        lib/data/database/server_pin_deletion_dao.dart \
        test/data/database/fetched_bbox_dao_test.dart \
        test/data/database/server_pin_deletion_dao_test.dart
git commit -m "feat(db): FetchedBboxDao + ServerPinDeletionDao"
```

---

## Task 6: Remote data source — replace `getAllPins` with three targeted methods

**Files:**
- Modify: `lib/data/datasources/remote_data_source_interface.dart`
- Modify: `lib/data/datasources/supabase_remote_data_source.dart`
- Create: `lib/data/models/server_pin_deletion_dto.dart`
- Test: `test/data/models/server_pin_deletion_dto_test.dart`

This is where the over-the-wire shape of the new sync model lands. The interface change forces every call-site update (`SyncManager._downloadRemoteChanges` is the only one today and gets deleted in Task 11), so we'll temporarily comment out the call site in `sync_manager.dart` to keep the project compiling between this task and Task 11. (Alternative: do Task 11 first; chosen this order because the interface change is the harder constraint.)

- [ ] **Step 1: Write the failing test for ServerPinDeletionDto**

`test/data/models/server_pin_deletion_dto_test.dart`:

```dart
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses pin_deletions SELECT row', () {
    final dto = ServerPinDeletionDto.fromJson({
      'pin_id': 'pin-1',
      'deleted_at': '2026-05-16T12:00:00Z',
      'original_created_by': 'me',
    });
    expect(dto.pinId, 'pin-1');
    expect(dto.deletedAt, DateTime.utc(2026, 5, 16, 12));
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/models/server_pin_deletion_dto_test.dart
```

Expected: missing-file error.

- [ ] **Step 3: Create `lib/data/models/server_pin_deletion_dto.dart`**

```dart
/// Read-only DTO over one row of `public.pin_deletions`. RLS restricts
/// SELECT to rows where `original_created_by = auth.uid()`, so the client
/// only ever sees its own deletions.
class ServerPinDeletionDto {
  final String pinId;
  final DateTime deletedAt;

  const ServerPinDeletionDto({required this.pinId, required this.deletedAt});

  factory ServerPinDeletionDto.fromJson(Map<String, dynamic> json) {
    return ServerPinDeletionDto(
      pinId: json['pin_id'] as String,
      deletedAt: DateTime.parse(json['deleted_at'] as String),
    );
  }
}
```

- [ ] **Step 4: Run the DTO test and confirm it passes**

```bash
flutter test test/data/models/server_pin_deletion_dto_test.dart
```

Expected: pass.

- [ ] **Step 5: Update the interface in `lib/data/datasources/remote_data_source_interface.dart`**

Replace the file:

```dart
import '../../domain/models/map_item.dart';
import '../models/server_pin_deletion_dto.dart';
import '../models/supabase_pin_dto.dart';

/// Interface for remote pin data operations.
///
/// Phase 1 splits the legacy `getAllPins` into three targeted reads:
/// - [getMyPinsModifiedSince] feeds [MyPinsSync] (auth-uid-filtered delta).
/// - [getMyPinDeletionsSince] mirrors the server tombstones for my pins.
/// - [getPinsInView] feeds [ViewportPinsManager] (bbox-on-demand reads).
abstract class RemoteDataSourceInterface {
  /// Fetch my pins last modified strictly after [since]. Pass an epoch like
  /// `DateTime.utc(1970)` for a first-ever sync.
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  });

  /// Fetch tombstones for my pins deleted strictly after [since].
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  });

  /// Fetch pins (or server-side clusters) inside the bbox. Excludes pins
  /// created by [currentUserId] (those come down via MyPinsSync). Pass
  /// `null` when unauthenticated.
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  });

  Future<void> insertPin(SupabasePinDto pin);
  Future<void> updatePin(SupabasePinDto pin);
  Future<void> deletePin(String pinId);
  Future<SupabasePinDto?> getPinById(String pinId);
}
```

- [ ] **Step 6: Update `lib/data/datasources/supabase_remote_data_source.dart`**

Delete the `getAllPins` method. Add the three new methods. Keep `insertPin`, `updatePin`, `deletePin`, `getPinById` and the agreements/moderation methods unchanged.

```dart
  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async {
    final response = await _supabase
        .from('pins')
        .select()
        .eq('created_by', userId)
        .gt('last_modified', since.toIso8601String())
        .order('last_modified', ascending: true);

    return (response as List)
        .map((j) => SupabasePinDto.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async {
    // RLS already filters this to `original_created_by = auth.uid()`,
    // so the explicit .eq() is belt-and-suspenders. Cheap; keeps the
    // query intent legible at the call site.
    final response = await _supabase
        .from('pin_deletions')
        .select('pin_id, deleted_at, original_created_by')
        .eq('original_created_by', userId)
        .gt('deleted_at', since.toIso8601String())
        .order('deleted_at', ascending: true);

    return (response as List)
        .map((j) => ServerPinDeletionDto.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required String? currentUserId,
  }) async {
    final response = await _supabase.rpc(
      'get_pins_in_view',
      params: {
        'sw_lat': swLat,
        'sw_lng': swLng,
        'ne_lat': neLat,
        'ne_lng': neLng,
        'zoom': zoom,
      },
    );

    final rows = (response as List).cast<Map<String, dynamic>>();
    return rows.map(GetPinsInViewRow.parse).toList();
  }
```

Add the imports at the top of the file:

```dart
import '../../domain/models/map_item.dart';
import '../models/get_pins_in_view_row.dart';
import '../models/server_pin_deletion_dto.dart';
```

Delete the old `getAllPins` method.

- [ ] **Step 7: Temporarily stub the broken call site in `lib/data/sync/sync_manager.dart`**

Find the call `_remoteDataSource.getAllPins()` in `_downloadRemoteChanges` and replace with a stub that returns empty (this file will be deleted entirely in Task 11; this stub just keeps the project compiling for the intervening tasks):

```dart
      // Temporarily disabled — see Phase 1 plan Task 11 (sync_manager.dart
      // is being deleted in favor of MyPinsSync + ViewportPinsManager).
      final remotePins = <SupabasePinDto>[];
```

Add the import for `SupabasePinDto` if not already present.

- [ ] **Step 8: `flutter analyze` and `flutter test` to confirm the project still compiles and existing tests still pass**

```bash
flutter analyze
flutter test
```

Expected: zero analyzer warnings tied to this change; full test suite green. The sync_manager_test (if one exists) may emit a benign warning about download being a no-op — accept it; the file is on death row.

- [ ] **Step 9: Commit**

```bash
git add lib/data/datasources/remote_data_source_interface.dart \
        lib/data/datasources/supabase_remote_data_source.dart \
        lib/data/models/server_pin_deletion_dto.dart \
        lib/data/sync/sync_manager.dart \
        test/data/models/server_pin_deletion_dto_test.dart
git commit -m "refactor(remote): replace getAllPins with three targeted reads"
```

---

## Task 7: `LastSyncedAtStore` — per-user delta watermark

**Files:**
- Create: `lib/data/sync/last_synced_at_store.dart`
- Test: `test/data/sync/last_synced_at_store_test.dart`

`MyPinsSync` does delta queries with `last_modified > {watermark}`. Storing one watermark per user means sign-out + sign-back-in doesn't replay the wrong user's deltas.

- [ ] **Step 1: Write the failing test**

`test/data/sync/last_synced_at_store_test.dart`:

```dart
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LastSyncedAtStore', () {
    test('returns epoch when no watermark recorded', () async {
      final store = await LastSyncedAtStore.create();
      final at = await store.readPinsWatermark('user-1');
      expect(at, DateTime.utc(1970));
    });

    test('round-trips the pin watermark for a specific user', () async {
      final store = await LastSyncedAtStore.create();
      final ts = DateTime.utc(2026, 5, 16, 12);

      await store.writePinsWatermark('user-1', ts);

      expect(await store.readPinsWatermark('user-1'), ts);
      // Different user keeps the default epoch.
      expect(await store.readPinsWatermark('user-2'), DateTime.utc(1970));
    });

    test('round-trips the deletion watermark separately', () async {
      final store = await LastSyncedAtStore.create();
      final pinsTs = DateTime.utc(2026, 5, 16, 12);
      final deletionsTs = DateTime.utc(2026, 5, 16, 11);

      await store.writePinsWatermark('user-1', pinsTs);
      await store.writeDeletionsWatermark('user-1', deletionsTs);

      expect(await store.readPinsWatermark('user-1'), pinsTs);
      expect(await store.readDeletionsWatermark('user-1'), deletionsTs);
    });

    test('clearForUser removes both watermarks for that user', () async {
      final store = await LastSyncedAtStore.create();
      await store.writePinsWatermark('user-1', DateTime.utc(2026));
      await store.writeDeletionsWatermark('user-1', DateTime.utc(2026));

      await store.clearForUser('user-1');

      expect(await store.readPinsWatermark('user-1'), DateTime.utc(1970));
      expect(await store.readDeletionsWatermark('user-1'), DateTime.utc(1970));
    });
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/sync/last_synced_at_store_test.dart
```

Expected: missing-file error.

- [ ] **Step 3: Create `lib/data/sync/last_synced_at_store.dart`**

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// Per-user storage for the `MyPinsSync` delta watermarks.
///
/// One key per `(user_id, kind)` pair so signing out and back into a
/// different account doesn't replay the wrong account's history.
///
/// "Pins" and "deletions" advance independently — they're separate Supabase
/// queries served from separate tables.
class LastSyncedAtStore {
  static const String _pinsPrefix = 'mypins.last_synced_at.';
  static const String _deletionsPrefix = 'mypins.deletions_last_synced_at.';

  static final DateTime _epoch = DateTime.utc(1970);

  final SharedPreferences _prefs;

  LastSyncedAtStore._(this._prefs);

  static Future<LastSyncedAtStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LastSyncedAtStore._(prefs);
  }

  Future<DateTime> readPinsWatermark(String userId) async {
    final iso = _prefs.getString('$_pinsPrefix$userId');
    return iso == null ? _epoch : DateTime.parse(iso);
  }

  Future<void> writePinsWatermark(String userId, DateTime at) =>
      _prefs.setString('$_pinsPrefix$userId', at.toUtc().toIso8601String());

  Future<DateTime> readDeletionsWatermark(String userId) async {
    final iso = _prefs.getString('$_deletionsPrefix$userId');
    return iso == null ? _epoch : DateTime.parse(iso);
  }

  Future<void> writeDeletionsWatermark(String userId, DateTime at) =>
      _prefs.setString(
          '$_deletionsPrefix$userId', at.toUtc().toIso8601String());

  Future<void> clearForUser(String userId) async {
    await _prefs.remove('$_pinsPrefix$userId');
    await _prefs.remove('$_deletionsPrefix$userId');
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
flutter test test/data/sync/last_synced_at_store_test.dart
```

Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/last_synced_at_store.dart \
        test/data/sync/last_synced_at_store_test.dart
git commit -m "feat(sync): LastSyncedAtStore — per-user delta watermarks"
```

---

## Task 8: `MyPinsSync`

**Files:**
- Create: `lib/data/sync/my_pins_sync.dart`
- Test: `test/data/sync/my_pins_sync_test.dart`

`MyPinsSync` owns the full bidirectional sync for `created_by = auth.uid()`. It absorbs queue-processing from the old `SyncManager` (write-queue upload with retry/backoff, queue optimization) and replaces the legacy "download every pin" with the delta+tombstone pair. Anonymous users → no-op.

- [ ] **Step 1: Write the failing test**

`test/data/sync/my_pins_sync_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:ccwmap/data/sync/my_pins_sync.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-test fake — no mockito to keep dependencies light. Records calls
/// so individual tests can assert on them.
class _FakeRemote implements RemoteDataSourceInterface {
  List<SupabasePinDto> pinsToReturn = [];
  List<ServerPinDeletionDto> deletionsToReturn = [];
  final List<SupabasePinDto> inserts = [];
  final List<SupabasePinDto> updates = [];
  final List<String> deletes = [];

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince({
    required String userId,
    required DateTime since,
  }) async => pinsToReturn;

  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince({
    required String userId,
    required DateTime since,
  }) async => deletionsToReturn;

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat, required double swLng,
    required double neLat, required double neLng,
    required int zoom, required String? currentUserId,
  }) async => [];

  @override
  Future<void> insertPin(SupabasePinDto pin) async => inserts.add(pin);

  @override
  Future<void> updatePin(SupabasePinDto pin) async => updates.add(pin);

  @override
  Future<void> deletePin(String id) async => deletes.add(id);

  @override
  Future<SupabasePinDto?> getPinById(String id) async => null;
}

class _AlwaysOnline implements NetworkMonitor {
  @override bool get isOnline => true;
  @override Stream<bool> get isOnlineStream => const Stream.empty();
  @override Future<void> initialize() async {}
  @override void dispose() {}
}

void main() {
  late AppDatabase db;
  late _FakeRemote remote;
  late _AlwaysOnline network;
  late LastSyncedAtStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemote();
    network = _AlwaysOnline();
    store = await LastSyncedAtStore.create();
  });

  tearDown(() async => db.close());

  MyPinsSync _build(String? userId) => MyPinsSync(
        userIdProvider: () => userId,
        syncQueueDao: db.syncQueueDao,
        pinDao: db.pinDao,
        tombstoneDao: db.pinTombstoneDao,
        serverDeletionDao: db.serverPinDeletionDao,
        remote: remote,
        networkMonitor: network,
        watermarks: store,
      );

  test('returns early no-op for anonymous user', () async {
    final sync = _build(null);
    final result = await sync.sync();
    expect(result.uploaded, 0);
    expect(result.downloaded, 0);
    expect(result.errorMessage, isNull);
  });

  test('downloads pins from the delta endpoint and writes them locally',
      () async {
    final sync = _build('me');
    final iso = DateTime.utc(2026, 5, 16).toIso8601String();
    remote.pinsToReturn = [
      SupabasePinDto(
        id: 'pin-1', name: 'mine', latitude: 30, longitude: -95,
        status: 0, restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: iso, lastModified: iso,
        photoUri: null, notes: null, votes: 0,
      ),
    ];

    final result = await sync.sync();

    expect(result.downloaded, 1);
    final row = await db.pinDao.getPinById('pin-1');
    expect(row, isNotNull);
    expect(row!.createdBy, 'me');
    // Watermark advanced to (or past) the row's lastModified.
    final w = await store.readPinsWatermark('me');
    expect(w.isAfter(DateTime.utc(2026, 5, 15)), isTrue);
  });

  test('applies server tombstones for my deleted pins', () async {
    final sync = _build('me');

    // Pre-seed a local row that will be deleted.
    await db.pinDao.insertPin(PinEntity(
      id: 'pin-doomed', name: 'x', latitude: 30, longitude: -95,
      status: 0, restrictionTag: null,
      hasSecurityScreening: false, hasPostedSignage: false,
      createdBy: 'me', createdAt: 1, lastModified: 1,
      photoUri: null, notes: null, votes: 0,
      source: 'user', userModified: true, cachedAt: null,
    ));

    remote.deletionsToReturn = [
      ServerPinDeletionDto(
        pinId: 'pin-doomed',
        deletedAt: DateTime.utc(2026, 5, 16),
      ),
    ];

    final result = await sync.sync();

    expect(result.downloaded, 0);
    expect(await db.pinDao.getPinById('pin-doomed'), isNull);
    expect(
      await db.serverPinDeletionDao.getPinIdsDeletedSince(DateTime.utc(1970)),
      contains('pin-doomed'),
    );
  });

  test('respects local tombstones — does not re-insert pin user deleted',
      () async {
    final sync = _build('me');
    await db.pinTombstoneDao
        .insertTombstone('pin-1', DateTime.utc(2026, 5, 16));

    final iso = DateTime.utc(2026, 5, 16).toIso8601String();
    remote.pinsToReturn = [
      SupabasePinDto(
        id: 'pin-1', name: 'ghost', latitude: 30, longitude: -95,
        status: 0, restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'me', createdAt: iso, lastModified: iso,
        photoUri: null, notes: null, votes: 0,
      ),
    ];

    await sync.sync();

    expect(await db.pinDao.getPinById('pin-1'), isNull);
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/sync/my_pins_sync_test.dart
```

Expected: missing-file error.

- [ ] **Step 3: Create `lib/data/sync/my_pins_sync.dart`**

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/data/mappers/supabase_pin_mapper.dart';
import 'package:ccwmap/data/mappers/sync_operation_mapper.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:ccwmap/domain/models/sync_operation.dart';
import 'package:ccwmap/domain/repositories/pin_repository.dart';

/// Bidirectional sync for `created_by = auth.uid()` pins only.
///
/// Replaces the legacy [SyncManager] in two ways:
/// 1. Download is a delta query (`last_modified > watermark`) instead of a
///    full fetch.
/// 2. Tombstones for *my* pins are mirrored from server-side `pin_deletions`
///    so cross-device deletes apply locally.
///
/// Anonymous callers (`userIdProvider() == null`) are an unconditional
/// no-op — they have no own pins to sync.
class MyPinsSync {
  static const int _maxRetries = 3;

  final String? Function() userIdProvider;
  final SyncQueueDao syncQueueDao;
  final PinDao pinDao;
  final PinTombstoneDao tombstoneDao;
  final ServerPinDeletionDao serverDeletionDao;
  final RemoteDataSourceInterface remote;
  final NetworkMonitor networkMonitor;
  final LastSyncedAtStore watermarks;

  MyPinsSync({
    required this.userIdProvider,
    required this.syncQueueDao,
    required this.pinDao,
    required this.tombstoneDao,
    required this.serverDeletionDao,
    required this.remote,
    required this.networkMonitor,
    required this.watermarks,
  });

  Future<SyncResult> sync() async {
    final userId = userIdProvider();
    if (userId == null) {
      return const SyncResult(uploaded: 0, downloaded: 0, errors: 0);
    }
    if (!networkMonitor.isOnline) {
      return const SyncResult(
        uploaded: 0, downloaded: 0, errors: 0,
        errorMessage: 'Device is offline',
      );
    }

    int uploaded = 0;
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;

    try {
      await _optimizeQueue();
      final upload = await _processQueue();
      uploaded = upload.uploaded;
      errors += upload.errors;
      errorMessage ??= upload.errorMessage;

      final download = await _downloadMyPins(userId, upload.deletedPinIds);
      downloaded = download.downloaded;
      errors += download.errors;
      errorMessage ??= download.errorMessage;

      final tomb = await _downloadMyTombstones(userId);
      errors += tomb.errors;
      errorMessage ??= tomb.errorMessage;
    } catch (e) {
      errors++;
      errorMessage ??= e.toString();
    }

    return SyncResult(
      uploaded: uploaded,
      downloaded: downloaded,
      errors: errors,
      errorMessage: errorMessage,
    );
  }

  // --- Upload path: identical semantics to the deleted SyncManager. --

  Future<void> _optimizeQueue() async {
    final all = await syncQueueDao.getPendingOperationsSorted();
    if (all.isEmpty) return;

    final byPin = <String, List<SyncQueueEntity>>{};
    for (final op in all) {
      byPin.putIfAbsent(op.pinId, () => []).add(op);
    }

    for (final ops in byPin.values) {
      if (ops.length <= 1) continue;
      final del = ops.lastWhere(
        (o) => o.operationType == 'DELETE',
        orElse: () => ops.first,
      );
      if (del.operationType == 'DELETE') {
        for (final o in ops) {
          if (o.id != del.id) await syncQueueDao.dequeue(o.id);
        }
      } else {
        final updates = ops.where((o) => o.operationType == 'UPDATE').toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        for (int i = 0; i < updates.length - 1; i++) {
          await syncQueueDao.dequeue(updates[i].id);
        }
      }
    }
  }

  Future<_ProcessQueueResult> _processQueue() async {
    final ops = await syncQueueDao.getPendingOperationsSorted();
    if (ops.isEmpty) {
      return _ProcessQueueResult(uploaded: 0, errors: 0, deletedPinIds: {});
    }

    int uploaded = 0;
    int errors = 0;
    String? errorMessage;
    final deletedIds = <String>{};

    for (final entity in ops) {
      final op = SyncOperationMapper.fromEntity(entity);

      if (op.hasExceededMaxRetries(maxRetries: _maxRetries)) {
        await syncQueueDao.dequeue(op.id);
        errors++;
        errorMessage ??= 'Some operations exceeded max retries';
        continue;
      }
      if (!op.canRetry()) continue;

      try {
        await _processOperation(op);
        uploaded++;
        if (op.operationType == SyncOperationType.delete) {
          deletedIds.add(op.pinId);
        }
        await syncQueueDao.dequeue(op.id);
      } catch (e) {
        errors++;
        errorMessage ??= e.toString();
        await syncQueueDao.incrementRetryCount(op.id, e.toString());
      }
    }

    return _ProcessQueueResult(
      uploaded: uploaded,
      errors: errors,
      errorMessage: errorMessage,
      deletedPinIds: deletedIds,
    );
  }

  Future<void> _processOperation(SyncOperation op) async {
    switch (op.operationType) {
      case SyncOperationType.create:
        final entity = await pinDao.getPinById(op.pinId);
        if (entity == null) return;
        try {
          await remote.insertPin(
              SupabasePinMapper.toDto(PinMapper.fromEntity(entity)));
        } catch (e) {
          final m = e.toString();
          if (m.contains('duplicate') ||
              m.contains('already exists') ||
              m.contains('unique')) return;
          rethrow;
        }
        break;
      case SyncOperationType.update:
        final entity = await pinDao.getPinById(op.pinId);
        if (entity == null) return;
        try {
          await remote.updatePin(
              SupabasePinMapper.toDto(PinMapper.fromEntity(entity)));
        } catch (e) {
          final m = e.toString();
          if (m.contains('not found') || m.contains('no rows')) return;
          rethrow;
        }
        break;
      case SyncOperationType.delete:
        try {
          await remote.deletePin(op.pinId);
        } catch (e) {
          final m = e.toString();
          if (m.contains('not found') || m.contains('no rows')) return;
          rethrow;
        }
        break;
    }
  }

  // --- Download path: delta + tombstone mirroring. ---

  Future<SyncResult> _downloadMyPins(
    String userId,
    Set<String> justDeletedIds,
  ) async {
    int downloaded = 0;
    int errors = 0;
    String? errorMessage;
    final fetchStartedAt = DateTime.now().toUtc();

    try {
      final since = await watermarks.readPinsWatermark(userId);
      final remotePins =
          await remote.getMyPinsModifiedSince(userId: userId, since: since);

      final pending = (await syncQueueDao.getPendingOperationsSorted())
          .where((o) => o.operationType == 'DELETE')
          .map((o) => o.pinId)
          .toSet();
      final localTombstones = await tombstoneDao.getAllTombstonedPinIds();
      final suppress = {...pending, ...justDeletedIds, ...localTombstones};

      final toInsert = <PinEntity>[];
      final toUpdate = <PinEntity>[];
      DateTime maxLastModified = since;

      for (final dto in remotePins) {
        try {
          if (suppress.contains(dto.id)) continue;
          final remotePin = SupabasePinMapper.fromDto(dto);
          final entity = PinMapper.toEntity(remotePin);
          final local = await pinDao.getPinById(remotePin.id);
          if (local == null) {
            toInsert.add(entity);
            downloaded++;
          } else {
            final localDomain = PinMapper.fromEntity(local);
            if (remotePin.metadata.lastModified
                .isAfter(localDomain.metadata.lastModified)) {
              toUpdate.add(entity);
              downloaded++;
            }
          }
          if (remotePin.metadata.lastModified.isAfter(maxLastModified)) {
            maxLastModified = remotePin.metadata.lastModified;
          }
        } catch (e) {
          errors++;
          errorMessage ??= e.toString();
        }
      }

      if (toInsert.isNotEmpty || toUpdate.isNotEmpty) {
        await pinDao.batchUpsertPins(toInsert, toUpdate);
      }

      // Advance the watermark to the newest row we saw (or fetchStartedAt
      // if no rows came back — keeps subsequent queries cheap).
      final advanceTo =
          maxLastModified == since ? fetchStartedAt : maxLastModified;
      await watermarks.writePinsWatermark(userId, advanceTo);
    } catch (e) {
      errors++;
      errorMessage ??= e.toString();
    }

    return SyncResult(
      uploaded: 0,
      downloaded: downloaded,
      errors: errors,
      errorMessage: errorMessage,
    );
  }

  Future<SyncResult> _downloadMyTombstones(String userId) async {
    int errors = 0;
    String? errorMessage;
    final fetchStartedAt = DateTime.now().toUtc();

    try {
      final since = await watermarks.readDeletionsWatermark(userId);
      final tombstones =
          await remote.getMyPinDeletionsSince(userId: userId, since: since);

      DateTime maxDeletedAt = since;
      for (final t in tombstones) {
        try {
          await serverDeletionDao.upsert(
              pinId: t.pinId, deletedAt: t.deletedAt);
          await pinDao.deletePin(t.pinId);
          if (t.deletedAt.isAfter(maxDeletedAt)) maxDeletedAt = t.deletedAt;
        } catch (e) {
          errors++;
          errorMessage ??= e.toString();
        }
      }

      final advanceTo = maxDeletedAt == since ? fetchStartedAt : maxDeletedAt;
      await watermarks.writeDeletionsWatermark(userId, advanceTo);
    } catch (e) {
      errors++;
      errorMessage ??= e.toString();
    }

    return SyncResult(
      uploaded: 0,
      downloaded: 0,
      errors: errors,
      errorMessage: errorMessage,
    );
  }
}

class _ProcessQueueResult {
  final int uploaded;
  final int errors;
  final String? errorMessage;
  final Set<String> deletedPinIds;

  _ProcessQueueResult({
    required this.uploaded,
    required this.errors,
    this.errorMessage,
    required this.deletedPinIds,
  });
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
flutter test test/data/sync/my_pins_sync_test.dart
```

Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/my_pins_sync.dart \
        test/data/sync/my_pins_sync_test.dart
git commit -m "feat(sync): MyPinsSync — delta sync + tombstone mirror for my pins"
```

---

## Task 9: `BboxRequestDebouncer`

**Files:**
- Create: `lib/data/sync/bbox_request_debouncer.dart`
- Test: `test/data/sync/bbox_request_debouncer_test.dart`

Decoupled from `ViewportPinsManager` so each can be unit-tested in isolation. The debouncer fires `onCameraIdle` callbacks 500 ms after the last call; if a new call lands during in-flight work, the in-flight `Future` is "abandoned" (the result is dropped, not awaited).

- [ ] **Step 1: Write the failing test**

`test/data/sync/bbox_request_debouncer_test.dart`:

```dart
import 'dart:async';

import 'package:ccwmap/data/sync/bbox_request_debouncer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BboxRequestDebouncer', () {
    test('fires the callback once after the debounce interval', () {
      fakeAsync((async) {
        int callCount = 0;
        final d = BboxRequestDebouncer(
          interval: const Duration(milliseconds: 500),
          onFire: () async => callCount++,
        );

        d.tick();
        d.tick();
        d.tick();

        async.elapse(const Duration(milliseconds: 400));
        expect(callCount, 0);
        async.elapse(const Duration(milliseconds: 200));
        expect(callCount, 1);
      });
    });

    test('cancel() aborts pending callbacks', () {
      fakeAsync((async) {
        int callCount = 0;
        final d = BboxRequestDebouncer(
          interval: const Duration(milliseconds: 500),
          onFire: () async => callCount++,
        );

        d.tick();
        async.elapse(const Duration(milliseconds: 200));
        d.cancel();
        async.elapse(const Duration(seconds: 2));

        expect(callCount, 0);
      });
    });

    test('in-flight onFire continues to completion; abandonment is the caller responsibility',
        () async {
      // Real-async test because we want to observe Future scheduling, not
      // synthetic time.
      //
      // Timer.cancel() in tick() only cancels *pending* timers — it does
      // not cancel an in-flight async callback. So both onFire calls run
      // to completion and both increments fire. The abandonment semantic
      // belongs to the caller: ViewportPinsManager (Task 10) reads
      // `currentGeneration` before and after its own work and drops the
      // result if the generation changed. This test pins the debouncer's
      // own narrow contract: it does not (and should not) interrupt the
      // user-supplied async work.
      final completer = Completer<void>();
      int finishedCalls = 0;
      final d = BboxRequestDebouncer(
        interval: const Duration(milliseconds: 1),
        onFire: () async {
          await completer.future;
          finishedCalls++;
        },
      );

      d.tick();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // At this point onFire #1 is awaiting completer.future.

      final genBeforeSecondTick = d.currentGeneration;
      d.tick(); // bumps the generation
      expect(d.currentGeneration, greaterThan(genBeforeSecondTick),
          reason: 'tick() must bump currentGeneration so callers can detect supersession');

      completer.complete(); // onFire #1 now resolves; Timer for #2 fires shortly after.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Both onFire bodies ran to completion — the debouncer does not
      // interrupt in-flight work. Caller (Task 10) uses currentGeneration
      // to decide whether to honor the result.
      expect(finishedCalls, 2);
    });
  });
}
```

(Add `dev_dependencies: fake_async: ^1.3.1` to `pubspec.yaml` if not present; check first with `grep fake_async pubspec.yaml`.)

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/sync/bbox_request_debouncer_test.dart
```

Expected: missing-file error.

- [ ] **Step 3: Create `lib/data/sync/bbox_request_debouncer.dart`**

```dart
import 'dart:async';

/// Debounces a callback (default 500 ms) and tracks an in-flight generation
/// so that a callback in progress when a new [tick] arrives can be ignored
/// by its caller.
///
/// Usage from [ViewportPinsManager]:
/// ```dart
/// final gen = debouncer.currentGeneration;
/// final items = await remote.getPinsInView(...);
/// if (gen != debouncer.currentGeneration) return; // abandon stale work
/// ```
class BboxRequestDebouncer {
  final Duration interval;
  final Future<void> Function() onFire;

  Timer? _timer;
  int _generation = 0;

  BboxRequestDebouncer({
    required this.interval,
    required this.onFire,
  });

  int get currentGeneration => _generation;

  void tick() {
    _generation++;
    _timer?.cancel();
    _timer = Timer(interval, () async {
      try {
        await onFire();
      } catch (_) {
        // Swallow — ViewportPinsManager handles its own errors.
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _generation++; // invalidate any in-flight result
  }

  void dispose() => cancel();
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
flutter test test/data/sync/bbox_request_debouncer_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/bbox_request_debouncer.dart \
        test/data/sync/bbox_request_debouncer_test.dart \
        pubspec.yaml pubspec.lock
git commit -m "feat(sync): BboxRequestDebouncer (500ms + generation tracking)"
```

---

## Task 10: `ViewportPinsManager`

**Files:**
- Create: `lib/data/sync/viewport_pins_manager.dart`
- Test: `test/data/sync/viewport_pins_manager_test.dart`

Owns bbox fetch, cache write, LRU eviction, and exposes the latest cluster list to UI. Uses `BboxRequestDebouncer`'s generation token to drop stale RPC results.

- [ ] **Step 1: Write the failing test**

`test/data/sync/viewport_pins_manager_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
import 'package:ccwmap/domain/models/location.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemote implements RemoteDataSourceInterface {
  List<MapItem> bboxResult = [];

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat, required double swLng,
    required double neLat, required double neLng,
    required int zoom, required String? currentUserId,
  }) async => bboxResult;

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince(
          {required String userId, required DateTime since}) async => [];
  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince(
          {required String userId, required DateTime since}) async => [];
  @override
  Future<void> insertPin(SupabasePinDto pin) async {}
  @override
  Future<void> updatePin(SupabasePinDto pin) async {}
  @override
  Future<void> deletePin(String id) async {}
  @override
  Future<SupabasePinDto?> getPinById(String id) async => null;
}

Pin _pin(String id, {String createdBy = 'other'}) => Pin(
      id: id, name: id,
      location: Location.fromLatLng(30, -95),
      status: PinStatus.allowed,
      restrictionTag: null,
      hasSecurityScreening: false,
      hasPostedSignage: false,
      metadata: PinMetadata(
        createdBy: createdBy,
        createdAt: DateTime.utc(2026, 1, 1),
        lastModified: DateTime.utc(2026, 1, 1),
      ),
    );

void main() {
  late AppDatabase db;
  late _FakeRemote remote;
  late ViewportPinsManager vpm;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = _FakeRemote();
    vpm = ViewportPinsManager(
      remote: remote,
      pinDao: db.pinDao,
      tombstoneDao: db.pinTombstoneDao,
      fetchedBboxDao: db.fetchedBboxDao,
      userIdProvider: () => 'me',
      cacheRowLimit: 100,
    );
  });

  tearDown(() async => db.close());

  test('persists pins and exposes cluster items separately', () async {
    remote.bboxResult = [
      MapItemPin(_pin('pin-1')),
      const MapItemCluster(
        centroidLat: 31, centroidLng: -94,
        count: 7,
        dominantStatus: PinStatus.noGun,
        dominantRestrictionTag: null,
      ),
    ];

    await vpm.fetch(swLat: 30, swLng: -96, neLat: 32, neLng: -94, zoom: 8);

    expect(await db.pinDao.getPinById('pin-1'), isNotNull);
    expect(vpm.clusters.value, hasLength(1));
    expect(vpm.clusters.value.single.count, 7);
  });

  test('filters out pins under local tombstones', () async {
    await db.pinTombstoneDao
        .insertTombstone('pin-ghost', DateTime.utc(2026, 5, 16));
    remote.bboxResult = [MapItemPin(_pin('pin-ghost'))];

    await vpm.fetch(swLat: 30, swLng: -96, neLat: 32, neLng: -94, zoom: 12);

    expect(await db.pinDao.getPinById('pin-ghost'), isNull);
  });

  test('LRU-evicts oldest cached non-mine pins past the cap', () async {
    // Seed 3 cached pins; cap is 2.
    final vpmSmall = ViewportPinsManager(
      remote: remote,
      pinDao: db.pinDao,
      tombstoneDao: db.pinTombstoneDao,
      fetchedBboxDao: db.fetchedBboxDao,
      userIdProvider: () => 'me',
      cacheRowLimit: 2,
    );
    await db.pinDao.upsertCachedPins([
      PinEntity(
        id: 'old', name: 'x', latitude: 30, longitude: -95, status: 0,
        restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'other', createdAt: 1, lastModified: 1,
        photoUri: null, notes: null, votes: 0,
        source: 'user', userModified: false, cachedAt: 100,
      ),
      PinEntity(
        id: 'mid', name: 'x', latitude: 30, longitude: -95, status: 0,
        restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'other', createdAt: 1, lastModified: 1,
        photoUri: null, notes: null, votes: 0,
        source: 'user', userModified: false, cachedAt: 200,
      ),
    ]);

    remote.bboxResult = [MapItemPin(_pin('new'))];

    await vpmSmall.fetch(
        swLat: 30, swLng: -96, neLat: 32, neLng: -94, zoom: 12);

    final remaining = (await db.pinDao.getAllPins()).map((p) => p.id).toSet();
    expect(remaining, contains('new'));
    expect(remaining, isNot(contains('old')));
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/data/sync/viewport_pins_manager_test.dart
```

Expected: missing-file error.

- [ ] **Step 3: Create `lib/data/sync/viewport_pins_manager.dart`**

```dart
import 'package:flutter/foundation.dart';

import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/mappers/pin_mapper.dart';
import 'package:ccwmap/domain/models/map_item.dart';

/// Drives bbox-on-demand reads:
/// - Calls `get_pins_in_view` for the supplied viewport.
/// - Persists [MapItemPin]s to local DB with `cachedAt = now`.
/// - Exposes [MapItemCluster]s through [clusters] for the map screen.
/// - LRU-evicts oldest non-mine cached pins when row count > [cacheRowLimit].
///
/// Works for anonymous callers — the RPC is open to `anon` (cf. migration
/// 008 § 7 GRANT). When unauthenticated, [userIdProvider] returns null and
/// "non-mine" effectively means "everything", which is the right semantics.
class ViewportPinsManager {
  final RemoteDataSourceInterface remote;
  final PinDao pinDao;
  final PinTombstoneDao tombstoneDao;
  final FetchedBboxDao fetchedBboxDao;
  final String? Function() userIdProvider;
  final int cacheRowLimit;

  final ValueNotifier<List<MapItemCluster>> clusters =
      ValueNotifier<List<MapItemCluster>>(const []);

  /// Bumped on every fetch. ViewModel-side debouncer compares to drop stale
  /// results that race with a fresh camera idle.
  int _fetchGeneration = 0;

  ViewportPinsManager({
    required this.remote,
    required this.pinDao,
    required this.tombstoneDao,
    required this.fetchedBboxDao,
    required this.userIdProvider,
    this.cacheRowLimit = 20000,
  });

  /// Single bbox fetch + cache write + LRU. Returns the generation it
  /// ran under so the caller can detect "newer fetch superseded this one".
  Future<int> fetch({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
  }) async {
    final generation = ++_fetchGeneration;
    final items = await remote.getPinsInView(
      swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng,
      zoom: zoom,
      currentUserId: userIdProvider(),
    );

    if (generation != _fetchGeneration) {
      // A newer fetch started before this one returned. Drop result.
      return generation;
    }

    final now = DateTime.now().toUtc();
    final tombstoned = await tombstoneDao.getAllTombstonedPinIds();

    final pinsToWrite = <PinEntity>[];
    final clustersOut = <MapItemCluster>[];
    int pinRowCount = 0;
    for (final item in items) {
      switch (item) {
        case MapItemPin(:final pin):
          if (tombstoned.contains(pin.id)) continue;
          pinsToWrite.add(PinMapper.toCachedEntity(pin, cachedAt: now));
          pinRowCount++;
        case MapItemCluster():
          clustersOut.add(item);
      }
    }

    if (pinsToWrite.isNotEmpty) {
      await pinDao.upsertCachedPins(pinsToWrite);
    }

    final myId = userIdProvider();
    if (myId != null) {
      await pinDao.evictOldestCachedNonMine(
          myUserId: myId, maxRows: cacheRowLimit);
    }

    await fetchedBboxDao.recordFetch(
      swLat: swLat, swLng: swLng, neLat: neLat, neLng: neLng,
      zoom: zoom,
      fetchedAt: now,
      pinCount: pinRowCount,
    );

    clusters.value = clustersOut;
    return generation;
  }

  /// Drop every cached non-mine pin and the bbox log. Used by the
  /// pathological-cache fallback on app start.
  Future<void> reset() async {
    final myId = userIdProvider();
    if (myId != null) {
      await pinDao.deleteAllCachedNonMinePins(myId);
    }
    await fetchedBboxDao.pruneOlderThan(
        DateTime.now().toUtc().add(const Duration(days: 365)));
    clusters.value = const [];
  }

  void dispose() {
    clusters.dispose();
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
flutter test test/data/sync/viewport_pins_manager_test.dart
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sync/viewport_pins_manager.dart \
        test/data/sync/viewport_pins_manager_test.dart
git commit -m "feat(sync): ViewportPinsManager — bbox fetch + LRU cache"
```

---

## Task 11: Delete `SyncManager`; wire `MyPinsSync` everywhere

**Files:**
- Delete: `lib/data/sync/sync_manager.dart`
- Modify: `lib/data/sync/background_sync.dart`
- Modify: `lib/data/repositories/pin_repository_impl.dart`
- Modify: `lib/data/repositories/supabase_auth_repository.dart`
- Modify: `lib/main.dart`
- Modify: `test/data/database/database_test.dart` if it references `SyncManager` (it shouldn't, but verify).

- [ ] **Step 1: Find every reference to `SyncManager`**

```bash
grep -rn "SyncManager\|sync_manager" lib/ test/ --include="*.dart"
```

Expected references (the surface to update):
- `lib/data/sync/sync_manager.dart` (the file itself — delete)
- `lib/data/sync/background_sync.dart` — replace ctor + constructor call
- `lib/data/repositories/pin_repository_impl.dart` — field, ctor param, `syncWithRemote` call
- `lib/data/repositories/supabase_auth_repository.dart` — check whether `SyncManager` is used; if it's used to clear local state on sign-out, swap to `MyPinsSync`/`watermarks.clearForUser`
- `lib/main.dart` — construction site

- [ ] **Step 2: Update `lib/data/repositories/pin_repository_impl.dart`**

Replace `SyncManager? _syncManager` with `MyPinsSync? _myPinsSync`. Update ctor param and `syncWithRemote()`:

```dart
import '../sync/my_pins_sync.dart';

class PinRepositoryImpl implements PinRepository {
  final PinDao _pinDao;
  final SyncQueueDao _syncQueueDao;
  final PinTombstoneDao _tombstoneDao;
  final MyPinsSync? _myPinsSync;
  final Uuid _uuid = const Uuid();

  PinRepositoryImpl(
    this._pinDao,
    this._syncQueueDao,
    this._tombstoneDao, {
    MyPinsSync? myPinsSync,
  }) : _myPinsSync = myPinsSync;
  // ... rest unchanged ...

  @override
  Future<SyncResult> syncWithRemote() async {
    final s = _myPinsSync;
    if (s != null) return s.sync();
    return const SyncResult(
      uploaded: 0, downloaded: 0, errors: 0,
      errorMessage: 'MyPinsSync not initialized',
    );
  }
}
```

- [ ] **Step 3: Update `lib/data/repositories/supabase_auth_repository.dart`**

```bash
grep -n "SyncManager\|syncManager\|sync_manager" lib/data/repositories/supabase_auth_repository.dart
```

If `SyncManager` is referenced, replace the field/ctor with `MyPinsSync? _myPinsSync`. If the only use is to trigger a sync on sign-in, simply rename the type; the call becomes `_myPinsSync?.sync()`. If it also clears local data on sign-out, add a paired `watermarks.clearForUser(oldUserId)` call (will need `LastSyncedAtStore` injected too — add a constructor param).

If you find no references, skip this step.

- [ ] **Step 4: Update `lib/data/sync/background_sync.dart`**

```dart
import 'last_synced_at_store.dart';
import 'my_pins_sync.dart';
// ...

      final supabaseClient = Supabase.instance.client;
      final remoteDataSource = SupabaseRemoteDataSource(supabaseClient);
      final watermarks = await LastSyncedAtStore.create();

      final myPinsSync = MyPinsSync(
        userIdProvider: () => supabaseClient.auth.currentUser?.id,
        syncQueueDao: database.syncQueueDao,
        pinDao: database.pinDao,
        tombstoneDao: database.pinTombstoneDao,
        serverDeletionDao: database.serverPinDeletionDao,
        remote: remoteDataSource,
        networkMonitor: networkMonitor,
        watermarks: watermarks,
      );

      final result = await myPinsSync.sync();
```

(Delete the `import 'sync_manager.dart';` and any references to the old class.)

- [ ] **Step 5: Update `lib/main.dart`**

```dart
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:ccwmap/data/sync/my_pins_sync.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
// remove: import 'package:ccwmap/data/sync/sync_manager.dart';
```

In `main()`:

```dart
  final watermarks = await LastSyncedAtStore.create();

  final myPinsSync = MyPinsSync(
    userIdProvider: () => supabaseClient.auth.currentUser?.id,
    syncQueueDao: database.syncQueueDao,
    pinDao: database.pinDao,
    tombstoneDao: database.pinTombstoneDao,
    serverDeletionDao: database.serverPinDeletionDao,
    remote: remoteDataSource,
    networkMonitor: networkMonitor,
    watermarks: watermarks,
  );

  final viewportPinsManager = ViewportPinsManager(
    remote: remoteDataSource,
    pinDao: database.pinDao,
    tombstoneDao: database.pinTombstoneDao,
    fetchedBboxDao: database.fetchedBboxDao,
    userIdProvider: () => supabaseClient.auth.currentUser?.id,
    // Default cacheRowLimit (20000) per spec.
  );

  final pinRepository = PinRepositoryImpl(
    database.pinDao,
    database.syncQueueDao,
    database.pinTombstoneDao,
    myPinsSync: myPinsSync,
  );

  final authRepository = SupabaseAuthRepository(
    supabaseClient,
    // If you renamed the ctor param in Step 3: pass myPinsSync.
    // Otherwise drop the named arg entirely.
  );

  // MapViewModel ctor signature will be widened in Task 12.
  final mapViewModel = MapViewModel(
    pinRepository,
    networkMonitor,
    blocklistService,
    viewportPinsManager: viewportPinsManager,
  );
```

- [ ] **Step 6: Delete `lib/data/sync/sync_manager.dart`**

```bash
git rm lib/data/sync/sync_manager.dart
```

If a test file references it (`test/data/sync/sync_manager_test.dart` etc.):

```bash
grep -rn "sync_manager" test/
```

Delete or rewrite those tests — the corresponding coverage is now in `my_pins_sync_test.dart`.

- [ ] **Step 7: `flutter analyze` and `flutter test`**

```bash
flutter analyze
flutter test
```

Expected: zero analyzer warnings; full suite passes (the MapViewModel ctor change in Step 5 will be uncovered by test code until Task 12; if a viewmodel test fails on missing `viewportPinsManager`, mark the test `skip: true` with a `// TODO Task 12` comment).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(sync): retire SyncManager; wire MyPinsSync + ViewportPinsManager"
```

---

## Task 12: `MapViewModel` — accept `ViewportPinsManager`, expose clusters, drive bbox fetch

**Files:**
- Modify: `lib/presentation/viewmodels/map_viewmodel.dart`
- Test: `test/presentation/viewmodels/map_viewmodel_viewport_test.dart`

`MapViewModel` becomes the single entry point the screen calls on camera idle. It owns the `BboxRequestDebouncer` so debounce state survives widget rebuilds.

- [ ] **Step 1: Write the failing test**

`test/presentation/viewmodels/map_viewmodel_viewport_test.dart`:

```dart
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/datasources/remote_data_source_interface.dart';
import 'package:ccwmap/data/models/server_pin_deletion_dto.dart';
import 'package:ccwmap/data/models/supabase_pin_dto.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'package:ccwmap/data/services/network_monitor.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/domain/models/map_item.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemote implements RemoteDataSourceInterface {
  List<MapItem> bboxResult = [];
  int bboxCalls = 0;

  @override
  Future<List<MapItem>> getPinsInView({
    required double swLat, required double swLng,
    required double neLat, required double neLng,
    required int zoom, required String? currentUserId,
  }) async {
    bboxCalls++;
    return bboxResult;
  }

  @override
  Future<List<SupabasePinDto>> getMyPinsModifiedSince(
          {required String userId, required DateTime since}) async => [];
  @override
  Future<List<ServerPinDeletionDto>> getMyPinDeletionsSince(
          {required String userId, required DateTime since}) async => [];
  @override
  Future<void> insertPin(SupabasePinDto pin) async {}
  @override
  Future<void> updatePin(SupabasePinDto pin) async {}
  @override
  Future<void> deletePin(String id) async {}
  @override
  Future<SupabasePinDto?> getPinById(String id) async => null;
}

class _AlwaysOnline implements NetworkMonitor {
  @override bool get isOnline => true;
  @override Stream<bool> get isOnlineStream => const Stream.empty();
  @override Future<void> initialize() async {}
  @override void dispose() {}
}

class _NullModeration implements ModerationRepository {
  @override Future<Set<String>> fetchBlocklist() async => const {};
  @override Future<void> blockUser(String id) async {}
  @override Future<void> unblockUser(String id) async {}
  @override Future<void> submitPinReport(
          {required String pinId, required String reason, String? note}) async {}
}

void main() {
  test('onCameraIdle dispatches debounced bbox fetch and publishes clusters',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final remote = _FakeRemote();
    remote.bboxResult = [
      const MapItemCluster(
        centroidLat: 30, centroidLng: -95, count: 5,
        dominantStatus: PinStatus.allowed,
        dominantRestrictionTag: null,
      ),
    ];
    final vpm = ViewportPinsManager(
      remote: remote,
      pinDao: db.pinDao,
      tombstoneDao: db.pinTombstoneDao,
      fetchedBboxDao: db.fetchedBboxDao,
      userIdProvider: () => null,
    );
    final repo = PinRepositoryImpl(
      db.pinDao, db.syncQueueDao, db.pinTombstoneDao,
    );
    final vm = MapViewModel(
      repo,
      _AlwaysOnline(),
      BlocklistService(_NullModeration()),
      viewportPinsManager: vpm,
      bboxDebounce: const Duration(milliseconds: 50),
    );

    vm.onCameraIdle(
      swLat: 30, swLng: -96, neLat: 32, neLng: -94, zoom: 8,
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(remote.bboxCalls, 1);
    expect(vm.viewportClusters.value, hasLength(1));
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
flutter test test/presentation/viewmodels/map_viewmodel_viewport_test.dart
```

Expected: ctor signature mismatch — `viewportPinsManager` / `bboxDebounce` not accepted.

- [ ] **Step 3: Extend `MapViewModel`**

Add fields & ctor params:

```dart
import 'package:ccwmap/data/sync/bbox_request_debouncer.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
import 'package:ccwmap/domain/models/map_item.dart';

class MapViewModel extends ChangeNotifier {
  // ... existing fields ...
  final ViewportPinsManager? _viewportPinsManager;
  late final BboxRequestDebouncer? _bboxDebouncer;

  // Pending viewport saved while the timer is counting down.
  double? _pendingSwLat, _pendingSwLng, _pendingNeLat, _pendingNeLng;
  int? _pendingZoom;

  MapViewModel(
    this._repository,
    this._networkMonitor,
    this._blocklist, {
    ViewportPinsManager? viewportPinsManager,
    Duration bboxDebounce = const Duration(milliseconds: 500),
  }) : _viewportPinsManager = viewportPinsManager {
    _bboxDebouncer = viewportPinsManager == null
        ? null
        : BboxRequestDebouncer(
            interval: bboxDebounce,
            onFire: _runPendingBboxFetch,
          );
    _blocklist.addListener(_applyBlocklistFilter);
  }

  /// Exposed for the map screen's cluster layer.
  ValueListenable<List<MapItemCluster>> get viewportClusters =>
      _viewportPinsManager?.clusters ??
      ValueNotifier<List<MapItemCluster>>(const []);

  /// Map screen calls this from `onCameraIdle`. Stores the viewport and
  /// kicks the debouncer; actual fetch fires [bboxDebounce] later.
  void onCameraIdle({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
  }) {
    if (_bboxDebouncer == null) return;
    _pendingSwLat = swLat;
    _pendingSwLng = swLng;
    _pendingNeLat = neLat;
    _pendingNeLng = neLng;
    _pendingZoom = zoom;
    _bboxDebouncer!.tick();
  }

  Future<void> _runPendingBboxFetch() async {
    final vpm = _viewportPinsManager;
    if (vpm == null) return;
    final sw_lat = _pendingSwLat,
        sw_lng = _pendingSwLng,
        ne_lat = _pendingNeLat,
        ne_lng = _pendingNeLng,
        z = _pendingZoom;
    if (sw_lat == null ||
        sw_lng == null ||
        ne_lat == null ||
        ne_lng == null ||
        z == null) {
      return;
    }
    try {
      await vpm.fetch(
        swLat: sw_lat, swLng: sw_lng,
        neLat: ne_lat, neLng: ne_lng, zoom: z,
      );
    } catch (_) {
      // Non-fatal; viewportClusters stays as-is.
    }
  }

  @override
  void dispose() {
    _bboxDebouncer?.dispose();
    _blocklist.removeListener(_applyBlocklistFilter);
    _pinsSubscription?.cancel();
    _networkSubscription?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
flutter test test/presentation/viewmodels/map_viewmodel_viewport_test.dart
```

Expected: pass.

- [ ] **Step 5: Run the full viewmodel suite**

```bash
flutter test test/presentation/viewmodels/
```

Expected: all green. Any previously-skipped tests from Task 11 can be re-enabled now.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/viewmodels/map_viewmodel.dart \
        test/presentation/viewmodels/map_viewmodel_viewport_test.dart
git commit -m "feat(viewmodel): MapViewModel.onCameraIdle + viewportClusters"
```

---

## Task 13: Map screen — hook `onCameraIdle`, compute viewport bbox

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

- [ ] **Step 1: Find the `MapLibreMap(...)` widget**

```bash
grep -n "MapLibreMap(" lib/presentation/screens/map_screen.dart
```

Expected: one match around line 1739.

- [ ] **Step 2: Add the `onCameraIdle` parameter to the widget**

Insert near `onMapClick`:

```dart
                  onCameraIdle: _onCameraIdle,
```

- [ ] **Step 3: Add the handler**

Near `_onMapClick` (search for `void _onMapClick`):

```dart
  /// Called by MapLibre after the camera settles from pan/zoom/rotate.
  /// Computes the visible bounding box + integer zoom and forwards to the
  /// view model, which debounces and dispatches to ViewportPinsManager.
  Future<void> _onCameraIdle() async {
    final controller = _mapController;
    final viewModel = _viewModel;
    if (controller == null || viewModel == null) return;

    try {
      final bounds = await controller.getVisibleRegion();
      final z = controller.cameraPosition?.zoom ?? _initialZoom;
      viewModel.onCameraIdle(
        swLat: bounds.southwest.latitude,
        swLng: bounds.southwest.longitude,
        neLat: bounds.northeast.latitude,
        neLng: bounds.northeast.longitude,
        zoom: z.round(),
      );
    } catch (e) {
      debugPrint('MapScreen: getVisibleRegion failed: $e');
    }
  }
```

- [ ] **Step 4: Fire one bbox fetch on style load** (initial viewport — onCameraIdle won't fire until the user moves the camera)

In `_onStyleLoadedCallback`, after `_updatePinsLayer()`:

```dart
    // Initial bbox fetch for the starting viewport.
    _onCameraIdle();
```

- [ ] **Step 5: Run `flutter analyze`**

```bash
flutter analyze
```

Expected: zero warnings. UI changes will be smoke-tested in Task 17.

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): onCameraIdle → ViewportPinsManager via MapViewModel"
```

---

## Task 14: Map screen — cluster rendering layer

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

A new GeoJSON source + circle + symbol layer renders the cluster aggregates. Cluster circles are sized by count and colored by `dominantStatus`; the label shows the count.

- [ ] **Step 1: Add a `_updateClustersLayer` method**

Near `_updatePinsLayer`:

```dart
  bool _isUpdatingClusters = false;
  bool _pendingClusterUpdate = false;

  Future<void> _updateClustersLayer(List<MapItemCluster> clusters) async {
    if (_mapController == null) return;
    if (_isUpdatingClusters) {
      _pendingClusterUpdate = true;
      return;
    }
    _isUpdatingClusters = true;
    _pendingClusterUpdate = false;

    try {
      final features = clusters.map((c) => {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [c.centroidLng, c.centroidLat],
            },
            'properties': {
              'count': c.count,
              'status': c.dominantStatus.colorCode,
            },
          }).toList();

      final geojson = {'type': 'FeatureCollection', 'features': features};

      try { await _mapController!.removeLayer('clusters-count-layer'); } catch (_) {}
      try { await _mapController!.removeLayer('clusters-circle-layer'); } catch (_) {}
      try { await _mapController!.removeSource('clusters-source'); } catch (_) {}

      await _mapController!.addGeoJsonSource('clusters-source', geojson);

      await _mapController!.addCircleLayer(
        'clusters-source',
        'clusters-circle-layer',
        CircleLayerProperties(
          circleRadius: [
            'interpolate', ['linear'], ['get', 'count'],
            1, 14,
            10, 20,
            100, 30,
            1000, 40,
          ],
          circleColor: [
            'match', ['get', 'status'],
            0, '#4CAF50',
            1, '#FFC107',
            2, '#F44336',
            '#999999',
          ],
          circleStrokeWidth: 2.0,
          circleStrokeColor: '#FFFFFF',
          circleOpacity: 0.85,
        ),
      );

      await _mapController!.addSymbolLayer(
        'clusters-source',
        'clusters-count-layer',
        SymbolLayerProperties(
          textField: ['get', 'count'],
          textSize: 14.0,
          textColor: '#FFFFFF',
          textHaloColor: '#000000',
          textHaloWidth: 1.0,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
        enableInteraction: false,
      );
    } catch (e) {
      debugPrint('MapScreen: Error updating clusters layer: $e');
    } finally {
      _isUpdatingClusters = false;
      if (_pendingClusterUpdate) {
        _pendingClusterUpdate = false;
        // Re-pull from viewModel — captured cluster list could be stale.
        _updateClustersLayer(_viewModel?.viewportClusters.value ?? const []);
      }
    }
  }
```

- [ ] **Step 2: Wire the cluster listener**

In `_initializeViewModel` after `_viewModel!.addListener(_onPinsChanged);`:

```dart
    _viewModel!.viewportClusters.addListener(_onClustersChanged);
```

Add the handler:

```dart
  void _onClustersChanged() {
    if (!mounted) return;
    final clusters = _viewModel?.viewportClusters.value ?? const [];
    _updateClustersLayer(clusters);
  }
```

Detach in `dispose`:

```dart
    _viewModel?.viewportClusters.removeListener(_onClustersChanged);
```

Add the import:

```dart
import 'package:ccwmap/domain/models/map_item.dart';
```

- [ ] **Step 3: `flutter analyze`**

```bash
flutter analyze
```

Expected: zero warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): cluster rendering layer (count + dominant status)"
```

---

## Task 15: Map screen — cluster tap zooms into cluster cell

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

Tapping a cluster should advance the camera to the cell, triggering another `onCameraIdle` → bbox fetch which will return either a finer cluster or individual pins. The simplest correct UX: zoom 2 levels in centered on the cluster centroid.

- [ ] **Step 1: Extend `_onFeatureTapped` to handle cluster layer**

Near the top of `_onFeatureTapped`, just after the layerId guard:

```dart
    if (layerId == 'clusters-circle-layer' || layerId == 'clusters-count-layer') {
      await _onClusterTapped(coordinates);
      return;
    }
```

(Replace the existing `if (layerId != 'pins-layer') return;` with the two-layer check above + retain the existing pin-layer logic for `layerId == 'pins-layer'`.)

Add:

```dart
  Future<void> _onClusterTapped(LatLng centroid) async {
    final controller = _mapController;
    if (controller == null) return;
    final currentZoom = controller.cameraPosition?.zoom ?? _initialZoom;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(centroid, (currentZoom + 2).clamp(4.0, 18.0)),
    );
    // animateCamera completion triggers a fresh onCameraIdle which the
    // viewmodel debounces + dispatches.
  }
```

- [ ] **Step 2: Add `clusters-circle-layer` to feature-tap routing**

`MapLibreMap` only emits `onFeatureTapped` for layers added with default interaction; cluster circles already get it. Verify by adding the listener attachment — `controller.onFeatureTapped.add(_onFeatureTapped)` is already added in `_onMapCreated` and dispatches by layerId.

- [ ] **Step 3: `flutter analyze` + run the analyze step**

```bash
flutter analyze
```

Expected: zero warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): cluster tap zooms in 2 levels, retriggers bbox fetch"
```

---

## Task 16: Map screen — zoom-based pin/cluster visibility

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

At low zoom the cluster layer overlays the pin layer; both render every cached pin twice. Hide the pins layer when clusters are present.

- [ ] **Step 1: After cluster layer is added, conditionally set the pins layer visibility**

At the end of `_updatePinsLayer`, after the symbol layer is added:

```dart
      await _applyPinLayerVisibility();
```

At the end of `_updateClustersLayer`, after the symbol layer is added:

```dart
      await _applyPinLayerVisibility();
```

Add:

```dart
  Future<void> _applyPinLayerVisibility() async {
    final controller = _mapController;
    if (controller == null) return;
    final hideForClusters =
        (_viewModel?.viewportClusters.value ?? const []).isNotEmpty;
    try {
      await controller.setLayerVisibility('pins-layer', !hideForClusters);
      await controller.setLayerVisibility('pins-labels-layer', !hideForClusters);
    } catch (e) {
      debugPrint('MapScreen: setLayerVisibility failed: $e');
    }
  }
```

- [ ] **Step 2: `flutter analyze`**

```bash
flutter analyze
```

Expected: zero warnings. If `setLayerVisibility` is not in maplibre_gl 0.24.1, grep the controller for an alternative:

```bash
grep -n "setLayerVisibility\|setLayerProperties" \
  /c/Users/camil/AppData/Local/Pub/Cache/hosted/pub.dev/maplibre_gl-0.24.1/lib/src/controller.dart
```

If only `setLayerProperties` exists, swap to:

```dart
      await controller.setLayerProperties('pins-layer',
          LayerProperties(visibility: hideForClusters ? 'none' : 'visible'));
      await controller.setLayerProperties('pins-labels-layer',
          LayerProperties(visibility: hideForClusters ? 'none' : 'visible'));
```

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(map): hide pins layer when clusters present (zoom-based)"
```

---

## Task 17: Pathological-cache hard fallback on app start

**Files:**
- Modify: `lib/main.dart` (or `lib/presentation/viewmodels/map_viewmodel.dart` — chosen path below)
- Test: `test/data/sync/viewport_pins_manager_test.dart` (extend with a reset test)

Per spec §6: "if cached count > 2× soft limit, drop all `created_by != me` rows, rebuild via bbox." Cheapest place to enforce is right after `MapViewModel.initialize`, before the first `onCameraIdle` runs.

- [ ] **Step 1: Extend the ViewportPinsManager test with a reset assertion**

In `test/data/sync/viewport_pins_manager_test.dart`, add:

```dart
  test('reset() drops every cached non-mine pin and clears clusters', () async {
    await db.pinDao.upsertCachedPins([
      PinEntity(
        id: 'cached', name: 'x', latitude: 30, longitude: -95, status: 0,
        restrictionTag: null,
        hasSecurityScreening: false, hasPostedSignage: false,
        createdBy: 'other', createdAt: 1, lastModified: 1,
        photoUri: null, notes: null, votes: 0,
        source: 'user', userModified: false, cachedAt: 100,
      ),
    ]);

    await vpm.reset();

    expect(await db.pinDao.getAllPins(), isEmpty);
    expect(vpm.clusters.value, isEmpty);
  });
```

Run it; it should already pass (`reset` was added in Task 10). If it fails, fix `reset`.

- [ ] **Step 2: Wire the fallback into `MapViewModel.initialize`**

```dart
  /// Hard cap per spec §6 — twice the soft cache limit. Configurable for tests.
  static const int _pathologicalCacheCap = 40000;

  Future<void> initialize() async {
    // ... existing code ...

    // Pathological-cache safety: if the on-disk cache is suspiciously large
    // (e.g. crashed mid-eviction in a prior run), drop the non-mine pins and
    // let the next onCameraIdle rebuild.
    final vpm = _viewportPinsManager;
    if (vpm != null) {
      final myId = _resolveMyUserId();
      if (myId != null) {
        final count = await _repository.getPins().then(
              (pins) => pins.where((p) =>
                  p.metadata.createdBy != myId).length,
            );
        if (count > _pathologicalCacheCap) {
          await vpm.reset();
        }
      }
    }
  }
```

Add a small helper `String? _resolveMyUserId()` — easiest path is to inject a `userIdProvider` callback into `MapViewModel` (mirrors the pattern used in `MyPinsSync`/`ViewportPinsManager`). Add a named ctor param:

```dart
  final String? Function()? _userIdProvider;

  MapViewModel(
    this._repository,
    this._networkMonitor,
    this._blocklist, {
    ViewportPinsManager? viewportPinsManager,
    Duration bboxDebounce = const Duration(milliseconds: 500),
    String? Function()? userIdProvider,
  })  : _viewportPinsManager = viewportPinsManager,
        _userIdProvider = userIdProvider {
    // ...
  }

  String? _resolveMyUserId() => _userIdProvider?.call();
```

In `main.dart`, pass it:

```dart
  final mapViewModel = MapViewModel(
    pinRepository,
    networkMonitor,
    blocklistService,
    viewportPinsManager: viewportPinsManager,
    userIdProvider: () => supabaseClient.auth.currentUser?.id,
  );
```

- [ ] **Step 3: `flutter analyze` + `flutter test`**

```bash
flutter analyze
flutter test
```

Expected: zero warnings; suite green.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart \
        lib/presentation/viewmodels/map_viewmodel.dart \
        test/data/sync/viewport_pins_manager_test.dart
git commit -m "feat(sync): pathological-cache hard fallback on app start"
```

---

## Task 18: End-to-end verification against staging

**Files:**
- No code changes.
- Documentation: append findings to `docs/dev/STAGING.md` if anything surprises you.

The migration target is staging (production stays at the pre-Phase-0 schema per the deferral commit). Run the app pointed at staging and verify the new sync model loads existing pins, debounces correctly, and clusters on regional viewports.

- [ ] **Step 1: Confirm `.env` points at staging**

```bash
grep SUPABASE_URL .env
```

Expected: `https://miihmfhnsfmwgrvgayns.supabase.co`. If not, swap temporarily; remember to swap back before any prod-targeted release work.

- [ ] **Step 2: Seed staging with at least one signed-in test user and a handful of pins**

Use the staging dashboard or run the existing app build against staging to create three pins as a test user. Confirm via SQL Editor:

```sql
SELECT count(*) FROM pins;
SELECT count(*) FROM pin_deletions;
```

Expected: ≥ 3 pins; possibly 0 deletions (none yet).

- [ ] **Step 3: Run the app on Android emulator (or device)**

```bash
flutter run -d android
```

Verify in the order:
- [ ] **Map renders** at the continental-US starting viewport. Within ~1 s, an `onCameraIdle` fires and the bbox RPC returns either pins or clusters (you should see your seed data clustered, or visible pins if zoomed in).
- [ ] **Sign in as the test user** via the app's existing flow. The pre-existing `MyPinsSync` flow should fire (watch logs for `MyPinsSync` activity). Your seed pins should appear as "mine".
- [ ] **Pan to a different region** (Texas). After 500 ms, the bbox RPC fires again; cached pins for the new viewport land in local DB.
- [ ] **Pan back to original region**. The cached pins should still be visible (no re-fetch needed for the rendering, though one will fire to refresh `cachedAt`).
- [ ] **Delete one of your pins**. It should disappear from the map. After a manual app restart, it should remain gone (server tombstone + `MyPinsSync`).
- [ ] **Sign out**. The map should remain visible. Your pins now appear as "other-user" pins (via bbox cache).

- [ ] **Step 4: Test on web**

```bash
flutter run -d chrome
```

Repeat the verification. Web's in-memory storage means cache is lost on refresh; verify that's the only behavior difference.

- [ ] **Step 5: If you find a regression, file a `BUG-00X` entry in `CLAUDE.md` under the "Known Bugs" section.** Do not attempt to fix it within Phase 1 unless it's a true blocker (the sync model literally doesn't work).

- [ ] **Step 6: Commit the verification notes**

If you updated `docs/dev/STAGING.md`:

```bash
git add docs/dev/STAGING.md
git commit -m "docs(staging): Phase 1 end-to-end verification notes"
```

Otherwise skip the commit.

---

## Task 19: Run the full suite and analyzer, format, ship

**Files:** None (verification only).

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```

Expected: every test passes. The total count should grow by roughly 25–30 new tests across Phase 1.

- [ ] **Step 2: `flutter analyze`**

```bash
flutter analyze
```

Expected: zero warnings.

- [ ] **Step 3: Format**

```bash
dart format .
```

Expected: zero file changes (CI's format check would otherwise fail). If any files are reformatted, commit them in a `style:` commit.

- [ ] **Step 4: Make sure nothing was left commented-out for "Task N"**

```bash
grep -rn "TODO Task" lib/ test/
```

Expected: no matches.

- [ ] **Step 5: Final commit if anything trivial got rolled up**

```bash
git status
# If clean, you're done.
```

Phase 1 is complete when the test suite is green, `flutter analyze` is clean, and the end-to-end verification (Task 18) shows the new tiered sync working against staging with no regressions in pin create/edit/delete flows. Production has not been touched — that happens together with Phase 4's first pre-populated wave per the migration-deferral note (`4cf91d6`).

---

## References

- Spec: `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` §5 (sync model), §6 (observability), §8 (rollout — Phase 1 row).
- Phase 0 plan: `docs/superpowers/plans/2026-05-16-pre-populate-pins-phase-0.md`.
- Migration in place: `supabase/migrations/008_provenance_and_view_rpc.sql` (provenance columns, `get_pins_in_view` RPC, `pin_deletions`, deny-system-user RLS).
- maplibre_gl API: `MapLibreMap.onCameraIdle`, `MapLibreMapController.getVisibleRegion()`, `LatLngBounds` (in `maplibre_gl_platform_interface-0.24.1`).
- `kSystemUserId` constant: `lib/core/system_constants.dart`.
