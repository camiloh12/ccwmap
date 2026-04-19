## Baseline

**Flutter & Dart:**
```
Flutter 3.41.1 • channel stable
Framework • revision 582a0e7c55 (9 weeks ago) • 2026-02-12 17:12:32 -0800
Engine • hash cc8e596aa65130a0678cc59613ed1c5125184db4 (revision 3452d735bd) (2 months ago) • 2026-02-09 22:03:17.000Z
Tools • Dart 3.11.0 • DevTools 2.54.1
```

**Analyzer:**
- 16 issues (all infos)
  - 1 deprecated_member_use: `package:drift/web.dart` (consider migrating to `package:drift/wasm.dart`)
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums use UPPER_CASE

**Tests:**
- 109/109 passing

**Notes:**
- 60 packages have newer versions incompatible with dependency constraints
- Baseline is green: all tests pass, no errors in analyze

## Phase B (Flutter SDK)

**Flutter & Dart (Upgraded):**
```
Flutter 3.41.7 • channel stable
Framework • revision cc0734ac71 (4 days ago) • 2026-04-15 21:21:08 -0700
Engine • hash 7a53c052bc4b472cf780b199087e1368e4a9aa8c (revision 59aa584fdf) (3 days ago) • 2026-04-16 02:32:16.000Z
Tools • Dart 3.11.5 • DevTools 2.54.2
```

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums

**Tests:**
- 109/109 passing — **No regression**

**Dependencies:**
- `pubspec.lock` changed: 2 transitive packages updated
  - matcher: 0.12.18 → 0.12.19
  - test_api: 0.7.9 → 0.7.10
- Command: `flutter pub get` completed successfully

## Phase C (caret upgrades)

**Direct packages upgraded (within caret constraints):**
- `drift`: 2.30.0 → 2.32.1
- `drift_dev`: 2.30.0 → 2.32.1 (matched)
- `uuid`: 4.5.2 → 4.5.3
- `supabase_flutter`: 2.12.0 → 2.12.4
- `build_runner`: 2.10.4 → 2.13.1

**Notable transitive bumps:**
- `analyzer`: 9.0.0 → 10.0.1 (minor)
- `_fe_analyzer_shared`: 92.0.0 → 93.0.0 (minor)
- `source_gen`: 4.1.1 → 4.2.2 (minor)
- `sqlite3`: 2.9.4 → 3.3.1 (major — internal to drift workflow)
- `sqlparser`: 0.42.1 → 0.44.3 (minor)

**Drift codegen:**
- Command: `dart run build_runner build --delete-conflicting-outputs` succeeded
- Output: 109 files written (60 skipped, 108 output, 72 no-op)
- File changes: `lib/data/database/database.g.dart` updated (+26 lines)

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums

**Tests:**
- 109/109 passing — **No regression**

**Status:** DONE

## Phase D1 (Java 11 → 21)

**Change:** Bumped Java bytecode source/target from 11 to 21 in `android/app/build.gradle.kts`.

Exact diff (3 lines changed):
```
-        sourceCompatibility = JavaVersion.VERSION_11
+        sourceCompatibility = JavaVersion.VERSION_21
-        targetCompatibility = JavaVersion.VERSION_11
+        targetCompatibility = JavaVersion.VERSION_21
-        jvmTarget = JavaVersion.VERSION_11.toString()
+        jvmTarget = JavaVersion.VERSION_21.toString()
```

**Toolchain at time of change:**
- Local Java: 21.0.9 LTS (Oracle HotSpot)
- AGP: 8.9.1
- Gradle wrapper: 8.12
- Kotlin: 2.1.0

**`flutter build apk --debug`:**
- Result: succeeded (140.9 s)
- Output: `build/app/outputs/flutter-apk/app-debug.apk` (216 MB)
- No Java-21 or AGP-8.9 warnings in build output

**Tests:**
- 109/109 passing — No regression

**Status:** DONE

## Phase D2 (Kotlin 2.1.0 → 2.3.20)

**Change:** Bumped Kotlin plugin from 2.1.0 to 2.3.20 in `android/settings.gradle.kts` (line 23).
  - Also required migrating from deprecated `kotlinOptions { jvmTarget }` to new `kotlin { compilerOptions { jvmTarget } }` DSL in `android/app/build.gradle.kts`.

Exact diffs:

**settings.gradle.kts (1 line):**
```
-    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
+    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
```

