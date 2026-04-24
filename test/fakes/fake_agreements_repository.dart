import 'package:ccwmap/domain/repositories/agreements_repository.dart';

class FakeAgreementsRepository implements AgreementsRepository {
  final Set<({String userId, int version})> accepted = {};
  bool willReportAccepted = false;

  @override
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) async {
    if (willReportAccepted) return true;
    return accepted.contains((userId: userId, version: version));
  }

  @override
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) async {
    accepted.add((userId: userId, version: version));
  }
}
