import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';
import 'package:ccwmap/presentation/screens/sign_up_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

class _FakeAgreementsRepository implements AgreementsRepository {
  int recordCount = 0;

  @override
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) async => true;

  @override
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) async {
    recordCount++;
  }
}

Widget _hosted(AuthViewModel vm, AgreementsRepository agreements) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewModel>.value(value: vm),
      Provider<AgreementsRepository>.value(value: agreements),
    ],
    child: const MaterialApp(home: SignUpScreen()),
  );
}

// SignUpScreen has many vertically-stacked elements (app icon + title +
// 3 form fields + EULA wrap + Create Account button + footer link) that
// overflow the default 800x600 test viewport. Without a taller viewport,
// the tap target for Create Account and the footer link sit below the
// visible area and `tester.tap` silently misses (logs a hit-test warning
// and the form never submits). Bump the surface to 800x1400 for the
// duration of each test using tester.binding.setSurfaceSize, then reset
// via addTearDown.
Future<void> _setTallViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  group('SignUpScreen', () {
    testWidgets('Create Account is disabled until EULA is checked',
        (tester) async {
      await _setTallViewport(tester);
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      await tester.pumpWidget(_hosted(vm, agreements));

      final button = find.widgetWithText(ElevatedButton, 'Create Account');
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('mismatched passwords block submit', (tester) async {
      await _setTallViewport(tester);
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      await tester.pumpWidget(_hosted(vm, agreements));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'password1');
      await tester.enterText(fields.at(2), 'password2');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(agreements.recordCount, 0);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('valid form submits, records agreement, shows snackbar',
        (tester) async {
      await _setTallViewport(tester);
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      // Pre-set the user so post-signup `vm.currentUser` is non-null when
      // SignUpScreen reads it (the fake's signUp also sets it, but the
      // notify ordering means the read inside the screen needs the user
      // available immediately).
      //
      // initialize() must be called to wire up the auth-stream subscription
      // inside AuthViewModel — without it, vm._currentUser is never updated
      // when FakeAuthRepository.signUpWithEmail fires setCurrentUser, so
      // vm.currentUser returns null and recordAgreementAcceptance is skipped.
      fake.setCurrentUser(User(id: 'u1', email: 'user@example.com'));
      await vm.initialize();
      await tester.pumpWidget(_hosted(vm, agreements));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'password1');
      await tester.enterText(fields.at(2), 'password1');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(agreements.recordCount, 1);
      expect(find.textContaining('Account created'), findsOneWidget);

      vm.dispose();
      fake.dispose();
    });

    testWidgets('"Sign in" footer link pops the screen', (tester) async {
      await _setTallViewport(tester);
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      final agreements = _FakeAgreementsRepository();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>.value(value: vm),
            Provider<AgreementsRepository>.value(value: agreements),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignUpScreen(),
                    ),
                  ),
                  child: const Text('open signup'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open signup'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);

      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsNothing);

      vm.dispose();
      fake.dispose();
    });
  });
}
