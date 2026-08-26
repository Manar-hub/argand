import 'dart:typed_data';

import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_refinement.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:flutter_test/flutter_test.dart';

SpeakerSpan span(int startMs, int endMs, int speaker) =>
    SpeakerSpan(startMs: startMs, endMs: endMs, speaker: speaker);

WordTiming wt(String text, int startMs, int endMs) =>
    (text: text, startMs: startMs, endMs: endMs);

/// Words for a sentence of [count] evenly spaced tokens, ending in a stop.
List<WordTiming> sentence(int startMs, int endMs, int count) {
  final step = (endMs - startMs) ~/ count;
  return [
    for (var i = 0; i < count; i++)
      wt(
        i == count - 1 ? 'word.' : 'word',
        startMs + i * step,
        i == count - 1 ? endMs : startMs + (i + 1) * step,
      ),
  ];
}

Float32List vec(List<double> values) => Float32List.fromList(values);

void main() {
  // Measured on device from the development clip. Committed as literals so the
  // rules can be exercised against material that actually failed, with no
  // device and no inference.
  final alberta = [
    span(31, 2444, 0),
    span(2444, 4368, 1),
    span(4115, 5195, 0),
    span(5161, 7861, 1),
    span(7203, 12552, 0),
    span(12468, 15472, 1),
    span(15472, 17142, 0),
    span(17142, 19319, 1),
    span(19319, 22762, 0),
    span(21833, 23504, 1),
    span(23555, 26356, 0),
    span(27571, 34186, 1),
    span(35452, 41965, 0),
    span(37088, 39772, 1),
  ];

  group('vector maths', () {
    test('unitVector scales to length one', () {
      final u = unitVector(vec([3, 4]))!;
      expect(u[0], closeTo(0.6, 1e-6));
      expect(u[1], closeTo(0.8, 1e-6));
    });

    test('unitVector returns null when there is no direction', () {
      expect(unitVector(vec([0, 0])), isNull);
      expect(unitVector(Float32List(0)), isNull);
      expect(unitVector(null), isNull);
    });

    test('cosineSimilarity is 1 for identical and 0 for orthogonal', () {
      final a = unitVector(vec([1, 1]))!;
      final b = unitVector(vec([2, 2]))!;
      final c = unitVector(vec([1, -1]))!;
      expect(cosineSimilarity(a, b), closeTo(1.0, 1e-6));
      expect(cosineSimilarity(a, c), closeTo(0.0, 1e-6));
    });

    test('centroidOf averages then re-normalises', () {
      final centroid = centroidOf([
        unitVector(vec([1, 0]))!,
        unitVector(vec([0, 1]))!,
      ])!;
      expect(centroid[0], closeTo(centroid[1], 1e-6));
      expect(cosineSimilarity(centroid, centroid), closeTo(1.0, 1e-6));
    });

    test('centroidOf returns null for an empty set', () {
      expect(centroidOf(const []), isNull);
    });
  });

  group('decideOne', () {
    const config = SpeakerRefinement();

    test('moves on a clear win over the runner-up', () {
      // The measured "Tokens cost money." case: 0.571 against 0.266.
      expect(
        decideOne(
          similarities: {1: 0.571, 0: 0.266},
          currentSpeaker: 0,
          config: config,
        ),
        RefinementOutcome.moved,
      );
    });

    test('does nothing when the current speaker already wins', () {
      expect(
        decideOne(
          similarities: {0: 0.706, 1: 0.418},
          currentSpeaker: 0,
          config: config,
        ),
        RefinementOutcome.keptAlreadyBest,
      );
    });

    test('declines when the margin is too thin', () {
      // Two speakers holding a region about equally is not evidence.
      expect(
        decideOne(
          similarities: {1: 0.40, 0: 0.34},
          currentSpeaker: 0,
          config: config,
        ),
        RefinementOutcome.keptNoMargin,
      );
    });

    test('declines when the region sounds like nobody', () {
      // Music, noise or silence: a wide margin over an equally poor match is
      // still no reason to act.
      expect(
        decideOne(
          similarities: {1: 0.11, 0: -0.20},
          currentSpeaker: 0,
          config: config,
        ),
        RefinementOutcome.keptWeakMatch,
      );
    });

    test('reports a missing embedding rather than guessing', () {
      expect(
        decideOne(
          similarities: const {},
          currentSpeaker: 0,
          config: config,
        ),
        RefinementOutcome.skippedNoEmbedding,
      );
    });

    test('a lone speaker cannot win on absence of competition', () {
      // With one candidate the runner-up is negative infinity, so the margin
      // is met trivially -- the similarity floor is what stops it acting.
      expect(
        decideOne(
          similarities: {1: 0.05},
          currentSpeaker: 0,
          config: config,
        ),
        RefinementOutcome.keptWeakMatch,
      );
    });
  });

  group('planRefinement', () {
    test('asks about a sentence two speakers both claim', () {
      // "Of course, yeah, that makes sense." sits inside both 0:35452-41965
      // and 1:37088-39772.
      final words = sentence(38650, 39650, 6);
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: List.filled(words.length, 0),
      );

      expect(
        plan.candidates.any((c) => c.startMs < 39650 && c.endMs > 38650),
        isTrue,
      );
    });

    test('asks about a sentence buried in an over-long span', () {
      // "Tokens cost money." has only one speaker overlapping it, so it is not
      // ambiguous -- it qualifies because 0:7203-12552 also covers its
      // neighbours, which is where a missing turn would hide.
      final words = [
        ...sentence(7170, 7920, 4),
        ...sentence(7920, 9400, 3),
        ...sentence(9400, 12390, 12),
      ];
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: List.filled(words.length, 0),
      );

      expect(
        plan.candidates.any((c) => c.startMs >= 7920 && c.endMs <= 9400),
        isTrue,
        reason: 'The buried sentence must be asked about',
      );
    });

    test('leaves an unambiguous lone sentence alone', () {
      // One speaker, one span, nothing else in it: no question to ask, and
      // embedding it would only cost time and risk moving a correct answer.
      final words = sentence(200, 2000, 8);
      final plan = planRefinement(
        spans: [span(0, 2400, 0), span(30000, 34000, 1)],
        words: words,
        assigned: List.filled(words.length, 0),
      );

      expect(plan.candidates, isEmpty);
    });

    test('never builds a voice print from a region under test', () {
      final words = [
        ...sentence(7170, 7920, 4),
        ...sentence(7920, 9400, 3),
        ...sentence(9400, 12390, 12),
      ];
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: List.filled(words.length, 0),
      );

      for (final entry in plan.references.entries) {
        for (final region in entry.value) {
          for (final candidate in plan.candidates) {
            final overlaps = region.startMs < candidate.endMs &&
                region.endMs > candidate.startMs;
            expect(
              overlaps,
              isFalse,
              reason: 'Reference ${region.startMs}-${region.endMs} for speaker '
                  '${entry.key} contains the region being tested against it',
            );
          }
        }
      }
    });

    test('never builds a voice print from mixed-speaker audio', () {
      final words = [
        ...sentence(7170, 7920, 4),
        ...sentence(7920, 9400, 3),
      ];
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: List.filled(words.length, 0),
      );

      for (final entry in plan.references.entries) {
        for (final region in entry.value) {
          final shared = alberta.any((other) =>
              other.speaker != entry.key &&
              other.overlapWith(region.startMs, region.endMs) > 0);
          expect(shared, isFalse,
              reason: 'Reference for speaker ${entry.key} overlaps another '
                  'speaker, so it is not that speaker alone');
        }
      }
    });

    test('a region shorter than the floor is not asked about', () {
      final words = sentence(38650, 39000, 2);
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: List.filled(words.length, 0),
        // 350ms, minus 50ms trimmed from each end, falls under 400ms.
        config: const SpeakerRefinement(),
      );

      expect(plan.candidates, isEmpty);
    });

    test('still finds references when most sentences are candidates', () {
      // The bug this pins: an earlier rule rejected any span that touched a
      // region under test. On real material almost every sentence is a
      // candidate, so that rejected every span for both speakers, left no
      // voice prints, and turned the whole pass into a silent no-op -- which
      // looks exactly like "found nothing worth changing".
      final words = [
        for (final s in [
          (60, 2390, 8), (2390, 2780, 2), (2780, 4120, 5), (4120, 5120, 4),
          (5120, 7170, 9), (7170, 7920, 4), (7920, 9400, 3), (9400, 12390, 12),
          (12390, 13280, 3), (13280, 15380, 11), (15380, 17050, 8),
          (17050, 19240, 9), (19240, 21670, 10), (21670, 23470, 8),
          (23470, 25260, 6), (25260, 27090, 4), (27090, 28590, 1),
          (28630, 33590, 16), (33590, 35650, 3), (35650, 36650, 4),
          (36650, 37650, 4), (37650, 38650, 5), (38650, 39650, 6),
          (39650, 41850, 10),
        ])
          ...sentence(s.$1, s.$2, s.$3),
      ];
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: assignSpeakers(words, alberta),
      );

      expect(plan.candidates, isNotEmpty);
      expect(
        plan.references.length,
        greaterThanOrEqualTo(2),
        reason: 'Both speakers need a voice print or the pass cannot run',
      );
      expect(plan.isEmpty, isFalse);
    });

    test('the trigger does not depend on how the model segments sentences', () {
      // The property that matters for model independence. Same audio, same
      // spans, two different sentence segmentations -- as base and small-q5_1
      // genuinely produce -- must ask about the same region, because the
      // trigger is a span-duration comparison and never consults whisper.
      List<RefinementCandidate> candidatesFor(List<WordTiming> words) =>
          planRefinement(
            spans: alberta,
            words: words,
            assigned: assignSpeakers(words, alberta),
          ).candidates;

      // One model splits the reply into its own sentence.
      final split = [
        ...sentence(7170, 7920, 4),
        ...sentence(7920, 9400, 3),
        ...sentence(9400, 12390, 12),
      ];
      // Another merges the first two, as small-q5_1 does elsewhere in this clip.
      final merged = [
        ...sentence(7170, 9400, 7),
        ...sentence(9400, 12390, 12),
      ];

      // Both must reach into the over-long span, whichever way it was cut up.
      expect(
        candidatesFor(split).any((c) => c.startMs >= 7170 && c.endMs <= 12390),
        isTrue,
      );
      expect(
        candidatesFor(merged).any((c) => c.startMs >= 7170 && c.endMs <= 12390),
        isTrue,
      );
    });

    test('a span sharing time with another speaker is never a voice print', () {
      final words = [
        ...sentence(7170, 7920, 4),
        ...sentence(7920, 9400, 3),
        ...sentence(9400, 12390, 12),
      ];
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: assignSpeakers(words, alberta),
      );

      // 0:7203-12552 conceals the employee's reply, and segmentation also
      // declares an overlap with 1:5161-7861 -- which is what excludes it here.
      // A span that conceals a turn *without* any declared overlap is caught
      // acoustically instead, by the coherence check in SpeakerRefiner, since
      // no span-shape rule can see it.
      for (final regions in plan.references.values) {
        expect(
          regions.any((r) => r.startMs == 7203 && r.endMs == 12552),
          isFalse,
        );
      }
    });

    test('flags a region a speaker change cuts through, for testing', () {
      // "I like that one." 36650-37650. Span 1:37088-39772 opens 388ms into the
      // trimmed region, splitting it 43/57. The cut is recorded rather than
      // acted on: whether it is a genuine handover -- in which case the audio
      // is a blend and unusable -- or one segmentation invented is decided by
      // listening to each side, in SpeakerRefiner.
      final words = sentence(36650, 37650, 4);
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: assignSpeakers(words, alberta),
      );

      final candidate = plan.candidates
          .where((c) => c.startMs >= 36650 && c.endMs <= 37650)
          .firstOrNull;
      expect(candidate, isNotNull);
      expect(candidate!.cutMs, 37088);
    });

    test('still asks when the change lands right at the edge', () {
      // "What do you mean?" 7170-7920. Span 1:5161-7861 ends 9ms before the
      // trimmed region does -- a cut, but one leaving the region essentially
      // pure, so it must still be asked about. This region moved *correctly*,
      // and a blanket "no cuts" rule would have thrown that fix away.
      final words = sentence(7170, 7920, 4);
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: assignSpeakers(words, alberta),
      );

      final candidate = plan.candidates
          .where((c) => c.startMs >= 7170 && c.endMs <= 7920)
          .firstOrNull;
      expect(candidate, isNotNull);
      expect(
        candidate!.cutMs,
        isNull,
        reason: 'A cut 9ms from the edge leaves the region effectively pure, '
            'so there is no boundary worth testing',
      );
    });

    test('overlapping spans covering the whole region are not a cut', () {
      // Two speakers both marked active across the entire sentence is the
      // ambiguity this pass exists for, not a handover inside it. Neither span
      // has an edge within the region, so nothing is split.
      final words = sentence(38650, 39650, 6);
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: assignSpeakers(words, alberta),
      );

      final candidate = plan.candidates
          .where((c) => c.startMs >= 38650 && c.endMs <= 39650)
          .firstOrNull;
      expect(candidate, isNotNull);
      expect(
        candidate!.cutMs,
        isNull,
        reason: 'Nothing splits this region, so there is no boundary to test',
      );
    });

    test('records the cut that segmentation invented, rather than obeying it',
        () {
      // two_speakers.wav "That's right." 16910-18460, which the user confirms
      // is one speaker. Segmentation disagrees, reporting a handover at 17817
      // between two short spans. The cut is carried forward so the refiner can
      // listen to both sides -- refusing here would trust segmentation about
      // exactly the thing it got wrong.
      final twoSpeakers = [
        span(31, 2765, 0),
        span(2765, 7810, 1),
        span(7844, 11118, 0),
        span(11287, 13902, 1),
        span(13953, 16923, 0),
        span(17159, 17817, 1),
        span(17817, 18627, 0),
        span(18374, 21125, 1),
        span(21125, 27453, 0),
      ];
      final words = sentence(16910, 18460, 2);
      final plan = planRefinement(
        spans: twoSpeakers,
        words: words,
        assigned: assignSpeakers(words, twoSpeakers),
      );

      final candidate = plan.candidates
          .where((c) => c.startMs >= 16910 && c.endMs <= 18460)
          .firstOrNull;
      expect(candidate, isNotNull);
      expect(candidate!.cutMs, 17817);
    });

    test('SpeakerRefinement.none plans nothing at all', () {
      final words = sentence(38650, 39650, 6);
      final plan = planRefinement(
        spans: alberta,
        words: words,
        assigned: List.filled(words.length, 0),
        config: SpeakerRefinement.none,
      );

      expect(plan.candidates, isEmpty);
      expect(plan.isEmpty, isTrue);
    });
  });

  group('applyRefinements', () {
    RefinementDecision move(int startMs, int endMs, int from, int to) =>
        RefinementDecision(
          candidate: RefinementCandidate(
            startMs: startMs,
            endMs: endMs,
            currentSpeaker: from,
            firstWord: 0,
            lastWord: 0,
          ),
          similarities: {to: 0.6, from: 0.2},
          newSpeaker: to,
          outcome: RefinementOutcome.moved,
        );

    test('a moved region actually wins its words afterwards', () {
      // The test that matters. Inserting a span is not enough: speakerForWord
      // breaks ties toward the longer span, so without carving the region out
      // of 0:7203-12552 the new span would lose every word it was created to
      // claim, and the pass would be a silent no-op.
      final refined = applyRefinements(alberta, [move(7970, 9350, 0, 1)]);

      expect(
        speakerForWord(startMs: 8200, endMs: 8600, spans: refined),
        1,
        reason: 'The carve-out is what makes the re-label take effect',
      );
    });

    test('audio outside the moved region keeps its original speaker', () {
      final refined = applyRefinements(alberta, [move(7970, 9350, 0, 1)]);

      expect(speakerForWord(startMs: 10000, endMs: 10400, spans: refined), 0);
      expect(speakerForWord(startMs: 500, endMs: 900, spans: refined), 0);
    });

    test('no decisions leaves the spans untouched', () {
      expect(applyRefinements(alberta, const []), same(alberta));
    });

    test('declined decisions change nothing', () {
      final declined = [
        RefinementDecision(
          candidate: RefinementCandidate(
            startMs: 7970,
            endMs: 9350,
            currentSpeaker: 0,
            firstWord: 0,
            lastWord: 0,
          ),
          similarities: const {1: 0.30, 0: 0.28},
          newSpeaker: null,
          outcome: RefinementOutcome.keptNoMargin,
        ),
      ];

      expect(applyRefinements(alberta, declined), same(alberta));
    });

    test('output stays sorted and free of empty spans', () {
      final refined = applyRefinements(alberta, [move(7970, 9350, 0, 1)]);

      for (var i = 1; i < refined.length; i++) {
        expect(refined[i].startMs, greaterThanOrEqualTo(refined[i - 1].startMs));
      }
      for (final s in refined) {
        expect(s.endMs, greaterThan(s.startMs));
      }
    });

    test('refining an already-refined list is a no-op', () {
      final once = applyRefinements(alberta, [move(7970, 9350, 0, 1)]);
      final twice = applyRefinements(once, [move(7970, 9350, 0, 1)]);

      expect(
        twice.map((s) => '${s.speaker}:${s.startMs}-${s.endMs}').toList(),
        once.map((s) => '${s.speaker}:${s.startMs}-${s.endMs}').toList(),
      );
    });

    test('splitting a span leaves the head and tail intact', () {
      // 0:7203-12552 straddles the region, so it must become two pieces.
      final refined = applyRefinements(alberta, [move(7970, 9350, 0, 1)]);
      final pieces = refined
          .where((s) => s.speaker == 0 && s.startMs < 12552 && s.endMs > 7203)
          .toList();

      expect(pieces.any((s) => s.endMs == 7970), isTrue, reason: 'head');
      expect(pieces.any((s) => s.startMs == 9350), isTrue, reason: 'tail');
    });
  });
}
