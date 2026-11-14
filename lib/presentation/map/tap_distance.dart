import 'dart:math' show Point;

import 'package:flutter/foundation.dart' show TargetPlatform;

/// Radius of the individual-pin circles, in logical pixels.
const double kPinCircleRadius = 12.0;

/// Stroke drawn around the pin circles, in logical pixels. MapLibre draws it
/// outside [kPinCircleRadius], so the visible pin reaches radius + stroke.
const double kPinCircleStrokeWidth = 2.0;

/// How far from a pin's center a tap still counts as a tap on that pin, in
/// logical pixels. It reaches past the drawn circle to give a small
/// forgiveness ring, without catching taps in unrelated empty space.
const double kPinTapRadius = 30.0;

/// Whether maplibre_gl reports screen coordinates in physical pixels.
///
/// The tap `point` passed to `onMapClick` / `onFeatureTapped` and the result
/// of `toScreenLocation` are physical pixels on Android (the native
/// `Projection.toScreenLocation`), but logical pixels on iOS (UIKit points)
/// and on web (CSS pixels).
bool mapPixelsArePhysical({
  required bool isWeb,
  required TargetPlatform platform,
}) => !isWeb && platform == TargetPlatform.android;

/// Distance between two maplibre_gl screen points, in logical pixels.
///
/// Every tap threshold in the app is in logical pixels, so a physical
/// distance (see [mapPixelsArePhysical]) is divided by [devicePixelRatio].
/// Comparing raw Android distances against a logical threshold made the
/// threshold ~3x too small on a typical phone, rejecting taps that landed
/// on the outer part of the drawn pin.
double logicalPixelDistance(
  Point<num> a,
  Point<num> b, {
  required bool physicalPixels,
  required double devicePixelRatio,
}) {
  final d = a.distanceTo(b).toDouble();
  return physicalPixels ? d / devicePixelRatio : d;
}
