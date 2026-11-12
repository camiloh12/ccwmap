import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

const _note = 'Set by law (X). This can\'t be changed here.';

Future<void> _pump(
  WidgetTester tester, {
  required bool locked,
  required void Function(PinDialogResult) onConfirm,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PinDialog(
          isEditMode: true,
          poiName: 'Courthouse',
          initialStatus: PinStatus.NO_GUN,
          initialRestrictionTag: RestrictionTag.FEDERAL_PROPERTY,
          isStatusLocked: locked,
          lockedStatusNote: locked ? _note : null,
          onConfirm: onConfirm,
          onCancel: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('PinDialog locked status', () {
    testWidgets('tapping another status does nothing when locked', (
      tester,
    ) async {
      PinDialogResult? result;
      await _pump(tester, locked: true, onConfirm: (r) => result = r);
      await tester.tap(find.text('Allowed'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      expect(result!.status, PinStatus.NO_GUN);
      expect(result!.restrictionTag, RestrictionTag.FEDERAL_PROPERTY);
    });

    testWidgets('the tag dropdown is disabled when locked', (tester) async {
      await _pump(tester, locked: true, onConfirm: (_) {});
      final dd = tester.widget<DropdownButton<RestrictionTag>>(
        find.byType(DropdownButton<RestrictionTag>),
      );
      expect(dd.onChanged, isNull);
    });

    testWidgets('the locked note shows', (tester) async {
      await _pump(tester, locked: true, onConfirm: (_) {});
      expect(find.text(_note), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('name and checkboxes still edit when locked', (tester) async {
      PinDialogResult? result;
      await _pump(tester, locked: true, onConfirm: (r) => result = r);
      await tester.enterText(find.byType(TextField), 'New name');
      await tester.tap(find.text('Posted signage visible'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      expect(result!.name, 'New name');
      expect(result!.hasPostedSignage, isTrue);
    });

    testWidgets('unlocked dialog unchanged', (tester) async {
      PinDialogResult? result;
      await _pump(tester, locked: false, onConfirm: (r) => result = r);
      await tester.tap(find.text('Allowed'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      expect(result!.status, PinStatus.ALLOWED);
    });
  });
}
