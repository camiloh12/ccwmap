import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/eula_modal.dart';

void main() {
  group('EulaModal', () {
    testWidgets('passive mode shows Got it + Read full terms; dismissible', (
      tester,
    ) async {
      var accepted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EulaModal(
              mode: EulaModalMode.passiveFirstLaunch,
              onAccept: () => accepted = true,
              onReadTerms: () {},
            ),
          ),
        ),
      );

      expect(find.widgetWithText(ElevatedButton, 'Got it'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Read full terms'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Got it'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
    });

    testWidgets(
      'retroactive mode shows I Agree + Sign Out; no passive Got it',
      (tester) async {
        var agreed = false;
        var signedOut = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EulaModal(
                mode: EulaModalMode.retroactiveBlocking,
                onAccept: () => agreed = true,
                onReadTerms: () {},
                onSignOut: () => signedOut = true,
              ),
            ),
          ),
        );

        expect(find.widgetWithText(ElevatedButton, 'I Agree'), findsOneWidget);
        expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsOneWidget);
        expect(find.widgetWithText(ElevatedButton, 'Got it'), findsNothing);

        await tester.tap(find.widgetWithText(ElevatedButton, 'I Agree'));
        await tester.pumpAndSettle();
        expect(agreed, isTrue);
        expect(signedOut, isFalse);
      },
    );

    testWidgets('Read full terms fires the callback', (tester) async {
      var read = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EulaModal(
              mode: EulaModalMode.passiveFirstLaunch,
              onAccept: () {},
              onReadTerms: () => read = true,
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Read full terms'));
      await tester.pumpAndSettle();
      expect(read, isTrue);
    });

    testWidgets('retroactive mode asserts onSignOut is provided', (
      tester,
    ) async {
      expect(
        () => EulaModal(
          mode: EulaModalMode.retroactiveBlocking,
          onAccept: () {},
          onReadTerms: () {},
        ),
        throwsAssertionError,
      );
    });
  });
}
