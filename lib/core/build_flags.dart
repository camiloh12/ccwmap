import 'package:flutter/foundation.dart';

/// Compile-time build configuration flags.
///
/// All flags in this file are `const` so Dart's compiler tree-shakes disabled
/// code paths out of release binaries — a flag that evaluates to `false` at
/// compile time leaves no trace in the production APK/IPA.

/// Whether to expose the on-screen debug UI (bug-icon toggle in the top bar
/// and the tap-detection overlay).
///
/// Resolution:
///   • `flutter run` (debug) or `flutter run --profile`        → true
///   • `flutter build … --release --dart-define=SHOW_DEBUG_UI=true` → true
///   • `flutter build … --release` (no flag)                   → false
///
/// Keep `--dart-define=SHOW_DEBUG_UI=true` on internal/TestFlight workflows
/// and OMIT it on App Store / Play Store release workflows so the debug UI
/// never ships to end users. See the "CI/CD & Build Flags" section of
/// CLAUDE.md.
const bool kShowDebugUI =
    !kReleaseMode || bool.fromEnvironment('SHOW_DEBUG_UI');