**app/build.gradle.kts (4 lines removed, 6 lines added):**
```
# Removed:
-    kotlinOptions {
-        jvmTarget = JavaVersion.VERSION_21.toString()
-    }

# Added (after android block closes):
+kotlin {
+    compilerOptions {
+        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
+    }
+}
```

**Toolchain at time of change:**
- Local Java: 21.0.9 LTS
- AGP: 8.9.1
- Gradle wrapper: 8.12
- Kotlin: 2.3.20 (upgraded from 2.1.0)

**Kotlin 2.3.20 compatibility:**
- Kotlin 2.3.x requires AGP ≥8.7.0 (we have 8.9.1 ✓)
- Kotlin 2.3.x supports Gradle 7.6.3–9.4.0 (we have 8.12 ✓)
- Breaking change: Old `kotlinOptions.jvmTarget` DSL deprecated; requires `kotlin.compilerOptions.jvmTarget` with enum value

**`flutter build apk --debug`:**
- Result: succeeded (78.9 s)
- Output: `build/app/outputs/flutter-apk/app-debug.apk` (216 MB)
- Warnings (pre-existing, unrelated):
  - `[options] source value 8 is obsolete and will be removed in a future release` (transitive dependency, not our code)
  - `[options] target value 8 is obsolete and will be removed in a future release` (transitive dependency, not our code)
  - 2 deprecation notes from compiled dependencies (not our code)
- No Kotlin 2.3.20 warnings; no incompatibility errors

**Tests:**
- 109/109 passing — No regression

**Status:** DONE

## Phase D3+D4 (Gradle 8.14 + AGP 8.13.0)

**Changes:**
- Gradle wrapper: 8.12 → 8.14 (`android/gradle/wrapper/gradle-wrapper.properties`)
- AGP: 8.9.1 → 8.13.0 (`android/settings.gradle.kts`)

**AGP 9 attempt — deferred:**
A prior attempt targeting AGP 9.1.1 was blocked by two upstream incompatibilities:
1. `maplibre_gl` still applies `kotlin-android` via the legacy `apply plugin:` DSL, which AGP 9 rejects (plugin must be applied via `plugins {}` block).
2. Flutter's bundled Gradle tooling requires `android.newDsl=false` to opt-out of AGP 9's DSL-breaking changes — an escape hatch not yet removed by the Flutter team.
Tracking issue: flutter/flutter#181383. AGP 9 will be revisited once maplibre_gl and Flutter's Gradle plugin are updated.

**Gradle 8.14 version rationale:**
The `services.gradle.org/versions/current` endpoint returned 9.4.1 (Gradle 9.x current). Per plan, the latest stable Gradle 8.x was chosen instead. AGP 8.13 officially supports Gradle 8.11.1–9.x; Gradle 8.14 is the highest 8.x release and is the recommended stable 8.x at time of writing.

**Exact diffs:**

`android/gradle/wrapper/gradle-wrapper.properties` (1 line):
```
- distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-all.zip
+ distributionUrl=https\://services.gradle.org/distributions/gradle-8.14-all.zip
```

`android/settings.gradle.kts` (1 line):
```
-     id("com.android.application") version "8.9.1" apply false
+     id("com.android.application") version "8.13.0" apply false
```

**Toolchain at time of change:**
- Local Java: 21.0.9 LTS
- AGP: 8.13.0 (upgraded from 8.9.1)
- Gradle wrapper: 8.14 (upgraded from 8.12)
- Kotlin: 2.3.20

**`flutter build apk --debug`:**
- Result: succeeded (292.0 s — Gradle 8.14 wrapper download included in first-run time)
- Output: `build/app/outputs/flutter-apk/app-debug.apk`
- Warnings (pre-existing, unrelated to this change):
  - `[options] source value 8 is obsolete` / `target value 8 is obsolete` (transitive deps)
  - Deprecation notes from compiled dependencies (not our code)
- No new AGP 8.13 or Gradle 8.14 warnings

**`flutter build apk --release`:**
- Result: succeeded (131.3 s)
- Output: `build/app/outputs/flutter-apk/app-release.apk` (92.4 MB)

**Tests:**
- 109/109 passing — No regression

**Deprecation warnings for future AGP 9 prep:**
- No new deprecations introduced by this bump. The pre-existing `source value 8 / target value 8 obsolete` warnings originate from transitive dependencies compiled against Java 8 bytecode targets — unrelated to our AGP/Gradle version and will need addressing upstream.

**No escape hatches added** to `android/gradle.properties`.

**Status:** DONE

