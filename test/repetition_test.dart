import 'package:argand/core/text/repetition.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> words(String text) => text.split(' ');

void main() {
  group('normalizeForRepetition', () {
    test('strips case and punctuation so one loop reads as one phrase', () {
      expect(normalizeForRepetition('Ha,'), 'ha');
      expect(normalizeForRepetition('ha.'), 'ha');
      expect(normalizeForRepetition('HA!'), 'ha');
      expect(normalizeForRepetition('"ha"'), 'ha');
    });

    test('keeps digits and non-Latin letters', () {
      expect(normalizeForRepetition('1999.'), '1999');
      expect(normalizeForRepetition('نعم،'), 'نعم');
    });

    test('a punctuation-only word normalises to empty', () {
      expect(normalizeForRepetition('--'), '');
      expect(normalizeForRepetition('...'), '');
    });
  });

  group('findRepetitions', () {
    test('ordinary speech contains no runs', () {
      expect(
        findRepetitions(words('the quick brown fox jumps over the lazy dog')),
        isEmpty,
      );
    });

    test('finds a single-word laughter loop at its full extent', () {
      final runs = findRepetitions(words('so he said ha ha ha ha ha ha then'));
      expect(runs, hasLength(1));
      expect(runs.single.phrase, ['ha']);
      expect(runs.single.repeats, 6);
      expect(runs.single.startIndex, 3);
      expect(runs.single.endIndex, 9);
      expect(runs.single.wordCount, 6);
    });

    test('matches across differing punctuation and case within one loop', () {
      // Whisper routinely punctuates the last copy differently, which is
      // exactly when a naive string compare would split one loop into two.
      final runs = findRepetitions(words('Ha, ha. HA! ha ha ha.'));
      expect(runs, hasLength(1));
      expect(runs.single.repeats, 6);
    });

    test('prefers the longest coverage over a factor of the same loop', () {
      // "ha" x6 and "ha ha" x3 describe the same six words. Reporting the
      // shorter phrase states the loop's true period.
      final runs = findRepetitions(words('ha ha ha ha ha ha'));
      expect(runs.single.phrase, ['ha']);
      expect(runs.single.repeats, 6);
    });

    test('finds a multi-word phrase loop', () {
      // The shape of the Phase 1 failure: a seven-word phrase run to length.
      // A four-word scan limit would miss this entirely.
      const phrase = 'I am the director of the project';
      final runs = findRepetitions(words('$phrase $phrase $phrase'));
      expect(runs, hasLength(1));
      expect(runs.single.phrase, hasLength(7));
      expect(runs.single.repeats, 3);
      expect(runs.single.wordCount, 21);
    });

    test('two consecutive copies is ordinary English, not a loop', () {
      expect(findRepetitions(words('I had had enough')), isEmpty);
      expect(findRepetitions(words('that that is fine')), isEmpty);
    });

    test('minRepeats is configurable for a stricter or looser read', () {
      final loose = findRepetitions(words('no no here'), minRepeats: 2);
      expect(loose, hasLength(1));
      expect(loose.single.repeats, 2);
    });

    test('reports separate loops separately and does not overlap them', () {
      final runs = findRepetitions(
        words('ha ha ha ha and then yes yes yes yes yes'),
      );
      expect(runs, hasLength(2));
      expect(runs.first.phrase, ['ha']);
      expect(runs.first.repeats, 4);
      expect(runs.last.phrase, ['yes']);
      expect(runs.last.repeats, 5);
      expect(runs.first.endIndex, lessThanOrEqualTo(runs.last.startIndex));
    });

    test('a punctuation-only word cannot be part of a repeated phrase', () {
      // These normalise to empty, so treating them as equal would invent a
      // loop out of whatever the engine emitted around a pause.
      expect(findRepetitions(words('-- -- -- --')), isEmpty);
    });

    test('a loop running to the end of the list is still found', () {
      final runs = findRepetitions(words('and then ha ha ha ha'));
      expect(runs.single.repeats, 4);
      expect(runs.single.endIndex, 6);
    });

    test('an empty list yields nothing', () {
      expect(findRepetitions(const []), isEmpty);
    });
  });

  group('findWorstRepetition', () {
    test('returns the run covering the most words', () {
      final worst = findWorstRepetition(
        words('ha ha ha and yes yes yes yes yes yes yes'),
      );
      expect(worst!.phrase, ['yes']);
      expect(worst.repeats, 7);
    });

    test('returns null when there is no loop', () {
      expect(findWorstRepetition(words('a clean sentence here')), isNull);
    });
  });

  group('findWithinWordRepetition', () {
    test('catches a loop glued together without spaces', () {
      // The shape a real failing decode produced: one 273-character token,
      // which whitespace scanning reports as a single ordinary word.
      final token = 'Peek-a-' * 39;
      final run = findWithinWordRepetition(token, 7);
      expect(run, isNotNull);
      expect(run!.withinWord, isTrue);
      expect(run.phrase.single, 'peeka');
      expect(run.repeats, 39);
      expect(run.startIndex, 7);
      // One word slot, however long the loop runs.
      expect(run.wordCount, 1);
    });

    test('reports the shortest repeating unit', () {
      expect(findWithinWordRepetition('abababababab', 0)!.phrase.single, 'ab');
    });

    test('allows a loop cut off mid-unit by the end of a window', () {
      final run = findWithinWordRepetition('peekapeekapeekapeek', 0);
      expect(run!.phrase.single, 'peeka');
      expect(run.repeats, 3);
    });

    test('finds a loop that starts partway into the token', () {
      // The real second false-clean: a lead-in before the loop. Requiring
      // periodicity from index 0 scored this transcript as clean.
      final run = findWithinWordRepetition('Peek-a-${'boo-' * 30}', 3);
      expect(run, isNotNull);
      expect(run!.phrase.single, 'boo');
      expect(run.repeats, 30);
    });

    test('leaves ordinary long words alone', () {
      expect(findWithinWordRepetition('international', 0), isNull);
      expect(findWithinWordRepetition('transcription', 0), isNull);
      expect(findWithinWordRepetition('Massachusetts', 0), isNull);
    });

    test('minLength stops short words being called loops', () {
      // "hahaha" is three repeats of "ha", and says nothing about the decoder.
      expect(findWithinWordRepetition('hahaha', 0), isNull);
      expect(findWithinWordRepetition('bonbon', 0), isNull);
      // Long enough to mean something.
      expect(findWithinWordRepetition('hahahahahahaha', 0), isNotNull);
    });

    test('finds every within-word loop in a list', () {
      final runs = findWithinWordRepetitions(
        ['fine', 'ha-ha-ha-ha-ha-ha-ha', 'also', 'no-no-no-no-no-no'],
      );
      expect(runs, hasLength(2));
      expect(runs.first.startIndex, 1);
      expect(runs.last.startIndex, 3);
    });
  });

  group('analyzeRepetition', () {
    test('sees a loop that word scanning alone misses', () {
      final words = ['Green.', 'Peek-a-' * 39, 'What'];
      final report = analyzeRepetition(words);
      expect(report.acrossWords, isEmpty, reason: 'never crosses a space');
      expect(report.withinWords, hasLength(1));
      expect(report.hasLoop, isTrue);
    });

    test('sees a loop that spans words', () {
      final report = analyzeRepetition(words('a b ha ha ha ha ha'));
      expect(report.acrossWords, hasLength(1));
      expect(report.withinWords, isEmpty);
      expect(report.hasLoop, isTrue);
    });

    test('clean speech has no loop of either kind', () {
      final report = analyzeRepetition(words('the quick brown fox jumps over'));
      expect(report.hasLoop, isFalse);
      expect(report.ratio, 0.0);
    });

    test('ratio does not pretend to summarise a within-word loop', () {
      // Half the transcript is garbage but it occupies one word slot, which is
      // exactly why hasLoop exists and ratio must not be read alone.
      final report = analyzeRepetition(['ok', 'peekapeeka' * 20]);
      expect(report.ratio, 0.0);
      expect(report.hasLoop, isTrue);
      expect(report.withinWordRepeats, greaterThan(10));
    });
  });

  group('repetitionRatio', () {
    test('is zero for clean speech', () {
      expect(repetitionRatio(words('the quick brown fox jumps')), 0.0);
    });

    test('is the fraction of words consumed by loops', () {
      // 6 of 10 words are the loop.
      final ratio = repetitionRatio(words('a b c d ha ha ha ha ha ha'));
      expect(ratio, closeTo(0.6, 1e-9));
    });

    test('is one when the whole window is a loop', () {
      expect(repetitionRatio(words('ha ha ha ha')), 1.0);
    });

    test('is zero for an empty list rather than dividing by zero', () {
      expect(repetitionRatio(const []), 0.0);
    });
  });
}
