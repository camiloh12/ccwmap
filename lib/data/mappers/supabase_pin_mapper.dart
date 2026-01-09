import '../../domain/models/location.dart';
import '../../domain/models/pin.dart';
import '../../domain/models/pin_metadata.dart';
import '../../domain/models/pin_status.dart';
import '../../domain/models/restriction_tag.dart';
import '../models/supabase_pin_dto.dart';

/// Maps between SupabasePinDto (API) and Pin (Domain)
class SupabasePinMapper {
  /// Convert domain Pin to Supabase DTO
  static SupabasePinDto toDto(Pin pin) {
    return SupabasePinDto(
      id: pin.id,
      name: pin.name,
      latitude: pin.location.latitude,
      longitude: pin.location.longitude,
      status: pin.status.colorCode,
      restrictionTag: pin.restrictionTag?.name,
      hasSecurityScreening: pin.hasSecurityScreening,
      hasPostedSignage: pin.hasPostedSignage,
      createdBy: pin.metadata.createdBy,
      createdAt: pin.metadata.createdAt.toIso8601String(),
      lastModified: pin.metadata.lastModified.toIso8601String(),
      photoUri: pin.metadata.photoUri,
      notes: pin.metadata.notes,
      votes: pin.metadata.votes,
    );
  }

  /// Convert Supabase DTO to domain Pin
  static Pin fromDto(SupabasePinDto dto) {
    return Pin(
      id: dto.id,
      name: dto.name,
      location: Location.fromLatLng(dto.latitude, dto.longitude),
      status: PinStatus.fromColorCode(dto.status),
      restrictionTag: RestrictionTag.fromString(dto.restrictionTag),
      hasSecurityScreening: dto.hasSecurityScreening,
      hasPostedSignage: dto.hasPostedSignage,
      metadata: PinMetadata(
        createdBy: dto.createdBy,
        createdAt: DateTime.parse(dto.createdAt),
        lastModified: DateTime.parse(dto.lastModified),
        photoUri: dto.photoUri,
        notes: dto.notes,
        votes: dto.votes,
      ),
    );
  }

  /// Convert list of DTOs to domain Pins
  static List<Pin> fromDtoList(List<SupabasePinDto> dtos) {
    return dtos.map((dto) => fromDto(dto)).toList();
  }

  /// Convert list of Pins to DTOs
  static List<SupabasePinDto> toDtoList(List<Pin> pins) {
    return pins.map((pin) => toDto(pin)).toList();
  }
}
