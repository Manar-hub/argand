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

  group('speakerForWord overlap specificity', () {
    test('a nested short span beats the long one enclosing it', () {
      // The exact shape measured on a real clip: spk0 talks across spk1's
      // reply, so both spans cover the word completely. Scoring by raw
      // milliseconds gave it to spk0 and swallowed the reply.
      final spans = [span(35452, 41965, 0), span(37088, 39772, 1)];

      expect(speakerForWord(startMs: 38000, endMs: 38400, spans: spans), 1);
    });

    test('order does not decide it when one span encloses another', () {
      final nestedFirst = [span(37088, 39772, 1), span(35452, 41965, 0)];

      expect(speakerForWord(startMs: 38000, endMs: 38400, spans: nestedFirst), 1);
    });

    test('the enclosing span still wins outside the nested one', () {
      final spans = [span(35452, 41965, 0), span(37088, 39772, 1)];

      expect(speakerForWord(startMs: 36000, endMs: 36400, spans: spans), 0);
      expect(speakerForWord(startMs: 40500, endMs: 40900, spans: spans), 0);
    });

    test('higher coverage beats a shorter span that only clips the word', () {
      // Specificity is the tie-break, not the primary rule: a span covering
      // the whole word must beat a tiny one grazing its edge.
      final spans = [span(1000, 2000, 0), span(1900, 1950, 1)];

      expect(speakerForWord(startMs: 1000, endMs: 1400, spans: spans), 0);
    });
  });

  group('assignSpeakers sentence smoothing', () {
    WordTiming wt(String text, int startMs, int endMs) =>
        (text: text, startMs: startMs, endMs: endMs);

    test('pulls a stray leading word onto its own sentence', () {
      // The reported case: "AI is expensive." arrived with "AI" on the
      // previous speaker because the turn boundary landed one word late.
      final words = [
        wt('you?', 0, 300),
        wt('AI', 300, 600),
        wt('is', 600, 900),
        wt('expensive.', 900, 1200),
      ];
      final spans = [span(0, 650, 0), span(650, 1200, 1)];

      final result = assignSpeakers(words, spans);

      expect(result[0], 0, reason: 'The earlier sentence is untouched');
      expect(result.sublist(1), [1, 1, 1], reason: '"AI" joins its own sentence');
    });

    test('pulls a stray trailing word back', () {
      final words = [
        wt('I', 0, 300),
        wt('like', 300, 600),
        wt('that', 600, 900),
        wt('one.', 900, 1200),
      ];
      // The boundary lands early, stranding "one." with the next speaker.
      final spans = [span(0, 850, 0), span(850, 2000, 1)];

      expect(assignSpeakers(words, spans), [0, 0, 0, 0]);
    });

    test('leaves a genuinely shared sentence alone', () {
      // A long minority run is a real mid-sentence handover, not a boundary
      // slip, and flattening it would invent a turn that did not happen.
      final words = [
        wt('What', 0, 300),
        wt('do', 300, 600),
        wt('you', 600, 900),
        wt('mean', 900, 1200),
        wt('by', 1200, 1500),
        wt('that?', 1500, 1800),
      ];
      final spans = [span(0, 900, 0), span(900, 1800, 1)];

      expect(assignSpeakers(words, spans), [0, 0, 0, 1, 1, 1]);
    });

    test('a tie leaves the sentence alone', () {
      final words = [
        wt('What', 0, 300),
        wt('do', 300, 600),
        wt('you', 600, 900),
        wt('mean?', 900, 1200),
      ];
      final spans = [span(0, 600, 0), span(600, 1200, 1)];

      expect(
        assignSpeakers(words, spans),
        [0, 0, 1, 1],
        reason: 'Two against two is no evidence, so nothing should move',
      );
    });

    test('a sentence too short to have a majority is left alone', () {
      final words = [wt("That's", 0, 300), wt('right.', 300, 600)];
      final spans = [span(0, 350, 1), span(350, 600, 0)];

      expect(assignSpeakers(words, spans), [1, 0]);
    });

    test('smoothing can be switched off for measurement', () {
      final words = [
        wt('you?', 0, 300),
        wt('AI', 300, 600),
        wt('is', 600, 900),
        wt('expensive.', 900, 1200),
      ];
      final spans = [span(0, 650, 0), span(650, 1200, 1)];

      expect(
        assignSpeakers(words, spans, smoothing: SpeakerSmoothing.none),
        [0, 0, 1, 1],
      );
    });

    test('handles the final sentence when it has no closing punctuation', () {
      final words = [
        wt('and', 0, 300),
        wt('then', 300, 600),
        wt('we', 600, 900),
        wt('left', 900, 1200),
      ];
      final spans = [span(0, 250, 1), span(250, 1200, 0)];

      expect(assignSpeakers(words, spans), [0, 0, 0, 0]);
    });

    test('returns all nulls when diarization produced nothing', () {
      final words = [wt('a', 0, 300), wt('b.', 300, 600)];

      expect(assignSpeakers(words, const []), [null, null]);
    });

    test('returns one entry per word', () {
      final words = [
        for (var i = 0; i < 7; i++) wt('w$i', i * 100, i * 100 + 90),
      ];

      expect(assignSpeakers(words, [span(0, 700, 0)]).length, 7);
    });
  });
}
