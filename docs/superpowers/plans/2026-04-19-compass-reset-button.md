# Compass Reset Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bottom-right FAB that rotates live with the map's bearing and resets bearing + pitch to 0 when tapped.

**Architecture:** A new self-contained `CompassButton` `StatefulWidget` takes a `Listenable` (the `MapLibreMapController`) and a `double Function()` bearing getter, and only it rebuilds when the map rotates — so `MapScreen`'s ~1500-line tree isn't touched on every camera tick. `MapScreen` supplies the controller, the getter, and a `_onCompassTapped` handler that calls `animateCamera(CameraUpdate.newCameraPosition(...))` with `bearing: 0.0, tilt: 0.0`.

**Tech Stack:** Flutter 3.x, `maplibre_gl: ^0.24.1` (controller is a `ChangeNotifier` that fires `notifyListeners()` on every camera move, confirmed at `maplibre_gl-0.24.1/lib/src/controller.dart:182-185`). No new dependencies.

**Spec reference:** `docs/superpowers/specs/2026-04-19-compass-reset-design.md`

---

## File Structure

- **Create** `lib/presentation/widgets/compass_button.dart` — new `CompassButton` widget, ~60 LOC, no business logic.
- **Create** `test/presentation/widgets/compass_button_test.dart` — three widget tests; uses `ValueNotifier<double>` to stand in for the controller (no MapLibre mock needed).
- **Modify** `lib/presentation/screens/map_screen.dart` — add one `import`, add one `_onCompassTapped` method, add one `Positioned` entry in the existing `Stack`, and flip `compassEnabled: true` → `compassEnabled: false` (commit `5fca5f5` enabled MapLibre's built-in compass; the custom `CompassButton` replaces it, so the built-in must be turned off to avoid two compasses). `dart:math` is already imported as `math` (line 3), so `math.pi` is available without a new import.

---

### Task 1: `CompassButton` widget (TDD)

**Files:**
- Create: `test/presentation/widgets/compass_button_test.dart`
- Create: `lib/presentation/widgets/compass_button.dart`

- [ ] **Step 1: Write the failing test file**

Create `test/presentation/widgets/compass_button_test.dart`:

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/compass_button.dart';

void main() {
  group('CompassButton', () {
    testWidgets('icon rotation matches -bearing * pi / 180 radians',
        (tester) async {
      final bearing = ValueNotifier<double>(0.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompassButton(
              listenable: bearing,
              bearingGetter: () => bearing.value,
              onReset: () {},
            ),
          ),
        ),
      );

      // At bearing 0, the Transform.rotate angle should be 0.
      Transform rotateWidget = tester.widget<Transform>(
        find.descendant(
          of: find.byType(CompassButton),
          matching: find.byType(Transform),
        ),
      );
      // Transform.rotate stores rotation in entry [0][0] = cos(angle);
      // easier to pump and read the angle we configured. Re-read via key.
      // Instead: verify by changing bearing and checking the matrix updates.

      // Change bearing to 90 degrees.
      bearing.value = 90.0;
      await tester.pump();

      rotateWidget = tester.widget<Transform>(
        find.descendant(
          of: find.byType(CompassButton),
          matching: find.byType(Transform),
        ),
      );

      // At bearing 90, icon rotation = -90 * pi / 180 = -pi/2.
      // Matrix4 Z-rotation at angle theta has [0][0] = cos(theta).
      // cos(-pi/2) ≈ 0; sin(-pi/2) = -1. Verify [0][0] is close to 0.
      expect(rotateWidget.transform.entry(0, 0), closeTo(0.0, 1e-9));
      expect(rotateWidget.transform.entry(1, 0), closeTo(-1.0, 1e-9));

      bearing.dispose();
    });

    testWidgets('tap invokes onReset exactly once', (tester) async {
      final bearing = ValueNotifier<double>(0.0);
      var resetCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompassButton(
              listenable: bearing,
              bearingGetter: () => bearing.value,
              onReset: () => resetCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(CompassButton));
      await tester.pump();

      expect(resetCount, 1);
      bearing.dispose();
    });

    testWidgets('renders safely with null listenable and null getter',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompassButton(
              listenable: null,
              bearingGetter: null,
              onReset: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CompassButton), findsOneWidget);
      expect(find.byIcon(Icons.explore), findsOneWidget);

      // No bearing → rotation angle 0 → matrix [0][0] = cos(0) = 1.
      final rotateWidget = tester.widget<Transform>(
        find.descendant(
          of: find.byType(CompassButton),
          matching: find.byType(Transform),
        ),
      );
      expect(rotateWidget.transform.entry(0, 0), closeTo(1.0, 1e-9));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/presentation/widgets/compass_button_test.dart`

Expected: FAIL — "Target of URI doesn't exist: 'package:ccwmap/presentation/widgets/compass_button.dart'" or "Undefined class 'CompassButton'".

- [ ] **Step 3: Write the widget implementation**

Create `lib/presentation/widgets/compass_button.dart`:

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class CompassButton extends StatefulWidget {
  final Listenable? listenable;
  final double Function()? bearingGetter;
  final VoidCallback onReset;

  const CompassButton({
    super.key,
    required this.listenable,
    required this.bearingGetter,
    required this.onReset,
  });

  @override
  State<CompassButton> createState() => _CompassButtonState();
}

class _CompassButtonState extends State<CompassButton> {
  double _bearing = 0.0;

  @override
  void initState() {
    super.initState();
    _readBearing();
    widget.listenable?.addListener(_onChange);
  }

  @override
  void didUpdateWidget(CompassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_onChange);
      widget.listenable?.addListener(_onChange);
      _readBearing();
    }
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_onChange);
    super.dispose();
  }

  void _readBearing() {
    final next = widget.bearingGetter?.call() ?? 0.0;
    _bearing = next;
  }

  void _onChange() {
    final next = widget.bearingGetter?.call() ?? 0.0;
    if (next != _bearing) {
      setState(() => _bearing = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: widget.onReset,
      backgroundColor: const Color(0xFFE8DEF8),
      elevation: 4,
      tooltip: 'Reset map orientation to north',
      child: Transform.rotate(
        angle: -_bearing * math.pi / 180.0,
        child: const Icon(
          Icons.explore,
          color: Colors.black87,
          semanticLabel: 'Reset map orientation to north',
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/presentation/widgets/compass_button_test.dart`

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/compass_button.dart test/presentation/widgets/compass_button_test.dart
git commit -m "feat: add CompassButton widget

Self-contained widget that listens to a Listenable (typically the
MapLibreMapController) and rotates its compass icon to reflect the
current bearing. Calls onReset on tap."
```

---

### Task 2: Wire `CompassButton` into `MapScreen`

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart` (flip `compassEnabled: true` → `false` on `MapLibreMap`; add import; add `_onCompassTapped` near `_onRecenterTapped` at line 1220; add `Positioned` entry in `Stack` just before or after the re-center FAB at line 1490–1505)

- [ ] **Step 1: Disable MapLibre's built-in compass**

The built-in compass was enabled in commit `5fca5f5`. Since the custom `CompassButton` replaces it, the built-in must be disabled to avoid rendering two compasses.

In `lib/presentation/screens/map_screen.dart`, change:

```dart
              compassEnabled: true,
```

to:

```dart
              compassEnabled: false,
```

(Location: inside the `MapLibreMap` widget constructor, near the other gesture/enable flags.)

- [ ] **Step 2: Add the import**

At the top of `lib/presentation/screens/map_screen.dart`, add alongside the other `ccwmap` widget imports (after line 17 `import 'package:ccwmap/presentation/widgets/pin_dialog.dart';`):

```dart
import 'package:ccwmap/presentation/widgets/compass_button.dart';
```

- [ ] **Step 3: Add the `_onCompassTapped` method**

Immediately after the `_onRecenterTapped` method (ends at line 1253), add:

```dart
  Future<void> _onCompassTapped() async {
    final controller = _mapController;
    final current = controller?.cameraPosition;
    if (controller == null || current == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current.target,
          zoom: current.zoom,
          bearing: 0.0,
          tilt: 0.0,
        ),
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
```

No new imports required: `CameraUpdate` and `CameraPosition` come from the existing `package:maplibre_gl/maplibre_gl.dart` import at line 8.

- [ ] **Step 4: Add the `Positioned` entry in the `Stack`**

Immediately after the closing `),` of the re-center FAB's `Positioned` (line 1505), insert:

```dart
          // Compass reset FAB (stacked above re-center FAB).
          Positioned(
            bottom: 160,
            right: 16,
            child: CompassButton(
              listenable: _mapController,
              bearingGetter: () =>
                  _mapController?.cameraPosition?.bearing ?? 0.0,
              onReset: _onCompassTapped,
            ),
          ),
```

- [ ] **Step 5: Run the existing widget test to verify no regression**

Run: `flutter test test/widget_test.dart`

Expected: both tests still PASS ("App launches and shows CCW Map title when authenticated" and "App shows login screen when not authenticated").

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`

Expected: all tests PASS (74 existing + 3 new = 77 total).

- [ ] **Step 7: Run Flutter analyzer**

Run: `flutter analyze`

Expected: no new warnings or errors attributable to the changes.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat: wire CompassButton into MapScreen

Replaces MapLibre's built-in compass (which had placement and style
issues across platforms) with a custom CompassButton stacked above
the re-center FAB. Tapping it animates the camera to bearing 0 and
tilt 0 over 300 ms, preserving current target and zoom."
```

---

### Task 3: Manual verification across platforms

The automated tests cover widget behavior in isolation. The integration with MapLibre must be verified by hand because there is no MapLibre test harness in this repo.

**Files:** None (verification only).

- [ ] **Step 1: Verify on web (fastest feedback loop, Windows-native)**

Run: `flutter run -d chrome`

Checks:
1. Compass FAB is visible at bottom-right, directly above the re-center FAB with a consistent gap.
2. Style matches the re-center FAB (light-purple `#E8DEF8` background, FAB shape, elevation).
3. Rotate the map (shift+drag on web): the compass icon rotates counter-clockwise as the map rotates clockwise, keeping "N" pointed at true north.
4. Tilt the map (ctrl+drag on web): pitch changes.
5. Tap the compass FAB: map animates to bearing 0 and tilt 0 over ~300 ms; icon spins to upright simultaneously.
6. Tap the compass when already at bearing 0 and tilt 0: no-op (or inconsequential re-anim); no errors.

- [ ] **Step 2: Verify on Android**

Run: `flutter run -d <android-device-id>` (use `flutter devices` to list).

Repeat checks 1–6 from Step 1. On Android the rotation gesture is two-finger twist; tilt is two-finger vertical drag.

- [ ] **Step 3: Verify on iOS**

iOS builds run via GitHub Actions (see CLAUDE.md: "iOS builds: GitHub Actions only"). Trigger the `ios-testflight.yml` workflow and verify on a TestFlight build. Repeat checks 1–6 from Step 1. iOS gestures are identical to Android (two-finger twist to rotate, two-finger vertical drag to tilt).

- [ ] **Step 4: Final confirmation**

If all three platforms behave correctly, update the spec's `Status:` line from "Draft — pending user review" to "Implemented" and commit:

```bash
git add docs/superpowers/specs/2026-04-19-compass-reset-design.md
git commit -m "docs: mark compass-reset spec as implemented"
```

---

## Self-Review

**Spec coverage:**
- Visibility (always visible) → Task 1 (widget always renders) + Task 2 Step 4 (always in the `Stack`). ✅
- Icon = `Icons.explore`, rotated by `-bearing * pi / 180` → Task 1 Step 3 `build` method. ✅
- On-tap resets bearing + tilt → Task 2 Step 3 `_onCompassTapped`. ✅
- Accessibility (Tooltip + `semanticLabel`) → Task 1 Step 3. ✅
- Placement `bottom: 160, right: 16` → Task 2 Step 4. ✅
- Style matches re-center FAB → Task 1 Step 3. ✅
- Widget constructor with `Listenable?` + `double Function()?` + `VoidCallback` → Task 1 Step 3. ✅
- Three-test suite → Task 1 Step 1. ✅
- Verify on web (shift+drag) → Task 3 Step 1. ✅
- Deviation from spec: the spec says "No changes to `compassEnabled`", but between spec approval and plan writing, commit `5fca5f5` set `compassEnabled: true`. Task 2 Step 1 flips it back to `false` so the custom button replaces the built-in one (documented reasoning in the File Structure section). ✅

**Placeholder scan:** No `TBD`, `TODO`, "handle edge cases", or vague instructions. All code blocks are complete and copy-pasteable.

**Type consistency:** `CompassButton` constructor parameters (`listenable`, `bearingGetter`, `onReset`) are identical in the test (Task 1 Step 1), the implementation (Task 1 Step 3), and the call site (Task 2 Step 4). `_onCompassTapped` is declared in Task 2 Step 3 and referenced in Task 2 Step 4.
