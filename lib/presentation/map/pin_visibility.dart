import 'package:ccwmap/core/map_constants.dart';

/// Whether the individual-pin layers (`mine-pins-layer`, `cached-pins-layer`,
/// and their label layers) should be visible at the given [zoom].
///
/// Visible only at individual-pin zoom (>= [kClusterCutoverZoom]) AND when the
/// server returned no clusters for the viewport.
///
/// Gating on zoom — not solely on cluster presence — is what keeps individual
/// pins from lingering at low zoom in sparse areas, where the RPC returns no
/// clusters at all (e.g. a viewport containing only the caller's own pins, which
/// the RPC excludes from its aggregation). [hasClusters] still hides pins at the
/// zoom >= 12 density fallback, where an over-dense viewport returns clusters
/// even at high zoom.
bool individualPinsVisible({required int zoom, required bool hasClusters}) =>
    zoom >= kClusterCutoverZoom && !hasClusters;
