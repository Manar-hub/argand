import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/diarization_truth.dart';

void main() {
  group('parseDiarizationTruth', () {
    test('reads the committed alberta fixture', () {
      final truth = parseDiarizationTruth(
        File('test/fixtures/diarization/alberta.truth.json').readAsStringSync(),
      );
      expect(truth.clip, 'alberta.mp4');
      expect(truth.sentences, hasLength(24));
      expect(truth.speakers, {0, 1});
      // Both fixtures now name their documented-failure list "known". The
      // parser still accepts the retired "unreachable" spelling, so an old
      // fixture keeps parsing; the name was dropped because it asserted a
      // ceiling (see the fixture's own note on entry 6).
      expect(truth.knownIndices, {6});
    });

    test('reads the committed two_speakers fixture', () {
      final truth = parseDiarizationTruth(
        File('test/fixtures/diarization/two_speakers.truth.json')
            .readAsStringSync(),
      );
      expect(truth.clip, 'two_speakers.wav');
      expect(truth.sentences, hasLength(16));
      // Empty on purpose. It held {8, 14} until both were measured correct on
      // BOTH bundled models; tolerating them now would stop the gate catching
      // a regression. The fixture's `knownNote` records what they were and what
      // fixed them, and `knownPrevious` keeps the original entries.
      expect(truth.knownIndices, isEmpty);
      // Explicit turns, so scoring no longer depends on sentence times that go
      // stale whenever a decoder setting moves whisper's word timings.
      expect(truth.turns, hasLength(11));
    });

    test('both fixtures are armed with a measured error floor', () {
      // A fixture without a floor makes the gate fail rather than pass, which
      // is the honest state for a clip nobody has measured -- but it also means
      // an unarmed fixture protects nothing. These are the figures observed on
      // the worst-performing bundled model, so the weakest one has to clear the
      // same bar.
      final alberta = parseDiarizationTruth(
        File('test/fixtures/diarization/alberta.truth.json').readAsStringSync(),
      );
      final two = parseDiarizationTruth(
        File('test/fixtures/diarization/two_speakers.truth.json')
            .readAsStringSync(),
      );
      expect(alberta.maxWordErrorRate, closeTo(0.018, 1e-9));
      expect(two.maxWordErrorRate, closeTo(0.02, 1e-9));
      expect(alberta.sentences, hasLength(24));
      expect(two.sentences, hasLength(16));
      expect(alberta.turns, hasLength(17));
    });
  });

  group('scoreAgainstTruth', () {
    DiarizationTruth truthOf(List<int> speakers, {Set<int> known = const {}}) =>
        DiarizationTruth(
          clip: 'test',
          sentences: [
            for (final (i, speaker) in speakers.indexed)
              TruthSentence(
                index: i,
                startMs: i * 1000,
                endMs: (i + 1) * 1000,
                speaker: speaker,
                text: 's$i',
              ),
          ],
          known: [for (final i in known) KnownIssue(index: i, why: 'documented')],
        );

    test('a perfect run scores full marks', () {
      final score = scoreAgainstTruth(
        observed: const [0, 1, 0, 1],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 4);
      expect(score.total, 4);
      expect(score.mismatched, isEmpty);
    });

    test('cluster ids are arbitrary, so a relabelled run still scores full', () {
      // Diarization numbers clusters by discovery order. Comparing ids directly
      // would score this perfect run at 0/4.
      final score = scoreAgainstTruth(
        observed: const [1, 0, 1, 0],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 4);
      expect(score.mapping, {1: 0, 0: 1});
    });

    test('cluster ids need not be 0-based or contiguous', () {
      final score = scoreAgainstTruth(
        observed: const [7, 3, 7, 3],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 4);
    });

    test('reports which sentences are wrong', () {
      final score = scoreAgainstTruth(
        observed: const [0, 1, 1, 1],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 3);
      expect(score.mismatched, [2]);
    });

    test('separates new failures from documented ones', () {
      // The distinction a regression gate lives on: re-failing a documented
      // case is the status quo, anything else is new damage.
      final score = scoreAgainstTruth(
        observed: const [0, 1, 1, 1, 1, 1],
        truth: truthOf(const [0, 1, 0, 1, 0, 1], known: {2}),
      );
      expect(score.matched, 4);
      expect(score.mismatched, [2, 4]);
      expect(score.expectedMismatches, [2]);
      expect(score.newMismatches, [4]);
    });

    test('on a tie, a bijection beats collapsing two clusters into one', () {
      // Every mapping here scores 2. The honest reading is that the two
      // clusters are two people and half the sentences are misattributed, not
      // that both clusters are the same person.
      final score = scoreAgainstTruth(
        observed: const [0, 1, 1, 0],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 2);
      expect(score.mapping.values.toSet(), hasLength(2));
    });

    test('an unassigned sentence counts as wrong, never as a match', () {
      final score = scoreAgainstTruth(
        observed: const [0, null, 0, 1],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 3);
      expect(score.mismatched, [1]);
    });

    test('a different sentence count is refused rather than mapped by time', () {
      // The documented trap: mapping one segmentation onto another by overlap
      // averaged away a sentence visibly on the wrong speaker.
      final score = scoreAgainstTruth(
        observed: const [0, 1, 0],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.comparable, isFalse);
      expect(score.incomparableReason, contains('one segmentation'));
    });

    test('over-segmentation is surfaced rather than hidden by the mapping', () {
      // Three clusters for two people. The mapping can fold two of them onto
      // one speaker and still score well, so the cluster count is reported.
      final score = scoreAgainstTruth(
        observed: const [0, 1, 2, 1],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.observedClusters, 3);
      expect(score.matched, 4);
    });

    test('collapsing everyone into one cluster scores poorly', () {
      final score = scoreAgainstTruth(
        observed: const [0, 0, 0, 0],
        truth: truthOf(const [0, 1, 0, 1]),
      );
      expect(score.matched, 2);
      expect(score.observedClusters, 1);
    });

    test('a run with no speakers at all is comparable and scores zero', () {
      final score = scoreAgainstTruth(
        observed: const [null, null],
        truth: truthOf(const [0, 1]),
      );
      expect(score.comparable, isTrue);
      expect(score.matched, 0);
      expect(score.mismatched, [0, 1]);
    });
  });

  group('turnsFromSentences', () {
    DiarizationTruth truthOf(List<int> speakers) => DiarizationTruth(
          clip: 'test',
          sentences: [
            for (final (i, speaker) in speakers.indexed)
              TruthSentence(
                index: i,
                startMs: i * 1000,
                endMs: (i + 1) * 1000,
                speaker: speaker,
                text: 's$i',
              ),
          ],
          known: const [],
        );

    test('merges consecutive sentences on the same speaker', () {
      final turns = truthOf(const [0, 0, 1, 1, 1, 0]).turns;
      expect(turns.map((t) => t.speaker), [0, 1, 0]);
      expect(turns.map((t) => t.startMs), [0, 2000, 5000]);
      expect(turns.map((t) => t.endMs), [2000, 5000, 6000]);
    });

    test('never merges across a speaker change', () {
      final turns = truthOf(const [0, 1, 0, 1]).turns;
      expect(turns, hasLength(4));
    });

    test('an explicit turns list wins over the derived one', () {
      const stated = TruthTurn(startMs: 0, endMs: 9000, speaker: 7);
      final truth = DiarizationTruth(
        clip: 'test',
        sentences: truthOf(const [0, 1]).sentences,
        known: const [],
        explicitTurns: const [stated],
      );
      expect(truth.turns, hasLength(1));
      expect(truth.turns.single.speaker, 7);
    });

    test('the committed fixtures both derive usable turns', () {
      for (final path in const [
        'test/fixtures/diarization/alberta.truth.json',
        'test/fixtures/diarization/two_speakers.truth.json',
      ]) {
        final truth =
            parseDiarizationTruth(File(path).readAsStringSync());
        expect(truth.turns, isNotEmpty, reason: path);
        // Turns must not overlap or run backwards, or a midpoint lookup would
        // depend on list order rather than on time.
        for (var i = 1; i < truth.turns.length; i++) {
          expect(
            truth.turns[i].startMs,
            greaterThanOrEqualTo(truth.turns[i - 1].endMs),
            reason: '$path turn $i',
          );
        }
      }
    });
  });

  group('speakerAtMs', () {
    const turns = [
      TruthTurn(startMs: 0, endMs: 1000, speaker: 0),
      TruthTurn(startMs: 2000, endMs: 3000, speaker: 1),
    ];

    test('answers inside a turn', () {
      expect(speakerAtMs(turns, 500), 0);
      expect(speakerAtMs(turns, 2500), 1);
    });

    test('falls back to the nearest turn in a gap', () {
      // Gaps are an artifact of sentence extents not abutting, not a claim that
      // nobody is speaking; refusing to answer would penalise a run for that.
      expect(speakerAtMs(turns, 1100), 0);
      expect(speakerAtMs(turns, 1900), 1);
    });

    test('answers null only when there is no truth at all', () {
      expect(speakerAtMs(const [], 500), isNull);
    });
  });

  group('scoreWordsAgainstTruth', () {
    DiarizationTruth twoTurns() => const DiarizationTruth(
          clip: 'test',
          sentences: [],
          known: [],
          explicitTurns: [
            TruthTurn(startMs: 0, endMs: 2000, speaker: 0),
            TruthTurn(startMs: 2000, endMs: 4000, speaker: 1),
          ],
        );

    List<TruthWord> wordsEvery(int count, int stepMs) => [
          for (var i = 0; i < count; i++)
            (startMs: i * stepMs, endMs: (i + 1) * stepMs),
        ];

    test('a perfect run has a zero error rate', () {
      final score = scoreWordsAgainstTruth(
        words: wordsEvery(4, 1000),
        assigned: const [0, 0, 1, 1],
        truth: twoTurns(),
      );
      expect(score.matchedWords, 4);
      expect(score.errorRate, 0.0);
      expect(score.mismatchedIndices, isEmpty);
    });

    test('relabelled clusters still score full marks', () {
      final score = scoreWordsAgainstTruth(
        words: wordsEvery(4, 1000),
        assigned: const [9, 9, 3, 3],
        truth: twoTurns(),
      );
      expect(score.errorRate, 0.0);
      expect(score.mapping, {9: 0, 3: 1});
    });

    test('a half-split sentence costs half, not all of it', () {
      // The resolution the sentence scorer lacks. `two_speakers` #8 is one
      // sentence diarization splits between two speakers; scored per sentence
      // that is a total loss and a rule that fixes half of it registers as no
      // change at all.
      final score = scoreWordsAgainstTruth(
        words: wordsEvery(4, 1000),
        assigned: const [0, 0, 1, 0],
        truth: twoTurns(),
      );
      expect(score.matchedWords, 3);
      expect(score.mismatchedIndices, [3]);
    });

    test('an unassigned word counts against the run', () {
      final score = scoreWordsAgainstTruth(
        words: wordsEvery(4, 1000),
        assigned: const [0, 0, null, 1],
        truth: twoTurns(),
      );
      expect(score.mismatchedIndices, [2]);
    });

    test('the same labels score a re-segmented run', () {
      // The property the whole time-anchored scheme exists for. Nothing about
      // these labels mentions sentences, so a decoder that emits twice as many
      // words over the same audio is scored without re-labelling — which is
      // precisely what `alberta.mp4` needed and could not have.
      final coarse = scoreWordsAgainstTruth(
        words: wordsEvery(4, 1000),
        assigned: const [0, 0, 1, 1],
        truth: twoTurns(),
      );
      final fine = scoreWordsAgainstTruth(
        words: wordsEvery(8, 500),
        assigned: const [0, 0, 0, 0, 1, 1, 1, 1],
        truth: twoTurns(),
      );
      expect(coarse.errorRate, 0.0);
      expect(fine.errorRate, 0.0);
      expect(fine.totalWords, 8);
    });
  });
}
