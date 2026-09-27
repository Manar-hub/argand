import 'package:argand/core/database/database.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/features/transcription/layer_transcription_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

MediaClip clip(String id, String path) => MediaClip(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: 'p',
      position: 0,
      mediaPath: path,
      durationMs: 30000,
      title: id,
      scale: 1,
      rotation: 0,
      offsetX: 0,
      offsetY: 0,
      audioStartOffsetMs: 0,
      audioEndOffsetMs: 0,
      audioMuted: false,
    );

ClipRange range(String clipId, int from, int to) => (
      clipId: clipId,
      clipStartMs: from,
      clipEndMs: to,
      projectStartMs: from,
      projectEndMs: to,
    );

WhisperTranscribeSegment segment(int fromMs, int toMs, String text) =>
    WhisperTranscribeSegment(
      fromTs: Duration(milliseconds: fromMs),
      toTs: Duration(milliseconds: toMs),
      text: text,
    );

void main() {
  group('groupContiguousRanges', () {
    final clips = {
      'a': clip('a', '/media/one.mp4'),
      'b': clip('b', '/media/one.mp4'),
      'c': clip('c', '/media/two.mp4'),
    };

    test('the two halves of a split are one recording', () {
      // **The whole point.** Splitting a clip does not make it two
      // recordings, and running the engine twice over it gave two independent
      // diarization runs -- so one person came back as two speakers.
      final groups = groupContiguousRanges(
        [range('a', 0, 6000), range('b', 6000, 14000)],
        clips,
      );

      expect(groups, hasLength(1));
      expect(groups.single.map((r) => r.clipId), ['a', 'b']);
    });

    test('a different file starts a new recording', () {
      final groups = groupContiguousRanges(
        [range('a', 0, 6000), range('c', 0, 5000)],
        clips,
      );

      expect(groups, hasLength(2));
    });

    test('a gap starts a new recording', () {
      // The audio between was deliberately cut out. Running across it would
      // transcribe words the project does not contain.
      final groups = groupContiguousRanges(
        [range('a', 0, 6000), range('b', 9000, 14000)],
        clips,
      );

      expect(groups, hasLength(2));
    });

    test('a clip that has vanished is skipped, not crashed on', () {
      final groups = groupContiguousRanges(
        [range('gone', 0, 6000), range('a', 0, 6000)],
        clips,
      );

      expect(groups, hasLength(1));
      expect(groups.single.single.clipId, 'a');
    });

    test('nothing in, nothing out', () {
      expect(groupContiguousRanges(const [], clips), isEmpty);
    });
  });

  group('segmentsWithin', () {
    final whole = WhisperTranscribeResponse(
      type: 'transcribe',
      text: 'one two three',
      detectedLanguage: 'en',
      segments: [
        segment(0, 900, ' one'),
        segment(6000, 6900, ' two'),
        segment(12000, 12900, ' three'),
      ],
    );

    test('shares the run out by time', () {
      final first = segmentsWithin(whole, fromMs: 0, toMs: 6000);
      final second = segmentsWithin(whole, fromMs: 6000, toMs: 14000);

      expect(first.segments!.map((s) => s.text.trim()), ['one']);
      expect(second.segments!.map((s) => s.text.trim()), ['two', 'three']);
    });

    test('a segment on the cut belongs to the clip after it', () {
      // Half-open, like every other interval here, so no word is stored twice.
      final first = segmentsWithin(whole, fromMs: 0, toMs: 6000);

      expect(first.segments!.any((s) => s.text.contains('two')), isFalse);
    });

    test('every word lands in exactly one clip', () {
      final first = segmentsWithin(whole, fromMs: 0, toMs: 6000);
      final second = segmentsWithin(whole, fromMs: 6000, toMs: 14000);

      expect(
        first.segments!.length + second.segments!.length,
        whole.segments!.length,
        reason: 'sharing the run out must neither lose nor duplicate words',
      );
    });

    test('the text follows the segments it kept', () {
      expect(segmentsWithin(whole, fromMs: 6000, toMs: 14000).text,
          'two three');
    });

    test('the detected language is carried, not re-guessed', () {
      // One run detected it once; each clip's share reports the same answer
      // rather than looking like an independent transcription.
      expect(
        segmentsWithin(whole, fromMs: 0, toMs: 6000).detectedLanguage,
        'en',
      );
    });
  });
}
