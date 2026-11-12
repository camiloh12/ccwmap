/// Pure presentation rules for imported-pin locking and report reasons. No
/// Flutter imports so it is unit-testable without pumping a widget.
library;

import '../../core/system_constants.dart';
import '../../domain/models/restriction_tag.dart';
import '../../domain/repositories/moderation_repository.dart';

/// True when the pin was created by the system (importer) user.
bool isImportedPin(String? createdBy) => createdBy == kSystemUserId;

/// Statutory (confidence high) imported pins can't have status, tag or
/// location changed by users (migration 013).
bool isStatutoryLocked({
  required String? createdBy,
  required String? confidence,
}) => isImportedPin(createdBy) && confidence == 'high';

String lockedStatusNote(String? legalCitation) {
  final cite = (legalCitation == null || legalCitation.isEmpty)
      ? ''
      : ' ($legalCitation)';
  return "Set by law$cite. This can't be changed here. "
      "If it's wrong, use Report a problem.";
}

String notCategoryLabel(RestrictionTag? tag) {
  switch (tag) {
    case RestrictionTag.FEDERAL_PROPERTY:
      return 'Not a federal building';
    case RestrictionTag.AIRPORT_SECURE:
      return 'Not an airport secure area';
    case RestrictionTag.STATE_LOCAL_GOVT:
      return 'Not a government building';
    case RestrictionTag.SCHOOL_K12:
      return 'Not a school';
    case RestrictionTag.COLLEGE_UNIVERSITY:
      return 'Not a college or university';
    case RestrictionTag.BAR_ALCOHOL:
      return 'Not a bar';
    case RestrictionTag.HEALTHCARE:
      return 'Not a healthcare facility';
    case RestrictionTag.PLACE_OF_WORSHIP:
      return 'Not a place of worship';
    case RestrictionTag.SPORTS_ENTERTAINMENT:
      return 'Not a sports or entertainment venue';
    case RestrictionTag.PRIVATE_PROPERTY:
      return 'Not private property';
    case null:
      return 'Not what this pin says';
  }
}

List<(ReportReason, String)> reportReasonsFor({
  required bool imported,
  RestrictionTag? tag,
}) {
  if (imported) {
    return [
      (ReportReason.CLOSED, 'Closed or no longer there'),
      (ReportReason.WRONG_LOCATION, 'Wrong location'),
      (ReportReason.NOT_CATEGORY, notCategoryLabel(tag)),
      (ReportReason.DUPLICATE, 'Duplicate of another pin'),
      (ReportReason.OTHER, 'Something else'),
    ];
  }
  return [
    (ReportReason.INACCURATE, 'Inaccurate'),
    (ReportReason.OFFENSIVE, 'Offensive'),
    (ReportReason.SPAM, 'Spam'),
    (ReportReason.OTHER, 'Other'),
  ];
}
