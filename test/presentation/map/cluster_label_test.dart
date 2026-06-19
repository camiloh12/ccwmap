import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/presentation/map/cluster_label.dart';

void main() {
  group('abbreviateCount', () {
    test('leaves counts below 1000 as plain integers', () {
      expect(abbreviateCount(0), '0');
      expect(abbreviateCount(1), '1');
      expect(abbreviateCount(42), '42');
      expect(abbreviateCount(999), '999');
    });

    test('abbreviates thousands with a "k" suffix', () {
      expect(abbreviateCount(1000), '1k');
      expect(abbreviateCount(1500), '1.5k');
      expect(abbreviateCount(4500), '4.5k');
    });

    test('drops the trailing .0 on whole thousands', () {
      expect(abbreviateCount(12000), '12k');
      expect(abbreviateCount(23000), '23k');
      expect(abbreviateCount(999000), '999k');
    });

    test('abbreviates millions with an "M" suffix', () {
      expect(abbreviateCount(1000000), '1M');
      expect(abbreviateCount(1500000), '1.5M');
      expect(abbreviateCount(2300000), '2.3M');
    });
  });
}
