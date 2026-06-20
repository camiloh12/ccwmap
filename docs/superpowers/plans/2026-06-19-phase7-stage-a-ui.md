# Phase 7 Stage A — Pre-Import UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface existing pin provenance (`source`/`confidence`/`legal_citation`) up through the Dart domain layer and render a "verify locally" caveat on system pins plus ODbL attribution, shipping as the app release that precedes the production import.

**Architecture:** A vertical slice. Tasks 1–4 thread five provenance fields from the RPC/DB (which already carry them) up onto `PinMetadata` and through both mappers, fixing a latent bug where `PinMapper.toEntity` hardcoded `source: 'user'`. Tasks 5–7 render the caveat in `PinDialog` (logic isolated in a pure, unit-testable helper). Task 8 adds the ODbL/MapTiler About-Legal screen + a guest-reachable map attribution badge. No migration, no RPC change, no importer change.

**Tech Stack:** Flutter/Dart, Drift (local DB), Supabase RPC, `url_launcher` ^6.2.0, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-19-phase7-stage-a-ui-design.md`

---

## File structure

| File | Responsibility | Task |
|---|---|---|
| `lib/domain/models/pin_metadata.dart` | + 5 provenance fields | 1 |
| `lib/data/mappers/pin_mapper.dart` | carry provenance to/from local entity; drop hardcoded `'user'` | 2 |
| `lib/data/models/get_pins_in_view_row.dart` | parse provenance from RPC row | 3 |
| `lib/data/mappers/supabase_pin_mapper.dart` | carry provenance DTO↔domain | 4 |
| `lib/presentation/widgets/pin_provenance.dart` (new) | pure caveat/label/URL logic | 5 |
| `lib/presentation/widgets/pin_dialog.dart` | provenance params + banner widget | 6 |
| `lib/presentation/screens/map_screen.dart` | pass `pin.metadata.*` into the two dialog call sites; add attribution badge | 7, 8 |
| `lib/presentation/screens/about_legal_screen.dart` (new) | ODbL + MapTiler + dump URL screen | 8 |
| `lib/presentation/screens/settings_screen.dart` | link to About-Legal | 8 |

Baseline: 233 Flutter tests green (per CLAUDE.md). Each task adds tests and keeps the suite green.

---

## Task 1: Add provenance fields to `PinMetadata`

**Files:**
- Modify: `lib/domain/models/pin_metadata.dart`
- Test: `test/domain/models/pin_metadata_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/domain/models/pin_metadata_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_metadata.dart';

