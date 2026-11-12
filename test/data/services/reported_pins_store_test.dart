import 'package:ccwmap/data/services/reported_pins_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('mark then isReported is true', () async {
    final s = await ReportedPinsStore.create();
    expect(s.isReported('u1', 'p1'), isFalse);
    await s.markReported('u1', 'p1');
    expect(s.isReported('u1', 'p1'), isTrue);
  });

  test('other users and other pins stay false', () async {
    final s = await ReportedPinsStore.create();
    await s.markReported('u1', 'p1');
    expect(s.isReported('u2', 'p1'), isFalse);
    expect(s.isReported('u1', 'p2'), isFalse);
  });

  test('mark survives a fresh create()', () async {
    final s = await ReportedPinsStore.create();
    await s.markReported('u1', 'p1');
    final s2 = await ReportedPinsStore.create();
    expect(s2.isReported('u1', 'p1'), isTrue);
  });
}
