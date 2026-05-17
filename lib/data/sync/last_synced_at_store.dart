import 'package:shared_preferences/shared_preferences.dart';

/// Per-user storage for the `MyPinsSync` delta watermarks.
///
/// One key per `(user_id, kind)` pair so signing out and back into a
/// different account doesn't replay the wrong account's history.
///
/// "Pins" and "deletions" advance independently — they're separate Supabase
/// queries served from separate tables.
class LastSyncedAtStore {
  static const String _pinsPrefix = 'mypins.last_synced_at.';
  static const String _deletionsPrefix = 'mypins.deletions_last_synced_at.';

  static final DateTime _epoch = DateTime.utc(1970);

  final SharedPreferences _prefs;

  LastSyncedAtStore._(this._prefs);

  static Future<LastSyncedAtStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LastSyncedAtStore._(prefs);
  }

  Future<DateTime> readPinsWatermark(String userId) async {
    final iso = _prefs.getString('$_pinsPrefix$userId');
    return iso == null ? _epoch : DateTime.parse(iso);
  }

  Future<void> writePinsWatermark(String userId, DateTime at) =>
      _prefs.setString('$_pinsPrefix$userId', at.toUtc().toIso8601String());

  Future<DateTime> readDeletionsWatermark(String userId) async {
    final iso = _prefs.getString('$_deletionsPrefix$userId');
    return iso == null ? _epoch : DateTime.parse(iso);
  }

  Future<void> writeDeletionsWatermark(String userId, DateTime at) => _prefs
      .setString('$_deletionsPrefix$userId', at.toUtc().toIso8601String());

  Future<void> clearForUser(String userId) async {
    await _prefs.remove('$_pinsPrefix$userId');
    await _prefs.remove('$_deletionsPrefix$userId');
  }
}
