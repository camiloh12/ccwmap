import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/presentation/screens/forgot_password_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

Widget _hostedScreen(AuthViewModel vm) {
  return ChangeNotifierProvider<AuthViewModel>.value(
    value: vm,
    child: const MaterialApp(home: ForgotPasswordScreen()),
  );
}

void main() {
  group('ForgotPasswordScreen', () {
    testWidgets('empty email blocks submit with validation error',
        (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await tester.pumpWidget(_hostedScreen(vm));

      await tester.tap(find.text('Send reset link'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
      expect(fake.sendResetCallCount, 0);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('valid email + submit calls VM and shows success state',
        (tester) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await tester.pumpWidget(_hostedScreen(vm));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      expect(fake.sendResetCallCount, 1);
      expect(fake.sendResetLastEmail, 'user@example.com');
      expect(find.textContaining('user@example.com'), findsOneWidget);
      expect(find.text('Back to sign in'), findsOneWidget);
      expect(find.text('Send reset link'), findsNothing);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('error from VM renders the red banner', (tester) async {
      final fake = FakeAuthRepository();
      fake.sendResetShouldThrow = true;
      final vm = AuthViewModel(fake);
      await tester.pumpWidget(_hostedScreen(vm));

      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      // Generic catch-all copy from sendPasswordReset's `catch (e)` branch.
      expect(find.textContaining('Could not send reset link'), findsOneWidget);
      // Stays on form, does NOT show success state.
      expect(find.text('Send reset link'), findsOneWidget);

      vm.dispose();
      fake.dispose();
    });
  });
}
