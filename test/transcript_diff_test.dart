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

  group('verbatim tokenization', () {
    test('keeps the case and punctuation the normalized mode discards', () {
      expect(
        transcriptWords(
          'Chlamydia, like.',
          tokenization: TranscriptTokenization.verbatim,
        ),
        ['Chlamydia,', 'like.'],
      );
    });

    test('two transcripts can agree normalized and differ word for word', () {
      // This is the whole reason the second number exists.
      const reference = 'Yes, of course. It was the first one.';
      const candidate = 'yes of course it was the first one';

      final normalized = compareTranscripts(
        transcriptWords(reference),
        transcriptWords(candidate),
      );
      final verbatim = compareTranscripts(
        transcriptWords(
          reference,
          tokenization: TranscriptTokenization.verbatim,
        ),
        transcriptWords(
          candidate,
          tokenization: TranscriptTokenization.verbatim,
        ),
      );

      expect(normalized.wer, 0.0);
      expect(verbatim.wer, greaterThan(0.0));
    });
  });

  group('bracketed tags', () {
    test('a real timestamp is still stripped', () {
      expect(
        transcriptWords(
          '[00:00:01.000 --> 00:00:02.000] Green.',
          tokenization: TranscriptTokenization.verbatim,
        ),
        ['Green.'],
      );
    });

    test('a non-speech tag survives when the caller keeps tags', () {
      // `suppress_nst` decides whether these appear at all. Stripping them
      // unconditionally, as this file used to, scored that flag with an
      // instrument blind to its only effect.
      expect(
        transcriptWords('[BLANK_AUDIO]', stripBracketedTags: false),
        ['blankaudio'],
      );
    });

    test('and is dropped by default, preserving the recorded numbers', () {
      expect(transcriptWords('[BLANK_AUDIO] green'), ['green']);
    });

    test('a tag difference is invisible by default and visible when kept', () {
      const reference = 'green explosion';
      const candidate = '[BLANK_AUDIO] green explosion';

      expect(
        compareTranscripts(
          transcriptWords(reference),
          transcriptWords(candidate),
        ).wer,
        0.0,
      );
      expect(
        compareTranscripts(
          transcriptWords(reference, stripBracketedTags: false),
          transcriptWords(candidate, stripBracketedTags: false),
        ).wer,
        greaterThan(0.0),
      );
    });
  });

  group('comparePunctuation', () {
    test('identical punctuation reports no delta', () {
      final delta = comparePunctuation('One. Two, three.', 'One. Two, three.');
      expect(delta.sentenceEndDelta, 0);
      expect(delta.clauseEndDelta, 0);
      expect(delta.sentenceCountMatches, isTrue);
    });

    test('an extra sentence terminator is reported even when words match', () {
      // The failure this exists to catch: a decoder change that leaves every
      // word right but splits one sentence into two. WER cannot see it, and it
      // re-cuts every sentence unit that speaker assignment attributes whole.
      const reference = 'No of course yeah that makes sense.';
      const candidate = 'No, of course. Yeah, that makes sense.';

      expect(
        compareTranscripts(
          transcriptWords(reference),
          transcriptWords(candidate),
        ).wer,
        0.0,
      );

      final delta = comparePunctuation(reference, candidate);
      expect(delta.sentenceEndDelta, 1);
      expect(delta.sentenceCountMatches, isFalse);
    });

    test('counts clause terminators separately from sentence ones', () {
      final delta = comparePunctuation('One two three.', 'One, two, three.');
      expect(delta.sentenceEndDelta, 0);
      expect(delta.clauseEndDelta, 2);
    });
  });
}
