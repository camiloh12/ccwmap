import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('AuthViewModel.sendPasswordReset', () {
    late FakeAuthRepository fake;
    late AuthViewModel vm;

    setUp(() {
      fake = FakeAuthRepository();
      vm = AuthViewModel(fake);
    });

    tearDown(() {
      vm.dispose();
      fake.dispose();
    });

    test('passes email through to repository without modification', () async {
      await vm.sendPasswordReset('user@example.com');
      expect(fake.sendResetCallCount, 1);
      expect(fake.sendResetLastEmail, 'user@example.com');
      expect(vm.error, isNull);
    });

    test('toggles isLoading around the call', () async {
      expect(vm.isLoading, isFalse);
      final future = vm.sendPasswordReset('u@example.com');
      expect(vm.isLoading, isTrue);
      await future;
      expect(vm.isLoading, isFalse);
    });

    test('rate-limit error formats to friendly copy', () async {
      fake.sendResetShouldThrow = true;
      fake.sendResetThrownError = const supabase.AuthException(
        'over_email_send_rate_limit: too many requests',
      );
      await vm.sendPasswordReset('u@example.com');
      expect(vm.error, contains('Too many'));
    });
  });

  group('AuthViewModel.updatePassword', () {
    late FakeAuthRepository fake;
    late AuthViewModel vm;

    setUp(() async {
      fake = FakeAuthRepository();
      vm = AuthViewModel(fake);
      await vm.initialize();
      // Put the VM into recovery mode by emitting the synthetic event.
      fake.emitPasswordRecovery();
      // Allow the broadcast stream to deliver.
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() {
      vm.dispose();
      fake.dispose();
    });

    test('precondition: recovery flag is set after the synthetic event',
        () {
      expect(vm.isInPasswordRecovery, isTrue);
    });

    test('success clears the recovery flag', () async {
      await vm.updatePassword('newpass123');
      expect(fake.updatePasswordCallCount, 1);
      expect(fake.updatePasswordLastValue, 'newpass123');
      expect(vm.isInPasswordRecovery, isFalse);
      expect(vm.error, isNull);
    });

    test('failure: surfaces error and leaves the recovery flag set',
        () async {
      fake.updatePasswordShouldThrow = true;
      fake.updatePasswordThrownError = const supabase.AuthException(
        'New password should be different from the old password.',
      );
      await vm.updatePassword('newpass123');
      expect(vm.error, contains('differ'));
      expect(vm.isInPasswordRecovery, isTrue);
    });

    test('expired-link error formats to friendly copy', () async {
      fake.updatePasswordShouldThrow = true;
      fake.updatePasswordThrownError = const supabase.AuthException(
        'Token has expired or is invalid (otp_expired).',
      );
      await vm.updatePassword('newpass123');
      expect(vm.error, contains('expired'));
    });
  });

  group('AuthViewModel password-recovery flag plumbing', () {
    test('emitPasswordRecovery sets the flag and notifies listeners',
        () async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await vm.initialize();
      var notified = 0;
      vm.addListener(() => notified++);

      expect(vm.isInPasswordRecovery, isFalse);
      fake.emitPasswordRecovery();
      await Future<void>.delayed(Duration.zero);

      expect(vm.isInPasswordRecovery, isTrue);
      expect(notified, greaterThanOrEqualTo(1));

      vm.dispose();
      fake.dispose();
    });

    test('clearRecoveryState resets the flag without signing out',
        () async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      await vm.initialize();
      fake.emitPasswordRecovery();
      await Future<void>.delayed(Duration.zero);
      expect(vm.isInPasswordRecovery, isTrue);

      vm.clearRecoveryState();
      expect(vm.isInPasswordRecovery, isFalse);
      // currentUser remains untouched — clearRecoveryState does not log out.

      vm.dispose();
      fake.dispose();
    });
  });
}
