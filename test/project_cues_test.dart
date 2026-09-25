import 'package:argand/core/captions/caption_cue.dart';
import 'package:argand/core/captions/project_cues.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/timeline/clip_trim.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/core/video/video_export.dart';
import 'package:flutter_test/flutter_test.dart';

MediaClip clip(
  String id,
  int durationMs,
  int position, {
  int? trimStartMs,
  int? trimEndMs,
}) =>
    MediaClip(
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
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
    );

/// One word per second-long slot, each ending a sentence so every word is its
/// own cue and the arithmetic stays readable.
List<Word> sentences(List<String> texts, {int fromMs = 0, String? speaker}) => [
      for (final (index, text) in texts.indexed)
        Word(
          id: '$text-$index',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          transcriptId: 't',
          position: index,
          word: '$text.',
          startMs: fromMs + index * 1000,
          endMs: fromMs + index * 1000 + 800,
          speakerId: speaker,
        ),
    ];

void main() {
  group('projectSubtitleCues', () {
    test('places the second clip after the first, on the project clock', () {
      final clips = [clip('a', 3000, 0), clip('b', 3000, 1)];
      final timeline = ProjectTimeline.fromClips(clips);

      final cues = projectSubtitleCues(
        timeline: timeline,
        clips: clips,
        wordsByClip: {
          'a': sentences(['One', 'Two', 'Three']),
          'b': sentences(['Four', 'Five', 'Six']),
        },
      );

      expect(cues.map((cue) => cue.text), [
        'One.', 'Two.', 'Three.', 'Four.', 'Five.', 'Six.',
      ]);
      // The whole point: "Four" starts where the second clip starts in the
      // exported video, not at zero where it starts in its own file.
      expect(cues[3].startMs, 3000);
      expect(cues[5].startMs, 5000);
    });

    test('follows a trim, dropping what was cut and rebasing the rest', () {
      // The second clip plays only 1s-3s of its file.
      final clips = [
        clip('a', 3000, 0),
        clip('b', 3000, 1, trimStartMs: 1000, trimEndMs: 3000),
      ];
      final timeline = ProjectTimeline.fromClips(clips);

      final cues = projectSubtitleCues(
        timeline: timeline,
        clips: clips,
        wordsByClip: {
          'a': sentences(['One', 'Two', 'Three']),
          'b': sentences(['Four', 'Five', 'Six']),
        },
      );

      expect(cues.map((cue) => cue.text), [
        'One.', 'Two.', 'Three.', 'Five.', 'Six.',
      ]);
      // "Five" is 1s into the file, which is the first moment the trimmed clip
      // plays -- so it lands exactly where the clip begins on the timeline.
      expect(cues[3].startMs, 3000);
    });

    test('breaks its lines exactly where the burned captions do', () {
      // SRT beside the exported video must show the captions the video already
      // has in it. Both come from the same step, so compare them directly.
      final clips = [clip('a', 3000, 0), clip('b', 3000, 1, trimStartMs: 500)];
      final timeline = ProjectTimeline.fromClips(clips);
      final words = {
        'a': sentences(['One', 'Two', 'Three']),
        'b': sentences(['Four', 'Five', 'Six']),
      };

      final subtitles = projectSubtitleCues(
        timeline: timeline,
        clips: clips,
        wordsByClip: words,
      );

      final burned = [
        for (final placement in timeline.placements)
          for (final caption in exportCaptionsFor(
            words[placement.clipId]!,
            window: clipWindow(clips.firstWhere((c) => c.id == placement.clipId)),
          ))
            (
              text: caption.text,
              startMs: caption.startMs + placement.startMs,
            ),
      ];

      expect(
        [for (final cue in subtitles) (text: cue.text, startMs: cue.startMs)],
        burned,
      );
    });

    test('cuts a cue short at its clip\'s out-point', () {
      // A word spoken across the cut would otherwise carry on over the next
      // clip, and a player pushes that clip's first caption late to make room.
      final clips = [
        clip('a', 3000, 0, trimEndMs: 2500),
        clip('b', 3000, 1),
      ];
      final timeline = ProjectTimeline.fromClips(clips);

      final cues = projectSubtitleCues(
        timeline: timeline,
        clips: clips,
        wordsByClip: {
          // "Three" starts at 2000 and would end at 2800.
          'a': sentences(['One', 'Two', 'Three']),
          'b': sentences(['Four']),
        },
      );

      final three = cues.firstWhere((cue) => cue.text == 'Three.');
      expect(three.endMs, 2500);
      expect(cues.firstWhere((cue) => cue.text == 'Four.').startMs, 2500);
    });

    test('an untranscribed clip still takes its place on the clock', () {
      final clips = [clip('a', 3000, 0), clip('b', 3000, 1)];
      final timeline = ProjectTimeline.fromClips(clips);

      final cues = projectSubtitleCues(
        timeline: timeline,
        clips: clips,
        wordsByClip: {'b': sentences(['Four'])},
      );

      expect(cues.single.startMs, 3000);
    });
  });

  group('SubtitleLineLength', () {
    // Forty characters: one line at the standard length, two at the short one.
    final cue = CaptionCue(
      words: const [],
      startMs: 0,
      endMs: 2000,
      text: 'forty characters of text on a line here!',
      speaker: null,
    );

    List<String> linesAt(SubtitleLineLength length) {
      final file = formatSubtitles(
        [cue],
        format: SubtitleFormat.srt,
        options: SubtitleOptions(maxLineCharacters: length.maxCharacters),
      );
      // Counter, timing, then the body up to the blank line that ends the cue.
      return file.split('\n').skip(2).takeWhile((l) => l.isNotEmpty).toList();
    }

    test('standard keeps a forty-character cue on one line', () {
      expect(linesAt(SubtitleLineLength.standard), hasLength(1));
    });

    test('short wraps it, for vertical video', () {
      final lines = linesAt(SubtitleLineLength.short);

      expect(lines, hasLength(2));
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(32));
      }
    });
  });
}
