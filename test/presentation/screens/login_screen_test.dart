import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/screens/login_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('LoginScreen auto-pop on auth', () {
    testWidgets('pops when authStateChanges emits an authenticated user', (
      tester,
    ) async {
      // Reproduces the race that required two Sign In taps before this fix:
      // Supabase's signInWithPassword resolves before the onAuthStateChange
      // stream delivers the new user to the ViewModel, so an imperative
      // `isAuthenticated` check right after `await signIn(...)` misses.
      // LoginScreen must react to the stream, not to the signIn Future.
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authViewModel,
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
        ),
      );

      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // Simulate the auth stream emitting a user AFTER the screen is up,
      // without any user interaction on LoginScreen — the same shape as
      // the real race where the stream event arrives after signIn() returns.
      fakeRepo.setCurrentUser(User(id: 'test-id', email: 'me@example.com'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);

      fakeRepo.dispose();
      authViewModel.dispose();
    });

    testWidgets('stays when authStateChanges emits null (still guest)', (
      tester,
    ) async {
      final fakeRepo = FakeAuthRepository();
      final authViewModel = AuthViewModel(fakeRepo);
      await authViewModel.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: authViewModel,
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
        ),
      );

      await tester.tap(find.text('open login'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      // No auth change → no pop.
      fakeRepo.setCurrentUser(null);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);

      fakeRepo.dispose();
      authViewModel.dispose();
    });
  });
}
