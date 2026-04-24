import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'package:ccwmap/presentation/screens/settings_screen.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';

import '../../fakes/fake_auth_repository.dart';

void main() {
  group('SettingsScreen', () {
    Future<(AuthViewModel, FakeAuthRepository)> pump(
      WidgetTester tester, {
      required User user,
    }) async {
      final fake = FakeAuthRepository();
      final vm = AuthViewModel(fake);
      fake.setCurrentUser(user);
      await vm.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewModel>.value(
          value: vm,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return (vm, fake);
    }

    testWidgets('renders signed-in email, Sign Out, Delete Account',
        (tester) async {
      await pump(tester, user: User(id: 'u', email: 'u@example.com'));

      expect(find.text('u@example.com'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign Out'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Delete Account'),
        findsOneWidget,
      );
    });

    testWidgets('Delete button disabled in second dialog until DELETE typed',
        (tester) async {
      await pump(tester, user: User(id: 'u', email: 'u@example.com'));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
      await tester.pumpAndSettle();
      // First dialog: Continue.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      // Second dialog: Delete button present but disabled.
      final deleteBtn = find.widgetWithText(ElevatedButton, 'Delete');
      expect(deleteBtn, findsOneWidget);
      ElevatedButton btn = tester.widget<ElevatedButton>(deleteBtn);
      expect(btn.onPressed, isNull);

      // Type DELETE.
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();

      btn = tester.widget<ElevatedButton>(deleteBtn);
      expect(btn.onPressed, isNotNull);
    });

    testWidgets(
      'typing DELETE and tapping Delete calls deleteAccount',
      (tester) async {
        final (_, fake) = await pump(
          tester,
          user: User(id: 'u', email: 'u@example.com'),
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'DELETE');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(fake.deleteCallCount, 1);
      },
    );

    testWidgets('Sign Out calls signOut on the repository', (tester) async {
      final (_, fake) = await pump(
        tester,
        user: User(id: 'u', email: 'u@example.com'),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign Out'));
      await tester.pumpAndSettle();

      // FakeAuthRepository.signOut() nulls the currentUser.
      expect(await fake.getCurrentUser(), isNull);
    });
  });
}
