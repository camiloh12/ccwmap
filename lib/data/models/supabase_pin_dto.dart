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
  final String source; // 'user' | 'nces' | 'osm' | ...
  final String? sourceExternalId;
  final String? confidence; // 'high' | 'medium' | 'low'
  final String? legalCitation;
  final String? legalCitationVerifiedDate; // ISO date string (YYYY-MM-DD)

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
    this.source = 'user',
    this.sourceExternalId,
    this.confidence,
    this.legalCitation,
    this.legalCitationVerifiedDate,
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
      source: (json['source'] as String?) ?? 'user',
      sourceExternalId: json['source_external_id'] as String?,
      confidence: json['confidence'] as String?,
      legalCitation: json['legal_citation'] as String?,
      legalCitationVerifiedDate: json['legal_citation_verified_date'] as String?,
    );
  }

  /// Convert DTO to JSON for Supabase API (insert path).
  ///
  /// Provenance fields are included here because the server allows them on
  /// insert when the caller has service-role (the bulk-import path).
  /// Authenticated user inserts that include provenance will be silently
  /// ignored or rejected at the column-grant level — callers building a
  /// user-authored pin should leave them at their defaults.
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
      'source': source,
      'source_external_id': sourceExternalId,
      'confidence': confidence,
      'legal_citation': legalCitation,
      'legal_citation_verified_date': legalCitationVerifiedDate,
    };
  }

  /// Returns only the columns granted UPDATE to `authenticated` in
  /// migration 008. Sending `toJson()` (which includes immutable
  /// columns like `id`, `created_by`, `created_at`, and server-managed
  /// `last_modified`) would trigger a Postgres permission error after
  /// the column-level GRANT replaces the blanket UPDATE grant.
  ///
  /// Provenance columns (`source`, `source_external_id`, `confidence`,
  /// `legal_citation`, `legal_citation_verified_date`) are deliberately
  /// excluded — migration 008 §8 REVOKEs UPDATE on those from
  /// `authenticated`, so including them would 403.
  Map<String, dynamic> toJsonForUpdate() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
      'restriction_tag': restrictionTag,
      'has_security_screening': hasSecurityScreening,
      'has_posted_signage': hasPostedSignage,
      'notes': notes,
      'photo_uri': photoUri,
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
