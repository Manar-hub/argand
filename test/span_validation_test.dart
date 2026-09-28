import 'package:argand/core/diarization/speaker_span.dart';
import 'package:argand/core/diarization/span_validation.dart';
import 'package:flutter_test/flutter_test.dart';

SpeakerSpan span(int startMs, int endMs, int speaker) =>
    SpeakerSpan(startMs: startMs, endMs: endMs, speaker: speaker);

/// The real span list from `two_speakers.wav`, which is where every threshold
/// here was measured.
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

void main() {
  group('suspectSpans', () {
    test('finds the short span its own labels say never happened', () {
      final suspects = suspectSpans(twoSpeakers);

      expect(suspects.map((s) => s.index), contains(6));
      final suspect = suspects.firstWhere((s) => s.index == 6);
      expect(suspect.incumbent, 0);
      expect(suspect.challenger, 1);
      // spk1 resumes at 18374 while this span runs to 18627.
      expect(suspect.challengerOverlapMs, 253);
    });

    test('leaves long spans alone', () {
      // The 6.3s span 8 is wrong in places too, but re-labelling a span that
      // long would move far more than the error it was aimed at.
      expect(suspectSpans(twoSpeakers).map((s) => s.index), isNot(contains(8)));
    });

    test('a speaker on one side only is a turn boundary, not an artifact', () {
      // The other speaker leads but never returns, which is what an ordinary
      // handover looks like. Re-labelling here would erase a real turn.
      final spans = [
        span(0, 5000, 0),
        span(5000, 5600, 1),
        span(5600, 11000, 1),
      ];

      expect(suspectSpans(spans), isEmpty);
    });

    test('a short challenger cannot unseat anyone', () {
      // Neither side holds enough audio to be believed.
      final spans = [
        span(0, 900, 1),
        span(900, 1500, 0),
        span(1500, 2300, 1),
      ];

      expect(suspectSpans(spans), isEmpty);
    });

    test('the pass can be switched off entirely', () {
      expect(suspectSpans(twoSpeakers, config: SpanValidation.none), isEmpty);
    });

    test('a region too short to embed reports no region rather than guessing', () {
      const config = SpanValidation();
      final tiny = SuspectSpan(
        index: 0,
        incumbent: 0,
        challenger: 1,
        startMs: 1000,
        endMs: 1200,
        challengerOverlapMs: 0,
      );

      expect(tiny.embedRegion(config), isNull);
    });
  });

  group('challengerWins', () {
    final suspect = suspectSpans(twoSpeakers).firstWhere((s) => s.index == 6);

    test('clear acoustic evidence moves the span', () {
      expect(challengerWins(suspect, {0: 0.20, 1: 0.75}), isTrue);
    });

    test('clear acoustic evidence for the incumbent keeps it', () {
      expect(challengerWins(suspect, {0: 0.75, 1: 0.20}), isFalse);
    });

    test('audio too weak to answer lets the geometry decide', () {
      // The measured case: 0.359 against 0.273, both far below the 0.7-0.9 a
      // clean stretch of one voice scores on this clip.
      expect(challengerWins(suspect, {0: 0.359, 1: 0.273}), isTrue);
    });

    test('a confident incumbent survives even when it is the shorter span', () {
      // alberta's only suspect, which is a genuine interjection: 0.569 for its
      // own speaker is a real answer, so structure must not override it.
      final alberta = SuspectSpan(
        index: 2,
        incumbent: 0,
        challenger: 1,
        startMs: 4115,
        endMs: 5195,
        challengerOverlapMs: 253,
      );

      expect(challengerWins(alberta, {0: 0.569, 1: 0.308}), isFalse);
    });

    test('weak audio alone is not enough without the overlap signature', () {
      // Span 5 on the same clip: also weak, but no challenger speaks inside it,
      // so there is no reason to doubt the boundary and it is left alone.
      final noOverlap = SuspectSpan(
        index: 5,
        incumbent: 1,
        challenger: 0,
        startMs: 17159,
        endMs: 17817,
        challengerOverlapMs: 0,
      );

      expect(challengerWins(noOverlap, {0: 0.168, 1: 0.200}), isFalse);
    });

    test('a region that produced no embedding changes nothing', () {
      expect(challengerWins(suspect, const {}), isFalse);
    });

    test('a missing speaker print changes nothing', () {
      expect(challengerWins(suspect, {0: 0.30}), isFalse);
    });
  });

  group('applyValidations', () {
    test('re-labels only the named spans, leaving every boundary intact', () {
      final suspects = suspectSpans(twoSpeakers).where((s) => s.index == 6);
      final out = applyValidations(twoSpeakers, suspects);

      expect(out[6].speaker, 1);
      expect(out[6].startMs, twoSpeakers[6].startMs);
      expect(out[6].endMs, twoSpeakers[6].endMs);
      expect(out.length, twoSpeakers.length);
      for (var i = 0; i < out.length; i++) {
        if (i == 6) continue;
        expect(out[i].speaker, twoSpeakers[i].speaker, reason: 'span $i moved');
      }
    });

    test('no reassignments returns the original list', () {
      expect(applyValidations(twoSpeakers, const []), same(twoSpeakers));
    });
  });
}
