import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/widgets/report_pin_dialog.dart';

void main() {
  group('ReportPinDialog', () {
    testWidgets('lists four reason radios and Submit/Cancel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPinDialog(onSubmit: (_, __) async {}),
          ),
        ),
      );

      expect(find.text('Inaccurate'), findsOneWidget);
      expect(find.text('Offensive'), findsOneWidget);
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Submit'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Submit is disabled until a reason is selected',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPinDialog(onSubmit: (_, __) async {}),
          ),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Offensive'));
      await tester.pumpAndSettle();
      final button2 = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Submit'),
      );
      expect(button2.onPressed, isNotNull);
    });

    testWidgets('Submit invokes callback with selected reason and note',
        (tester) async {
      ReportReason? captured;
      String? capturedNote;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportPinDialog(
              onSubmit: (reason, note) async {
                captured = reason;
                capturedNote = note;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'duplicate of another');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(captured, equals(ReportReason.SPAM));
      expect(capturedNote, equals('duplicate of another'));
    });
  });
}
