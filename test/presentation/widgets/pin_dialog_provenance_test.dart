import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String source,
    String? confidence,
    String? legalCitation,
    String? sourceExternalId,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinDialog(
            isEditMode: true,
            poiName: 'Some Place',
            initialStatus: PinStatus.NO_GUN,
            initialRestrictionTag: RestrictionTag.SCHOOL_K12,
            onConfirm: (_) {},
            onCancel: () {},
            source: source,
            confidence: confidence,
            legalCitation: legalCitation,
            sourceExternalId: sourceExternalId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows caveat for a system pin with its citation', (tester) async {
    await pump(tester,
        source: 'nces',
        confidence: 'high',
        legalCitation: 'TX Penal Code 46.03');
    expect(find.textContaining('verify locally'), findsNWidgets(2));
    expect(find.textContaining('TX Penal Code 46.03'), findsOneWidget);
  });

  testWidgets('no caveat for a user pin', (tester) async {
    await pump(tester, source: 'user');
    expect(find.textContaining('verify locally'), findsNothing);
  });

  testWidgets('shows OSM/ODbL credit for osm pins', (tester) async {
    await pump(tester,
        source: 'osm', confidence: 'medium', sourceExternalId: 'node/123');
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
  });
}
