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
