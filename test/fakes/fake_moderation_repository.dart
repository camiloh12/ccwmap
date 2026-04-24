import 'package:ccwmap/domain/repositories/moderation_repository.dart';

class FakeModerationRepository implements ModerationRepository {
  Set<String> remoteBlocklist = <String>{};
  final List<({String pinId, ReportReason reason, String? note})> reports = [];

  @override
  Future<void> submitPinReport({
    required String pinId,
    required ReportReason reason,
    String? note,
  }) async {
    reports.add((pinId: pinId, reason: reason, note: note));
  }

  @override
  Future<Set<String>> fetchBlocklist() async => Set<String>.from(remoteBlocklist);

  @override
  Future<void> blockUser(String userId) async {
    remoteBlocklist.add(userId);
  }

  @override
  Future<void> unblockUser(String userId) async {
    remoteBlocklist.remove(userId);
  }
}
