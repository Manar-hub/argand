import 'package:argand/core/text/sentence_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<TimedWord> wordsOf(List<String> texts) => [
        for (final (i, text) in texts.indexed)
          (text: text, startMs: i * 100, endMs: (i + 1) * 100),
      ];

  group('sentenceUnitsOf', () {
    test('cuts after every sentence terminator', () {
      final units = sentenceUnitsOf(wordsOf(['Hello', 'there.', 'How', 'now?']));
      expect(units, hasLength(2));
      expect(units[0].first, 0);
      expect(units[0].last, 1);
      expect(units[1].first, 2);
      expect(units[1].last, 3);
    });

    test('takes its extent from the first and last word', () {
      final units = sentenceUnitsOf(wordsOf(['One', 'two.']));
      expect(units.single.startMs, 0);
      expect(units.single.endMs, 200);
      expect(units.single.durationMs, 200);
      expect(units.single.wordCount, 2);
    });

    test('closes a trailing sentence that carries no terminator', () {
      // Speech that trails off unpunctuated is still a sentence for every
      // purpose here. Dropping it would silently exclude the end of every
      // transcript from smoothing and refinement alike.
      final units = sentenceUnitsOf(wordsOf(['Well', 'I', 'suppose']));
      expect(units, hasLength(1));
      expect(units.single.last, 2);
    });

    test('does not break on clause punctuation', () {
      // A comma is a weaker boundary that caption grouping may break on for
      // line length. A handover at a comma is rare enough that treating clauses
      // as units would fragment the evidence a speaker decision rests on.
      final units = sentenceUnitsOf(wordsOf(['No,', 'of', 'course.']));
      expect(units, hasLength(1));
    });

    test('handles a terminator wrapped in quotes', () {
      final units = sentenceUnitsOf(wordsOf(['he', 'said."', 'Then']));
      expect(units, hasLength(2));
      expect(units.first.last, 1);
    });

    test('every word belongs to exactly one unit', () {
      // The property both call sites depend on: refinement indexes words by
      // `first`/`last`, and a gap or an overlap would move a decision onto the
      // wrong words.
      final words = wordsOf(['a.', 'b', 'c?', 'd', 'e']);
      final units = sentenceUnitsOf(words);
      final covered = <int>[];
      for (final unit in units) {
        for (var i = unit.first; i <= unit.last; i++) {
          covered.add(i);
        }
      }
      expect(covered, [0, 1, 2, 3, 4]);
    });

    test('an empty transcript yields no units', () {
      expect(sentenceUnitsOf(const []), isEmpty);
    });
  });
}
