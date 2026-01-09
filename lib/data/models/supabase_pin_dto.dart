/// Data Transfer Object for Pin synchronization with Supabase
///
/// This DTO matches the Supabase PostgreSQL schema exactly and handles
/// JSON serialization for API communication.
class SupabasePinDto {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int status; // 0=ALLOWED, 1=UNCERTAIN, 2=NO_GUN
  final String? restrictionTag; // Enum string (e.g., "FEDERAL_PROPERTY")
  final bool hasSecurityScreening;
  final bool hasPostedSignage;
  final String? createdBy; // UUID string
  final String createdAt; // ISO 8601 timestamp
  final String lastModified; // ISO 8601 timestamp
  final String? photoUri;
  final String? notes;
  final int votes;

  const SupabasePinDto({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.restrictionTag,
    required this.hasSecurityScreening,
    required this.hasPostedSignage,
    this.createdBy,
    required this.createdAt,
    required this.lastModified,
    this.photoUri,
    this.notes,
    required this.votes,
  });

  /// Create DTO from Supabase JSON response
  factory SupabasePinDto.fromJson(Map<String, dynamic> json) {
    return SupabasePinDto(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      status: json['status'] as int,
      restrictionTag: json['restriction_tag'] as String?,
      hasSecurityScreening: json['has_security_screening'] as bool? ?? false,
      hasPostedSignage: json['has_posted_signage'] as bool? ?? false,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] as String,
      lastModified: json['last_modified'] as String,
      photoUri: json['photo_uri'] as String?,
      notes: json['notes'] as String?,
      votes: json['votes'] as int? ?? 0,
    );
  }

  /// Convert DTO to JSON for Supabase API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
      'restriction_tag': restrictionTag,
      'has_security_screening': hasSecurityScreening,
      'has_posted_signage': hasPostedSignage,
      'created_by': createdBy,
      'created_at': createdAt,
      'last_modified': lastModified,
      'photo_uri': photoUri,
      'notes': notes,
      'votes': votes,
    };
  }

  @override
  String toString() {
    return 'SupabasePinDto(id: $id, name: $name, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SupabasePinDto && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
