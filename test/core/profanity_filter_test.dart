import 'package:flutter_test/flutter_test.dart';
import 'package:ccwmap/core/profanity_filter.dart';

void main() {
  group('ProfanityFilter.contains', () {
    test('returns false for empty string', () {
      expect(ProfanityFilter.contains(''), isFalse);
    });

    test('returns false for clean text', () {
      expect(ProfanityFilter.contains('Main Street Diner'), isFalse);
      expect(ProfanityFilter.contains('City Hall'), isFalse);
    });

    test('is case-insensitive', () {
      // "FUCK" is in the deny-list; mix case should match.
      expect(ProfanityFilter.contains('This is FUcK'), isTrue);
      expect(ProfanityFilter.contains('this is fuck'), isTrue);
    });

    test('matches substrings (intentional)', () {
      // By design we accept false positives like "Scunthorpe". The report
      // mechanism is the real defense; this filter exists to block the
      // most obvious cases. Verify the intended substring behavior.
      expect(ProfanityFilter.contains('fuckity'), isTrue);
    });

    test('returns false for whitespace-only input', () {
      expect(ProfanityFilter.contains('   '), isFalse);
    });
  });
}
