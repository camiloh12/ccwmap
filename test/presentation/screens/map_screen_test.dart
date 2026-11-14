import 'package:ccwmap/core/system_constants.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
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

  group('canDeletePin', () {
    test('returns false for a pre-populated system pin', () {
      expect(canDeletePin(pinCreatorId: kSystemUserId), isFalse);
    });

    test('returns true for a user-created pin', () {
      expect(
        canDeletePin(pinCreatorId: 'f7e6d5c4-2222-4333-9444-555555555555'),
        isTrue,
      );
    });

    test('returns true when the creator is unknown', () {
      expect(canDeletePin(pinCreatorId: null), isTrue);
    });
  });

  group('canReportPin', () {
    const me = 'a3b8c1d4-1111-4222-9333-444444444444';
    const other = 'f7e6d5c4-2222-4333-9444-555555555555';
    bool call({bool edit = true, String? user = me, String? creator = other}) =>
        canReportPin(
          isEditMode: edit,
          currentUserId: user,
          pinCreatorId: creator,
        );

    test('true for a signed-in user on a system pin', () {
      expect(call(creator: kSystemUserId), isTrue);
    });
    test('true on another user pin', () => expect(call(), isTrue));
    test('false on own pins', () => expect(call(creator: me), isFalse));
    test('false for guests', () => expect(call(user: null), isFalse));
    test('false in create mode', () => expect(call(edit: false), isFalse));
  });

  group('reportOutcomeFor', () {
    test('maps null and each exception', () {
      expect(reportOutcomeFor(null), ReportOutcome.filed);
      expect(
        reportOutcomeFor(const ReportAlreadyFiledException()),
        ReportOutcome.alreadyFiled,
      );
      expect(
        reportOutcomeFor(const ReportLimitReachedException()),
        ReportOutcome.limitReached,
      );
      expect(
        reportOutcomeFor(const ReportedPinGoneException()),
        ReportOutcome.pinGone,
      );
      expect(reportOutcomeFor(Exception('x')), ReportOutcome.failed);
    });

    test('duplicate report marks the pin reported', () {
      expect(
        reportOutcomeFor(const ReportAlreadyFiledException()),
        ReportOutcome.alreadyFiled,
      );
      expect(shouldMarkReported(ReportOutcome.filed), isTrue);
      expect(shouldMarkReported(ReportOutcome.alreadyFiled), isTrue);
      expect(shouldMarkReported(ReportOutcome.limitReached), isFalse);
      expect(shouldMarkReported(ReportOutcome.pinGone), isFalse);
      expect(shouldMarkReported(ReportOutcome.failed), isFalse);
    });
  });
}
