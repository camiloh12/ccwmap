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

void main() {
  // Initialize dotenv before running tests
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Load test environment variables or use empty config
    dotenv.testLoad(fileInput: '''
MAPTILER_API_KEY=test_key
''');
  });

  testWidgets('App launches and shows CCW Map title', (WidgetTester tester) async {
    // Create in-memory database for testing
    final testDatabase = AppDatabase.forTesting(NativeDatabase.memory());

    // Create repository and ViewModel
    final repository = PinRepositoryImpl(testDatabase.pinDao);
    final viewModel = MapViewModel(repository);

    // Build our app and trigger a frame.
    await tester.pumpWidget(CCWMapApp(mapViewModel: viewModel));

    // Verify that the CCW Map title is displayed
    expect(find.text('CCW Map'), findsOneWidget);

    // Verify that the exit/sign out icon is present
    expect(find.byIcon(Icons.exit_to_app), findsOneWidget);

    // Verify that the re-center FAB is present
    expect(find.byIcon(Icons.my_location), findsOneWidget);

    // Clean up
    await testDatabase.close();
  });
}