## Phase E1 (flutter_lints 5 → 6)

**Change:** Bumped `flutter_lints` from `^5.0.0` to `^6.0.0` in `pubspec.yaml`.
Resolved version in `pubspec.lock`: `6.0.0`.

**New lints introduced by flutter_lints 6:**
- `strict_top_level_inference` — requires explicit type annotations on top-level variables/fields that rely on inference
- `unnecessary_underscores` — flags `_`/`__` unused-parameter names that can be simplified

**New-lint issues surfaced:** 0
Neither `strict_top_level_inference` nor `unnecessary_underscores` triggered on any file in this codebase. No code changes required.

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums

**Tests:**
- 109/109 passing — No regression

**Status:** DONE

## Phase F1 (maplibre_gl 0.24.1 → 0.25.0)

**Change:** Bumped `maplibre_gl` from `^0.24.1` to `^0.25.0` in `pubspec.yaml`.
Resolved version in `pubspec.lock`: `0.25.0` (transitive `maplibre_gl_platform_interface` and `maplibre_gl_web` also at 0.25.0).

**Changelog review:**
- maplibre_gl 0.25.0 lists NO breaking API changes.
- Features: logo customization, annotation manager init.
- Fixes: zoom preferences, feature querying, memory leaks.
- All critical APIs used in this project are unchanged:
  - `queryRenderedFeatures`, `toScreenLocation`, `addGeoJsonSource` with `promoteId: 'id'` (BUG-004 fix)
  - `addCircleLayer`, `addSymbolLayer`
  - `onMapCreated`, `onStyleLoadedCallback`, `onFeatureTapped`
  - `animateCamera`, `updateMyLocationTrackingMode`

**`flutter pub upgrade maplibre_gl`:**
- Result: Resolved to 0.25.0
- No other direct dependency changes
- Command succeeded (0 errors)

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums
- No new maplibre_gl-related warnings or errors

**Tests:**
- 109/109 passing — **No regression**

**`flutter build apk --debug`:**
- Result: succeeded (78.0 s)
- Output: `build/app/outputs/flutter-apk/app-debug.apk` (218 MB)
- Warnings: None related to maplibre_gl. Pre-existing deprecation notes from transitive dependencies only.

**`flutter build apk --release`:**
- Result: succeeded (64.8 s)
- Output: `build/app/outputs/flutter-apk/app-release.apk` (92.8 MB)
- Warnings: Font tree-shaking notice (expected, not a regression). No R8/maplibre_gl-specific warnings.

**Regression testing notes:**
- Manual BUG-001 (POI tap iOS) and BUG-004 (pin tap web) regression TBD in Phase H1 (after all F-phase commits land).
- APIs unchanged → no functional regression expected.

**Status:** DONE

## Phase E2 (flutter_launcher_icons 0.13.1 → 0.14.4)

**Change:** Bumped `flutter_launcher_icons` from `^0.13.1` to `^0.14.4` in `pubspec.yaml`.
Resolved version in `pubspec.lock`: `0.14.4`.

**New features in 0.14.x:**
- Monochrome icons for Android (adaptive icon enhancements)
- Dark/tinted icons for iOS 18+

**Icon regeneration:**
Command: `dart run flutter_launcher_icons`
- Result: succeeded
- Output: Created default icons (Android), created adaptive icons (Android), overwriting default iOS launcher icon with new icon

