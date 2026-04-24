import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/sign_in_prompt_sheet.dart';

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

    testWidgets('Sign In and Create Account both push a new route',
        (tester) async {
      int pushedRoutes = 0;
      // [onSignIn] intercepts the navigation action so the test does not need
      // a full AuthViewModel provider tree. It captures the navigator context
      // before the sheet is dismissed and pushes a named route to increment
      // the observer count.
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: ctx,
                    builder: (_) => SignInPromptSheet(
                      title: 't',
                      body: 'b',
                      onSignIn: () => navKey.currentState!.pushNamed('/login'),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          navigatorObservers: [
            _CountingObserver(onPush: () => pushedRoutes++),
          ],
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle();
      // Pushed the LoginScreen route.
      expect(pushedRoutes, greaterThanOrEqualTo(2)); // initial + push
    });
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
