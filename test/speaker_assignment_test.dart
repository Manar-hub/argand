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

  group('speakerForWord with overlapping spans', () {
    test('the dominant span wins over a short nested one', () {
      // Nested spans are mostly spurious on real media -- one clip had 253ms,
      // 658ms and 1030ms spans scattered inside multi-second turns. Letting
      // the short one win lets each steal individual words, which flaps the
      // transcript between speakers mid-sentence.
      final spans = [span(9667, 17277, 0), span(13666, 13919, 1)];

      expect(speakerForWord(startMs: 13700, endMs: 13800, spans: spans), 0);
    });

    test('order does not decide it when one span encloses another', () {
      final nestedFirst = [span(13666, 13919, 1), span(9667, 17277, 0)];

      expect(
        speakerForWord(startMs: 13700, endMs: 13800, spans: nestedFirst),
        0,
      );
    });

    test('a span covering more of the word still wins', () {
      // The rule is plain longest-overlap, so a span holding most of the word
      // beats one grazing its edge regardless of either span's total length.
      final spans = [span(1000, 2000, 0), span(1900, 5000, 1)];

      expect(speakerForWord(startMs: 1000, endMs: 1400, spans: spans), 0);
      expect(speakerForWord(startMs: 1800, endMs: 2400, spans: spans), 1);
    });

    test('the known cost: a genuine nested reply is absorbed', () {
      // Recorded rather than hidden: this is the accepted cost of leaning the
      // tie-break long, and it is the smaller of the two failure modes.
      final spans = [span(35452, 41965, 0), span(37088, 39772, 1)];

      expect(
        speakerForWord(startMs: 38000, endMs: 38400, spans: spans),
        0,
        reason: 'Longest-overlap gives nested turns to the surrounding speaker',
      );
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

    test('a two-word sentence is attributed whole, not split', () {
      // "That's / right." landing on two different speakers was a standing
      // known error: edge smoothing needs a majority and refuses to act on
      // two words, so nothing could fix it. Sentence-level attribution can,
      // and should -- a two-word sentence shared between two people is a
      // boundary slip, because a real handover mid-sentence needs a sentence
      // long enough to hand over in.
      final words = [wt("That's", 0, 300), wt('right.', 300, 600)];
      final spans = [span(0, 350, 1), span(350, 600, 0)];

      expect(
        assignSpeakers(words, spans),
        [1, 1],
        reason: 'Speaker 1 holds 350ms of the 600ms sentence, speaker 0 250ms',
      );
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

  // Spans and sentence extents below are real, measured on device by
  // integration_test/diarization_probe_test.dart. They are committed as
  // literals so the reconciliation rule can be exercised against material that
  // actually failed, without a device and without re-running inference.
  //
  // Cluster 0 is the boss, cluster 1 the employee. That mapping is fixed by
  // the measured table in docs/engineering-notes.md.
  group('sentence attribution, on measured spans', () {
    /// `alberta.mp4`, the clip where replies were swallowed.
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

    /// Builds a sentence of [wordCount] evenly spaced words over the extent,
    /// ending in a full stop. Only the timings matter to the rule.
    List<WordTiming> sentence(int startMs, int endMs, int wordCount) {
      final step = (endMs - startMs) ~/ wordCount;
      return [
        for (var i = 0; i < wordCount; i++)
          (
            text: i == wordCount - 1 ? 'word.' : 'word',
            startMs: startMs + i * step,
            endMs: i == wordCount - 1 ? endMs : startMs + (i + 1) * step,
          ),
      ];
    }

    test('rescues a reply nested inside the other speaker\'s span', () {
      // "You want me to write code manually now?" 21670-23470. The employee's
      // span 21833-23504 is nested inside the boss's 19319-22762, so overlap
      // ties and the longer span takes every word. IoU sees that the boss's
      // span spends most of its length outside this sentence.
      final words = sentence(21670, 23470, 8);

      expect(
        assignSpeakers(words, alberta).toSet(),
        {1},
        reason: 'The whole sentence belongs to the employee',
      );
    });

    test('rescues two consecutive short replies at the end of the clip', () {
      // "Yeah, I'm sure you do." and "Of course, yeah, that makes sense."
      // both sit wholly inside 0:35452-41965 and 1:37088-39772, so both spans
      // cover them completely and raw overlap cannot tell them apart at all.
      for (final extent in [(37650, 38650, 5), (38650, 39650, 6)]) {
        final words = sentence(extent.$1, extent.$2, extent.$3);

        expect(
          assignSpeakers(words, alberta).toSet(),
          {1},
          reason: 'Sentence at ${extent.$1}-${extent.$2} is the employee',
        );
      }
    });

    test('leaves a correctly attributed sentence where it is', () {
      // "What do you mean?" 7170-7920 is the boss, and already correct. It is
      // the closest call in the clip -- 0.250 against 0.133 -- which is what
      // sets the lower bound on the margin. A smaller margin moves this and
      // breaks it.
      final words = sentence(7170, 7920, 4);

      expect(assignSpeakers(words, alberta).toSet(), {0});
    });

    test('cannot rescue a turn the segmenter never reported', () {
      // "Tokens cost money." 7920-9400 is the employee, and comes out as the
      // boss. It is not a reconciliation failure: the only span touching this
      // interval is 0:7203-12552, and there is no employee activity anywhere
      // between 7861 and 12468. No rule over these spans can place a word on
      // a speaker the segmenter never reported, so this is pinned as a known
      // limit rather than left looking like a bug in the rule.
      final words = sentence(7920, 9400, 3);

      expect(
        assignSpeakers(words, alberta).toSet(),
        {0},
        reason: 'Documents the segmentation gap, not desired behaviour',
      );
    });

    test('ignores spurious short spans nested in a long turn', () {
      // `syria.mp4`, the opposite failure. Three stray employee activations
      // -- 658ms, 253ms and 1030ms -- sit inside one 7.6s span. Preferring
      // the shorter span let each steal words and flapped the transcript;
      // IoU scores them near zero because they cover almost none of the
      // sentence they land in.
      final syria = [
        span(31, 6562, 0),
        span(6562, 9751, 1),
        span(9667, 17277, 0),
        span(10527, 11185, 1),
        span(13666, 13919, 1),
        span(14695, 15725, 1),
      ];
      final words = sentence(9751, 17277, 20);

      expect(
        assignSpeakers(words, syria).toSet(),
        {0},
        reason: 'The dominant speaker keeps the sentence',
      );
    });

    test('a genuinely shared sentence is left to the per-word rule', () {
      // Two speakers holding half a sentence each score too close to act on,
      // which is what stops this pass flattening a real mid-sentence handover.
      final words = sentence(0, 4000, 8);
      final shared = [span(0, 2000, 0), span(2000, 4000, 1)];

      expect(assignSpeakers(words, shared).toSet(), {0, 1});
    });
  });
}
