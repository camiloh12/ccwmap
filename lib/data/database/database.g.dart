// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PinsTable extends Pins with TableInfo<$PinsTable, PinEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _restrictionTagMeta = const VerificationMeta(
    'restrictionTag',
  );
  @override
  late final GeneratedColumn<String> restrictionTag = GeneratedColumn<String>(
    'restriction_tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasSecurityScreeningMeta =
      const VerificationMeta('hasSecurityScreening');
  @override
  late final GeneratedColumn<bool> hasSecurityScreening = GeneratedColumn<bool>(
    'has_security_screening',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_security_screening" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasPostedSignageMeta = const VerificationMeta(
    'hasPostedSignage',
  );
  @override
  late final GeneratedColumn<bool> hasPostedSignage = GeneratedColumn<bool>(
    'has_posted_signage',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_posted_signage" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastModifiedMeta = const VerificationMeta(
    'lastModified',
  );
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
    'last_modified',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _photoUriMeta = const VerificationMeta(
    'photoUri',
  );
  @override
  late final GeneratedColumn<String> photoUri = GeneratedColumn<String>(
    'photo_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _votesMeta = const VerificationMeta('votes');
  @override
  late final GeneratedColumn<int> votes = GeneratedColumn<int>(
    'votes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('user'),
  );
  static const VerificationMeta _sourceExternalIdMeta = const VerificationMeta(
    'sourceExternalId',
  );
  @override
  late final GeneratedColumn<String> sourceExternalId = GeneratedColumn<String>(
    'source_external_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceDatasetVersionMeta =
      const VerificationMeta('sourceDatasetVersion');
  @override
  late final GeneratedColumn<String> sourceDatasetVersion =
      GeneratedColumn<String>(
        'source_dataset_version',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
    'imported_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userModifiedMeta = const VerificationMeta(
    'userModified',
  );
  @override
  late final GeneratedColumn<bool> userModified = GeneratedColumn<bool>(
    'user_modified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("user_modified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<String> confidence = GeneratedColumn<String>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _legalCitationMeta = const VerificationMeta(
    'legalCitation',
  );
  @override
  late final GeneratedColumn<String> legalCitation = GeneratedColumn<String>(
    'legal_citation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _legalCitationVerifiedDateMeta =
      const VerificationMeta('legalCitationVerifiedDate');
  @override
  late final GeneratedColumn<String> legalCitationVerifiedDate =
      GeneratedColumn<String>(
        'legal_citation_verified_date',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sourceOrphanedAtMeta = const VerificationMeta(
    'sourceOrphanedAt',
  );
  @override
  late final GeneratedColumn<int> sourceOrphanedAt = GeneratedColumn<int>(
    'source_orphaned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    latitude,
    longitude,
    status,
    restrictionTag,
    hasSecurityScreening,
    hasPostedSignage,
    createdBy,
    createdAt,
    lastModified,
    photoUri,
    notes,
    votes,
    source,
    sourceExternalId,
    sourceDatasetVersion,
    importedAt,
    userModified,
    confidence,
    legalCitation,
    legalCitationVerifiedDate,
    sourceOrphanedAt,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<PinEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('restriction_tag')) {
      context.handle(
        _restrictionTagMeta,
        restrictionTag.isAcceptableOrUnknown(
          data['restriction_tag']!,
          _restrictionTagMeta,
        ),
      );
    }
    if (data.containsKey('has_security_screening')) {
      context.handle(
        _hasSecurityScreeningMeta,
        hasSecurityScreening.isAcceptableOrUnknown(
          data['has_security_screening']!,
          _hasSecurityScreeningMeta,
        ),
      );
    }
    if (data.containsKey('has_posted_signage')) {
      context.handle(
        _hasPostedSignageMeta,
        hasPostedSignage.isAcceptableOrUnknown(
          data['has_posted_signage']!,
          _hasPostedSignageMeta,
        ),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_modified')) {
      context.handle(
        _lastModifiedMeta,
        lastModified.isAcceptableOrUnknown(
          data['last_modified']!,
          _lastModifiedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('photo_uri')) {
      context.handle(
        _photoUriMeta,
        photoUri.isAcceptableOrUnknown(data['photo_uri']!, _photoUriMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('votes')) {
      context.handle(
        _votesMeta,
        votes.isAcceptableOrUnknown(data['votes']!, _votesMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('source_external_id')) {
      context.handle(
        _sourceExternalIdMeta,
        sourceExternalId.isAcceptableOrUnknown(
          data['source_external_id']!,
          _sourceExternalIdMeta,
        ),
      );
    }
    if (data.containsKey('source_dataset_version')) {
      context.handle(
        _sourceDatasetVersionMeta,
        sourceDatasetVersion.isAcceptableOrUnknown(
          data['source_dataset_version']!,
          _sourceDatasetVersionMeta,
        ),
      );
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    }
    if (data.containsKey('user_modified')) {
      context.handle(
        _userModifiedMeta,
        userModified.isAcceptableOrUnknown(
          data['user_modified']!,
          _userModifiedMeta,
        ),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('legal_citation')) {
      context.handle(
        _legalCitationMeta,
        legalCitation.isAcceptableOrUnknown(
          data['legal_citation']!,
          _legalCitationMeta,
        ),
      );
    }
    if (data.containsKey('legal_citation_verified_date')) {
      context.handle(
        _legalCitationVerifiedDateMeta,
        legalCitationVerifiedDate.isAcceptableOrUnknown(
          data['legal_citation_verified_date']!,
          _legalCitationVerifiedDateMeta,
        ),
      );
    }
    if (data.containsKey('source_orphaned_at')) {
      context.handle(
        _sourceOrphanedAtMeta,
        sourceOrphanedAt.isAcceptableOrUnknown(
          data['source_orphaned_at']!,
          _sourceOrphanedAtMeta,
        ),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PinEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PinEntity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      restrictionTag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restriction_tag'],
      ),
      hasSecurityScreening: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_security_screening'],
      )!,
      hasPostedSignage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_posted_signage'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastModified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_modified'],
      )!,
      photoUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_uri'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      votes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}votes'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      sourceExternalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_external_id'],
      ),
      sourceDatasetVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_dataset_version'],
      ),
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at'],
      ),
      userModified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}user_modified'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confidence'],
      ),
      legalCitation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legal_citation'],
      ),
      legalCitationVerifiedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legal_citation_verified_date'],
      ),
      sourceOrphanedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_orphaned_at'],
      ),
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      ),
    );
  }

  @override
  $PinsTable createAlias(String alias) {
    return $PinsTable(attachedDatabase, alias);
  }
}

class PinEntity extends DataClass implements Insertable<PinEntity> {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int status;
  final String? restrictionTag;
  final bool hasSecurityScreening;
  final bool hasPostedSignage;
  final String? createdBy;
  final int createdAt;
  final int lastModified;
  final String? photoUri;
  final String? notes;
  final int votes;

  /// Origin of this pin. `'user'` for user-created, otherwise the source
  /// module name (`'nces'`, `'hifld_courts'`, `'osm'`, etc.).
  final String source;

  /// Stable per-source identifier. Used as the upsert key by the importer.
  /// Null for user-created pins.
  final String? sourceExternalId;

  /// Version/snapshot of the upstream source data, e.g. `NCES-2024-25`.
  final String? sourceDatasetVersion;

  /// Milliseconds since epoch — when the importer last touched this row.
  final int? importedAt;

  /// True once any non-importer write hits the row. Server-side trigger
  /// is authoritative; we just mirror the value when we sync down.
  final bool userModified;

  /// `'high'` / `'medium'` / `'low'` from the state-law lookup table.
  final String? confidence;

  /// Statute citation, e.g. `'18 USC 930(a)'` or `'TX Penal Code §46.035(b)(1)'`.
  final String? legalCitation;

  /// ISO date string (YYYY-MM-DD) — when the citation was last reconciled.
  final String? legalCitationVerifiedDate;

  /// Milliseconds since epoch — when the pin disappeared from its source
  /// dataset. Surfaces in dry-run reports; never auto-deletes.
  final int? sourceOrphanedAt;

