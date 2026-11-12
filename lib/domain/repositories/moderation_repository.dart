/// Reason codes accepted by the server-side CHECK on `pin_reports.reason`.
/// Keep in sync with migrations 005_pin_reports.sql and
/// 014 (imported-pin reasons).
enum ReportReason {
  INACCURATE,
  OFFENSIVE,
  SPAM,
  OTHER,
  CLOSED,
  WRONG_LOCATION,
  NOT_CATEGORY,
  DUPLICATE,
}

/// The user already has an open report on this pin.
class ReportAlreadyFiledException implements Exception {
  const ReportAlreadyFiledException();
}

/// The user hit the per-account daily report limit.
class ReportLimitReachedException implements Exception {
  const ReportLimitReachedException();
}

/// The reported pin no longer exists.
class ReportedPinGoneException implements Exception {
  const ReportedPinGoneException();
}

/// Report-and-block operations for user-generated content moderation.
abstract class ModerationRepository {
  /// Files a report against [pinId]. [note] is optional and capped at
  /// 500 characters server-side. Throws on network/server failure.
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  });

  /// Returns the set of user IDs the current user has blocked.
  Future<Set<String>> fetchBlocklist();

  /// Blocks [userId] for the current user. Idempotent; succeeds even if
  /// already blocked.
  Future<void> blockUser(String userId);

  /// Removes [userId] from the current user's blocklist. Idempotent.
  Future<void> unblockUser(String userId);
}
