import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, per account, which pins the user has already reported so the
/// UI can show "Reported" without a round trip.
class ReportedPinsStore {
  static const String _prefix = 'reports.reported_pin_ids.';

  final SharedPreferences _prefs;

  ReportedPinsStore._(this._prefs);

  static Future<ReportedPinsStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ReportedPinsStore._(prefs);
  }

  bool isReported(String userId, String pinId) =>
      (_prefs.getStringList('$_prefix$userId') ?? const []).contains(pinId);

  Future<void> markReported(String userId, String pinId) async {
    final key = '$_prefix$userId';
    final ids = List<String>.of(_prefs.getStringList(key) ?? const []);
    if (ids.contains(pinId)) return;
    ids.add(pinId);
    await _prefs.setStringList(key, ids);
  }
}
