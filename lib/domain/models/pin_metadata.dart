class PinMetadata {
  final String? createdBy;
  final DateTime createdAt;
  final DateTime lastModified;
  final String? photoUri;
  final String? notes;
  final int votes;

  PinMetadata({
    this.createdBy,
    required this.createdAt,
    required this.lastModified,
    this.photoUri,
    this.notes,
    this.votes = 0,
  });

  PinMetadata copyWith({
    String? createdBy,
    DateTime? createdAt,
    DateTime? lastModified,
    String? photoUri,
    String? notes,
    int? votes,
  }) {
    return PinMetadata(
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      photoUri: photoUri ?? this.photoUri,
      notes: notes ?? this.notes,
      votes: votes ?? this.votes,
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
          votes == other.votes;

  @override
  int get hashCode =>
      createdBy.hashCode ^
      createdAt.hashCode ^
      lastModified.hashCode ^
      photoUri.hashCode ^
      notes.hashCode ^
      votes.hashCode;
}
