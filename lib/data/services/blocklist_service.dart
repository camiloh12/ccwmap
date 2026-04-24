import 'package:flutter/foundation.dart';
import 'package:ccwmap/domain/repositories/moderation_repository.dart';

/// In-memory cache of the current user's blocklist.
///
/// Design per spec (SP-2): pure in-memory, refreshed on sign-in and after
/// any block/unblock. No Drift persistence in v1. The "offline-before-
/// first-sign-in" gap is acceptable because a guest cannot block anyone
/// — blocking is auth-gated.
///
/// Extends [ChangeNotifier] so [MapViewModel] can refresh its pin stream
/// when the blocklist changes (after calling [block] / [unblock] /
/// [refresh] / [clear]).
class BlocklistService extends ChangeNotifier {
  final ModerationRepository _repo;
  final Set<String> _blocked = <String>{};

  BlocklistService(this._repo);

  /// Unmodifiable view of currently blocked user IDs.
  Set<String> get blocked => Set<String>.unmodifiable(_blocked);

  bool isBlocked(String? userId) => userId != null && _blocked.contains(userId);

  /// Loads the blocklist from the server into the cache. Overwrites any
  /// prior cached state. Call after sign-in.
  Future<void> refresh() async {
    final remote = await _repo.fetchBlocklist();
    _blocked
      ..clear()
      ..addAll(remote);
    notifyListeners();
  }

  Future<void> block(String userId) async {
    await _repo.blockUser(userId);
    _blocked.add(userId);
    notifyListeners();
  }

  Future<void> unblock(String userId) async {
    await _repo.unblockUser(userId);
    _blocked.remove(userId);
    notifyListeners();
  }

  /// Empties the cache. Call on sign-out.
  void clear() {
    if (_blocked.isEmpty) return;
    _blocked.clear();
    notifyListeners();
  }
}
