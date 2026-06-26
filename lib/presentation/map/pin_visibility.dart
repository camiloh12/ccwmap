/// Zoom level at which `get_pins_in_view` switches from returning clustered
/// aggregates (below) to individual pin rows (at or above). MUST stay in sync
/// with the `zoom >= 12` cutover in the SQL RPC (migration 008 §7) so the client
/// hides its individual-pin layers in lockstep with the server's mode switch.
const int kClusterCutoverZoom = 12;

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
