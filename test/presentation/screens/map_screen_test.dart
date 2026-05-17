import 'package:ccwmap/core/system_constants.dart';
import 'package:ccwmap/presentation/screens/map_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOtherUserPin', () {
    const someUser = 'a3b8c1d4-1111-4222-9333-444444444444';
    const otherUser = 'f7e6d5c4-2222-4333-9444-555555555555';

    test('returns false when pin has no creator', () {
      expect(
        isOtherUserPin(pinCreatorId: null, currentUserId: someUser),
        isFalse,
      );
    });

    test('returns false when current user is the creator', () {
      expect(
        isOtherUserPin(pinCreatorId: someUser, currentUserId: someUser),
        isFalse,
      );
    });

    test('returns false for pre-populated system pins', () {
      expect(
        isOtherUserPin(pinCreatorId: kSystemUserId, currentUserId: someUser),
        isFalse,
      );
    });

    test('returns true for another real user\'s pin', () {
      expect(
        isOtherUserPin(pinCreatorId: otherUser, currentUserId: someUser),
        isTrue,
      );
    });

    test('returns true even when current user is null (guest viewer)', () {
      expect(
        isOtherUserPin(pinCreatorId: otherUser, currentUserId: null),
        isTrue,
      );
    });
  });
}