  /// Milliseconds since epoch — when this pin was last fetched via the
  /// bbox cache. NULL for user-created pins (the "mine" tier never evicts).
  /// Used by ViewportPinsManager for LRU eviction.
  final int? cachedAt;
  const PinEntity({
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
    required this.source,
    this.sourceExternalId,
    this.sourceDatasetVersion,
    this.importedAt,
    required this.userModified,
    this.confidence,
    this.legalCitation,
    this.legalCitationVerifiedDate,
    this.sourceOrphanedAt,
    this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || restrictionTag != null) {
      map['restriction_tag'] = Variable<String>(restrictionTag);
    }
    map['has_security_screening'] = Variable<bool>(hasSecurityScreening);
    map['has_posted_signage'] = Variable<bool>(hasPostedSignage);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['last_modified'] = Variable<int>(lastModified);
    if (!nullToAbsent || photoUri != null) {
      map['photo_uri'] = Variable<String>(photoUri);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['votes'] = Variable<int>(votes);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || sourceExternalId != null) {
      map['source_external_id'] = Variable<String>(sourceExternalId);
    }
    if (!nullToAbsent || sourceDatasetVersion != null) {
      map['source_dataset_version'] = Variable<String>(sourceDatasetVersion);
    }
    if (!nullToAbsent || importedAt != null) {
      map['imported_at'] = Variable<int>(importedAt);
    }
    map['user_modified'] = Variable<bool>(userModified);
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<String>(confidence);
    }
    if (!nullToAbsent || legalCitation != null) {
      map['legal_citation'] = Variable<String>(legalCitation);
    }
    if (!nullToAbsent || legalCitationVerifiedDate != null) {
      map['legal_citation_verified_date'] = Variable<String>(
        legalCitationVerifiedDate,
      );
    }
    if (!nullToAbsent || sourceOrphanedAt != null) {
      map['source_orphaned_at'] = Variable<int>(sourceOrphanedAt);
    }
    if (!nullToAbsent || cachedAt != null) {
      map['cached_at'] = Variable<int>(cachedAt);
    }
    return map;
  }

  PinsCompanion toCompanion(bool nullToAbsent) {
    return PinsCompanion(
      id: Value(id),
      name: Value(name),
      latitude: Value(latitude),
      longitude: Value(longitude),
      status: Value(status),
      restrictionTag: restrictionTag == null && nullToAbsent
          ? const Value.absent()
          : Value(restrictionTag),
      hasSecurityScreening: Value(hasSecurityScreening),
      hasPostedSignage: Value(hasPostedSignage),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      createdAt: Value(createdAt),
      lastModified: Value(lastModified),
      photoUri: photoUri == null && nullToAbsent
          ? const Value.absent()
          : Value(photoUri),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      votes: Value(votes),
      source: Value(source),
      sourceExternalId: sourceExternalId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceExternalId),
      sourceDatasetVersion: sourceDatasetVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDatasetVersion),
      importedAt: importedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(importedAt),
      userModified: Value(userModified),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      legalCitation: legalCitation == null && nullToAbsent
          ? const Value.absent()
          : Value(legalCitation),
      legalCitationVerifiedDate:
          legalCitationVerifiedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(legalCitationVerifiedDate),
      sourceOrphanedAt: sourceOrphanedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceOrphanedAt),
      cachedAt: cachedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cachedAt),
    );
  }

  factory PinEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PinEntity(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      status: serializer.fromJson<int>(json['status']),
      restrictionTag: serializer.fromJson<String?>(json['restrictionTag']),
      hasSecurityScreening: serializer.fromJson<bool>(
        json['hasSecurityScreening'],
      ),
      hasPostedSignage: serializer.fromJson<bool>(json['hasPostedSignage']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      photoUri: serializer.fromJson<String?>(json['photoUri']),
      notes: serializer.fromJson<String?>(json['notes']),
      votes: serializer.fromJson<int>(json['votes']),
      source: serializer.fromJson<String>(json['source']),
      sourceExternalId: serializer.fromJson<String?>(json['sourceExternalId']),
      sourceDatasetVersion: serializer.fromJson<String?>(
        json['sourceDatasetVersion'],
      ),
      importedAt: serializer.fromJson<int?>(json['importedAt']),
      userModified: serializer.fromJson<bool>(json['userModified']),
      confidence: serializer.fromJson<String?>(json['confidence']),
      legalCitation: serializer.fromJson<String?>(json['legalCitation']),
      legalCitationVerifiedDate: serializer.fromJson<String?>(
        json['legalCitationVerifiedDate'],
      ),
      sourceOrphanedAt: serializer.fromJson<int?>(json['sourceOrphanedAt']),
      cachedAt: serializer.fromJson<int?>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'status': serializer.toJson<int>(status),
      'restrictionTag': serializer.toJson<String?>(restrictionTag),
      'hasSecurityScreening': serializer.toJson<bool>(hasSecurityScreening),
      'hasPostedSignage': serializer.toJson<bool>(hasPostedSignage),
      'createdBy': serializer.toJson<String?>(createdBy),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'photoUri': serializer.toJson<String?>(photoUri),
      'notes': serializer.toJson<String?>(notes),
      'votes': serializer.toJson<int>(votes),
      'source': serializer.toJson<String>(source),
      'sourceExternalId': serializer.toJson<String?>(sourceExternalId),
      'sourceDatasetVersion': serializer.toJson<String?>(sourceDatasetVersion),
      'importedAt': serializer.toJson<int?>(importedAt),
      'userModified': serializer.toJson<bool>(userModified),
      'confidence': serializer.toJson<String?>(confidence),
      'legalCitation': serializer.toJson<String?>(legalCitation),
      'legalCitationVerifiedDate': serializer.toJson<String?>(
        legalCitationVerifiedDate,
      ),
      'sourceOrphanedAt': serializer.toJson<int?>(sourceOrphanedAt),
      'cachedAt': serializer.toJson<int?>(cachedAt),
    };
  }

  PinEntity copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    int? status,
    Value<String?> restrictionTag = const Value.absent(),
    bool? hasSecurityScreening,
    bool? hasPostedSignage,
    Value<String?> createdBy = const Value.absent(),
    int? createdAt,
    int? lastModified,
    Value<String?> photoUri = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? votes,
    String? source,
    Value<String?> sourceExternalId = const Value.absent(),
    Value<String?> sourceDatasetVersion = const Value.absent(),
    Value<int?> importedAt = const Value.absent(),
    bool? userModified,
    Value<String?> confidence = const Value.absent(),
    Value<String?> legalCitation = const Value.absent(),
    Value<String?> legalCitationVerifiedDate = const Value.absent(),
    Value<int?> sourceOrphanedAt = const Value.absent(),
    Value<int?> cachedAt = const Value.absent(),
  }) => PinEntity(
    id: id ?? this.id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    status: status ?? this.status,
    restrictionTag: restrictionTag.present
        ? restrictionTag.value
        : this.restrictionTag,
    hasSecurityScreening: hasSecurityScreening ?? this.hasSecurityScreening,
    hasPostedSignage: hasPostedSignage ?? this.hasPostedSignage,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    lastModified: lastModified ?? this.lastModified,
    photoUri: photoUri.present ? photoUri.value : this.photoUri,
    notes: notes.present ? notes.value : this.notes,
    votes: votes ?? this.votes,
    source: source ?? this.source,
    sourceExternalId: sourceExternalId.present
        ? sourceExternalId.value
        : this.sourceExternalId,
    sourceDatasetVersion: sourceDatasetVersion.present
        ? sourceDatasetVersion.value
        : this.sourceDatasetVersion,
    importedAt: importedAt.present ? importedAt.value : this.importedAt,
    userModified: userModified ?? this.userModified,
    confidence: confidence.present ? confidence.value : this.confidence,
    legalCitation: legalCitation.present
        ? legalCitation.value
        : this.legalCitation,
    legalCitationVerifiedDate: legalCitationVerifiedDate.present
        ? legalCitationVerifiedDate.value
        : this.legalCitationVerifiedDate,
    sourceOrphanedAt: sourceOrphanedAt.present
        ? sourceOrphanedAt.value
        : this.sourceOrphanedAt,
    cachedAt: cachedAt.present ? cachedAt.value : this.cachedAt,
  );
  PinEntity copyWithCompanion(PinsCompanion data) {
    return PinEntity(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      status: data.status.present ? data.status.value : this.status,
      restrictionTag: data.restrictionTag.present
          ? data.restrictionTag.value
          : this.restrictionTag,
      hasSecurityScreening: data.hasSecurityScreening.present
          ? data.hasSecurityScreening.value
          : this.hasSecurityScreening,
      hasPostedSignage: data.hasPostedSignage.present
          ? data.hasPostedSignage.value
          : this.hasPostedSignage,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      photoUri: data.photoUri.present ? data.photoUri.value : this.photoUri,
      notes: data.notes.present ? data.notes.value : this.notes,
      votes: data.votes.present ? data.votes.value : this.votes,
      source: data.source.present ? data.source.value : this.source,
      sourceExternalId: data.sourceExternalId.present
          ? data.sourceExternalId.value
          : this.sourceExternalId,
      sourceDatasetVersion: data.sourceDatasetVersion.present
          ? data.sourceDatasetVersion.value
          : this.sourceDatasetVersion,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      userModified: data.userModified.present
          ? data.userModified.value
          : this.userModified,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      legalCitation: data.legalCitation.present
          ? data.legalCitation.value
          : this.legalCitation,
      legalCitationVerifiedDate: data.legalCitationVerifiedDate.present
          ? data.legalCitationVerifiedDate.value
          : this.legalCitationVerifiedDate,
      sourceOrphanedAt: data.sourceOrphanedAt.present
          ? data.sourceOrphanedAt.value
          : this.sourceOrphanedAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PinEntity(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('status: $status, ')
          ..write('restrictionTag: $restrictionTag, ')
          ..write('hasSecurityScreening: $hasSecurityScreening, ')
          ..write('hasPostedSignage: $hasPostedSignage, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('photoUri: $photoUri, ')
          ..write('notes: $notes, ')
          ..write('votes: $votes, ')
          ..write('source: $source, ')
          ..write('sourceExternalId: $sourceExternalId, ')
          ..write('sourceDatasetVersion: $sourceDatasetVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('userModified: $userModified, ')
          ..write('confidence: $confidence, ')
          ..write('legalCitation: $legalCitation, ')
          ..write('legalCitationVerifiedDate: $legalCitationVerifiedDate, ')
          ..write('sourceOrphanedAt: $sourceOrphanedAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    latitude,
    longitude,
    status,
    restrictionTag,
    hasSecurityScreening,
    hasPostedSignage,
    createdBy,
    createdAt,
    lastModified,
    photoUri,
    notes,
    votes,
    source,
    sourceExternalId,
    sourceDatasetVersion,
    importedAt,
    userModified,
    confidence,
    legalCitation,
    legalCitationVerifiedDate,
    sourceOrphanedAt,
    cachedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PinEntity &&
          other.id == this.id &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.status == this.status &&
          other.restrictionTag == this.restrictionTag &&
          other.hasSecurityScreening == this.hasSecurityScreening &&
          other.hasPostedSignage == this.hasPostedSignage &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.lastModified == this.lastModified &&
          other.photoUri == this.photoUri &&
          other.notes == this.notes &&
          other.votes == this.votes &&
          other.source == this.source &&
          other.sourceExternalId == this.sourceExternalId &&
          other.sourceDatasetVersion == this.sourceDatasetVersion &&
          other.importedAt == this.importedAt &&
          other.userModified == this.userModified &&
          other.confidence == this.confidence &&
          other.legalCitation == this.legalCitation &&
          other.legalCitationVerifiedDate == this.legalCitationVerifiedDate &&
          other.sourceOrphanedAt == this.sourceOrphanedAt &&
          other.cachedAt == this.cachedAt);
}

class PinsCompanion extends UpdateCompanion<PinEntity> {
  final Value<String> id;
  final Value<String> name;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<int> status;
  final Value<String?> restrictionTag;
  final Value<bool> hasSecurityScreening;
  final Value<bool> hasPostedSignage;
  final Value<String?> createdBy;
  final Value<int> createdAt;
  final Value<int> lastModified;
  final Value<String?> photoUri;
  final Value<String?> notes;
  final Value<int> votes;
  final Value<String> source;
  final Value<String?> sourceExternalId;
  final Value<String?> sourceDatasetVersion;
  final Value<int?> importedAt;
  final Value<bool> userModified;
  final Value<String?> confidence;
  final Value<String?> legalCitation;
  final Value<String?> legalCitationVerifiedDate;
  final Value<int?> sourceOrphanedAt;
  final Value<int?> cachedAt;
  final Value<int> rowid;
  const PinsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.status = const Value.absent(),
    this.restrictionTag = const Value.absent(),
    this.hasSecurityScreening = const Value.absent(),
    this.hasPostedSignage = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.photoUri = const Value.absent(),
    this.notes = const Value.absent(),
    this.votes = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceExternalId = const Value.absent(),
    this.sourceDatasetVersion = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.userModified = const Value.absent(),
    this.confidence = const Value.absent(),
    this.legalCitation = const Value.absent(),
    this.legalCitationVerifiedDate = const Value.absent(),
    this.sourceOrphanedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PinsCompanion.insert({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    required int status,
    this.restrictionTag = const Value.absent(),
    this.hasSecurityScreening = const Value.absent(),
    this.hasPostedSignage = const Value.absent(),
    this.createdBy = const Value.absent(),
    required int createdAt,
    required int lastModified,
    this.photoUri = const Value.absent(),
    this.notes = const Value.absent(),
    this.votes = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceExternalId = const Value.absent(),
    this.sourceDatasetVersion = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.userModified = const Value.absent(),
    this.confidence = const Value.absent(),
    this.legalCitation = const Value.absent(),
    this.legalCitationVerifiedDate = const Value.absent(),
    this.sourceOrphanedAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       latitude = Value(latitude),
       longitude = Value(longitude),
       status = Value(status),
       createdAt = Value(createdAt),
       lastModified = Value(lastModified);
  static Insertable<PinEntity> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? status,
    Expression<String>? restrictionTag,
    Expression<bool>? hasSecurityScreening,
    Expression<bool>? hasPostedSignage,
    Expression<String>? createdBy,
    Expression<int>? createdAt,
    Expression<int>? lastModified,
    Expression<String>? photoUri,
    Expression<String>? notes,
    Expression<int>? votes,
    Expression<String>? source,
    Expression<String>? sourceExternalId,
    Expression<String>? sourceDatasetVersion,
    Expression<int>? importedAt,
    Expression<bool>? userModified,
    Expression<String>? confidence,
    Expression<String>? legalCitation,
    Expression<String>? legalCitationVerifiedDate,
    Expression<int>? sourceOrphanedAt,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (status != null) 'status': status,
      if (restrictionTag != null) 'restriction_tag': restrictionTag,
      if (hasSecurityScreening != null)
        'has_security_screening': hasSecurityScreening,
      if (hasPostedSignage != null) 'has_posted_signage': hasPostedSignage,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (photoUri != null) 'photo_uri': photoUri,
      if (notes != null) 'notes': notes,
      if (votes != null) 'votes': votes,
      if (source != null) 'source': source,
      if (sourceExternalId != null) 'source_external_id': sourceExternalId,
      if (sourceDatasetVersion != null)
        'source_dataset_version': sourceDatasetVersion,
      if (importedAt != null) 'imported_at': importedAt,
      if (userModified != null) 'user_modified': userModified,
      if (confidence != null) 'confidence': confidence,
      if (legalCitation != null) 'legal_citation': legalCitation,
      if (legalCitationVerifiedDate != null)
        'legal_citation_verified_date': legalCitationVerifiedDate,
      if (sourceOrphanedAt != null) 'source_orphaned_at': sourceOrphanedAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PinsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<int>? status,
    Value<String?>? restrictionTag,
    Value<bool>? hasSecurityScreening,
    Value<bool>? hasPostedSignage,
    Value<String?>? createdBy,
    Value<int>? createdAt,
    Value<int>? lastModified,
    Value<String?>? photoUri,
    Value<String?>? notes,
    Value<int>? votes,
    Value<String>? source,
    Value<String?>? sourceExternalId,
    Value<String?>? sourceDatasetVersion,
    Value<int?>? importedAt,
    Value<bool>? userModified,
    Value<String?>? confidence,
    Value<String?>? legalCitation,
    Value<String?>? legalCitationVerifiedDate,
    Value<int?>? sourceOrphanedAt,
    Value<int?>? cachedAt,
    Value<int>? rowid,
  }) {
    return PinsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      restrictionTag: restrictionTag ?? this.restrictionTag,
      hasSecurityScreening: hasSecurityScreening ?? this.hasSecurityScreening,
      hasPostedSignage: hasPostedSignage ?? this.hasPostedSignage,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
      photoUri: photoUri ?? this.photoUri,
      notes: notes ?? this.notes,
      votes: votes ?? this.votes,
      source: source ?? this.source,
      sourceExternalId: sourceExternalId ?? this.sourceExternalId,
      sourceDatasetVersion: sourceDatasetVersion ?? this.sourceDatasetVersion,
      importedAt: importedAt ?? this.importedAt,
      userModified: userModified ?? this.userModified,
      confidence: confidence ?? this.confidence,
      legalCitation: legalCitation ?? this.legalCitation,
      legalCitationVerifiedDate:
          legalCitationVerifiedDate ?? this.legalCitationVerifiedDate,
      sourceOrphanedAt: sourceOrphanedAt ?? this.sourceOrphanedAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (restrictionTag.present) {
      map['restriction_tag'] = Variable<String>(restrictionTag.value);
    }
    if (hasSecurityScreening.present) {
      map['has_security_screening'] = Variable<bool>(
        hasSecurityScreening.value,
      );
    }
    if (hasPostedSignage.present) {
      map['has_posted_signage'] = Variable<bool>(hasPostedSignage.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (photoUri.present) {
      map['photo_uri'] = Variable<String>(photoUri.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (votes.present) {
      map['votes'] = Variable<int>(votes.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceExternalId.present) {
      map['source_external_id'] = Variable<String>(sourceExternalId.value);
    }
    if (sourceDatasetVersion.present) {
      map['source_dataset_version'] = Variable<String>(
        sourceDatasetVersion.value,
      );
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (userModified.present) {
      map['user_modified'] = Variable<bool>(userModified.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<String>(confidence.value);
    }
    if (legalCitation.present) {
      map['legal_citation'] = Variable<String>(legalCitation.value);
    }
    if (legalCitationVerifiedDate.present) {
      map['legal_citation_verified_date'] = Variable<String>(
        legalCitationVerifiedDate.value,
      );
    }
    if (sourceOrphanedAt.present) {
      map['source_orphaned_at'] = Variable<int>(sourceOrphanedAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('status: $status, ')
          ..write('restrictionTag: $restrictionTag, ')
          ..write('hasSecurityScreening: $hasSecurityScreening, ')
          ..write('hasPostedSignage: $hasPostedSignage, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('photoUri: $photoUri, ')
          ..write('notes: $notes, ')
          ..write('votes: $votes, ')
          ..write('source: $source, ')
          ..write('sourceExternalId: $sourceExternalId, ')
          ..write('sourceDatasetVersion: $sourceDatasetVersion, ')
          ..write('importedAt: $importedAt, ')
          ..write('userModified: $userModified, ')
          ..write('confidence: $confidence, ')
          ..write('legalCitation: $legalCitation, ')
          ..write('legalCitationVerifiedDate: $legalCitationVerifiedDate, ')
          ..write('sourceOrphanedAt: $sourceOrphanedAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, SyncQueueEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinIdMeta = const VerificationMeta('pinId');
  @override
  late final GeneratedColumn<String> pinId = GeneratedColumn<String>(
    'pin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pinId,
    operationType,
    timestamp,
    retryCount,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncQueueEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pin_id')) {
      context.handle(
        _pinIdMeta,
        pinId.isAcceptableOrUnknown(data['pin_id']!, _pinIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pinIdMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncQueueEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncQueueEntity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pinId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin_id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class SyncQueueEntity extends DataClass implements Insertable<SyncQueueEntity> {
  final String id;
  final String pinId;
  final String operationType;
  final int timestamp;
  final int retryCount;
  final String? lastError;
  const SyncQueueEntity({
    required this.id,
    required this.pinId,
    required this.operationType,
    required this.timestamp,
    required this.retryCount,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pin_id'] = Variable<String>(pinId);
    map['operation_type'] = Variable<String>(operationType);
    map['timestamp'] = Variable<int>(timestamp);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      pinId: Value(pinId),
      operationType: Value(operationType),
      timestamp: Value(timestamp),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncQueueEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncQueueEntity(
      id: serializer.fromJson<String>(json['id']),
      pinId: serializer.fromJson<String>(json['pinId']),
      operationType: serializer.fromJson<String>(json['operationType']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pinId': serializer.toJson<String>(pinId),
      'operationType': serializer.toJson<String>(operationType),
      'timestamp': serializer.toJson<int>(timestamp),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncQueueEntity copyWith({
    String? id,
    String? pinId,
    String? operationType,
    int? timestamp,
    int? retryCount,
    Value<String?> lastError = const Value.absent(),
  }) => SyncQueueEntity(
    id: id ?? this.id,
    pinId: pinId ?? this.pinId,
    operationType: operationType ?? this.operationType,
    timestamp: timestamp ?? this.timestamp,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncQueueEntity copyWithCompanion(SyncQueueCompanion data) {
    return SyncQueueEntity(
      id: data.id.present ? data.id.value : this.id,
      pinId: data.pinId.present ? data.pinId.value : this.pinId,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueEntity(')
          ..write('id: $id, ')
          ..write('pinId: $pinId, ')
          ..write('operationType: $operationType, ')
          ..write('timestamp: $timestamp, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, pinId, operationType, timestamp, retryCount, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncQueueEntity &&
          other.id == this.id &&
          other.pinId == this.pinId &&
          other.operationType == this.operationType &&
          other.timestamp == this.timestamp &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError);
}

class SyncQueueCompanion extends UpdateCompanion<SyncQueueEntity> {
  final Value<String> id;
  final Value<String> pinId;
  final Value<String> operationType;
  final Value<int> timestamp;
  final Value<int> retryCount;
  final Value<String?> lastError;
  final Value<int> rowid;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.pinId = const Value.absent(),
    this.operationType = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    required String id,
    required String pinId,
    required String operationType,
    required int timestamp,
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pinId = Value(pinId),
       operationType = Value(operationType),
       timestamp = Value(timestamp);
  static Insertable<SyncQueueEntity> custom({
    Expression<String>? id,
    Expression<String>? pinId,
    Expression<String>? operationType,
    Expression<int>? timestamp,
    Expression<int>? retryCount,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pinId != null) 'pin_id': pinId,
      if (operationType != null) 'operation_type': operationType,
      if (timestamp != null) 'timestamp': timestamp,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? pinId,
    Value<String>? operationType,
    Value<int>? timestamp,
    Value<int>? retryCount,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      pinId: pinId ?? this.pinId,
      operationType: operationType ?? this.operationType,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pinId.present) {
      map['pin_id'] = Variable<String>(pinId.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('pinId: $pinId, ')
          ..write('operationType: $operationType, ')
          ..write('timestamp: $timestamp, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PinTombstonesTable extends PinTombstones
    with TableInfo<$PinTombstonesTable, PinTombstoneEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pinIdMeta = const VerificationMeta('pinId');
  @override
  late final GeneratedColumn<String> pinId = GeneratedColumn<String>(
    'pin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [pinId, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pin_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<PinTombstoneEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pin_id')) {
      context.handle(
        _pinIdMeta,
        pinId.isAcceptableOrUnknown(data['pin_id']!, _pinIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pinIdMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pinId};
  @override
  PinTombstoneEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PinTombstoneEntity(
      pinId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin_id'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $PinTombstonesTable createAlias(String alias) {
    return $PinTombstonesTable(attachedDatabase, alias);
  }
}

class PinTombstoneEntity extends DataClass
    implements Insertable<PinTombstoneEntity> {
  final String pinId;
  final int deletedAt;
  const PinTombstoneEntity({required this.pinId, required this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pin_id'] = Variable<String>(pinId);
    map['deleted_at'] = Variable<int>(deletedAt);
    return map;
  }

  PinTombstonesCompanion toCompanion(bool nullToAbsent) {
    return PinTombstonesCompanion(
      pinId: Value(pinId),
      deletedAt: Value(deletedAt),
    );
  }

  factory PinTombstoneEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PinTombstoneEntity(
      pinId: serializer.fromJson<String>(json['pinId']),
      deletedAt: serializer.fromJson<int>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pinId': serializer.toJson<String>(pinId),
      'deletedAt': serializer.toJson<int>(deletedAt),
    };
  }

  PinTombstoneEntity copyWith({String? pinId, int? deletedAt}) =>
      PinTombstoneEntity(
        pinId: pinId ?? this.pinId,
        deletedAt: deletedAt ?? this.deletedAt,
      );
  PinTombstoneEntity copyWithCompanion(PinTombstonesCompanion data) {
    return PinTombstoneEntity(
      pinId: data.pinId.present ? data.pinId.value : this.pinId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PinTombstoneEntity(')
          ..write('pinId: $pinId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pinId, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PinTombstoneEntity &&
          other.pinId == this.pinId &&
          other.deletedAt == this.deletedAt);
}

class PinTombstonesCompanion extends UpdateCompanion<PinTombstoneEntity> {
  final Value<String> pinId;
  final Value<int> deletedAt;
  final Value<int> rowid;
  const PinTombstonesCompanion({
    this.pinId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PinTombstonesCompanion.insert({
    required String pinId,
    required int deletedAt,
    this.rowid = const Value.absent(),
  }) : pinId = Value(pinId),
       deletedAt = Value(deletedAt);
  static Insertable<PinTombstoneEntity> custom({
    Expression<String>? pinId,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pinId != null) 'pin_id': pinId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PinTombstonesCompanion copyWith({
    Value<String>? pinId,
    Value<int>? deletedAt,
    Value<int>? rowid,
  }) {
    return PinTombstonesCompanion(
      pinId: pinId ?? this.pinId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pinId.present) {
      map['pin_id'] = Variable<String>(pinId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinTombstonesCompanion(')
          ..write('pinId: $pinId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FetchedBboxesTable extends FetchedBboxes
    with TableInfo<$FetchedBboxesTable, FetchedBboxEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FetchedBboxesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _swLatMeta = const VerificationMeta('swLat');
  @override
  late final GeneratedColumn<double> swLat = GeneratedColumn<double>(
    'sw_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _swLngMeta = const VerificationMeta('swLng');
  @override
  late final GeneratedColumn<double> swLng = GeneratedColumn<double>(
    'sw_lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _neLatMeta = const VerificationMeta('neLat');
  @override
  late final GeneratedColumn<double> neLat = GeneratedColumn<double>(
    'ne_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _neLngMeta = const VerificationMeta('neLng');
  @override
  late final GeneratedColumn<double> neLng = GeneratedColumn<double>(
    'ne_lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zoomMeta = const VerificationMeta('zoom');
  @override
  late final GeneratedColumn<int> zoom = GeneratedColumn<int>(
    'zoom',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinCountMeta = const VerificationMeta(
    'pinCount',
  );
  @override
  late final GeneratedColumn<int> pinCount = GeneratedColumn<int>(
    'pin_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    swLat,
    swLng,
    neLat,
    neLng,
    zoom,
    fetchedAt,
    pinCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fetched_bboxes';
  @override
  VerificationContext validateIntegrity(
    Insertable<FetchedBboxEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sw_lat')) {
      context.handle(
        _swLatMeta,
        swLat.isAcceptableOrUnknown(data['sw_lat']!, _swLatMeta),
      );
    } else if (isInserting) {
      context.missing(_swLatMeta);
    }
    if (data.containsKey('sw_lng')) {
      context.handle(
        _swLngMeta,
        swLng.isAcceptableOrUnknown(data['sw_lng']!, _swLngMeta),
      );
    } else if (isInserting) {
      context.missing(_swLngMeta);
    }
    if (data.containsKey('ne_lat')) {
      context.handle(
        _neLatMeta,
        neLat.isAcceptableOrUnknown(data['ne_lat']!, _neLatMeta),
      );
    } else if (isInserting) {
      context.missing(_neLatMeta);
    }
    if (data.containsKey('ne_lng')) {
      context.handle(
        _neLngMeta,
        neLng.isAcceptableOrUnknown(data['ne_lng']!, _neLngMeta),
      );
    } else if (isInserting) {
      context.missing(_neLngMeta);
    }
    if (data.containsKey('zoom')) {
      context.handle(
        _zoomMeta,
        zoom.isAcceptableOrUnknown(data['zoom']!, _zoomMeta),
      );
    } else if (isInserting) {
      context.missing(_zoomMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('pin_count')) {
      context.handle(
        _pinCountMeta,
        pinCount.isAcceptableOrUnknown(data['pin_count']!, _pinCountMeta),
      );
    } else if (isInserting) {
      context.missing(_pinCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FetchedBboxEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FetchedBboxEntity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      swLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sw_lat'],
      )!,
      swLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sw_lng'],
      )!,
      neLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ne_lat'],
      )!,
      neLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ne_lng'],
      )!,
      zoom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}zoom'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      pinCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pin_count'],
      )!,
    );
  }

  @override
  $FetchedBboxesTable createAlias(String alias) {
    return $FetchedBboxesTable(attachedDatabase, alias);
  }
}

class FetchedBboxEntity extends DataClass
    implements Insertable<FetchedBboxEntity> {
  final int id;
  final double swLat;
  final double swLng;
  final double neLat;
  final double neLng;
  final int zoom;
  final int fetchedAt;
  final int pinCount;
  const FetchedBboxEntity({
    required this.id,
    required this.swLat,
    required this.swLng,
    required this.neLat,
    required this.neLng,
    required this.zoom,
    required this.fetchedAt,
    required this.pinCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sw_lat'] = Variable<double>(swLat);
    map['sw_lng'] = Variable<double>(swLng);
    map['ne_lat'] = Variable<double>(neLat);
    map['ne_lng'] = Variable<double>(neLng);
    map['zoom'] = Variable<int>(zoom);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['pin_count'] = Variable<int>(pinCount);
    return map;
  }

  FetchedBboxesCompanion toCompanion(bool nullToAbsent) {
    return FetchedBboxesCompanion(
      id: Value(id),
      swLat: Value(swLat),
      swLng: Value(swLng),
      neLat: Value(neLat),
      neLng: Value(neLng),
      zoom: Value(zoom),
      fetchedAt: Value(fetchedAt),
      pinCount: Value(pinCount),
    );
  }

  factory FetchedBboxEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FetchedBboxEntity(
      id: serializer.fromJson<int>(json['id']),
      swLat: serializer.fromJson<double>(json['swLat']),
      swLng: serializer.fromJson<double>(json['swLng']),
      neLat: serializer.fromJson<double>(json['neLat']),
      neLng: serializer.fromJson<double>(json['neLng']),
      zoom: serializer.fromJson<int>(json['zoom']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      pinCount: serializer.fromJson<int>(json['pinCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'swLat': serializer.toJson<double>(swLat),
      'swLng': serializer.toJson<double>(swLng),
      'neLat': serializer.toJson<double>(neLat),
      'neLng': serializer.toJson<double>(neLng),
      'zoom': serializer.toJson<int>(zoom),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'pinCount': serializer.toJson<int>(pinCount),
    };
  }

  FetchedBboxEntity copyWith({
    int? id,
    double? swLat,
    double? swLng,
    double? neLat,
    double? neLng,
    int? zoom,
    int? fetchedAt,
    int? pinCount,
  }) => FetchedBboxEntity(
    id: id ?? this.id,
    swLat: swLat ?? this.swLat,
    swLng: swLng ?? this.swLng,
    neLat: neLat ?? this.neLat,
    neLng: neLng ?? this.neLng,
    zoom: zoom ?? this.zoom,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    pinCount: pinCount ?? this.pinCount,
  );
  FetchedBboxEntity copyWithCompanion(FetchedBboxesCompanion data) {
    return FetchedBboxEntity(
      id: data.id.present ? data.id.value : this.id,
      swLat: data.swLat.present ? data.swLat.value : this.swLat,
      swLng: data.swLng.present ? data.swLng.value : this.swLng,
      neLat: data.neLat.present ? data.neLat.value : this.neLat,
      neLng: data.neLng.present ? data.neLng.value : this.neLng,
      zoom: data.zoom.present ? data.zoom.value : this.zoom,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      pinCount: data.pinCount.present ? data.pinCount.value : this.pinCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FetchedBboxEntity(')
          ..write('id: $id, ')
          ..write('swLat: $swLat, ')
          ..write('swLng: $swLng, ')
          ..write('neLat: $neLat, ')
          ..write('neLng: $neLng, ')
          ..write('zoom: $zoom, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('pinCount: $pinCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, swLat, swLng, neLat, neLng, zoom, fetchedAt, pinCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FetchedBboxEntity &&
          other.id == this.id &&
          other.swLat == this.swLat &&
          other.swLng == this.swLng &&
          other.neLat == this.neLat &&
          other.neLng == this.neLng &&
          other.zoom == this.zoom &&
          other.fetchedAt == this.fetchedAt &&
          other.pinCount == this.pinCount);
}

class FetchedBboxesCompanion extends UpdateCompanion<FetchedBboxEntity> {
  final Value<int> id;
  final Value<double> swLat;
  final Value<double> swLng;
  final Value<double> neLat;
  final Value<double> neLng;
  final Value<int> zoom;
  final Value<int> fetchedAt;
  final Value<int> pinCount;
  const FetchedBboxesCompanion({
    this.id = const Value.absent(),
    this.swLat = const Value.absent(),
    this.swLng = const Value.absent(),
    this.neLat = const Value.absent(),
    this.neLng = const Value.absent(),
    this.zoom = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.pinCount = const Value.absent(),
  });
  FetchedBboxesCompanion.insert({
    this.id = const Value.absent(),
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required int zoom,
    required int fetchedAt,
    required int pinCount,
  }) : swLat = Value(swLat),
       swLng = Value(swLng),
       neLat = Value(neLat),
       neLng = Value(neLng),
       zoom = Value(zoom),
       fetchedAt = Value(fetchedAt),
       pinCount = Value(pinCount);
  static Insertable<FetchedBboxEntity> custom({
    Expression<int>? id,
    Expression<double>? swLat,
    Expression<double>? swLng,
    Expression<double>? neLat,
    Expression<double>? neLng,
    Expression<int>? zoom,
    Expression<int>? fetchedAt,
    Expression<int>? pinCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (swLat != null) 'sw_lat': swLat,
      if (swLng != null) 'sw_lng': swLng,
      if (neLat != null) 'ne_lat': neLat,
      if (neLng != null) 'ne_lng': neLng,
      if (zoom != null) 'zoom': zoom,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (pinCount != null) 'pin_count': pinCount,
    });
  }

  FetchedBboxesCompanion copyWith({
    Value<int>? id,
    Value<double>? swLat,
    Value<double>? swLng,
    Value<double>? neLat,
    Value<double>? neLng,
    Value<int>? zoom,
    Value<int>? fetchedAt,
    Value<int>? pinCount,
  }) {
    return FetchedBboxesCompanion(
      id: id ?? this.id,
      swLat: swLat ?? this.swLat,
      swLng: swLng ?? this.swLng,
      neLat: neLat ?? this.neLat,
      neLng: neLng ?? this.neLng,
      zoom: zoom ?? this.zoom,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      pinCount: pinCount ?? this.pinCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (swLat.present) {
      map['sw_lat'] = Variable<double>(swLat.value);
    }
    if (swLng.present) {
      map['sw_lng'] = Variable<double>(swLng.value);
    }
    if (neLat.present) {
      map['ne_lat'] = Variable<double>(neLat.value);
    }
    if (neLng.present) {
      map['ne_lng'] = Variable<double>(neLng.value);
    }
    if (zoom.present) {
      map['zoom'] = Variable<int>(zoom.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (pinCount.present) {
      map['pin_count'] = Variable<int>(pinCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FetchedBboxesCompanion(')
          ..write('id: $id, ')
          ..write('swLat: $swLat, ')
          ..write('swLng: $swLng, ')
          ..write('neLat: $neLat, ')
          ..write('neLng: $neLng, ')
          ..write('zoom: $zoom, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('pinCount: $pinCount')
          ..write(')'))
        .toString();
  }
}

class $ServerPinDeletionsTable extends ServerPinDeletions
    with TableInfo<$ServerPinDeletionsTable, ServerPinDeletionEntity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServerPinDeletionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pinIdMeta = const VerificationMeta('pinId');
  @override
  late final GeneratedColumn<String> pinId = GeneratedColumn<String>(
    'pin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [pinId, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'server_pin_deletions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServerPinDeletionEntity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pin_id')) {
      context.handle(
        _pinIdMeta,
        pinId.isAcceptableOrUnknown(data['pin_id']!, _pinIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pinIdMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pinId};
  @override
  ServerPinDeletionEntity map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerPinDeletionEntity(
      pinId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin_id'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $ServerPinDeletionsTable createAlias(String alias) {
    return $ServerPinDeletionsTable(attachedDatabase, alias);
  }
}

class ServerPinDeletionEntity extends DataClass
    implements Insertable<ServerPinDeletionEntity> {
  final String pinId;
  final int deletedAt;
  const ServerPinDeletionEntity({required this.pinId, required this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pin_id'] = Variable<String>(pinId);
    map['deleted_at'] = Variable<int>(deletedAt);
    return map;
  }

  ServerPinDeletionsCompanion toCompanion(bool nullToAbsent) {
    return ServerPinDeletionsCompanion(
      pinId: Value(pinId),
      deletedAt: Value(deletedAt),
    );
  }

  factory ServerPinDeletionEntity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerPinDeletionEntity(
      pinId: serializer.fromJson<String>(json['pinId']),
      deletedAt: serializer.fromJson<int>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pinId': serializer.toJson<String>(pinId),
      'deletedAt': serializer.toJson<int>(deletedAt),
    };
  }

  ServerPinDeletionEntity copyWith({String? pinId, int? deletedAt}) =>
      ServerPinDeletionEntity(
        pinId: pinId ?? this.pinId,
        deletedAt: deletedAt ?? this.deletedAt,
      );
  ServerPinDeletionEntity copyWithCompanion(ServerPinDeletionsCompanion data) {
    return ServerPinDeletionEntity(
      pinId: data.pinId.present ? data.pinId.value : this.pinId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServerPinDeletionEntity(')
          ..write('pinId: $pinId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pinId, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerPinDeletionEntity &&
          other.pinId == this.pinId &&
          other.deletedAt == this.deletedAt);
}

class ServerPinDeletionsCompanion
    extends UpdateCompanion<ServerPinDeletionEntity> {
  final Value<String> pinId;
  final Value<int> deletedAt;
  final Value<int> rowid;
  const ServerPinDeletionsCompanion({
    this.pinId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServerPinDeletionsCompanion.insert({
    required String pinId,
    required int deletedAt,
    this.rowid = const Value.absent(),
  }) : pinId = Value(pinId),
       deletedAt = Value(deletedAt);
  static Insertable<ServerPinDeletionEntity> custom({
    Expression<String>? pinId,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pinId != null) 'pin_id': pinId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServerPinDeletionsCompanion copyWith({
    Value<String>? pinId,
    Value<int>? deletedAt,
    Value<int>? rowid,
  }) {
    return ServerPinDeletionsCompanion(
      pinId: pinId ?? this.pinId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pinId.present) {
      map['pin_id'] = Variable<String>(pinId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServerPinDeletionsCompanion(')
          ..write('pinId: $pinId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PinsTable pins = $PinsTable(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $PinTombstonesTable pinTombstones = $PinTombstonesTable(this);
  late final $FetchedBboxesTable fetchedBboxes = $FetchedBboxesTable(this);
  late final $ServerPinDeletionsTable serverPinDeletions =
      $ServerPinDeletionsTable(this);
  late final PinDao pinDao = PinDao(this as AppDatabase);
  late final SyncQueueDao syncQueueDao = SyncQueueDao(this as AppDatabase);
  late final PinTombstoneDao pinTombstoneDao = PinTombstoneDao(
    this as AppDatabase,
  );
  late final FetchedBboxDao fetchedBboxDao = FetchedBboxDao(
    this as AppDatabase,
  );
  late final ServerPinDeletionDao serverPinDeletionDao = ServerPinDeletionDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pins,
    syncQueue,
    pinTombstones,
    fetchedBboxes,
    serverPinDeletions,
  ];
}

typedef $$PinsTableCreateCompanionBuilder =
    PinsCompanion Function({
      required String id,
      required String name,
      required double latitude,
      required double longitude,
      required int status,
      Value<String?> restrictionTag,
      Value<bool> hasSecurityScreening,
      Value<bool> hasPostedSignage,
      Value<String?> createdBy,
      required int createdAt,
      required int lastModified,
      Value<String?> photoUri,
      Value<String?> notes,
      Value<int> votes,
      Value<String> source,
      Value<String?> sourceExternalId,
      Value<String?> sourceDatasetVersion,
      Value<int?> importedAt,
      Value<bool> userModified,
      Value<String?> confidence,
      Value<String?> legalCitation,
      Value<String?> legalCitationVerifiedDate,
      Value<int?> sourceOrphanedAt,
      Value<int?> cachedAt,
      Value<int> rowid,
    });
typedef $$PinsTableUpdateCompanionBuilder =
    PinsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<double> latitude,
      Value<double> longitude,
      Value<int> status,
      Value<String?> restrictionTag,
      Value<bool> hasSecurityScreening,
      Value<bool> hasPostedSignage,
      Value<String?> createdBy,
      Value<int> createdAt,
      Value<int> lastModified,
      Value<String?> photoUri,
      Value<String?> notes,
      Value<int> votes,
      Value<String> source,
      Value<String?> sourceExternalId,
      Value<String?> sourceDatasetVersion,
      Value<int?> importedAt,
      Value<bool> userModified,
      Value<String?> confidence,
      Value<String?> legalCitation,
      Value<String?> legalCitationVerifiedDate,
      Value<int?> sourceOrphanedAt,
      Value<int?> cachedAt,
      Value<int> rowid,
    });

class $$PinsTableFilterComposer extends Composer<_$AppDatabase, $PinsTable> {
  $$PinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restrictionTag => $composableBuilder(
    column: $table.restrictionTag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasSecurityScreening => $composableBuilder(
    column: $table.hasSecurityScreening,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasPostedSignage => $composableBuilder(
    column: $table.hasPostedSignage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoUri => $composableBuilder(
    column: $table.photoUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get votes => $composableBuilder(
    column: $table.votes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceExternalId => $composableBuilder(
    column: $table.sourceExternalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDatasetVersion => $composableBuilder(
    column: $table.sourceDatasetVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get userModified => $composableBuilder(
    column: $table.userModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legalCitation => $composableBuilder(
    column: $table.legalCitation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legalCitationVerifiedDate => $composableBuilder(
    column: $table.legalCitationVerifiedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceOrphanedAt => $composableBuilder(
    column: $table.sourceOrphanedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PinsTableOrderingComposer extends Composer<_$AppDatabase, $PinsTable> {
  $$PinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restrictionTag => $composableBuilder(
    column: $table.restrictionTag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasSecurityScreening => $composableBuilder(
    column: $table.hasSecurityScreening,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasPostedSignage => $composableBuilder(
    column: $table.hasPostedSignage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoUri => $composableBuilder(
    column: $table.photoUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get votes => $composableBuilder(
    column: $table.votes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceExternalId => $composableBuilder(
    column: $table.sourceExternalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDatasetVersion => $composableBuilder(
    column: $table.sourceDatasetVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get userModified => $composableBuilder(
    column: $table.userModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legalCitation => $composableBuilder(
    column: $table.legalCitation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legalCitationVerifiedDate => $composableBuilder(
    column: $table.legalCitationVerifiedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceOrphanedAt => $composableBuilder(
    column: $table.sourceOrphanedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PinsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PinsTable> {
  $$PinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get restrictionTag => $composableBuilder(
    column: $table.restrictionTag,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasSecurityScreening => $composableBuilder(
    column: $table.hasSecurityScreening,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasPostedSignage => $composableBuilder(
    column: $table.hasPostedSignage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
    column: $table.lastModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoUri =>
      $composableBuilder(column: $table.photoUri, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get votes =>
      $composableBuilder(column: $table.votes, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get sourceExternalId => $composableBuilder(
    column: $table.sourceExternalId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceDatasetVersion => $composableBuilder(
    column: $table.sourceDatasetVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get userModified => $composableBuilder(
    column: $table.userModified,
    builder: (column) => column,
  );

  GeneratedColumn<String> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get legalCitation => $composableBuilder(
    column: $table.legalCitation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get legalCitationVerifiedDate => $composableBuilder(
    column: $table.legalCitationVerifiedDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceOrphanedAt => $composableBuilder(
    column: $table.sourceOrphanedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$PinsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PinsTable,
          PinEntity,
          $$PinsTableFilterComposer,
          $$PinsTableOrderingComposer,
          $$PinsTableAnnotationComposer,
          $$PinsTableCreateCompanionBuilder,
          $$PinsTableUpdateCompanionBuilder,
          (PinEntity, BaseReferences<_$AppDatabase, $PinsTable, PinEntity>),
          PinEntity,
          PrefetchHooks Function()
        > {
  $$PinsTableTableManager(_$AppDatabase db, $PinsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> restrictionTag = const Value.absent(),
                Value<bool> hasSecurityScreening = const Value.absent(),
                Value<bool> hasPostedSignage = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> lastModified = const Value.absent(),
                Value<String?> photoUri = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> votes = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceExternalId = const Value.absent(),
                Value<String?> sourceDatasetVersion = const Value.absent(),
                Value<int?> importedAt = const Value.absent(),
                Value<bool> userModified = const Value.absent(),
                Value<String?> confidence = const Value.absent(),
                Value<String?> legalCitation = const Value.absent(),
                Value<String?> legalCitationVerifiedDate = const Value.absent(),
                Value<int?> sourceOrphanedAt = const Value.absent(),
                Value<int?> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PinsCompanion(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                status: status,
                restrictionTag: restrictionTag,
                hasSecurityScreening: hasSecurityScreening,
                hasPostedSignage: hasPostedSignage,
                createdBy: createdBy,
                createdAt: createdAt,
                lastModified: lastModified,
                photoUri: photoUri,
                notes: notes,
                votes: votes,
                source: source,
                sourceExternalId: sourceExternalId,
                sourceDatasetVersion: sourceDatasetVersion,
                importedAt: importedAt,
                userModified: userModified,
                confidence: confidence,
                legalCitation: legalCitation,
                legalCitationVerifiedDate: legalCitationVerifiedDate,
                sourceOrphanedAt: sourceOrphanedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required double latitude,
                required double longitude,
                required int status,
                Value<String?> restrictionTag = const Value.absent(),
                Value<bool> hasSecurityScreening = const Value.absent(),
                Value<bool> hasPostedSignage = const Value.absent(),
                Value<String?> createdBy = const Value.absent(),
                required int createdAt,
                required int lastModified,
                Value<String?> photoUri = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> votes = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> sourceExternalId = const Value.absent(),
                Value<String?> sourceDatasetVersion = const Value.absent(),
                Value<int?> importedAt = const Value.absent(),
                Value<bool> userModified = const Value.absent(),
                Value<String?> confidence = const Value.absent(),
                Value<String?> legalCitation = const Value.absent(),
                Value<String?> legalCitationVerifiedDate = const Value.absent(),
                Value<int?> sourceOrphanedAt = const Value.absent(),
                Value<int?> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PinsCompanion.insert(
                id: id,
                name: name,
                latitude: latitude,
                longitude: longitude,
                status: status,
                restrictionTag: restrictionTag,
                hasSecurityScreening: hasSecurityScreening,
                hasPostedSignage: hasPostedSignage,
                createdBy: createdBy,
                createdAt: createdAt,
                lastModified: lastModified,
                photoUri: photoUri,
                notes: notes,
                votes: votes,
                source: source,
                sourceExternalId: sourceExternalId,
                sourceDatasetVersion: sourceDatasetVersion,
                importedAt: importedAt,
                userModified: userModified,
                confidence: confidence,
                legalCitation: legalCitation,
                legalCitationVerifiedDate: legalCitationVerifiedDate,
                sourceOrphanedAt: sourceOrphanedAt,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PinsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PinsTable,
      PinEntity,
      $$PinsTableFilterComposer,
      $$PinsTableOrderingComposer,
      $$PinsTableAnnotationComposer,
      $$PinsTableCreateCompanionBuilder,
      $$PinsTableUpdateCompanionBuilder,
      (PinEntity, BaseReferences<_$AppDatabase, $PinsTable, PinEntity>),
      PinEntity,
      PrefetchHooks Function()
    >;
typedef $$SyncQueueTableCreateCompanionBuilder =
    SyncQueueCompanion Function({
      required String id,
      required String pinId,
      required String operationType,
      required int timestamp,
      Value<int> retryCount,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$SyncQueueTableUpdateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<String> id,
      Value<String> pinId,
      Value<String> operationType,
      Value<int> timestamp,
      Value<int> retryCount,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$SyncQueueTableFilterComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pinId =>
      $composableBuilder(column: $table.pinId, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncQueueTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncQueueTable,
          SyncQueueEntity,
          $$SyncQueueTableFilterComposer,
          $$SyncQueueTableOrderingComposer,
          $$SyncQueueTableAnnotationComposer,
          $$SyncQueueTableCreateCompanionBuilder,
          $$SyncQueueTableUpdateCompanionBuilder,
          (
            SyncQueueEntity,
            BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueEntity>,
          ),
          SyncQueueEntity,
          PrefetchHooks Function()
        > {
  $$SyncQueueTableTableManager(_$AppDatabase db, $SyncQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pinId = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion(
                id: id,
                pinId: pinId,
                operationType: operationType,
                timestamp: timestamp,
                retryCount: retryCount,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pinId,
                required String operationType,
                required int timestamp,
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion.insert(
                id: id,
                pinId: pinId,
                operationType: operationType,
                timestamp: timestamp,
                retryCount: retryCount,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncQueueTable,
      SyncQueueEntity,
      $$SyncQueueTableFilterComposer,
      $$SyncQueueTableOrderingComposer,
      $$SyncQueueTableAnnotationComposer,
      $$SyncQueueTableCreateCompanionBuilder,
      $$SyncQueueTableUpdateCompanionBuilder,
      (
        SyncQueueEntity,
        BaseReferences<_$AppDatabase, $SyncQueueTable, SyncQueueEntity>,
      ),
      SyncQueueEntity,
      PrefetchHooks Function()
    >;
typedef $$PinTombstonesTableCreateCompanionBuilder =
    PinTombstonesCompanion Function({
      required String pinId,
      required int deletedAt,
      Value<int> rowid,
    });
typedef $$PinTombstonesTableUpdateCompanionBuilder =
    PinTombstonesCompanion Function({
      Value<String> pinId,
      Value<int> deletedAt,
      Value<int> rowid,
    });

class $$PinTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $PinTombstonesTable> {
  $$PinTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PinTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $PinTombstonesTable> {
  $$PinTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PinTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PinTombstonesTable> {
  $$PinTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pinId =>
      $composableBuilder(column: $table.pinId, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$PinTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PinTombstonesTable,
          PinTombstoneEntity,
          $$PinTombstonesTableFilterComposer,
          $$PinTombstonesTableOrderingComposer,
          $$PinTombstonesTableAnnotationComposer,
          $$PinTombstonesTableCreateCompanionBuilder,
          $$PinTombstonesTableUpdateCompanionBuilder,
          (
            PinTombstoneEntity,
            BaseReferences<
              _$AppDatabase,
              $PinTombstonesTable,
              PinTombstoneEntity
            >,
          ),
          PinTombstoneEntity,
          PrefetchHooks Function()
        > {
  $$PinTombstonesTableTableManager(_$AppDatabase db, $PinTombstonesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pinId = const Value.absent(),
                Value<int> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PinTombstonesCompanion(
                pinId: pinId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pinId,
                required int deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => PinTombstonesCompanion.insert(
                pinId: pinId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PinTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PinTombstonesTable,
      PinTombstoneEntity,
      $$PinTombstonesTableFilterComposer,
      $$PinTombstonesTableOrderingComposer,
      $$PinTombstonesTableAnnotationComposer,
      $$PinTombstonesTableCreateCompanionBuilder,
      $$PinTombstonesTableUpdateCompanionBuilder,
      (
        PinTombstoneEntity,
        BaseReferences<_$AppDatabase, $PinTombstonesTable, PinTombstoneEntity>,
      ),
      PinTombstoneEntity,
      PrefetchHooks Function()
    >;
typedef $$FetchedBboxesTableCreateCompanionBuilder =
    FetchedBboxesCompanion Function({
      Value<int> id,
      required double swLat,
      required double swLng,
      required double neLat,
      required double neLng,
      required int zoom,
      required int fetchedAt,
      required int pinCount,
    });
typedef $$FetchedBboxesTableUpdateCompanionBuilder =
    FetchedBboxesCompanion Function({
      Value<int> id,
      Value<double> swLat,
      Value<double> swLng,
      Value<double> neLat,
      Value<double> neLng,
      Value<int> zoom,
      Value<int> fetchedAt,
      Value<int> pinCount,
    });

class $$FetchedBboxesTableFilterComposer
    extends Composer<_$AppDatabase, $FetchedBboxesTable> {
  $$FetchedBboxesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get swLat => $composableBuilder(
    column: $table.swLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get swLng => $composableBuilder(
    column: $table.swLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get neLat => $composableBuilder(
    column: $table.neLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get neLng => $composableBuilder(
    column: $table.neLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pinCount => $composableBuilder(
    column: $table.pinCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FetchedBboxesTableOrderingComposer
    extends Composer<_$AppDatabase, $FetchedBboxesTable> {
  $$FetchedBboxesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get swLat => $composableBuilder(
    column: $table.swLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get swLng => $composableBuilder(
    column: $table.swLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get neLat => $composableBuilder(
    column: $table.neLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get neLng => $composableBuilder(
    column: $table.neLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pinCount => $composableBuilder(
    column: $table.pinCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FetchedBboxesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FetchedBboxesTable> {
  $$FetchedBboxesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get swLat =>
      $composableBuilder(column: $table.swLat, builder: (column) => column);

  GeneratedColumn<double> get swLng =>
      $composableBuilder(column: $table.swLng, builder: (column) => column);

  GeneratedColumn<double> get neLat =>
      $composableBuilder(column: $table.neLat, builder: (column) => column);

  GeneratedColumn<double> get neLng =>
      $composableBuilder(column: $table.neLng, builder: (column) => column);

  GeneratedColumn<int> get zoom =>
      $composableBuilder(column: $table.zoom, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get pinCount =>
      $composableBuilder(column: $table.pinCount, builder: (column) => column);
}

class $$FetchedBboxesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FetchedBboxesTable,
          FetchedBboxEntity,
          $$FetchedBboxesTableFilterComposer,
          $$FetchedBboxesTableOrderingComposer,
          $$FetchedBboxesTableAnnotationComposer,
          $$FetchedBboxesTableCreateCompanionBuilder,
          $$FetchedBboxesTableUpdateCompanionBuilder,
          (
            FetchedBboxEntity,
            BaseReferences<
              _$AppDatabase,
              $FetchedBboxesTable,
              FetchedBboxEntity
            >,
          ),
          FetchedBboxEntity,
          PrefetchHooks Function()
        > {
  $$FetchedBboxesTableTableManager(_$AppDatabase db, $FetchedBboxesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FetchedBboxesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FetchedBboxesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FetchedBboxesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> swLat = const Value.absent(),
                Value<double> swLng = const Value.absent(),
                Value<double> neLat = const Value.absent(),
                Value<double> neLng = const Value.absent(),
                Value<int> zoom = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> pinCount = const Value.absent(),
              }) => FetchedBboxesCompanion(
                id: id,
                swLat: swLat,
                swLng: swLng,
                neLat: neLat,
                neLng: neLng,
                zoom: zoom,
                fetchedAt: fetchedAt,
                pinCount: pinCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double swLat,
                required double swLng,
                required double neLat,
                required double neLng,
                required int zoom,
                required int fetchedAt,
                required int pinCount,
              }) => FetchedBboxesCompanion.insert(
                id: id,
                swLat: swLat,
                swLng: swLng,
                neLat: neLat,
                neLng: neLng,
                zoom: zoom,
                fetchedAt: fetchedAt,
                pinCount: pinCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FetchedBboxesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FetchedBboxesTable,
      FetchedBboxEntity,
      $$FetchedBboxesTableFilterComposer,
      $$FetchedBboxesTableOrderingComposer,
      $$FetchedBboxesTableAnnotationComposer,
      $$FetchedBboxesTableCreateCompanionBuilder,
      $$FetchedBboxesTableUpdateCompanionBuilder,
      (
        FetchedBboxEntity,
        BaseReferences<_$AppDatabase, $FetchedBboxesTable, FetchedBboxEntity>,
      ),
      FetchedBboxEntity,
      PrefetchHooks Function()
    >;
typedef $$ServerPinDeletionsTableCreateCompanionBuilder =
    ServerPinDeletionsCompanion Function({
      required String pinId,
      required int deletedAt,
      Value<int> rowid,
    });
typedef $$ServerPinDeletionsTableUpdateCompanionBuilder =
    ServerPinDeletionsCompanion Function({
      Value<String> pinId,
      Value<int> deletedAt,
      Value<int> rowid,
    });

class $$ServerPinDeletionsTableFilterComposer
    extends Composer<_$AppDatabase, $ServerPinDeletionsTable> {
  $$ServerPinDeletionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServerPinDeletionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ServerPinDeletionsTable> {
  $$ServerPinDeletionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pinId => $composableBuilder(
    column: $table.pinId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServerPinDeletionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServerPinDeletionsTable> {
  $$ServerPinDeletionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pinId =>
      $composableBuilder(column: $table.pinId, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$ServerPinDeletionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServerPinDeletionsTable,
          ServerPinDeletionEntity,
          $$ServerPinDeletionsTableFilterComposer,
          $$ServerPinDeletionsTableOrderingComposer,
          $$ServerPinDeletionsTableAnnotationComposer,
          $$ServerPinDeletionsTableCreateCompanionBuilder,
          $$ServerPinDeletionsTableUpdateCompanionBuilder,
          (
            ServerPinDeletionEntity,
            BaseReferences<
              _$AppDatabase,
              $ServerPinDeletionsTable,
              ServerPinDeletionEntity
            >,
          ),
          ServerPinDeletionEntity,
          PrefetchHooks Function()
        > {
  $$ServerPinDeletionsTableTableManager(
    _$AppDatabase db,
    $ServerPinDeletionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServerPinDeletionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServerPinDeletionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServerPinDeletionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> pinId = const Value.absent(),
                Value<int> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServerPinDeletionsCompanion(
                pinId: pinId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pinId,
                required int deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => ServerPinDeletionsCompanion.insert(
                pinId: pinId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ServerPinDeletionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServerPinDeletionsTable,
      ServerPinDeletionEntity,
      $$ServerPinDeletionsTableFilterComposer,
      $$ServerPinDeletionsTableOrderingComposer,
      $$ServerPinDeletionsTableAnnotationComposer,
      $$ServerPinDeletionsTableCreateCompanionBuilder,
      $$ServerPinDeletionsTableUpdateCompanionBuilder,
      (
        ServerPinDeletionEntity,
        BaseReferences<
          _$AppDatabase,
          $ServerPinDeletionsTable,
          ServerPinDeletionEntity
        >,
      ),
      ServerPinDeletionEntity,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PinsTableTableManager get pins => $$PinsTableTableManager(_db, _db.pins);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$PinTombstonesTableTableManager get pinTombstones =>
      $$PinTombstonesTableTableManager(_db, _db.pinTombstones);
  $$FetchedBboxesTableTableManager get fetchedBboxes =>
      $$FetchedBboxesTableTableManager(_db, _db.fetchedBboxes);
  $$ServerPinDeletionsTableTableManager get serverPinDeletions =>
      $$ServerPinDeletionsTableTableManager(_db, _db.serverPinDeletions);
}

mixin _$PinDaoMixin on DatabaseAccessor<AppDatabase> {
  $PinsTable get pins => attachedDatabase.pins;
  PinDaoManager get managers => PinDaoManager(this);
}

class PinDaoManager {
  final _$PinDaoMixin _db;
  PinDaoManager(this._db);
  $$PinsTableTableManager get pins =>
      $$PinsTableTableManager(_db.attachedDatabase, _db.pins);
}

mixin _$SyncQueueDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  SyncQueueDaoManager get managers => SyncQueueDaoManager(this);
}

class SyncQueueDaoManager {
  final _$SyncQueueDaoMixin _db;
  SyncQueueDaoManager(this._db);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}

mixin _$PinTombstoneDaoMixin on DatabaseAccessor<AppDatabase> {
  $PinTombstonesTable get pinTombstones => attachedDatabase.pinTombstones;
  PinTombstoneDaoManager get managers => PinTombstoneDaoManager(this);
}

class PinTombstoneDaoManager {
  final _$PinTombstoneDaoMixin _db;
  PinTombstoneDaoManager(this._db);
  $$PinTombstonesTableTableManager get pinTombstones =>
      $$PinTombstonesTableTableManager(_db.attachedDatabase, _db.pinTombstones);
}

mixin _$FetchedBboxDaoMixin on DatabaseAccessor<AppDatabase> {
  $FetchedBboxesTable get fetchedBboxes => attachedDatabase.fetchedBboxes;
  FetchedBboxDaoManager get managers => FetchedBboxDaoManager(this);
}

class FetchedBboxDaoManager {
  final _$FetchedBboxDaoMixin _db;
  FetchedBboxDaoManager(this._db);
  $$FetchedBboxesTableTableManager get fetchedBboxes =>
      $$FetchedBboxesTableTableManager(_db.attachedDatabase, _db.fetchedBboxes);
}

mixin _$ServerPinDeletionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ServerPinDeletionsTable get serverPinDeletions =>
      attachedDatabase.serverPinDeletions;
  ServerPinDeletionDaoManager get managers => ServerPinDeletionDaoManager(this);
}

class ServerPinDeletionDaoManager {
  final _$ServerPinDeletionDaoMixin _db;
  ServerPinDeletionDaoManager(this._db);
  $$ServerPinDeletionsTableTableManager get serverPinDeletions =>
      $$ServerPinDeletionsTableTableManager(
        _db.attachedDatabase,
        _db.serverPinDeletions,
      );
}
