import 'dart:math' as math;
import 'dart:typed_data';

import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/diarization/turn_assembly.dart';
import 'package:flutter_test/flutter_test.dart';

/// Orthogonal reference directions, so cosine similarity is readable by eye:
/// a vector's component along an axis *is* its similarity to that speaker.
final e0 = Float32List.fromList([1, 0, 0]);
final e1 = Float32List.fromList([0, 1, 0]);

/// A unit vector whose similarity to [e0] and [e1] is exactly as named.
Float32List mix({required double toE0, required double toE1}) {
  final rest = math.sqrt(1 - toE0 * toE0 - toE1 * toE1);
  return Float32List.fromList([toE0, toE1, rest]);
}

SpeakerSpan span(int startMs, int endMs, [int speaker = 0]) =>
    SpeakerSpan(startMs: startMs, endMs: endMs, speaker: speaker);

Phrase phrase(int startMs, int endMs, {int crossTalkMs = 0}) => Phrase(
      startMs: startMs,
      endMs: endMs,
      crossTalkMs: crossTalkMs,
      spanCount: 1,
    );

void main() {
  group('TurnAssembly', () {
    test('rejects a configuration where switching is easier than keeping', () {
      // Not cosmetic: with the thresholds inverted the state machine degrades
      // to a single static boundary, which is the behaviour this replaces.
      double keep = 0.6;
      double swap = 0.5;
      expect(
        () => TurnAssembly(
          keepSpeakerThreshold: keep,
          switchSpeakerThreshold: swap,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('buildPhrases', () {
    test('bridges a micro-silence into one phrase', () {
      // The mid-sentence-cutoff fix: one speaker pausing briefly is split by
      // segmentation, and the halves must be embedded as one region.
      final phrases = buildPhrases([span(0, 1000), span(1100, 2000)]);
      expect(phrases, hasLength(1));
      expect(phrases.single.startMs, 0);
      expect(phrases.single.endMs, 2000);
      expect(phrases.single.spanCount, 2);
    });

    test('leaves a real gap unbridged', () {
      final phrases = buildPhrases([span(0, 1000), span(1500, 2500)]);
      expect(phrases, hasLength(2));
    });

    test('the bridge distance is configurable', () {
      const wide = TurnAssembly(minSilenceBridgeMs: 600);
      expect(
        buildPhrases([span(0, 1000), span(1500, 2500)], config: wide),
        hasLength(1),
      );
    });

    test('never bridges overlapping spans, however small the gap', () {
      // Overlapping spans have a gap of zero, so without the overlap check they
      // would always bridge -- merging exactly the simultaneous speech this
      // design exists to isolate.
      final phrases = buildPhrases([span(0, 2000, 0), span(1500, 3000, 1)]);
      expect(phrases, hasLength(2));
      expect(phrases.first.crossTalkMs, 500);
    });

    test('records cross-talk as a fraction of the phrase', () {
      final phrases = buildPhrases([span(0, 1000, 0), span(800, 2000, 1)]);
      expect(phrases.first.crossTalkMs, 200);
      expect(phrases.first.crossTalkFraction, closeTo(0.2, 1e-9));
    });

    test('discards speaker labels entirely', () {
      // Two spans sherpa called different people, close in time, must still
      // become one phrase -- the labels are advisory and this layer reassigns.
      final phrases = buildPhrases([span(0, 1000, 0), span(1050, 2000, 7)]);
      expect(phrases, hasLength(1));
    });

    test('handles unordered input', () {
      final phrases = buildPhrases([span(1500, 2500), span(0, 1000)]);
      expect(phrases, hasLength(2));
      expect(phrases.first.startMs, 0);
    });

    test('no spans yields no phrases', () {
      expect(buildPhrases(const []), isEmpty);
    });
  });

  group('Phrase', () {
    test('a short phrase is assigned but not profile-eligible', () {
      const config = TurnAssembly();
      expect(phrase(0, 800).profileEligible(config), isFalse);
      expect(phrase(0, 2000).profileEligible(config), isTrue);
    });

    test('an overlap-heavy phrase is not profile-eligible however long', () {
      const config = TurnAssembly();
      expect(
        phrase(0, 4000, crossTalkMs: 1000).profileEligible(config),
        isFalse,
      );
    });

    test('trims drift-prone edges before embedding', () {
      const config = TurnAssembly(edgeTrimMs: 50);
      final region = phrase(1000, 2000).embedRegion(config);
      expect(region!.startMs, 1050);
      expect(region.endMs, 1950);
    });

    test('a phrase shorter than the trim yields no region', () {
      const config = TurnAssembly(edgeTrimMs: 50);
      expect(phrase(1000, 1080).embedRegion(config), isNull);
    });
  });

  group('assignTurns hysteresis', () {
    final long = [for (var i = 0; i < 6; i++) phrase(i * 2000, i * 2000 + 1900)];

    test('the first phrase seeds a speaker', () {
      final result = assignTurns(
        phrases: [long[0]],
        embeddings: [e0],
      );
      expect(result.speakers, [0]);
      expect(result.decisions.single.outcome, TurnOutcome.seeded);
    });

    test('a mid-turn dip is held by the lenient keep threshold', () {
      // 0.40 sits above keep (0.30) but below switch (0.50) -- under a single
      // static threshold this phrase would not match and would fragment the
      // speaker. That is the failure hysteresis exists to prevent.
      final result = assignTurns(
        phrases: [long[0], long[1]],
        embeddings: [e0, mix(toE0: 0.40, toE1: 0.0)],
      );
      expect(result.speakers, [0, 0]);
      expect(result.decisions.last.outcome, TurnOutcome.kept);
    });

    test('a genuine handover crosses the strict switch threshold', () {
      final result = assignTurns(
        phrases: [long[0], long[1], long[2]],
        embeddings: [e0, e1, e0],
      );
      // e1 matches nobody, so it opens speaker 1; returning to e0 must switch
      // back rather than stay.
      expect(result.speakers, [0, 1, 0]);
      expect(result.decisions[1].outcome, TurnOutcome.opened);
      expect(result.decisions[2].outcome, TurnOutcome.switched);
    });

    test('an ambiguous phrase holds the current speaker rather than moving', () {
      // 0.35 to the other speaker is above "new" (0.20) but below "switch"
      // (0.50). Neither confident enough to move nor strange enough to be a new
      // person, so the conservative answer is to stay put.
      final result = assignTurns(
        phrases: [long[0], long[1], long[2], long[3]],
        embeddings: [
          e0,
          e1,
          e0, // switches back to speaker 0
          mix(toE0: 0.10, toE1: 0.35),
        ],
      );
      expect(result.speakers.last, 0);
      expect(result.decisions.last.outcome, TurnOutcome.kept);
    });

    test('the speaker ceiling stops unbounded identities', () {
      const capped = TurnAssembly(maxSpeakers: 1);
      final result = assignTurns(
        phrases: [long[0], long[1]],
        embeddings: [e0, e1],
        config: capped,
      );
      expect(result.speakerCount, 1);
    });
  });

  group('assignTurns centroid pollution protection', () {
    test('a short phrase is assigned but never updates a profile', () {
      final result = assignTurns(
        phrases: [phrase(0, 2000), phrase(2000, 2400)],
        embeddings: [e0, mix(toE0: 0.40, toE1: 0.0)],
      );
      expect(result.speakers, [0, 0], reason: 'still assigned');
      expect(result.decisions[0].updatedProfile, isTrue);
      expect(result.decisions[1].updatedProfile, isFalse,
          reason: '400ms is below minCleanProfileMs');
    });

    test('a cross-talk phrase is assigned but never updates a profile', () {
      // The contamination path: a blended embedding averaged into a profile is
      // how one overlap poisons every later decision.
      final result = assignTurns(
        phrases: [phrase(0, 2000), phrase(2000, 5000, crossTalkMs: 1500)],
        embeddings: [e0, mix(toE0: 0.40, toE1: 0.0)],
      );
      expect(result.speakers, [0, 0]);
      expect(result.decisions[1].updatedProfile, isFalse);
    });

    test('a polluting phrase cannot drag the profile toward another voice', () {
      // Same two runs, differing only in whether the dirty phrase is long
      // enough to update. If protection works, the final decision must not
      // depend on the dirty phrase at all.
      List<int?> run({required int dirtyMs}) => assignTurns(
            phrases: [
              phrase(0, 2000),
              phrase(2000, 2000 + dirtyMs, crossTalkMs: dirtyMs),
              phrase(9000, 11000),
            ],
            embeddings: [e0, e1, mix(toE0: 0.45, toE1: 0.0)],
          ).speakers;

      expect(run(dirtyMs: 400), run(dirtyMs: 3000),
          reason: 'a cross-talk phrase must not change later attribution');
    });
  });

  group('TurnAssignment', () {
    test('re-emits assignments as spans the pipeline already consumes', () {
      final phrases = [phrase(0, 2000), phrase(3000, 5000)];
      final result = assignTurns(phrases: phrases, embeddings: [e0, e1]);
      final spans = result.toSpans(phrases);
      expect(spans, hasLength(2));
      expect(spans.first.startMs, 0);
      expect(spans.first.endMs, 2000);
      expect(spans.last.speaker, isNot(spans.first.speaker));
    });

    test('a phrase with no embedding inherits the current speaker', () {
      final result = assignTurns(
        phrases: [phrase(0, 2000), phrase(3000, 5000)],
        embeddings: [e0, null],
      );
      expect(result.speakers, [0, 0]);
      expect(result.decisions.last.outcome, TurnOutcome.unassigned);
    });

    test('no phrases yields no assignments', () {
      final result = assignTurns(phrases: const [], embeddings: const []);
      expect(result.speakers, isEmpty);
      expect(result.speakerCount, 0);
    });
  });
}
