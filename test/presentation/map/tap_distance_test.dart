import 'dart:math' show Point;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/map/tap_distance.dart';

void main() {
  group('mapPixelsArePhysical', () {
    test('Android reports physical pixels', () {
      expect(
        mapPixelsArePhysical(isWeb: false, platform: TargetPlatform.android),
        isTrue,
      );
    });

    test('iOS reports logical points', () {
      expect(
        mapPixelsArePhysical(isWeb: false, platform: TargetPlatform.iOS),
        isFalse,
      );
    });

    test('web reports CSS pixels, even in an Android browser', () {
      expect(
        mapPixelsArePhysical(isWeb: true, platform: TargetPlatform.android),
        isFalse,
      );
    });
  });

  group('logicalPixelDistance', () {
    test(
      'regression: the 34 px Android tap from the field log hits the pin',
      () {
        // "Feature tap rejected: Homer Thornberry Judicial Building is 34px
        // from tap" on an Android phone. 34 physical px at a typical 2.75x
        // density is ~12 logical px: on the drawn circle, not beside it.
        final d = logicalPixelDistance(
          const Point(500.0, 800.0),
          const Point(534.0, 800.0),
          physicalPixels: true,
          devicePixelRatio: 2.75,
        );
        expect(d, closeTo(12.36, 0.01));
        expect(d, lessThan(kPinTapRadius));
      },
    );

    test('a tap on the edge of the drawn pin counts at every Android '
        'density', () {
      // The circle is drawn in logical pixels (radius + outer stroke), so on
      // Android its edge sits that many logical px times the density away in
      // physical px.
      const edge = kPinCircleRadius + kPinCircleStrokeWidth;
      for (final dpr in [1.0, 1.5, 2.0, 2.625, 2.75, 3.0, 3.5, 4.0]) {
        final d = logicalPixelDistance(
          const Point(0.0, 0.0),
          Point(edge * dpr, 0.0),
          physicalPixels: true,
          devicePixelRatio: dpr,
        );
        expect(d, lessThanOrEqualTo(kPinTapRadius), reason: 'dpr $dpr');
      }
    });

    test('a tap well away from the pin is still rejected on Android', () {
      // 40 logical px away at 3x = 120 physical px.
      final d = logicalPixelDistance(
        const Point(0.0, 0.0),
        const Point(0.0, 120.0),
        physicalPixels: true,
        devicePixelRatio: 3.0,
      );
      expect(d, closeTo(40.0, 1e-9));
      expect(d, greaterThan(kPinTapRadius));
    });

    test('iOS and web distances pass through unchanged', () {
      final d = logicalPixelDistance(
        const Point(10.0, 10.0),
        const Point(13.0, 14.0),
        physicalPixels: false,
        devicePixelRatio: 3.0,
      );
      expect(d, closeTo(5.0, 1e-9));
    });

    test('the tap radius reaches past the drawn pin', () {
      expect(
        kPinTapRadius,
        greaterThan(kPinCircleRadius + kPinCircleStrokeWidth),
      );
    });
  });
}
