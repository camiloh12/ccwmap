import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/screens/about_legal_screen.dart';

void main() {
  testWidgets('shows OSM, ODbL, and MapTiler attribution', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutLegalScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
    expect(find.textContaining('ODbL'), findsWidgets);
    expect(find.textContaining('MapTiler'), findsWidgets);
  });
}
