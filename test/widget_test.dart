// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:drift/native.dart';

import 'package:ccwmap/main.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'fakes/fake_auth_repository.dart';
import 'fakes/fake_network_monitor.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.loadFromString(
      envString: '''
MAPTILER_API_KEY=test_key
''',
    );
  });

  testWidgets('App launches as guest: map visible and sign-in icon present', (
    WidgetTester tester,
  ) async {
    final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    final fakeNetworkMonitor = FakeNetworkMonitor();

    final pinRepository = PinRepositoryImpl(
      testDatabase.pinDao,
      testDatabase.syncQueueDao,
      testDatabase.pinTombstoneDao,
    );
    final authRepository = FakeAuthRepository();

    final mapViewModel = MapViewModel(pinRepository, fakeNetworkMonitor);
    final authViewModel = AuthViewModel(authRepository);

    // No setCurrentUser — user is unauthenticated.

    await tester.pumpWidget(
      CCWMapApp(mapViewModel: mapViewModel, authViewModel: authViewModel),
    );
    await tester.pumpAndSettle();

    // Map title always renders (visible to everyone).
    expect(find.text('CCW Map'), findsOneWidget);

    // Guest sees the sign-in icon, NOT the exit-to-app icon.
    expect(find.byIcon(Icons.login), findsOneWidget);
    expect(find.byIcon(Icons.exit_to_app), findsNothing);

    // Re-center FAB still present.
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    authRepository.dispose();
    fakeNetworkMonitor.dispose();
    await testDatabase.close();
  });

  testWidgets(
    'App launches authenticated: map visible and sign-out icon present',
    (WidgetTester tester) async {
      final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      final fakeNetworkMonitor = FakeNetworkMonitor();

      final pinRepository = PinRepositoryImpl(
        testDatabase.pinDao,
        testDatabase.syncQueueDao,
        testDatabase.pinTombstoneDao,
      );
      final authRepository = FakeAuthRepository();

      final mapViewModel = MapViewModel(pinRepository, fakeNetworkMonitor);
      final authViewModel = AuthViewModel(authRepository);

      authRepository.setCurrentUser(
        User(id: 'test-user-id', email: 'test@example.com'),
      );

      await tester.pumpWidget(
        CCWMapApp(mapViewModel: mapViewModel, authViewModel: authViewModel),
      );
      await tester.pumpAndSettle();

      expect(find.text('CCW Map'), findsOneWidget);

      // Authenticated user sees the exit (sign-out) icon, NOT sign-in.
      expect(find.byIcon(Icons.exit_to_app), findsOneWidget);
      expect(find.byIcon(Icons.login), findsNothing);

      expect(find.byIcon(Icons.my_location), findsOneWidget);

      authRepository.dispose();
      fakeNetworkMonitor.dispose();
      await testDatabase.close();
    },
  );
}
