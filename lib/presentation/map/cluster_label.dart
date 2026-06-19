/// Formats a cluster's pin count for display on a cluster bubble, abbreviating
/// thousands and millions so the label fits inside a small circle:
/// `4500 -> "4.5k"`, `23000 -> "23k"`, `1500000 -> "1.5M"`. Counts below 1000
/// are shown verbatim. Whole values drop the trailing `.0` (`12000 -> "12k"`,
/// not `"12.0k"`).
String abbreviateCount(int count) {
  if (count < 1000) return count.toString();
  if (count < 1000000) return '${_oneDecimal(count / 1000)}k';
  return '${_oneDecimal(count / 1000000)}M';
}

/// One decimal place, with a trailing `.0` trimmed (`4.5 -> "4.5"`, `12.0 ->
/// "12"`).
String _oneDecimal(double value) {
  final s = value.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
