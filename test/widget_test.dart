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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ccwmap/main.dart';
import 'package:ccwmap/data/database/database.dart';
import 'package:ccwmap/data/repositories/pin_repository_impl.dart';
import 'package:ccwmap/data/services/blocklist_service.dart';
import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:ccwmap/data/sync/viewport_pins_manager.dart';
import 'package:ccwmap/presentation/viewmodels/map_viewmodel.dart';
import 'package:ccwmap/presentation/viewmodels/auth_viewmodel.dart';
import 'package:ccwmap/domain/models/user.dart';
import 'fakes/fake_agreements_repository.dart';
import 'fakes/fake_auth_repository.dart';
import 'fakes/fake_moderation_repository.dart';
import 'fakes/fake_network_monitor.dart';
import 'fakes/fake_supabase_remote_data_source.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dotenv.loadFromString(
      envString: '''
MAPTILER_API_KEY=test_key
''',
    );
  });

  setUp(() {
    // Mark EULA as already acknowledged so the passive modal doesn't
    // appear mid-test.
    SharedPreferences.setMockInitialValues({'eula_acknowledged_v1': true});
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

    final moderationRepo = FakeModerationRepository();
    final agreementsRepo = FakeAgreementsRepository()
      ..willReportAccepted = true;
    final blocklist = BlocklistService(moderationRepo);

    final mapViewModel = MapViewModel(
      pinRepository,
      fakeNetworkMonitor,
      blocklist,
    );
    final authViewModel = AuthViewModel(authRepository);

    // No setCurrentUser — user is unauthenticated.

    final viewportPinsManager = ViewportPinsManager(
      remote: FakeSupabaseRemoteDataSource(),
      pinDao: testDatabase.pinDao,
      tombstoneDao: testDatabase.pinTombstoneDao,
      fetchedBboxDao: testDatabase.fetchedBboxDao,
      userIdProvider: () => null,
    );
    final lastSyncedAtStore = await LastSyncedAtStore.create();

    await tester.pumpWidget(
      CCWMapApp(
        mapViewModel: mapViewModel,
        authViewModel: authViewModel,
        blocklistService: blocklist,
        agreementsRepository: agreementsRepo,
        moderationRepository: moderationRepo,
        viewportPinsManager: viewportPinsManager,
        lastSyncedAtStore: lastSyncedAtStore,
      ),
    );
    await tester.pumpAndSettle();

    // Map title always renders (visible to everyone).
    expect(find.text('CCW Map'), findsOneWidget);

    // Guest sees the sign-in icon only — no sign-out, no settings.
    expect(find.byIcon(Icons.login), findsOneWidget);
    expect(find.byIcon(Icons.exit_to_app), findsNothing);
    expect(find.byIcon(Icons.settings), findsNothing);

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

      final moderationRepo = FakeModerationRepository();
      final agreementsRepo = FakeAgreementsRepository()
        ..willReportAccepted = true;
      final blocklist = BlocklistService(moderationRepo);

      final mapViewModel = MapViewModel(
        pinRepository,
        fakeNetworkMonitor,
        blocklist,
      );
      final authViewModel = AuthViewModel(authRepository);

      authRepository.setCurrentUser(
        User(id: 'test-user-id', email: 'test@example.com'),
      );

      final viewportPinsManager = ViewportPinsManager(
        remote: FakeSupabaseRemoteDataSource(),
        pinDao: testDatabase.pinDao,
        tombstoneDao: testDatabase.pinTombstoneDao,
        fetchedBboxDao: testDatabase.fetchedBboxDao,
        userIdProvider: () => 'test-user-id',
      );
      final lastSyncedAtStore = await LastSyncedAtStore.create();

      await tester.pumpWidget(
        CCWMapApp(
          mapViewModel: mapViewModel,
          authViewModel: authViewModel,
          blocklistService: blocklist,
          agreementsRepository: agreementsRepo,
          moderationRepository: moderationRepo,
          viewportPinsManager: viewportPinsManager,
          lastSyncedAtStore: lastSyncedAtStore,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CCW Map'), findsOneWidget);

      // Authenticated user sees the settings gear only; no sign-in or
      // sign-out icons on the map (Sign Out lives on SettingsScreen).
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.exit_to_app), findsNothing);
      expect(find.byIcon(Icons.login), findsNothing);

      expect(find.byIcon(Icons.my_location), findsOneWidget);

      authRepository.dispose();
      fakeNetworkMonitor.dispose();
      await testDatabase.close();
    },
  );
}
