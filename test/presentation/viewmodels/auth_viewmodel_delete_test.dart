import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('AuthViewModel.deleteAccount', () {
    late FakeAuthRepository fake;
    late AuthViewModel viewModel;

    setUp(() {
      fake = FakeAuthRepository();
      viewModel = AuthViewModel(fake);
      fake.setCurrentUser(User(id: 'u1', email: 'u1@example.com'));
    });

    tearDown(() {
      viewModel.dispose();
      fake.dispose();
    });

    test('success: delegates to repository and clears error', () async {
      await viewModel.deleteAccount();
      expect(fake.deleteCallCount, 1);
      expect(viewModel.error, isNull);
    });

    test('failure: surfaces error, does not throw', () async {
      fake.deleteShouldThrow = true;
      await viewModel.deleteAccount(); // should not throw
      expect(viewModel.error, isNotNull);
    });

    test('isLoading toggles around the call', () async {
      expect(viewModel.isLoading, isFalse);
      final future = viewModel.deleteAccount();
      expect(viewModel.isLoading, isTrue);
      await future;
      expect(viewModel.isLoading, isFalse);
    });
  });

  group('AuthViewModel.signIn banned error mapping', () {
    test(
      'maps "banned" AuthException to the suspension copy with appeals email',
      () async {
        final fake = _BannedAuthRepo();
        final vm = AuthViewModel(fake);

        await vm.signIn('u@example.com', 'whatever');

        expect(vm.error, contains('suspended'));
        expect(vm.error, contains('camilo@kyberneticlabs.com'));

        vm.dispose();
      },
    );
  });
}

/// Fake that throws an AuthException whose message contains "banned" on
/// sign in — reproduces Supabase's behavior for banned users.
class _BannedAuthRepo extends FakeAuthRepository {
  @override
  Future<void> signInWithEmail(String email, String password) async {
    throw const supabase.AuthException('User is banned until infinity.');
  }
}
