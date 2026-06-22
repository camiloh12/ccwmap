class PinMetadata {
  final String? createdBy;
  final DateTime createdAt;
  final DateTime lastModified;
  final String? photoUri;
  final String? notes;
  final int votes;

  /// Provenance — `'user'` for user-created pins, otherwise the importer
  /// source code (`nces`, `gsa`, `osm`, …). The other four are populated by
  /// the importer and are null on user pins.
  final String source;
  final String? sourceExternalId;
  final String? confidence; // 'high' | 'medium' | 'low'
  final String? legalCitation;
  final String? legalCitationVerifiedDate; // ISO date string (YYYY-MM-DD)

  PinMetadata({
    this.createdBy,
    required this.createdAt,
    required this.lastModified,
    this.photoUri,
    this.notes,
    this.votes = 0,
    this.source = 'user',
    this.sourceExternalId,
    this.confidence,
    this.legalCitation,
    this.legalCitationVerifiedDate,
  });

  PinMetadata copyWith({
    String? createdBy,
    DateTime? createdAt,
    DateTime? lastModified,
    String? photoUri,
    String? notes,
    int? votes,
    String? source,
    String? sourceExternalId,
    String? confidence,
    String? legalCitation,
    String? legalCitationVerifiedDate,
  }) {
    return PinMetadata(
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      photoUri: photoUri ?? this.photoUri,
      notes: notes ?? this.notes,
      votes: votes ?? this.votes,
      source: source ?? this.source,
      sourceExternalId: sourceExternalId ?? this.sourceExternalId,
      confidence: confidence ?? this.confidence,
      legalCitation: legalCitation ?? this.legalCitation,
      legalCitationVerifiedDate:
          legalCitationVerifiedDate ?? this.legalCitationVerifiedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'lastModified': lastModified.toIso8601String(),
      'photoUri': photoUri,
      'notes': notes,
      'votes': votes,
      'source': source,
      'sourceExternalId': sourceExternalId,
      'confidence': confidence,
      'legalCitation': legalCitation,
      'legalCitationVerifiedDate': legalCitationVerifiedDate,
    };
  }

  factory PinMetadata.fromJson(Map<String, dynamic> json) {
    return PinMetadata(
      createdBy: json['createdBy'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastModified: DateTime.parse(json['lastModified'] as String),
      photoUri: json['photoUri'] as String?,
      notes: json['notes'] as String?,
      votes: json['votes'] as int? ?? 0,
      source: (json['source'] as String?) ?? 'user',
      sourceExternalId: json['sourceExternalId'] as String?,
      confidence: json['confidence'] as String?,
      legalCitation: json['legalCitation'] as String?,
      legalCitationVerifiedDate: json['legalCitationVerifiedDate'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PinMetadata &&
          runtimeType == other.runtimeType &&
          createdBy == other.createdBy &&
          createdAt == other.createdAt &&
          lastModified == other.lastModified &&
          photoUri == other.photoUri &&
          notes == other.notes &&
          votes == other.votes &&
          source == other.source &&
          sourceExternalId == other.sourceExternalId &&
          confidence == other.confidence &&
          legalCitation == other.legalCitation &&
          legalCitationVerifiedDate == other.legalCitationVerifiedDate;

  @override
  int get hashCode =>
      createdBy.hashCode ^
      createdAt.hashCode ^
      lastModified.hashCode ^
      photoUri.hashCode ^
      notes.hashCode ^
      votes.hashCode ^
      source.hashCode ^
      sourceExternalId.hashCode ^
      confidence.hashCode ^
      legalCitation.hashCode ^
      legalCitationVerifiedDate.hashCode;
}
