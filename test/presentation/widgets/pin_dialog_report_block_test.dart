import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

void main() {
  group('PinDialog Report/Block buttons', () {
    testWidgets('hidden in create mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: false,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onReport: () {},
              onBlock: () {},
            ),
          ),
        ),
      );
      expect(find.text('Report pin'), findsNothing);
      expect(find.text('Block creator of this pin'), findsNothing);
    });

    testWidgets('hidden in read-only mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              isReadOnly: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onSignInToEdit: () {},
              onReport: () {},
              onBlock: () {},
            ),
          ),
        ),
      );
      expect(find.text('Report pin'), findsNothing);
      expect(find.text('Block creator of this pin'), findsNothing);
    });

    testWidgets('hidden in edit mode when callbacks are null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('Report pin'), findsNothing);
      expect(find.text('Block creator of this pin'), findsNothing);
    });

    testWidgets('visible in edit mode when callbacks provided', (tester) async {
      var reported = false;
      var blocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onDelete: () {},
              onReport: () => reported = true,
              onBlock: () => blocked = true,
            ),
          ),
        ),
      );

      // Scroll the dialog into view if needed.
      await tester.ensureVisible(find.text('Report pin'));
      await tester.tap(find.text('Report pin'));
      await tester.pumpAndSettle();
      expect(reported, isTrue);

      await tester.ensureVisible(find.text('Block creator of this pin'));
      await tester.tap(find.text('Block creator of this pin'));
      await tester.pumpAndSettle();
      expect(blocked, isTrue);
    });

    testWidgets('shows the custom report label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onReport: () {},
              reportLabel: 'Report a problem',
            ),
          ),
        ),
      );
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Report pin'), findsNothing);
    });

    testWidgets('reported state is disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              poiName: 'x',
              initialStatus: PinStatus.ALLOWED,
              onConfirm: (_) {},
              onCancel: () {},
              onReport: () {},
              isReported: true,
            ),
          ),
        ),
      );
      expect(find.text('Reported'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Reported'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}
