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
