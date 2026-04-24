/// Tracks whether a given authenticated user has accepted the current
/// version of the EULA / community guidelines.
///
/// Version numbers are monotonic integers. Bump the constant when
/// material wording changes and existing users should be re-prompted.
abstract class AgreementsRepository {
  static const int currentAgreementVersion = 1;

  /// Returns true if [userId] has an accepted row for [version].
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  });

  /// Persists acceptance of [version] for [userId].
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  });
}
