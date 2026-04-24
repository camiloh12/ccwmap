import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/domain/repositories/agreements_repository.dart';

class SupabaseAgreementsRepository implements AgreementsRepository {
  final SupabaseRemoteDataSource _remote;
  SupabaseAgreementsRepository(this._remote);

  @override
  Future<bool> hasAcceptedAgreement({
    required String userId,
    required int version,
  }) {
    return _remote.hasAcceptedAgreement(userId: userId, version: version);
  }

  @override
  Future<void> recordAgreementAcceptance({
    required String userId,
    required int version,
  }) {
    return _remote.recordAgreementAcceptance(userId: userId, version: version);
  }
}
