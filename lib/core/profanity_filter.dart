/// Minimal client-side profanity check for user-supplied pin names.
///
/// Intentionally minimal — the ~30-word deny-list handles the obvious
/// cases only. Bypasses with leet-speak, spacing, or homoglyphs are
/// tolerated; the report mechanism (see ReportPinDialog) is the real
/// defense against abuse. Per spec: "Obviously bypassable; the report
/// mechanism is the real defense."
class ProfanityFilter {
  // Non-exhaustive by design. Additions should be obvious slurs /
  // profanities that no legitimate place-name would contain.
  static const List<String> _deny = [
    'fuck',
    'shit',
    'bitch',
    'asshole',
    'bastard',
    'cunt',
    'dick',
    'faggot',
    'nigger',
    'nigga',
    'retard',
    'retarded',
    'slut',
    'whore',
    'chink',
    'gook',
    'kike',
    'spic',
    'tranny',
    'wetback',
  ];

  /// Returns true if [input] contains any deny-listed substring
  /// (case-insensitive). Whitespace-only and empty inputs return false.
  static bool contains(String input) {
    if (input.trim().isEmpty) return false;
    final lower = input.toLowerCase();
    for (final w in _deny) {
      if (lower.contains(w)) return true;
    }
    return false;
  }
}
