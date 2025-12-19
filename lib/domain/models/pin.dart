import 'location.dart';
import 'pin_metadata.dart';
import 'pin_status.dart';
import 'restriction_tag.dart';

class Pin {
  final String id;
  final String name;
  final Location location;
  final PinStatus status;
  final RestrictionTag? restrictionTag;
  final bool hasSecurityScreening;
  final bool hasPostedSignage;
  final PinMetadata metadata;

  Pin({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
    this.restrictionTag,
    this.hasSecurityScreening = false,
    this.hasPostedSignage = false,
    required this.metadata,
  }) {
    // Business rule: If status is NO_GUN, restrictionTag must not be null
    if (status == PinStatus.NO_GUN && restrictionTag == null) {
      throw ArgumentError(
        'Pin with NO_GUN status must have a restriction tag',
      );
    }
  }

  Pin withNextStatus() {
    final nextStatus = status.next();
    return Pin(
      id: id,
      name: name,
      location: location,
      status: nextStatus,
      restrictionTag: nextStatus == PinStatus.NO_GUN
          ? restrictionTag ?? RestrictionTag.PRIVATE_PROPERTY
          : null,
      hasSecurityScreening: hasSecurityScreening,
      hasPostedSignage: hasPostedSignage,
      metadata: metadata.copyWith(
        lastModified: DateTime.now(),
      ),
    );
  }

  Pin withStatus(PinStatus newStatus, {RestrictionTag? newRestrictionTag}) {
    return Pin(
      id: id,
      name: name,
      location: location,
      status: newStatus,
      restrictionTag: newStatus == PinStatus.NO_GUN
          ? (newRestrictionTag ?? restrictionTag ?? RestrictionTag.PRIVATE_PROPERTY)
          : null,
      hasSecurityScreening: hasSecurityScreening,
      hasPostedSignage: hasPostedSignage,
      metadata: metadata.copyWith(
        lastModified: DateTime.now(),
      ),
    );
  }

  Pin withMetadata(PinMetadata newMetadata) {
    return Pin(
      id: id,
      name: name,
      location: location,
      status: status,
      restrictionTag: restrictionTag,
      hasSecurityScreening: hasSecurityScreening,
      hasPostedSignage: hasPostedSignage,
      metadata: newMetadata,
    );
  }

  Pin copyWith({
    String? id,
    String? name,
    Location? location,
    PinStatus? status,
    RestrictionTag? restrictionTag,
    bool? hasSecurityScreening,
    bool? hasPostedSignage,
    PinMetadata? metadata,
  }) {
    return Pin(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      status: status ?? this.status,
      restrictionTag: restrictionTag ?? this.restrictionTag,
      hasSecurityScreening: hasSecurityScreening ?? this.hasSecurityScreening,
      hasPostedSignage: hasPostedSignage ?? this.hasPostedSignage,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Pin &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          location == other.location &&
          status == other.status &&
          restrictionTag == other.restrictionTag &&
          hasSecurityScreening == other.hasSecurityScreening &&
          hasPostedSignage == other.hasPostedSignage &&
          metadata == other.metadata;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      location.hashCode ^
      status.hashCode ^
      restrictionTag.hashCode ^
      hasSecurityScreening.hashCode ^
      hasPostedSignage.hashCode ^
      metadata.hashCode;

  @override
  String toString() {
    return 'Pin(id: $id, name: $name, status: ${status.displayName}, location: $location)';
  }
}
