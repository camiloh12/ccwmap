import '../../domain/models/location.dart';
import '../../domain/models/map_item.dart';
import '../../domain/models/pin.dart';
import '../../domain/models/pin_metadata.dart';
import '../../domain/models/pin_status.dart';
import '../../domain/models/restriction_tag.dart';

/// Parses one row of `get_pins_in_view` RPC output into a [MapItem].
///
/// The RPC returns a UNION-ALL of pin rows and cluster rows; the `kind`
/// column discriminates. Non-applicable columns are NULL.
class GetPinsInViewRow {
  GetPinsInViewRow._();

  static MapItem parse(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'pin':
        return MapItemPin(_parsePin(json));
      case 'cluster':
        return _parseCluster(json);
      default:
        throw FormatException('Unknown get_pins_in_view kind: $kind');
    }
  }

  static Pin _parsePin(Map<String, dynamic> j) {
    return Pin(
      id: j['pin_id'] as String,
      name: j['name'] as String,
      location: Location.fromLatLng(
        (j['latitude'] as num).toDouble(),
        (j['longitude'] as num).toDouble(),
      ),
      status: PinStatus.fromColorCode(j['status'] as int),
      restrictionTag: RestrictionTag.fromString(
        j['restriction_tag'] as String?,
      ),
      hasSecurityScreening: (j['has_security_screening'] as bool?) ?? false,
      hasPostedSignage: (j['has_posted_signage'] as bool?) ?? false,
      metadata: PinMetadata(
        createdBy: j['created_by'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        lastModified: DateTime.parse(j['last_modified'] as String),
      ),
    );
  }

  static MapItemCluster _parseCluster(Map<String, dynamic> j) {
    return MapItemCluster(
      centroidLat: (j['latitude'] as num).toDouble(),
      centroidLng: (j['longitude'] as num).toDouble(),
      count: j['cluster_count'] as int,
      dominantStatus: PinStatus.fromColorCode(j['dominant_status'] as int),
      dominantRestrictionTag: RestrictionTag.fromString(
        j['dominant_restriction_tag'] as String?,
      ),
    );
  }
}
