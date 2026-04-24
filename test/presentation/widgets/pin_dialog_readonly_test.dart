import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

void main() {
  group('PinDialog read-only mode', () {
    Future<void> pumpReadOnly(
      WidgetTester tester, {
      bool onSignInCalled = false,
      VoidCallback? onSignIn,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinDialog(
              isEditMode: true,
              isReadOnly: true,
              poiName: 'Courthouse',
              initialStatus: PinStatus.NO_GUN,
              initialRestrictionTag: RestrictionTag.STATE_LOCAL_GOVT,
              initialHasSecurityScreening: true,
              initialHasPostedSignage: false,
              onConfirm: (_) {},
              onCancel: () {},
              onSignInToEdit: onSignIn ?? () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders "Sign in to edit" and "Close", hides Save/Delete', (
      tester,
    ) async {
      await pumpReadOnly(tester);

      expect(
        find.widgetWithText(ElevatedButton, 'Sign in to edit'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Save'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Delete Pin'), findsNothing);
    });

    testWidgets('name field is disabled in read-only mode', (tester) async {
      await pumpReadOnly(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('Sign in to edit triggers the callback', (tester) async {
      var called = false;
      await pumpReadOnly(tester, onSignIn: () => called = true);

      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Sign in to edit'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in to edit'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });
  });
}