void main() {
  final base = PinMetadata(
    createdBy: 'u1',
    createdAt: DateTime.utc(2026, 1, 1),
    lastModified: DateTime.utc(2026, 1, 2),
  );

  test('defaults to a user pin with no provenance', () {
    expect(base.source, 'user');
    expect(base.sourceExternalId, isNull);
    expect(base.confidence, isNull);
    expect(base.legalCitation, isNull);
    expect(base.legalCitationVerifiedDate, isNull);
  });

  test('carries provenance when set', () {
    final m = base.copyWith(
      source: 'osm',
      sourceExternalId: 'node/123',
      confidence: 'medium',
      legalCitation: 'TX Penal Code 46.03',
      legalCitationVerifiedDate: '2026-05-31',
    );
    expect(m.source, 'osm');
    expect(m.confidence, 'medium');
    expect(m.legalCitation, 'TX Penal Code 46.03');
    expect(m.sourceExternalId, 'node/123');
    expect(m.legalCitationVerifiedDate, '2026-05-31');
  });

  test('JSON round-trip preserves provenance', () {
    final m = base.copyWith(source: 'nces', confidence: 'high');
    final back = PinMetadata.fromJson(m.toJson());
    expect(back.source, 'nces');
    expect(back.confidence, 'high');
  });

  test('equality distinguishes provenance', () {
    expect(base.copyWith(source: 'osm'), isNot(equals(base)));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/domain/models/pin_metadata_test.dart`
Expected: FAIL (no `source` getter / `copyWith` has no `source` param)

- [ ] **Step 3: Add the fields**

In `lib/domain/models/pin_metadata.dart`, replace the class body's field/constructor/copyWith/toJson/fromJson/==/hashCode to add the five fields. The full updated file:

```dart
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
```

- [ ] **Step 4: Run the test + full suite**

Run: `flutter test test/domain/models/pin_metadata_test.dart`
Expected: PASS. Then `flutter test test/domain/` → PASS (existing `pin_test.dart` still green — the new fields are all defaulted, so existing `PinMetadata(...)` calls compile unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/domain/models/pin_metadata.dart test/domain/models/pin_metadata_test.dart
git commit -m "feat(domain): add provenance fields to PinMetadata"
```

---

## Task 2: Carry provenance through `PinMapper` (+ fix hardcoded source)

**Files:**
- Modify: `lib/data/mappers/pin_mapper.dart`
- Test: `test/data/mappers/pin_mapper_test.dart` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `test/data/mappers/pin_mapper_test.dart` (inside the top-level `main()`'s group, or add a new group — match the file's existing structure):

```dart
  group('PinMapper provenance', () {
    Pin systemPin() => Pin(
          id: 'p1',
          name: 'Lincoln Elementary',
          location: Location.fromLatLng(30.1, -97.7),
          status: PinStatus.NO_GUN,
          restrictionTag: RestrictionTag.SCHOOL_K12,
          metadata: PinMetadata(
            createdBy: 'sys',
            createdAt: DateTime.utc(2026, 1, 1),
            lastModified: DateTime.utc(2026, 1, 1),
            source: 'nces',
            sourceExternalId: '480000100001',
            confidence: 'high',
            legalCitation: 'TX Penal Code 46.03(a)(1)',
            legalCitationVerifiedDate: '2026-05-31',
          ),
        );

    test('toEntity preserves source instead of hardcoding user', () {
      final e = PinMapper.toEntity(systemPin());
      expect(e.source, 'nces');
      expect(e.confidence, 'high');
      expect(e.legalCitation, 'TX Penal Code 46.03(a)(1)');
      expect(e.sourceExternalId, '480000100001');
      expect(e.legalCitationVerifiedDate, '2026-05-31');
    });

    test('toCachedEntity preserves provenance and sets cachedAt', () {
      final now = DateTime.utc(2026, 6, 1);
      final e = PinMapper.toCachedEntity(systemPin(), cachedAt: now);
      expect(e.source, 'nces');
      expect(e.cachedAt, now.millisecondsSinceEpoch);
    });

    test('round-trips provenance through fromEntity', () {
      final back = PinMapper.fromEntity(PinMapper.toEntity(systemPin()));
      expect(back.metadata.source, 'nces');
      expect(back.metadata.confidence, 'high');
      expect(back.metadata.legalCitation, 'TX Penal Code 46.03(a)(1)');
      expect(back.metadata.sourceExternalId, '480000100001');
    });
  });
```

If the imports for `Pin`, `Location`, `PinStatus`, `RestrictionTag`, `PinMetadata` are not already at the top of the file, add them.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/mappers/pin_mapper_test.dart`
Expected: FAIL (`expect(e.source, 'nces')` gets `'user'`)

- [ ] **Step 3: Update the mapper**

In `lib/data/mappers/pin_mapper.dart`, replace `toEntity` and `fromEntity` and the `toCachedEntity` doc comment:

```dart
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
```

Then update the `toCachedEntity` doc comment — replace the sentence "`source` is left at the default `'user'` — Phase 1 callers should overwrite from the RPC row before insert when provenance is known." with: "Provenance (`source`, `confidence`, …) is carried from `pin.metadata` by `toEntity`, so cached system pins retain their origin."

- [ ] **Step 4: Run the tests + suite**

Run: `flutter test test/data/mappers/pin_mapper_test.dart`
Expected: PASS. Then `flutter test test/data/` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/mappers/pin_mapper.dart test/data/mappers/pin_mapper_test.dart
git commit -m "fix(data): carry pin provenance through PinMapper (was hardcoding source=user)"
```

---

## Task 3: Parse provenance from the RPC row

**Files:**
- Modify: `lib/data/models/get_pins_in_view_row.dart`
- Test: `test/data/models/get_pins_in_view_row_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

Append a test to `test/data/models/get_pins_in_view_row_test.dart`:

```dart
  test('parses provenance columns for a system pin row', () {
    final item = GetPinsInViewRow.parse({
      'kind': 'pin',
      'pin_id': 'p1',
      'name': 'Federal Courthouse',
      'latitude': 30.0,
      'longitude': -97.0,
      'status': 2,
      'restriction_tag': 'STATE_LOCAL_GOVT',
      'has_security_screening': true,
      'has_posted_signage': false,
      'created_by': '81775f8b-1a6a-47d6-b793-e9ab7e38634e',
      'created_at': '2026-05-31T00:00:00Z',
      'last_modified': '2026-05-31T00:00:00Z',
      'source': 'hifld_courts',
      'source_external_id': 'GLOBALID-123',
      'confidence': 'high',
      'legal_citation': 'TX Penal Code 46.03(a)(3)',
      'legal_citation_verified_date': '2026-05-31',
    });
    expect(item, isA<MapItemPin>());
    final pin = (item as MapItemPin).pin;
    expect(pin.metadata.source, 'hifld_courts');
    expect(pin.metadata.confidence, 'high');
    expect(pin.metadata.legalCitation, 'TX Penal Code 46.03(a)(3)');
    expect(pin.metadata.sourceExternalId, 'GLOBALID-123');
    expect(pin.metadata.legalCitationVerifiedDate, '2026-05-31');
  });
```

Ensure `MapItemPin` is imported in the test (from `package:ccwmap/domain/models/map_item.dart`).

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/models/get_pins_in_view_row_test.dart`
Expected: FAIL (`pin.metadata.source` is `'user'` — `_parsePin` doesn't read the columns)

- [ ] **Step 3: Populate provenance in `_parsePin`**

In `lib/data/models/get_pins_in_view_row.dart`, replace the `metadata:` block inside `_parsePin`:

```dart
      metadata: PinMetadata(
        createdBy: j['created_by'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        lastModified: DateTime.parse(j['last_modified'] as String),
        source: (j['source'] as String?) ?? 'user',
        sourceExternalId: j['source_external_id'] as String?,
        confidence: j['confidence'] as String?,
        legalCitation: j['legal_citation'] as String?,
        legalCitationVerifiedDate: j['legal_citation_verified_date'] as String?,
      ),
```

- [ ] **Step 4: Run the test + suite**

Run: `flutter test test/data/models/get_pins_in_view_row_test.dart`
Expected: PASS. Then `flutter test test/data/` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/get_pins_in_view_row.dart test/data/models/get_pins_in_view_row_test.dart
git commit -m "feat(data): parse pin provenance from get_pins_in_view rows"
```

---

## Task 4: Carry provenance through `SupabasePinMapper`

**Files:**
- Modify: `lib/data/mappers/supabase_pin_mapper.dart`
- Test: `test/data/mappers/supabase_pin_mapper_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

Append to `test/data/mappers/supabase_pin_mapper_test.dart`:

```dart
  test('round-trips provenance DTO <-> domain', () {
    final dto = SupabasePinDto(
      id: 'p1',
      name: 'Bar None',
      latitude: 30.0,
      longitude: -97.0,
      status: 1,
      hasSecurityScreening: false,
      hasPostedSignage: false,
      createdAt: '2026-05-31T00:00:00Z',
      lastModified: '2026-05-31T00:00:00Z',
      votes: 0,
      source: 'osm',
      sourceExternalId: 'node/123',
      confidence: 'medium',
      legalCitation: 'TX Penal Code 46.03(a)(7)',
      legalCitationVerifiedDate: '2026-05-31',
    );
    final pin = SupabasePinMapper.fromDto(dto);
    expect(pin.metadata.source, 'osm');
    expect(pin.metadata.confidence, 'medium');

    final back = SupabasePinMapper.toDto(pin);
    expect(back.source, 'osm');
    expect(back.confidence, 'medium');
    expect(back.legalCitation, 'TX Penal Code 46.03(a)(7)');
    expect(back.sourceExternalId, 'node/123');
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/data/mappers/supabase_pin_mapper_test.dart`
Expected: FAIL (`pin.metadata.source` is `'user'`)

- [ ] **Step 3: Update the mapper**

In `lib/data/mappers/supabase_pin_mapper.dart`, add the provenance fields to both directions. In `toDto`, add after `votes: pin.metadata.votes,`:

```dart
      source: pin.metadata.source,
      sourceExternalId: pin.metadata.sourceExternalId,
      confidence: pin.metadata.confidence,
      legalCitation: pin.metadata.legalCitation,
      legalCitationVerifiedDate: pin.metadata.legalCitationVerifiedDate,
```

In `fromDto`, add to the `PinMetadata(...)` after `votes: dto.votes,`:

```dart
        source: dto.source,
        sourceExternalId: dto.sourceExternalId,
        confidence: dto.confidence,
        legalCitation: dto.legalCitation,
        legalCitationVerifiedDate: dto.legalCitationVerifiedDate,
```

- [ ] **Step 4: Run the test + suite**

Run: `flutter test test/data/mappers/supabase_pin_mapper_test.dart`
Expected: PASS. Then `flutter test test/data/` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/mappers/supabase_pin_mapper.dart test/data/mappers/supabase_pin_mapper_test.dart
git commit -m "feat(data): carry pin provenance through SupabasePinMapper"
```

---

## Task 5: Pure provenance-caveat helper

**Files:**
- Create: `lib/presentation/widgets/pin_provenance.dart`
- Test: `test/presentation/widgets/pin_provenance_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/presentation/widgets/pin_provenance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/widgets/pin_provenance.dart';

void main() {
  test('user pins get no caveat', () {
    expect(caveatFor(source: 'user'), isNull);
  });

  test('high-confidence system pin gets origin-phrased caveat', () {
    final c = caveatFor(
      source: 'nces',
      confidence: 'high',
      legalCitation: 'TX Penal Code 46.03',
      legalCitationVerifiedDate: '2026-05-31',
    )!;
    expect(c.elevated, isFalse);
    expect(c.body, contains('TX Penal Code 46.03'));
    expect(c.body.toLowerCase(), contains('verify locally'));
    // Phrased around origin, never a status word like "NO_GUN".
    expect(c.body, isNot(contains('NO_GUN')));
  });

  test('medium confidence is elevated and hedged harder', () {
    final c = caveatFor(
      source: 'osm',
      confidence: 'medium',
      legalCitation: 'TX Penal Code 46.03(a)(7)',
    )!;
    expect(c.elevated, isTrue);
    expect(c.body.toLowerCase(), contains('uncertain'));
  });

  test('sourceLabel maps known codes', () {
    expect(sourceLabel('osm'), contains('OpenStreetMap'));
    expect(sourceLabel('gsa'), contains('GSA'));
    expect(sourceLabel('zzz'), 'public records');
  });

  test('osmObjectUrl only for valid osm ids', () {
    expect(osmObjectUrl(source: 'osm', sourceExternalId: 'node/123'),
        'https://www.openstreetmap.org/node/123');
    expect(osmObjectUrl(source: 'nces', sourceExternalId: 'node/123'), isNull);
    expect(osmObjectUrl(source: 'osm', sourceExternalId: 'garbage'), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/presentation/widgets/pin_provenance_test.dart`
Expected: FAIL (file/functions don't exist)

- [ ] **Step 3: Create the helper**

Create `lib/presentation/widgets/pin_provenance.dart`:

```dart
/// Pure presentation logic for the system-pin provenance caveat. No Flutter
/// imports so it is unit-testable without pumping a widget.

class ProvenanceCaveat {
  /// Short bold line, e.g. "Uncertain — verify locally".
  final String headline;

  /// The explanation, phrased around the pin's ORIGIN (not its current
  /// status) so it stays coherent even after a community member edits it.
  final String body;

  /// Medium/UNCERTAIN pins get stronger visual treatment.
  final bool elevated;

  const ProvenanceCaveat({
    required this.headline,
    required this.body,
    required this.elevated,
  });
}

/// Friendly label for an importer source code.
String sourceLabel(String source) {
  switch (source) {
    case 'nces':
      return 'public school records (NCES)';
    case 'ipeds':
      return 'college records (IPEDS)';
    case 'gsa':
      return 'federal property records (GSA)';
    case 'hifld_courts':
      return 'courthouse records (HIFLD)';
    case 'hifld_military':
      return 'military site records (HIFLD/USACE)';
    case 'faa':
      return 'FAA airport records';
    case 'osm':
      return 'OpenStreetMap';
    default:
      return 'public records';
  }
}

/// Returns the caveat for a system pin, or null for user-created pins.
ProvenanceCaveat? caveatFor({
  required String source,
  String? confidence,
  String? legalCitation,
  String? legalCitationVerifiedDate,
}) {
  if (source == 'user') return null;

  final citation =
      (legalCitation == null || legalCitation.isEmpty) ? null : legalCitation;
  final verified =
      (legalCitationVerifiedDate == null || legalCitationVerifiedDate.isEmpty)
          ? null
          : legalCitationVerifiedDate;
  final cite = citation == null ? '' : ' under $citation';
  final asOf = verified == null ? '' : ' (verified $verified)';

  if (confidence == 'medium') {
    return ProvenanceCaveat(
      headline: 'Uncertain — verify locally',
      body: 'This venue may restrict carry$cite, but we could not confirm it '
          'meets the legal threshold. Treat as uncertain and verify locally.',
      elevated: true,
    );
  }

  return ProvenanceCaveat(
    headline: 'Auto-classified — verify locally',
    body: 'This location was auto-classified from ${sourceLabel(source)}$cite'
        '$asOf. Laws and posted signage change — verify locally before relying '
        'on this.',
    elevated: false,
  );
}

/// OSM object URL for an osm-sourced pin, or null otherwise.
String? osmObjectUrl({required String source, String? sourceExternalId}) {
  if (source != 'osm') return null;
  final id = sourceExternalId;
  if (id == null || !RegExp(r'^(node|way|relation)/\d+$').hasMatch(id)) {
    return null;
  }
  return 'https://www.openstreetmap.org/$id';
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/presentation/widgets/pin_provenance_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/widgets/pin_provenance.dart test/presentation/widgets/pin_provenance_test.dart
git commit -m "feat(ui): pure provenance-caveat helper (copy, labels, OSM url)"
```

---

## Task 6: Render the caveat block in `PinDialog`

**Files:**
- Modify: `lib/presentation/widgets/pin_dialog.dart`
- Test: `test/presentation/widgets/pin_dialog_provenance_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/presentation/widgets/pin_dialog_provenance_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/presentation/widgets/pin_dialog.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String source,
    String? confidence,
    String? legalCitation,
    String? sourceExternalId,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinDialog(
            isEditMode: true,
            poiName: 'Some Place',
            initialStatus: PinStatus.NO_GUN,
            initialRestrictionTag: RestrictionTag.SCHOOL_K12,
            onConfirm: (_) {},
            onCancel: () {},
            source: source,
            confidence: confidence,
            legalCitation: legalCitation,
            sourceExternalId: sourceExternalId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows caveat for a system pin with its citation', (tester) async {
    await pump(tester,
        source: 'nces',
        confidence: 'high',
        legalCitation: 'TX Penal Code 46.03');
    expect(find.textContaining('verify locally'), findsOneWidget);
    expect(find.textContaining('TX Penal Code 46.03'), findsOneWidget);
  });

  testWidgets('no caveat for a user pin', (tester) async {
    await pump(tester, source: 'user');
    expect(find.textContaining('verify locally'), findsNothing);
  });

  testWidgets('shows OSM/ODbL credit for osm pins', (tester) async {
    await pump(tester,
        source: 'osm', confidence: 'medium', sourceExternalId: 'node/123');
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/presentation/widgets/pin_dialog_provenance_test.dart`
Expected: FAIL (`PinDialog` has no `source`/`confidence`/… params)

- [ ] **Step 3: Add the params**

In `lib/presentation/widgets/pin_dialog.dart`, add to the `PinDialog` widget's fields (after `onBlock`):

```dart
  /// Provenance — non-null only for pins read from the server/cache. When
  /// [source] is not 'user', a verify-locally caveat block renders.
  final String? source;
  final String? confidence;
  final String? legalCitation;
  final String? legalCitationVerifiedDate;
  final String? sourceExternalId;
```

Add them to the constructor parameter list (all optional):

```dart
    this.source,
    this.confidence,
    this.legalCitation,
    this.legalCitationVerifiedDate,
    this.sourceExternalId,
```

- [ ] **Step 4: Add the imports + banner builder**

At the top of the file, add:

```dart
import 'package:url_launcher/url_launcher.dart';
import 'pin_provenance.dart';
```

In `_PinDialogState`, add a builder method (place near `_buildCheckbox`):

```dart
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget? _buildProvenanceBanner() {
    final source = widget.source;
    if (source == null) return null;
    final caveat = caveatFor(
      source: source,
      confidence: widget.confidence,
      legalCitation: widget.legalCitation,
      legalCitationVerifiedDate: widget.legalCitationVerifiedDate,
    );
    if (caveat == null) return null;

    final bg = caveat.elevated ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5);
    final border = caveat.elevated ? const Color(0xFFFFB74D) : const Color(0xFFBDBDBD);
    final osmUrl = osmObjectUrl(source: source, sourceExternalId: widget.sourceExternalId);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                caveat.elevated ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 18,
                color: Colors.black87,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  caveat.headline,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(caveat.body, style: const TextStyle(fontSize: 13)),
          if (osmUrl != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _openUrl(osmUrl),
              child: const Text(
                '© OpenStreetMap contributors (ODbL)',
                style: TextStyle(
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
```

- [ ] **Step 5: Insert the banner into the build tree**

In `build`, immediately after the title block's `const SizedBox(height: 24),` (the one right after the `'Edit Pin'/'Create Pin'` Text) and before the `// Name Text Field` comment, insert:

```dart
              if (_buildProvenanceBanner() case final banner?) banner,
```

- [ ] **Step 6: Run the tests + widget suite**

Run: `flutter test test/presentation/widgets/pin_dialog_provenance_test.dart`
Expected: PASS. Then `flutter test test/presentation/widgets/` → PASS (existing pin_dialog tests pass none of the new params, so the banner is absent there — unchanged behavior).

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/widgets/pin_dialog.dart test/presentation/widgets/pin_dialog_provenance_test.dart
git commit -m "feat(ui): render verify-locally + ODbL caveat in PinDialog"
```

---

## Task 7: Pass provenance from MapScreen into the dialogs

**Files:**
- Modify: `lib/presentation/screens/map_screen.dart`

Both dialog entry points already hold a full domain `Pin`: `_showReadOnlyPinDialog(Pin pin)` receives one, and `_showPinDialog` fetches `existing = await _viewModel?.getPinById(pinId)` for the creator id (line ~1269). After Tasks 1–3 those carry provenance — just forward it.

- [ ] **Step 1: Forward provenance in `_showPinDialog`**

In `lib/presentation/screens/map_screen.dart`, in `_showPinDialog`, the edit branch already computes `final existing = await _viewModel?.getPinById(pinId);` (reused for `pinCreatorId`). In the `PinDialog(...)` constructor call (the `builder:` at ~line 1284), add these arguments (after `initialHasPostedSignage:`):

```dart
        source: existing?.metadata.source,
        confidence: existing?.metadata.confidence,
        legalCitation: existing?.metadata.legalCitation,
        legalCitationVerifiedDate: existing?.metadata.legalCitationVerifiedDate,
        sourceExternalId: existing?.metadata.sourceExternalId,
```

Note: `existing` is currently declared inside `if (isEditMode && pinId != null)`. Hoist it so it is in scope at the `PinDialog` call: change that block to declare `Pin? existing;` at method top and assign `existing = await _viewModel?.getPinById(pinId);` inside the `if`. Replace the later `pinCreatorId = existing?.metadata.createdBy;` to use the hoisted variable. For create mode `existing` stays null → no banner (correct).

- [ ] **Step 2: Forward provenance in `_showReadOnlyPinDialog`**

In `_showReadOnlyPinDialog(Pin pin)` (~line 1583), find its `PinDialog(...)` construction and add:

```dart
        source: pin.metadata.source,
        confidence: pin.metadata.confidence,
        legalCitation: pin.metadata.legalCitation,
        legalCitationVerifiedDate: pin.metadata.legalCitationVerifiedDate,
        sourceExternalId: pin.metadata.sourceExternalId,
```

- [ ] **Step 3: Analyze + run the map_screen test**

Run: `flutter analyze lib/presentation/screens/map_screen.dart`
Expected: No errors.
Run: `flutter test test/presentation/screens/map_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/map_screen.dart
git commit -m "feat(ui): pass pin provenance into create/edit and read-only dialogs"
```

---

## Task 8: About-Legal screen + guest-reachable map badge + Settings link

**Files:**
- Create: `lib/presentation/screens/about_legal_screen.dart`
- Modify: `lib/presentation/screens/map_screen.dart` (attribution badge)
- Modify: `lib/presentation/screens/settings_screen.dart` (link)
- Test: `test/presentation/screens/about_legal_screen_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `test/presentation/screens/about_legal_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/screens/about_legal_screen.dart';

void main() {
  testWidgets('shows OSM, ODbL, and MapTiler attribution', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutLegalScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
    expect(find.textContaining('ODbL'), findsWidgets);
    expect(find.textContaining('MapTiler'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/presentation/screens/about_legal_screen_test.dart`
Expected: FAIL (file doesn't exist)

- [ ] **Step 3: Create the screen**

Create `lib/presentation/screens/about_legal_screen.dart`. The ODbL share-alike obligation is met by the dump being publicly hosted in the `odbl-dumps` bucket; the screen *credits* it in text. We avoid a tappable "download" link because the dump filename is date-stamped (`dump-YYYY-MM-DD.csv.gz`, no stable "latest" alias) and the prod bucket isn't created until Stage B's first prod OSM apply — a hardcoded direct link would 404. The actionable links (OSM copyright, MapTiler) work today.

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Attribution + legal credits. Reachable by everyone (including guests) via
/// the map attribution badge, and from Settings for signed-in users.
class AboutLegalScreen extends StatelessWidget {
  const AboutLegalScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & Legal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Map data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'Some pins are derived from OpenStreetMap and are made available '
              'under the Open Database License (ODbL). © OpenStreetMap '
              'contributors. Our OSM-derived data is republished under ODbL as '
              'a public data dump after each import.',
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _open('https://www.openstreetmap.org/copyright'),
              child: const Text('OpenStreetMap copyright & ODbL'),
            ),
            const Divider(height: 32),
            const Text('Basemap', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Basemap tiles © MapTiler © OpenStreetMap contributors.'),
            TextButton(
              onPressed: () => _open('https://www.maptiler.com/copyright/'),
              child: const Text('MapTiler attribution'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the screen test**

Run: `flutter test test/presentation/screens/about_legal_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Add the guest-reachable map badge**

In `lib/presentation/screens/map_screen.dart`, add a new `Positioned` to the map `Stack` children (alongside the other `Positioned` widgets, e.g. right after the top-right sign-in/settings `Positioned` block ~line 2215). Add the import `import 'about_legal_screen.dart';` near the other screen imports.

```dart
              // Always-visible attribution badge (guests have no menu). Tapping
              // opens the full ODbL/MapTiler credits.
              Positioned(
                bottom: 4,
                left: 8,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutLegalScreen(),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '© OSM · MapTiler',
                      style: TextStyle(fontSize: 10, color: Colors.black87),
                    ),
                  ),
                ),
              ),
```

- [ ] **Step 6: Add the Settings link**

In `lib/presentation/screens/settings_screen.dart`, add the import `import 'about_legal_screen.dart';`, and in the `build` Column children, add before the `Sign Out` `OutlinedButton` (after the email `SizedBox(height: 32)`):

```dart
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutLegalScreen(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('About & Legal'),
              ),
              const SizedBox(height: 16),
```

- [ ] **Step 7: Analyze + run affected suites**

Run: `flutter analyze lib/presentation/screens/`
Expected: No errors.
Run: `flutter test test/presentation/screens/`
Expected: PASS (existing `settings_screen_test.dart` and `map_screen_test.dart` still green).

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/screens/about_legal_screen.dart lib/presentation/screens/map_screen.dart lib/presentation/screens/settings_screen.dart test/presentation/screens/about_legal_screen_test.dart
git commit -m "feat(ui): ODbL/MapTiler About-Legal screen + guest map attribution badge"
```

---

## Task 9: Full suite + version bump

**Files:**
- Modify: `pubspec.yaml` (version)

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: all pass (233 baseline + the new provenance/caveat/about-legal tests).

- [ ] **Step 2: Run analyze + format**

Run: `flutter analyze` then `dart format --set-exit-if-changed lib test`
Expected: no issues; no files reformatted (fix any reported).

- [ ] **Step 3: Bump the version**

In `pubspec.yaml`, bump `version:` to `0.7.0+<next build number>` (increment the `+N` build code from the current value). This is the pre-import release per the spec §6.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 0.7.0 (pre-import UI release)"
```

---

## Self-review notes

- **Spec coverage:** §1 plumbing → Tasks 1–4; §2 caveat (origin-phrased, escalating) → Tasks 5–7; §3a per-pin OSM credit → Task 6; §3b global About-Legal + guest badge + Settings link → Task 8; §4 (caveat persists on edit, keyed on `source`, no `user_modified` on client) → satisfied by Tasks 5–7 keying on `source` only; §5 testing → tests in every task; §6 version → Task 9.
- **No `user_modified` is threaded** anywhere — consistent with the spec's deferral and "no migration/RPC change."
- **Type consistency:** field names `source`/`sourceExternalId`/`confidence`/`legalCitation`/`legalCitationVerifiedDate` are identical across `PinMetadata`, both mappers, `GetPinsInViewRow`, `PinDialog` params, and the helper. The RPC/DB JSON keys use snake_case (`source_external_id`, `legal_citation_verified_date`) only inside `GetPinsInViewRow._parsePin` (Task 3) and the Drift entity (already snake_case-mapped); domain/DTO use camelCase.
- **Pin business rule:** the caveat never constructs a `Pin`; `PinDialog` takes loose params, so the NO_GUN-requires-tag invariant is untouched.
- **Web caveat:** the two dialog call sites both resolve a domain `Pin` (read-only path receives one; edit path fetches via `getPinById`), so the caveat works on native (production) and the read-only/guest path; the web feature-tap edit path inherits it because it also routes through `_showPinDialog`/`getPinById`.