**Files modified/regenerated:**
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — updated (6 insertions)
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` — binary regenerated
- `ios/Runner.xcodeproj/project.pbxproj` — updated
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` — updated (123 deletions, simplified)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png` — binary regenerated
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@1x.png` — binary regenerated
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png` — binary regenerated

**`flutter build apk --debug`:**
- Result: succeeded (17.8 s)
- Output: `build/app/outputs/flutter-apk/app-debug.apk` (216 MB)

**Tests:**
- 109/109 passing — No regression

**Status:** DONE

## Phase E3 (flutter_dotenv 5 → 6)

**Change:** Bumped `flutter_dotenv` from `^5.1.0` to `^6.0.0` in `pubspec.yaml`.
Resolved version in `pubspec.lock`: `6.0.0`.

**Breaking changes in 6.0.0:**
- `testLoad()` method renamed to `loadFromString()` (same functionality)
- Parameter name changed: `fileInput` → `envString`
- Empty-file handling: when `isOptional = true`, returns empty env instead of throwing. Not used in this project.
- Dropped pre-release 2.12.0-0 Dart SDK support. We use Dart 3.11.5 (safe).

**Code changes required:**
- `test/widget_test.dart:27` — single line change: `dotenv.testLoad(fileInput: ...)` → `dotenv.loadFromString(envString: ...)`
- All other usage sites in the project (`lib/main.dart`, `lib/presentation/screens/map_screen.dart`, `lib/data/sync/background_sync.dart`) use `dotenv.load()` or `dotenv.env[...]`, which are unchanged.

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums

**Tests:**
- 109/109 passing — No regression

**Status:** DONE

## Phase F2 (geolocator 13.0.2 → 14.0.2)

**Change:** Bumped `geolocator` from `^13.0.2` to `^14.0.2` in `pubspec.yaml`.
Resolved version in `pubspec.lock`: `14.0.2`.

**Geolocator 14.0 breaking change review:**
- Flutter SDK min requirement: 3.29.0+ (we run 3.41.7 ✓)
- API renames in 14.x: **None** per changelog
- No deprecated parameter removals affecting this project
- All critical APIs used are unchanged:
  - `Geolocator.checkPermission()`, `requestPermission()`, `isLocationServiceEnabled()`
  - `Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, ...))`
  - `Geolocator.getPositionStream(locationSettings: ...)`
  - `Geolocator.openLocationSettings()`, `openAppSettings()`
  - `LocationPermission` enum (denied, deniedForever, whileInUse, always)
  - `Position` model unchanged

**Transitive bumps:**
- `geolocator_android`: transitive → 5.0.2 (major; from prior 4.x, now aligns with geolocator 14.x requirement)
- `geolocator_apple`: transitive → 2.3.13 (unchanged from prior state)

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums
- **No new geolocator-related deprecations or API warnings**

**Tests:**
- 109/109 passing — **No regression**

**`flutter build apk --debug`:**
- Result: succeeded (47.6 s)
- Output: `build/app/outputs/flutter-apk/app-debug.apk`
- Warnings: Pre-existing `[options] source/target value 8 obsolete` (transitive deps, unrelated to geolocator)

**Regression testing notes:**
- Manual BUG-003 (iOS auto-pan to user's location on cold-start) regression TBD in Phase H1 (after all F-phase commits land).
- All API call sites in `lib/data/services/location_service.dart` remain unchanged; no breaking changes detected.

**Status:** DONE

## Phase F3 (app_links 6.4.1 → 7.0.0)

**Change:** Bumped `app_links` from `^6.4.1` to `^7.0.0` in `pubspec.yaml`.
Resolved version in `pubspec.lock`: `7.0.0`.

**app_links 7.0.0 breaking changes review:**
- Minimum Flutter version: 3.38.1+ (we run 3.41.7 ✓)
- Minimum iOS deployment target: 13.0+ — **verified and met** (see below)
- No Dart API renames in 7.0 — all APIs unchanged from 6.4.1:
  - `AppLinks()` constructor (`lib/main.dart:145`)
  - `appLinks.getInitialLink()` (`lib/main.dart:149`)
  - `appLinks.uriLinkStream` (`lib/main.dart:160`)
- The 7.0 release aligns with Flutter's UIScene lifecycle updates (platform-side only; no Dart code changes required)

**iOS deployment target verification:**
- File: `ios/Runner.xcodeproj/project.pbxproj`
- Value found: `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (all occurrences, 3 lines checked)
- Status: **Meets requirement** — no Podfile changes needed

**`flutter pub upgrade app_links`:**
- Result: Resolved to 7.0.0
- Note: No direct dependency changes reported (7.0.0 was already selected by caret constraint)
- Command succeeded (0 errors)

**Analyzer:**
- 16 issues (all infos) — **No change from baseline**
  - 1 deprecated_member_use: `package:drift/web.dart`
  - 2 empty_catches: `lib/data/sync/background_sync.dart`
  - 13 constant_identifier_names: PinStatus and RestrictionTag enums
- No new app_links-related warnings or errors

**Tests:**
- 109/109 passing — **No regression**

**`flutter build apk --debug`:**
- Result: succeeded (22.6 s)
- Output: `build/app/outputs/flutter-apk/app-debug.apk`
- Warnings: Pre-existing `[options] source/target value 8 obsolete` (transitive deps, unrelated to app_links)

**Regression testing notes:**
- Manual email-confirmation deep-link regression (iOS/Android/web) TBD in Phase H1 (after all F-phase commits land).
- Dart APIs used in this project are unchanged — no functional regression expected.

**Status:** DONE
