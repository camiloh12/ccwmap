import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/map/pin_visibility.dart';

void main() {
  group('individualPinsVisible', () {
    test('hides individual pins at low zoom even when there are no clusters', () {
      // Regression: in a sparse viewport (e.g. prod with no imported pins) the
      // RPC returns no clusters at all, so gating visibility purely on cluster
      // presence left individual pins lingering at continental zoom. The zoom
      // cutover must hide them regardless. See get_pins_in_view (migration 008).
      expect(individualPinsVisible(zoom: 4, hasClusters: false), isFalse);
    });

    test('hides individual pins at low zoom when clusters are present', () {
      expect(individualPinsVisible(zoom: 8, hasClusters: true), isFalse);
    });

    test('shows individual pins at high zoom with no clusters', () {
      expect(individualPinsVisible(zoom: 14, hasClusters: false), isTrue);
    });

    test(
      'hides individual pins at high zoom when the density fallback clusters',
      () {
        // The RPC returns clusters even at zoom >= 12 when the viewport holds
        // > 2000 candidate pins; the cluster-presence check still hides pins.
        expect(individualPinsVisible(zoom: 14, hasClusters: true), isFalse);
      },
    );

    test('treats the cutover zoom as individual-pin zoom', () {
      expect(
        individualPinsVisible(zoom: kClusterCutoverZoom, hasClusters: false),
        isTrue,
      );
      expect(
        individualPinsVisible(
          zoom: kClusterCutoverZoom - 1,
          hasClusters: false,
        ),
        isFalse,
      );
    });
  });
}
