// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:ccwmap/main.dart';

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
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CCWMapApp());

    // Verify that the CCW Map title is displayed
    expect(find.text('CCW Map'), findsOneWidget);

    // Verify that the exit/sign out icon is present
    expect(find.byIcon(Icons.exit_to_app), findsOneWidget);

    // Verify that the re-center FAB is present
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });
}
