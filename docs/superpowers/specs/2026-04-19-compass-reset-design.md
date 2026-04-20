# Compass Reset Button — Design

**Date:** 2026-04-19
**Status:** Draft — pending user review
**Scope:** Add a compass button to the map screen that resets the map's bearing and pitch when tapped, with an icon that rotates live to reflect the current bearing.

## Motivation

The map currently has `rotateGesturesEnabled: true` and `tiltGesturesEnabled: true`, but `compassEnabled: false` (MapLibre's built-in compass is disabled). A user who rotates the map has no obvious way to restore north-up orientation. The re-center FAB (`my_location`) only pans to the user's location; it does not change bearing or pitch.

## Behavior

- **Visibility:** Always visible.
- **Icon:** `Icons.explore` (compass rose). The icon is rotated live via `Transform.rotate` by `-bearing * pi / 180` radians, so the "N" on the compass stays pointing to geographic north as the map rotates. MapLibre bearing is degrees clockwise, so the icon rotates counter-clockwise.
- **On tap:** Animate the camera to `bearing: 0, tilt: 0`, preserving current target and zoom. 300 ms duration. The controller's `ChangeNotifier` fires during the animation, so the icon spins smoothly back to 0 alongside the map.
- **Accessibility:** `Tooltip` ("Reset map orientation to north") + `semanticLabel` on the icon, matching the re-center FAB pattern.

## Placement

Bottom-right cluster, stacked directly above the existing re-center FAB.

- Re-center FAB: `bottom: 96, right: 16` (unchanged).
- Compass button: `bottom: 160, right: 16` (16 px gap above the re-center FAB; standard FAB diameter is 56 px, so 96 + 56 + 8 = 160).

Style matches the re-center FAB: light-purple background (`Color(0xFFE8DEF8)`), elevation 4, `black87` icon.

## Architecture

### New widget: `CompassButton`

File: `lib/presentation/widgets/compass_button.dart`.

A `StatefulWidget` that owns its own rebuild cycle so `MapScreen` (~1500 lines) is not rebuilt on every camera tick.

**Constructor parameters:**

- `Listenable? listenable` — typically the `MapLibreMapController`, which is a `ChangeNotifier`. Nullable because the controller is null until `onMapCreated` fires.
- `double Function()? bearingGetter` — returns the current bearing in degrees. Typically `() => mapController.cameraPosition?.bearing ?? 0.0`. Nullable for the same reason.
- `VoidCallback onReset` — invoked on tap. `MapScreen` supplies this.

Taking a `Listenable` and a getter (instead of a `MapLibreMapController` directly) keeps the widget framework-agnostic and testable without a MapLibre mock.

**Behavior:**

- `initState`: if `listenable` is non-null, subscribes with `listenable.addListener(_onChange)`. `_onChange` reads `bearingGetter()` and calls `setState` only if the bearing actually changed (avoid redundant rebuilds during non-rotation camera moves like panning).
- `dispose`: unsubscribes.
- `didUpdateWidget`: if the `listenable` identity changes, re-subscribe.
- `build`: renders a `FloatingActionButton` identical in style to the re-center FAB, with an `Icons.explore` child wrapped in `Transform.rotate(angle: -bearing * pi / 180)`.

### `MapScreen` changes

In `lib/presentation/screens/map_screen.dart`:

1. Import the new widget and `dart:math` (for `pi`, if not already imported).
2. Add a new `Positioned` entry in the `Stack` children at `bottom: 160, right: 16` rendering `CompassButton(listenable: _mapController, bearingGetter: () => _mapController?.cameraPosition?.bearing ?? 0.0, onReset: _onCompassTapped)`.
3. Add a new method `_onCompassTapped`:

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

No changes to `compassEnabled`, `rotateGesturesEnabled`, or `tiltGesturesEnabled` on `MapLibreMap`.

## Testing

New file: `test/presentation/widgets/compass_button_test.dart`. Three tests:

1. **Icon rotates with bearing changes** — construct `CompassButton` with a `ValueNotifier<double>` as both the listenable and the backing for the bearing getter. Pump the widget, change the notifier, pump again, verify the `Transform.rotate` angle matches `-bearing * pi / 180`.
2. **Tap invokes `onReset`** — pump the widget with a spy callback, tap the FAB, verify the spy fires exactly once.
3. **Null controller renders safely** — pass `listenable: null, bearingGetter: null`, pump, verify no exception and the icon renders at angle 0.

No widget test is added for `MapScreen` itself. Per CLAUDE.md, testing targets are: domain 100%, mappers 100%, repositories 90%+, ViewModels 80%+, UI 50%+. The new widget is fully covered on its own; the `MapScreen` wiring is trivial composition.

## Edge cases

- **Tap during in-flight animation:** `animateCamera` retargets cleanly; no explicit guard.
- **Null camera position before map is ready:** `_onCompassTapped` early-returns; the button renders at bearing 0 with a no-op tap.
- **Web:** `MapLibreMapController.animateCamera` with `CameraUpdate.newCameraPosition` works uniformly across Android/iOS/web per the `maplibre_gl` package. To be verified post-implementation by opening the map in a browser, rotating with shift+drag, and tapping the compass.
- **Bearing wrap-around (0° ↔ 360°):** not a visual problem because `Transform.rotate` handles arbitrary angles; the reset animation goes through whichever direction MapLibre chooses (acceptable — both Google and Apple Maps behave this way).

## Out of scope

- Auto-hide when `bearing == 0`.
- Non-FAB styling (e.g., custom compass rose artwork).
- Device-sensor heading indicator.
- Migrating to MapLibre's built-in `compassEnabled: true`.
- Any changes to the existing re-center FAB.

## Files touched

- **New:** `lib/presentation/widgets/compass_button.dart`
- **New:** `test/presentation/widgets/compass_button_test.dart`
- **Modified:** `lib/presentation/screens/map_screen.dart` (one `Positioned` added to the `Stack`, one new method, possibly a `dart:math` import)
