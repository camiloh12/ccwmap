/// Zoom level at which `get_pins_in_view` switches from returning clustered
/// aggregates (below) to individual pin rows (at or above). MUST stay in sync
/// with the `zoom >= 12` cutover in the SQL RPC (migration 008 §7 / 010) so the
/// client hides its individual-pin layers, and trusts a pin list as complete,
/// in lockstep with the server's mode switch.
const int kClusterCutoverZoom = 12;

/// Mirrors Supabase/PostgREST "Max rows" (`db-max-rows`), which also caps RPC
/// results. MUST NOT exceed that API setting (default 1,000); a response of
/// this many rows may be truncated, so it is never trusted as complete.
const int kMaxRowsPerResponse = 1000;
