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
      // alberta names its documented failure list "unreachable".
      expect(truth.knownIndices, {6});
    });

    test('reads the committed two_speakers fixture', () {
      final truth = parseDiarizationTruth(
        File('test/fixtures/diarization/two_speakers.truth.json')
            .readAsStringSync(),
      );
      expect(truth.clip, 'two_speakers.wav');
      expect(truth.sentences, hasLength(16));
      // two_speakers names the same list "known" -- both spellings must parse,
      // or a regression gate silently treats documented failures as new ones.
      expect(truth.knownIndices, {8, 14});
    });

    test('the fixtures still hold the documented scores', () {
      // 24/24 and 14/16 in docs/progress.md. If a fixture is ever relabelled,
      // this is the test that says so rather than a silently shifted baseline.
      final alberta = parseDiarizationTruth(
        File('test/fixtures/diarization/alberta.truth.json').readAsStringSync(),
      );
      final two = parseDiarizationTruth(
        File('test/fixtures/diarization/two_speakers.truth.json')
            .readAsStringSync(),
      );
      expect(alberta.sentences.length, 24);
      expect(two.sentences.length - two.known.length, 14);
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
}
