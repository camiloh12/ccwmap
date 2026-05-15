import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/screens/reset_password_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

Future<void> _pumpAndPushResetScreen(
  WidgetTester tester,
  AuthViewModel vm,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewModel>.value(
      value: vm,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ResetPasswordScreen(),
                  ),
                ),
                child: const Text('open reset'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open reset'));
  // Drive the push animation to completion frame-by-frame.
  // pumpAndSettle() deadlocks when the pushed screen contains
  // PopScope(canPop: false) in some Flutter versions; explicit pump calls
  // advance exactly one frame each and always return.
  await tester.pump(); // schedule the push
  await tester.pump(
    const Duration(milliseconds: 300),
  ); // complete the route animation
}

Future<(FakeAuthRepository, AuthViewModel)> _setupRecoveryVm() async {
  final fake = FakeAuthRepository();
  final vm = AuthViewModel(fake);
  await vm.initialize();
  // emitPasswordRecovery delivers synchronously to the broadcast stream listener,
  // so _isInPasswordRecovery is already true after this call — no delay needed.
  fake.emitPasswordRecovery();
  return (fake, vm);
}

void main() {
  group('ResetPasswordScreen', () {
    testWidgets('mismatched passwords block submit with validation error', (
      tester,
    ) async {
      final (fake, vm) = await _setupRecoveryVm();
      await _pumpAndPushResetScreen(tester, vm);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'newpass123');
      await tester.enterText(fields.at(1), 'different');
      await tester.tap(find.text('Update password'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(fake.updatePasswordCallCount, 0);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('matching passwords + submit calls VM', (tester) async {
      final (fake, vm) = await _setupRecoveryVm();
      await _pumpAndPushResetScreen(tester, vm);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'newpass123');
      await tester.enterText(fields.at(1), 'newpass123');
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();

      expect(fake.updatePasswordCallCount, 1);
      expect(fake.updatePasswordLastValue, 'newpass123');
      expect(vm.isInPasswordRecovery, isFalse);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('cancel signs out and clears recovery state', (tester) async {
      final (fake, vm) = await _setupRecoveryVm();
      // Make the VM look like a logged-in recovery session.
      fake.setCurrentUser(User(id: 'u1', email: 'u1@example.com'));
      await _pumpAndPushResetScreen(tester, vm);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(vm.isAuthenticated, isFalse); // signOut was called
      expect(vm.isInPasswordRecovery, isFalse);

      vm.dispose();
      fake.dispose();
    });
  });
}
