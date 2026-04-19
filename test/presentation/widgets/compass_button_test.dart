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
