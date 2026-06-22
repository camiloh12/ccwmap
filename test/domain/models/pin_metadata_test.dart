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
