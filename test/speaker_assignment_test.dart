import 'package:argand/core/diarization/speaker_assignment.dart';
import 'package:argand/core/diarization/speaker_span.dart';
import 'package:flutter_test/flutter_test.dart';

SpeakerSpan span(int startMs, int endMs, int speaker) =>
    SpeakerSpan(startMs: startMs, endMs: endMs, speaker: speaker);

void main() {
  group('SpeakerSpan geometry', () {
    test('overlap is zero for disjoint windows, never negative', () {
      final s = span(1000, 2000, 0);
      expect(s.overlapWith(3000, 4000), 0);
      expect(s.overlapWith(0, 500), 0);
      // Touching end-to-end is not overlapping.
      expect(s.overlapWith(2000, 3000), 0);
    });

    test('overlap is the shared millisecond count', () {
      final s = span(1000, 2000, 0);
      expect(s.overlapWith(1500, 2500), 500);
      expect(s.overlapWith(0, 1200), 200);
      // Window entirely inside the span.
      expect(s.overlapWith(1200, 1300), 100);
      // Span entirely inside the window.
      expect(s.overlapWith(0, 5000), 1000);
    });

    test('gap is zero whenever the two touch', () {
      final s = span(1000, 2000, 0);
      expect(s.gapTo(1500, 1600), 0);
      expect(s.gapTo(2500, 2600), 500);
      expect(s.gapTo(400, 600), 400);
    });
  });

  group('speakerForWord', () {
    test('returns null only when there are no spans at all', () {
      expect(
        speakerForWord(startMs: 0, endMs: 500, spans: const []),
        isNull,
        reason: 'No diarization data means no speaker, not speaker 0',
      );
    });

    test('assigns a word sitting inside one span', () {
      final spans = [span(0, 5000, 0), span(5000, 10000, 1)];
      expect(speakerForWord(startMs: 1000, endMs: 1400, spans: spans), 0);
      expect(speakerForWord(startMs: 6000, endMs: 6400, spans: spans), 1);
    });

    test('a word straddling a turn goes to whoever holds more of it', () {
      // Speaker change at 5000ms. The word runs 4900-5400: 100ms of speaker 0
      // and 400ms of speaker 1, so it belongs to 1.
      final spans = [span(0, 5000, 0), span(5000, 10000, 1)];
      expect(speakerForWord(startMs: 4900, endMs: 5400, spans: spans), 1);

      // Shift it the other way and the answer flips.
      expect(speakerForWord(startMs: 4600, endMs: 5100, spans: spans), 0);
    });

    test('a word in a gap falls back to the nearest span', () {
      // Diarization found speech either side of a pause; whisper placed a word
      // inside the pause. Word timings drift by tens of ms, so refusing to
      // label it would scatter unattributed words through the transcript.
      final spans = [span(0, 4000, 0), span(6000, 10000, 1)];
      expect(
        speakerForWord(startMs: 4200, endMs: 4400, spans: spans),
        0,
        reason: 'Closer to the span that ended at 4000',
      );
      expect(
        speakerForWord(startMs: 5700, endMs: 5900, spans: spans),
        1,
        reason: 'Closer to the span that starts at 6000',
      );
    });

    test('a word entirely before or after all speech still gets a speaker', () {
      final spans = [span(2000, 4000, 3)];
      expect(speakerForWord(startMs: 0, endMs: 100, spans: spans), 3);
      expect(speakerForWord(startMs: 9000, endMs: 9100, spans: spans), 3);
    });

    test('does not depend on the order spans arrive in', () {
      final ordered = [span(0, 5000, 0), span(5000, 10000, 1)];
      final shuffled = [span(5000, 10000, 1), span(0, 5000, 0)];

      for (final word in [
        (100, 400),
        (4900, 5400),
        (6000, 6400),
      ]) {
        expect(
          speakerForWord(startMs: word.$1, endMs: word.$2, spans: shuffled),
          speakerForWord(startMs: word.$1, endMs: word.$2, spans: ordered),
          reason: 'Word ${word.$1}-${word.$2} changed answer when reordered',
        );
      }
    });

    test('picks the dominant speaker across more than two candidates', () {
      final spans = [
        span(0, 1000, 0),
        span(1000, 1100, 1),
        span(1100, 3000, 2),
      ];
      // 900-1800: 100ms of 0, 100ms of 1, 700ms of 2.
      expect(speakerForWord(startMs: 900, endMs: 1800, spans: spans), 2);
    });

    test('zero-length words still resolve rather than returning null', () {
      // Word timings can collapse to a point on very short tokens; the nearest
      // -span fallback must cover that instead of falling through.
      final spans = [span(0, 5000, 0)];
      expect(speakerForWord(startMs: 2000, endMs: 2000, spans: spans), 0);
    });
  });

  group('speakerIdFor', () {
    test('is the plain decimal index', () {
      expect(speakerIdFor(0), '0');
      expect(speakerIdFor(12), '12');
    });
  });
}
