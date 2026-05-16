import 'package:ccwmap/core/system_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kSystemUserId', () {
    test('is a valid lowercase v4 UUID', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(pattern.hasMatch(kSystemUserId), isTrue,
          reason: 'kSystemUserId must be a v4 UUID in canonical lowercase form');
    });

    test('is not the zero UUID', () {
      expect(kSystemUserId, isNot('00000000-0000-0000-0000-000000000000'));
    });
  });
}
