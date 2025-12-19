import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/domain/models/pin_status.dart';

void main() {
  group('PinStatus', () {
    test('colorCode returns correct values', () {
      expect(PinStatus.ALLOWED.colorCode, 0);
      expect(PinStatus.UNCERTAIN.colorCode, 1);
      expect(PinStatus.NO_GUN.colorCode, 2);
    });

    test('displayName returns correct values', () {
      expect(PinStatus.ALLOWED.displayName, 'Allowed');
      expect(PinStatus.UNCERTAIN.displayName, 'Uncertain');
      expect(PinStatus.NO_GUN.displayName, 'No Guns');
    });

    test('next() cycles through statuses correctly', () {
      expect(PinStatus.ALLOWED.next(), PinStatus.UNCERTAIN);
      expect(PinStatus.UNCERTAIN.next(), PinStatus.NO_GUN);
      expect(PinStatus.NO_GUN.next(), PinStatus.ALLOWED);
    });

    test('fromColorCode converts correctly', () {
      expect(PinStatus.fromColorCode(0), PinStatus.ALLOWED);
      expect(PinStatus.fromColorCode(1), PinStatus.UNCERTAIN);
      expect(PinStatus.fromColorCode(2), PinStatus.NO_GUN);
    });

    test('fromColorCode throws on invalid code', () {
      expect(
        () => PinStatus.fromColorCode(3),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PinStatus.fromColorCode(-1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
