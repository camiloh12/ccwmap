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
