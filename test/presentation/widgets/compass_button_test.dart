import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/compass_button.dart';

void main() {
  group('CompassButton', () {
    testWidgets('icon rotation matches -(bearing + 45) * pi / 180 radians', (
      tester,
    ) async {
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

      bearing.value = 90.0;
      await tester.pump();

      final rotateWidget = tester.widget<Transform>(
        find.descendant(
          of: find.byType(CompassButton),
          matching: find.byType(Transform),
        ),
      );

      const expectedAngle = -(90.0 + 45.0) * math.pi / 180.0;
      expect(
        rotateWidget.transform.entry(0, 0),
        closeTo(math.cos(expectedAngle), 1e-9),
      );
      expect(
        rotateWidget.transform.entry(1, 0),
        closeTo(math.sin(expectedAngle), 1e-9),
      );

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

    testWidgets('renders safely with null listenable and null getter', (
      tester,
    ) async {
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

      // Null getter → bearing 0 → angle = -45° (icon-offset only).
      const expectedAngle = -45.0 * math.pi / 180.0;
      final rotateWidget = tester.widget<Transform>(
        find.descendant(
          of: find.byType(CompassButton),
          matching: find.byType(Transform),
        ),
      );
      expect(
        rotateWidget.transform.entry(0, 0),
        closeTo(math.cos(expectedAngle), 1e-9),
      );
      expect(
        rotateWidget.transform.entry(1, 0),
        closeTo(math.sin(expectedAngle), 1e-9),
      );
    });

    testWidgets('FAB has null heroTag to avoid duplicate-Hero assertions', (
      tester,
    ) async {
      // CompassButton is stacked with another FAB on MapScreen. Two FABs with
      // the default heroTag in the same route throw "multiple heroes share the
      // same tag" on every route push/pop (modal sheets, dialogs, etc.).
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

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.heroTag, isNull);
    });
  });
}
