import 'package:ccwmap/core/system_constants.dart';
import 'package:ccwmap/domain/models/restriction_tag.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';
import 'package:ccwmap/presentation/widgets/pin_report_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imported = created by the system user', () {
    expect(isImportedPin(kSystemUserId), isTrue);
    expect(isImportedPin('someone'), isFalse);
    expect(isImportedPin(null), isFalse);
  });

  test('locked only for imported high-confidence pins', () {
    expect(
      isStatutoryLocked(createdBy: kSystemUserId, confidence: 'high'),
      isTrue,
    );
    expect(
      isStatutoryLocked(createdBy: kSystemUserId, confidence: 'medium'),
      isFalse,
    );
    expect(isStatutoryLocked(createdBy: 'u1', confidence: 'high'), isFalse);
  });

  test('locked note names the citation when there is one', () {
    expect(
      lockedStatusNote('18 U.S.C. § 930'),
      "Set by law (18 U.S.C. § 930). This can't be changed here. "
      "If it's wrong, use Report a problem.",
    );
    expect(
      lockedStatusNote(''),
      "Set by law. This can't be changed here. "
      "If it's wrong, use Report a problem.",
    );
    expect(
      lockedStatusNote(null),
      "Set by law. This can't be changed here. "
      "If it's wrong, use Report a problem.",
    );
  });

  test('imported reasons, phrased from the tag', () {
    expect(
      reportReasonsFor(imported: true, tag: RestrictionTag.FEDERAL_PROPERTY),
      [
        (ReportReason.CLOSED, 'Closed or no longer there'),
        (ReportReason.WRONG_LOCATION, 'Wrong location'),
        (ReportReason.NOT_CATEGORY, 'Not a federal building'),
        (ReportReason.DUPLICATE, 'Duplicate of another pin'),
        (ReportReason.OTHER, 'Something else'),
      ],
    );
  });

  test('user-pin reasons unchanged', () {
    expect(reportReasonsFor(imported: false).map((r) => r.$1), [
      ReportReason.INACCURATE,
      ReportReason.OFFENSIVE,
      ReportReason.SPAM,
      ReportReason.OTHER,
    ]);
  });

  test('notCategoryLabel covers every tag', () {
    const expected = {
      RestrictionTag.FEDERAL_PROPERTY: 'Not a federal building',
      RestrictionTag.AIRPORT_SECURE: 'Not an airport secure area',
      RestrictionTag.STATE_LOCAL_GOVT: 'Not a government building',
      RestrictionTag.SCHOOL_K12: 'Not a school',
      RestrictionTag.COLLEGE_UNIVERSITY: 'Not a college or university',
      RestrictionTag.BAR_ALCOHOL: 'Not a bar',
      RestrictionTag.HEALTHCARE: 'Not a healthcare facility',
      RestrictionTag.PLACE_OF_WORSHIP: 'Not a place of worship',
      RestrictionTag.SPORTS_ENTERTAINMENT:
          'Not a sports or entertainment venue',
      RestrictionTag.PRIVATE_PROPERTY: 'Not private property',
    };
    expect(expected.length, RestrictionTag.values.length);
    expected.forEach((tag, label) => expect(notCategoryLabel(tag), label));
    expect(notCategoryLabel(null), 'Not what this pin says');
  });
}
