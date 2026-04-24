import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:ccwmap/presentation/widgets/sign_in_prompt_sheet.dart';
import '../../fakes/fake_auth_repository.dart';

void main() {
  group('SignInPromptSheet', () {
    testWidgets('renders title, body, and three buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SignInPromptSheet(
                      title: 'Sign in to add pins',
                      body:
                          'Create an account or sign in to contribute to the community map.',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to add pins'), findsOneWidget);
      expect(
        find.text(
          'Create an account or sign in to contribute to the community map.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Create Account'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Cancel dismisses the sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const SignInPromptSheet(
                      title: 't',
                      body: 'b',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInPromptSheet), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInPromptSheet), findsNothing);
    });

    testWidgets(
      'tapping Sign In pushes a new route; tapping Create Account pushes another',
      (tester) async {
        int pushedRoutes = 0;
        final fakeAuthRepo = FakeAuthRepository();
        final authViewModel = AuthViewModel(fakeAuthRepo);

        Widget buildSheet(BuildContext ctx) => const SignInPromptSheet(
          title: 't',
          body: 'b',
        );

        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewModel>.value(
            value: authViewModel,
            child: MaterialApp(
              navigatorObservers: [
                _CountingObserver(onPush: () => pushedRoutes++),
              ],
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        builder: buildSheet,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // After pumpWidget the home route has been pushed once.
        // Tap 'open' — the modal sheet is pushed (pushedRoutes increments).
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Capture count after sheet is showing (home + sheet = 2 so far).
        final countAfterSheetOpen = pushedRoutes;

        // Tap Sign In — sheet pops (no push), LoginScreen is pushed.
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
        await tester.pumpAndSettle();
        expect(pushedRoutes, countAfterSheetOpen + 1); // LoginScreen pushed

        // Go back to the home screen so we can re-open the sheet.
        final NavigatorState nav = tester.state(find.byType(Navigator).first);
        nav.pop();
        await tester.pumpAndSettle();

        // Re-open the sheet and tap Create Account.
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Sheet is open again — capture count (includes sheet push).
        final countAfterSecondSheetOpen = pushedRoutes;

        await tester.tap(find.widgetWithText(OutlinedButton, 'Create Account'));
        await tester.pumpAndSettle();
        expect(pushedRoutes, countAfterSecondSheetOpen + 1); // second LoginScreen pushed

        fakeAuthRepo.dispose();
      },
    );
  });
}

class _CountingObserver extends NavigatorObserver {
  final VoidCallback onPush;
  _CountingObserver({required this.onPush});
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onPush();
    super.didPush(route, previousRoute);
  }
}
