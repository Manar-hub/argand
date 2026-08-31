import 'package:argand/core/text/transcript_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transcriptWords', () {
    test('normalises case and punctuation', () {
      expect(transcriptWords('Chlamydia, like.'), ['chlamydia', 'like']);
    });

    test('strips whisper timestamps', () {
      expect(
        transcriptWords('[00:00:01.000 --> 00:00:02.000]   Green.'),
        ['green'],
      );
    });

    test('drops tokens that carry no letters or digits', () {
      expect(transcriptWords('a -- b ♪ c'), ['a', 'b', 'c']);
    });
  });

  group('compareTranscripts', () {
    test('identical transcripts have no edits and zero WER', () {
      final words = transcriptWords('the quick brown fox');
      final result = compareTranscripts(words, words);
      expect(result.edits, isEmpty);
      expect(result.wer, 0.0);
    });

    test('counts a substitution and names both words', () {
      final result = compareTranscripts(
        transcriptWords('I have chlamydia here'),
        transcriptWords('I have climidial here'),
      );
      expect(result.substitutions, 1);
      expect(result.insertions, 0);
      expect(result.deletions, 0);
      expect(result.edits.single.reference, 'chlamydia');
      expect(result.edits.single.candidate, 'climidial');
      expect(result.wer, closeTo(0.25, 1e-9));
    });

    test('counts a deletion when the candidate drops a word', () {
      final result = compareTranscripts(
        transcriptWords('one two three four'),
        transcriptWords('one three four'),
      );
      expect(result.deletions, 1);
      expect(result.edits.single.reference, 'two');
      expect(result.edits.single.candidate, isNull);
    });

    test('counts an insertion when the candidate invents a word', () {
      final result = compareTranscripts(
        transcriptWords('one two three'),
        transcriptWords('one two extra three'),
      );
      expect(result.insertions, 1);
      expect(result.edits.single.candidate, 'extra');
      expect(result.edits.single.reference, isNull);
    });

    test('edits come back in transcript order', () {
      final result = compareTranscripts(
        transcriptWords('a b c d e'),
        transcriptWords('a x c y e'),
      );
      expect(result.substitutions, 2);
      expect(
        result.edits.map((e) => e.reference).toList(),
        ['b', 'd'],
        reason: 'backtracking must be reversed before reporting',
      );
    });

    test('WER exceeds 1.0 when the candidate loops', () {
      // A repetition loop invents far more words than the reference holds, and
      // clamping would hide exactly the case this metric should shout about.
      final result = compareTranscripts(
        transcriptWords('green explosion'),
        transcriptWords('ha ha ha ha ha ha ha ha'),
      );
      expect(result.wer, greaterThan(1.0));
    });

    test('an empty candidate is a full miss, not a divide by zero', () {
      final result = compareTranscripts(transcriptWords('one two'), const []);
      expect(result.deletions, 2);
      expect(result.wer, 1.0);
    });

    test('two empty transcripts agree rather than erroring', () {
      expect(compareTranscripts(const [], const []).wer, 0.0);
    });
  });
}
