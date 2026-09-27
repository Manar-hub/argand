import 'package:argand/core/database/database.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/core/timeline/timeline_sentences.dart';
import 'package:flutter_test/flutter_test.dart';

MediaClip clip(String id, int? durationMs, int position) => MediaClip(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: 'p',
      position: position,
      mediaPath: '/media/$id.mp4',
      durationMs: durationMs,
      title: id,
      scale: 1,
      rotation: 0,
      offsetX: 0,
      offsetY: 0,
      audioStartOffsetMs: 0,
      audioEndOffsetMs: 0,
      audioMuted: false,
    );

SentenceWord word(String text, int startMs, int endMs, [String? speaker]) =>
    (
      text: text,
      startMs: startMs,
      endMs: endMs,
      speakerId: speaker,
      position: startMs,
    );

void main() {
  group('sentencesForClip', () {
    final timeline = ProjectTimeline.fromClips([
      clip('a', 10000, 0),
      clip('b', 5000, 1),
    ]);

    test('cuts on sentence endings and joins the words back', () {
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'a',
        transcriptId: 't1',
        words: [
          word('Hello', 0, 400),
          word('there.', 400, 900),
          word('Again', 1000, 1400),
          word('now.', 1400, 1900),
        ],
      );

      expect(sentences.map((s) => s.text), ['Hello there.', 'Again now.']);
    });

    test('places the first clip at its own times', () {
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'a',
        transcriptId: 't1',
        words: [word('One.', 500, 900)],
      );

      expect(sentences.single.projectStartMs, 500);
      expect(sentences.single.projectEndMs, 900);
    });

    test('offsets a later clip by everything before it', () {
      // The failure this catches is silent: clip-relative times drawn as if
      // they were project times put every sentence of clip two on top of clip
      // one, and each box still looks perfectly plausible where it lands.
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'b',
        transcriptId: 't2',
        words: [word('Later.', 500, 900)],
      );

      expect(sentences.single.projectStartMs, 10500);
      expect(sentences.single.projectEndMs, 10900);
    });

    test('takes the speaker from the sentence first word', () {
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'a',
        transcriptId: 't1',
        words: [
          word('Mine.', 0, 400, '2'),
          // A handover mid-sentence is attributed to whoever began it, the
          // same call the caption grouper makes.
          word('Yours', 400, 800, '1'),
          word('too.', 800, 1200, '3'),
        ],
      );

      expect(sentences.map((s) => s.speaker), [2, 1]);
    });

    test('a transcript with no speaker information has none', () {
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'a',
        transcriptId: 't1',
        words: [word('Quiet.', 0, 400)],
      );

      expect(sentences.single.speaker, isNull);
    });

    test('drops sentences whose clip is not on the timeline', () {
      // A clip removed from under a transcript. Placing it at zero would put
      // it over some other clip's audio and claim to describe it.
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'gone',
        transcriptId: 't1',
        words: [word('Orphan.', 0, 400)],
      );

      expect(sentences, isEmpty);
    });

    test('no words yields no sentences', () {
      expect(
        sentencesForClip(
          timeline: timeline,
          clipId: 'a',
          transcriptId: 't1',
          words: const [],
        ),
        isEmpty,
      );
    });

    test('closes a final run that carries no terminator', () {
      // Speech that trails off unpunctuated is still a sentence; dropping it
      // would silently omit the end of every transcript.
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'a',
        transcriptId: 't1',
        words: [word('Done.', 0, 400), word('and', 500, 700)],
      );

      expect(sentences.map((s) => s.text), ['Done.', 'and']);
    });

    test('carries the transcript it came from', () {
      // The box has to know which transcript to open when it is tapped; a
      // clip with two layers has two, covering different ranges.
      final sentences = sentencesForClip(
        timeline: timeline,
        clipId: 'a',
        transcriptId: 'second-range',
        words: [word('Hi.', 4000, 4400)],
      );

      expect(sentences.single.transcriptId, 'second-range');
      expect(sentences.single.clipId, 'a');
    });
  });
}
