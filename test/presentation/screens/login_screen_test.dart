import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/screens/forgot_password_screen.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

Widget _wrappedLoginEntry(AuthViewModel vm) {
  return ChangeNotifierProvider<AuthViewModel>.value(
    value: vm,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LoginScreen(),
                ),
              ),
              child: const Text('open login'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('LoginScreen auto-pop on auth', () {
    testWidgets('pops when authStateChanges emits an authenticated user',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.setCurrentUser(User(id: 'test-id', email: 'me@example.com'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('stays when authStateChanges emits null (still guest)',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.setCurrentUser(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets(
        'does NOT auto-pop when auth flips during password recovery '
        '(_AppRoot is responsible for pushing ResetPasswordScreen on top, and '
        'a self-pop here pops that screen out from under the user)',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // Real flow: getSessionFromUrl on a recovery code creates a session
      // AND fires AuthChangeEvent.passwordRecovery in the same SDK callback.
      // Both reach AuthViewModel before the next frame.
      fakeRepo.emitPasswordRecovery();
      fakeRepo.setCurrentUser(User(id: 'test-id', email: 'me@example.com'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget,
          reason: 'LoginScreen must remain so the recovery screen pushed by '
              '_AppRoot stays on top instead of being popped.');

      fakeRepo.dispose();
      authViewModel.dispose();
    });
  });

  group('LoginScreen post-split structure', () {
    testWidgets('does not render EULA checkbox or Create Account button',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Create Account'), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('"Forgot password?" link pushes ForgotPasswordScreen',
        (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('"Sign up" footer link pushes SignUpScreen', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      // SignUpScreen only reads AgreementsRepository inside its submit
      // handler, not during build. So a build-without-submit test like
      // this one needs no agreements provider.
      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Don't have an account? Sign up"));
      await tester.pumpAndSettle();

      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('sign-in form accepts a 5-character password (no client-side '
        'min-length on sign-in)', (tester) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(_wrappedLoginEntry(authViewModel));
      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'short');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle();

      // No client-side validator should have stopped the submit.
      expect(find.text('Password must be at least 6 characters'), findsNothing);
      // The fake's signIn auto-authenticates — LoginScreen should pop.
      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });
  });
}
