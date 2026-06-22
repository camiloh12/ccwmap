import 'package:drift/drift.dart' show Value;

import '../../domain/models/location.dart';
import '../../domain/models/pin.dart';
import '../../domain/models/pin_metadata.dart';
import '../../domain/models/pin_status.dart';
import '../../domain/models/restriction_tag.dart';
import '../database/database.dart';

class PinMapper {
  static PinEntity toEntity(Pin pin) {
    return PinEntity(
      id: pin.id,
      name: pin.name,
      latitude: pin.location.latitude,
      longitude: pin.location.longitude,
      status: pin.status.colorCode,
      restrictionTag: pin.restrictionTag?.name,
      hasSecurityScreening: pin.hasSecurityScreening,
      hasPostedSignage: pin.hasPostedSignage,
      createdBy: pin.metadata.createdBy,
      createdAt: pin.metadata.createdAt.millisecondsSinceEpoch,
      lastModified: pin.metadata.lastModified.millisecondsSinceEpoch,
      photoUri: pin.metadata.photoUri,
      notes: pin.metadata.notes,
      votes: pin.metadata.votes,
      source: pin.metadata.source,
      sourceExternalId: pin.metadata.sourceExternalId,
      confidence: pin.metadata.confidence,
      legalCitation: pin.metadata.legalCitation,
      legalCitationVerifiedDate: pin.metadata.legalCitationVerifiedDate,
      userModified: false,
      cachedAt: null,
    );
  }

  static Pin fromEntity(PinEntity entity) {
    final status = PinStatus.fromColorCode(entity.status);
    final restrictionTag = RestrictionTag.fromString(entity.restrictionTag);

    return Pin(
      id: entity.id,
      name: entity.name,
      location: Location.fromLatLng(entity.latitude, entity.longitude),
      status: status,
      restrictionTag: restrictionTag,
      hasSecurityScreening: entity.hasSecurityScreening,
      hasPostedSignage: entity.hasPostedSignage,
      metadata: PinMetadata(
        createdBy: entity.createdBy,
        createdAt: DateTime.fromMillisecondsSinceEpoch(entity.createdAt),
        lastModified: DateTime.fromMillisecondsSinceEpoch(entity.lastModified),
        photoUri: entity.photoUri,
        notes: entity.notes,
        votes: entity.votes,
        source: entity.source,
        sourceExternalId: entity.sourceExternalId,
        confidence: entity.confidence,
        legalCitation: entity.legalCitation,
        legalCitationVerifiedDate: entity.legalCitationVerifiedDate,
      ),
    );
  }

  /// Build a [PinEntity] for the bbox-cache flow. Sets `cachedAt` so the LRU
  /// eviction in `ViewportPinsManager` can find this row. Provenance (`source`,
  /// `confidence`, …) is carried from `pin.metadata` by `toEntity`, so cached
  /// system pins retain their origin.
  static PinEntity toCachedEntity(Pin pin, {required DateTime cachedAt}) {
    final base = toEntity(pin);
    return base.copyWith(cachedAt: Value(cachedAt.millisecondsSinceEpoch));
  }
}
