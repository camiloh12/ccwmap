import 'package:ccwmap/data/datasources/supabase_remote_data_source.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';

class SupabaseModerationRepository implements ModerationRepository {
  final SupabaseRemoteDataSource _remote;
  SupabaseModerationRepository(this._remote);

  @override
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  }) {
    return _remote.submitPinReport(
      pinId: pinId,
      reason: reason.name,
      note: note,
    );
  }

  @override
  Future<Set<String>> fetchBlocklist() => _remote.fetchBlocklist();

  @override
  Future<void> blockUser(String userId) => _remote.blockUser(userId);

  @override
  Future<void> unblockUser(String userId) => _remote.unblockUser(userId);
}
