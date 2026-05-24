import 'pin.dart';
import 'pin_status.dart';
import 'restriction_tag.dart';

/// A single result row from `get_pins_in_view`. Either an individual pin
/// (street-level zoom) or a server-side cluster (regional/national zoom).
sealed class MapItem {
  const MapItem();
}

/// Individual pin — the client persists the wrapped [Pin] to the local
/// bbox cache.
class MapItemPin extends MapItem {
  final Pin pin;
  const MapItemPin(this.pin);
}

/// Server-aggregated cluster — never persisted to local DB. Rendered as a
/// numbered circle by the map layer. Tapping zooms into the cluster's cell.
class MapItemCluster extends MapItem {
  final double centroidLat;
  final double centroidLng;
  final int count;
  final PinStatus dominantStatus;
  final RestrictionTag? dominantRestrictionTag;

  const MapItemCluster({
    required this.centroidLat,
    required this.centroidLng,
    required this.count,
    required this.dominantStatus,
    required this.dominantRestrictionTag,
  });
}
