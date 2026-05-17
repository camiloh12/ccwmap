import 'package:ccwmap/data/sync/last_synced_at_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LastSyncedAtStore', () {
    test('returns epoch when no watermark recorded', () async {
      final store = await LastSyncedAtStore.create();
      final at = await store.readPinsWatermark('user-1');
      expect(at, DateTime.utc(1970));
    });

    test('round-trips the pin watermark for a specific user', () async {
      final store = await LastSyncedAtStore.create();
      final ts = DateTime.utc(2026, 5, 16, 12);

      await store.writePinsWatermark('user-1', ts);

      expect(await store.readPinsWatermark('user-1'), ts);
      // Different user keeps the default epoch.
      expect(await store.readPinsWatermark('user-2'), DateTime.utc(1970));
    });

    test('round-trips the deletion watermark separately', () async {
      final store = await LastSyncedAtStore.create();
      final pinsTs = DateTime.utc(2026, 5, 16, 12);
      final deletionsTs = DateTime.utc(2026, 5, 16, 11);

      await store.writePinsWatermark('user-1', pinsTs);
      await store.writeDeletionsWatermark('user-1', deletionsTs);

      expect(await store.readPinsWatermark('user-1'), pinsTs);
      expect(await store.readDeletionsWatermark('user-1'), deletionsTs);
    });

    test('clearForUser removes both watermarks for that user', () async {
      final store = await LastSyncedAtStore.create();
      await store.writePinsWatermark('user-1', DateTime.utc(2026));
      await store.writeDeletionsWatermark('user-1', DateTime.utc(2026));

      await store.clearForUser('user-1');

      expect(await store.readPinsWatermark('user-1'), DateTime.utc(1970));
      expect(await store.readDeletionsWatermark('user-1'), DateTime.utc(1970));
    });
  });
}
