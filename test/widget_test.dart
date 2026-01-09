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
import 'fakes/fake_supabase_remote_data_source.dart';

void main() {
  // Initialize dotenv before running tests
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Load test environment variables or use empty config
    dotenv.testLoad(fileInput: '''
MAPTILER_API_KEY=test_key
''');
  });

  testWidgets('App launches and shows CCW Map title when authenticated',
      (WidgetTester tester) async {
    // Create in-memory database for testing
    final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    final fakeRemoteDataSource = FakeSupabaseRemoteDataSource();

    // Create repositories
    final pinRepository =
        PinRepositoryImpl(testDatabase.pinDao, fakeRemoteDataSource);
    final authRepository = FakeAuthRepository();

    // Create ViewModels
    final mapViewModel = MapViewModel(pinRepository);
    final authViewModel = AuthViewModel(authRepository);

    // Simulate authenticated user
    authRepository.setCurrentUser(
      User(id: 'test-user-id', email: 'test@example.com'),
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      CCWMapApp(
        mapViewModel: mapViewModel,
        authViewModel: authViewModel,
      ),
    );

    // Wait for AuthGate to initialize
    await tester.pumpAndSettle();

    // Verify that the CCW Map title is displayed (shows MapScreen)
    expect(find.text('CCW Map'), findsOneWidget);

    // Verify that the exit/sign out icon is present
    expect(find.byIcon(Icons.exit_to_app), findsOneWidget);

    // Verify that the re-center FAB is present
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    // Clean up
    authRepository.dispose();
    await testDatabase.close();
  });

  testWidgets('App shows login screen when not authenticated',
      (WidgetTester tester) async {
    // Create in-memory database for testing
    final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    final fakeRemoteDataSource = FakeSupabaseRemoteDataSource();

    // Create repositories
    final pinRepository =
        PinRepositoryImpl(testDatabase.pinDao, fakeRemoteDataSource);
    final authRepository = FakeAuthRepository();

    // Create ViewModels
    final mapViewModel = MapViewModel(pinRepository);
    final authViewModel = AuthViewModel(authRepository);

    // User is NOT authenticated (default state)

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      CCWMapApp(
        mapViewModel: mapViewModel,
        authViewModel: authViewModel,
      ),
    );

    // Wait for AuthGate to initialize
    await tester.pumpAndSettle();

    // Verify that the Login screen is displayed
    // Note: "Sign In" appears in both AppBar and button, so check for button specifically
    expect(find.widgetWithText(ElevatedButton, 'Sign In'), findsOneWidget);

    // Verify that email and password fields are present
    expect(find.byType(TextFormField), findsNWidgets(2));

    // Verify that Create Account button is present
    expect(find.widgetWithText(OutlinedButton, 'Create Account'), findsOneWidget);

    // Verify that app logo/title is present
    expect(find.text('CCW Map'), findsOneWidget);

    // Clean up
    authRepository.dispose();
    await testDatabase.close();
  });
}
