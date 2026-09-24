import 'package:argand/core/captions/caption_cue.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/features/transcription/subtitle_export_controller.dart';
import 'package:argand/core/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a cue directly, so a test can state exactly the timing it means --
/// including the degenerate ones the grouper is documented to emit.
CaptionCue cue(String text, int startMs, int endMs, {int? speaker}) {
  final now = DateTime(2026);
  final words = [
    for (final (index, word) in text.split(' ').indexed)
      Word(
        id: 'w$index-$startMs',
        createdAt: now,
        updatedAt: now,
        transcriptId: 't1',
        position: index,
        word: word,
        startMs: startMs,
        endMs: endMs,
        speakerId: speaker?.toString(),
      ),
  ];
  // Bypasses `fromWords` so the span is exactly what the test asked for rather
  // than re-derived from the synthetic word timings.
  return CaptionCue(
    words: words,
    startMs: startMs,
    endMs: endMs,
    text: text,
    speaker: speaker,
  );
}

String label(CaptionCue cue) => 'Speaker ${cue.speaker! + 1}';

void main() {
  group('SRT', () {
    test('numbers cues from one and uses a comma before milliseconds', () {
      final out = formatSubtitles(
        [cue('Hello there', 1234, 2500), cue('World', 2600, 4000)],
        format: SubtitleFormat.srt,
      );

      expect(out, '''
1
00:00:01,234 --> 00:00:02,500
Hello there

2
00:00:02,600 --> 00:00:04,000
World

''');
    });

    test('writes hours for a long recording', () {
      final out = formatSubtitles(
        [cue('Late', 3661234, 3662000)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains('01:01:01,234 --> 01:01:02,000'));
    });

    test('prefixes the speaker when a label is supplied', () {
      final out = formatSubtitles(
        [cue('That is right', 0, 1000, speaker: 0)],
        format: SubtitleFormat.srt,
        speakerLabel: label,
      );

      expect(out, contains('Speaker 1: That is right'));
    });

    test('omits attribution when no label function is given', () {
      final out = formatSubtitles(
        [cue('That is right', 0, 1000, speaker: 0)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains('That is right'));
      expect(out, isNot(contains('Speaker')));
    });

    test('leaves an ampersand alone, because SubRip has no markup', () {
      final out = formatSubtitles(
        [cue('Bell & Co', 0, 1000)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains('Bell & Co'));
      expect(out, isNot(contains('&amp;')));
    });
  });

  group('VTT', () {
    test('opens with the WEBVTT header and uses a dot before milliseconds', () {
      final out = formatSubtitles(
        [cue('Hello there', 1234, 2500)],
        format: SubtitleFormat.vtt,
      );

      expect(out, '''
WEBVTT

00:00:01.234 --> 00:00:02.500
Hello there

''');
    });

    test('wraps a speaker in a voice span', () {
      final out = formatSubtitles(
        [cue('That is right', 0, 1000, speaker: 1)],
        format: SubtitleFormat.vtt,
        speakerLabel: label,
      );

      expect(out, contains('<v Speaker 2>That is right</v>'));
    });

    test('escapes markup characters that would break the cue', () {
      final out = formatSubtitles(
        [cue('Bell & <Co>', 0, 1000)],
        format: SubtitleFormat.vtt,
      );

      expect(out, contains('Bell &amp; &lt;Co&gt;'));
    });

    test('escapes a speaker name too', () {
      final out = formatSubtitles(
        [cue('Hi', 0, 1000, speaker: 0)],
        format: SubtitleFormat.vtt,
        speakerLabel: (_) => 'A & B',
        );

      expect(out, contains('<v A &amp; B>'));
    });

    test('an empty transcript is still a valid file', () {
      expect(
        formatSubtitles(const [], format: SubtitleFormat.vtt),
        'WEBVTT\n\n',
      );
      expect(formatSubtitles(const [], format: SubtitleFormat.srt), isEmpty);
    });
  });

  group('timing is forced into something a player accepts', () {
    test('a zero-length cue is given a minimum duration', () {
      // whisper's DTW alignment does emit these; `CaptionCue` documents the
      // same drift. A cue that ends where it starts is skipped by most players.
      final out = formatSubtitles(
        [cue('Blip', 5000, 5000)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains('00:00:05,000 --> 00:00:05,100'));
    });

    test('overlapping cues are pushed apart, never pulled earlier', () {
      final out = formatSubtitles(
        [cue('First', 1000, 3000), cue('Second', 2000, 4000)],
        format: SubtitleFormat.srt,
      );

      // The second cue starts after the first ends, and the first keeps its own
      // start -- a caption must never appear before the word it transcribes.
      expect(out, contains('00:00:01,000 --> 00:00:03,000'));
      expect(out, contains('00:00:03,001 --> 00:00:04,000'));
    });

    test('a cue starting before the previous one ends still moves forward', () {
      final out = formatSubtitles(
        [cue('First', 1000, 5000), cue('Second', 2000, 2500)],
        format: SubtitleFormat.srt,
      );

      // Pushed past the first cue and then given its minimum, rather than
      // emitted with an end before its start.
      expect(out, contains('00:00:05,001 --> 00:00:05,101'));
    });

    test('a negative timestamp clamps to zero rather than writing a minus', () {
      final out = formatSubtitles(
        [cue('Early', -500, 400)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains('00:00:00,000 --> 00:00:00,400'));
      // Not a bare `contains('-')` check: the `-->` separator is full of them.
      expect(out, isNot(matches(RegExp(r'-\d\d:\d\d:\d\d'))));
    });

    test('every emitted cue ends after it starts and follows the last', () {
      final out = formatSubtitles(
        [
          cue('a', 0, 0),
          cue('b', 0, 0),
          cue('c', 100, 50),
          cue('d', 10000, 12000),
        ],
        format: SubtitleFormat.vtt,
      );

      final stamps = RegExp(
        r'(\d\d):(\d\d):(\d\d)\.(\d\d\d) --> (\d\d):(\d\d):(\d\d)\.(\d\d\d)',
      ).allMatches(out);
      expect(stamps, hasLength(4));

      var previousEnd = -1;
      for (final match in stamps) {
        int at(int group) => int.parse(match.group(group)!);
        final start = at(1) * 3600000 + at(2) * 60000 + at(3) * 1000 + at(4);
        final end = at(5) * 3600000 + at(6) * 60000 + at(7) * 1000 + at(8);

        expect(end, greaterThan(start));
        expect(start, greaterThan(previousEnd));
        previousEnd = end;
      }
    });
  });

  group('line wrapping', () {
    test('a short cue stays on one line', () {
      final out = formatSubtitles(
        [cue('Short enough', 0, 1000)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains('\nShort enough\n'));
    });

    test('a long cue breaks into two balanced lines', () {
      const text =
          'This is a rather long caption line that will certainly need to wrap';
      final out = formatSubtitles(
        [cue(text, 0, 4000)],
        format: SubtitleFormat.srt,
      );

      final body = out.split('\n').where((l) => l.contains('caption') || l.contains('wrap'));
      expect(body, hasLength(2));
      for (final line in body) {
        expect(line.length, lessThanOrEqualTo(42));
      }
      // Balanced rather than greedy: neither line is left as an orphan.
      final lengths = body.map((l) => l.length).toList();
      expect((lengths.first - lengths.last).abs(), lessThan(20));
    });

    test('never exceeds the line budget, and never drops words', () {
      const text =
          'One two three four five six seven eight nine ten eleven twelve '
          'thirteen fourteen fifteen sixteen seventeen eighteen nineteen';
      final out = formatSubtitles(
        [cue(text, 0, 6000)],
        format: SubtitleFormat.srt,
      );

      // Text that will not fit in two lines overruns the last one rather than
      // being truncated -- losing a word from a transcript is never right.
      for (final word in text.split(' ')) {
        expect(out, contains(word));
      }
      final bodyLines =
          out.split('\n').where((l) => l.contains('One') || l.contains('nineteen'));
      expect(bodyLines.length, lessThanOrEqualTo(2));
    });

    test('a single unbreakable token is emitted rather than dropped', () {
      final long = 'x' * 90;
      final out = formatSubtitles(
        [cue(long, 0, 1000)],
        format: SubtitleFormat.srt,
      );

      expect(out, contains(long));
    });
  });

  _filenames();

  test('the formats declare distinct extensions and mime types', () {
    expect(SubtitleFormat.srt.extension, 'srt');
    expect(SubtitleFormat.vtt.extension, 'vtt');
    expect(SubtitleFormat.srt.mimeType, isNot(SubtitleFormat.vtt.mimeType));
  });
}

/// Filename construction, which is the one piece of the export path that has
/// to survive a hostile input: titles come from imported filenames.
void _filenames() {
  group('subtitleFileName', () {
    test('pairs the title with the language, as players expect', () {
      expect(
        subtitleFileName(
          title: 'interview',
          language: 'en',
          format: SubtitleFormat.srt,
        ),
        'interview.en.srt',
      );
    });

    test('strips characters a file system would reject', () {
      expect(
        subtitleFileName(
          title: r'a/b\c:d*e?f"g<h>i|j',
          language: 'en',
          format: SubtitleFormat.vtt,
        ),
        'a b c d e f g h i j.en.vtt',
      );
    });

    test('drops a trailing dot, which Windows will not open', () {
      expect(
        subtitleFileName(
          title: 'Mr. Smith.',
          language: 'en',
          format: SubtitleFormat.srt,
        ),
        'Mr. Smith.en.srt',
      );
    });

    test('falls back to a generic name when nothing usable is left', () {
      expect(
        subtitleFileName(title: '///', language: 'en', format: SubtitleFormat.srt),
        'transcript.en.srt',
      );
      expect(
        subtitleFileName(title: '   ', language: 'en', format: SubtitleFormat.srt),
        'transcript.en.srt',
      );
    });

    test('omits the language tag when none was detected', () {
      expect(
        subtitleFileName(title: 'clip', language: '', format: SubtitleFormat.srt),
        'clip.srt',
      );
    });

    test('truncates a very long title rather than producing an unwritable name',
        () {
      final name = subtitleFileName(
        title: 'word ' * 60,
        language: 'en',
        format: SubtitleFormat.srt,
      );

      expect(name.length, lessThanOrEqualTo(90));
      expect(name, endsWith('.en.srt'));
      expect(name, isNot(endsWith(' .en.srt')));
    });
  });
}
