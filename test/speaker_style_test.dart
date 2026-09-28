import 'package:argand/core/captions/caption_cue.dart';
import 'package:argand/core/captions/speaker_palette.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/transcript/speaker_names.dart';
import 'package:argand/core/video/video_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Word _word(String text, int startMs, int endMs, {String? speaker, int position = 0}) =>
    Word(
      id: '$text-$startMs',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      transcriptId: 't',
      position: position,
      word: text,
      startMs: startMs,
      endMs: endMs,
      speakerId: speaker,
    );

CaptionCue _cue(String text, int startMs, int endMs, int speaker) => CaptionCue(
      words: [_word(text, startMs, endMs, speaker: '$speaker')],
      startMs: startMs,
      endMs: endMs,
      text: text,
      speaker: speaker,
    );

void main() {
  group('speaker colours', () {
    test('a colour survives storage, with or without a name', () {
      final names = const SpeakerNames.empty()
          .withName(0, 'Ana')
          .withColor(0, 0xFFE53935)
          .withColor(1, 0xFF1E88E5);
      final read = SpeakerNames.decode(names.encode());
      expect(read[0], 'Ana');
      expect(read.colorOf(0), 0xFFE53935);
      expect(read[1], isNull);
      expect(read.colorOf(1), 0xFF1E88E5);
    });

    test('clearing a colour goes back to the palette', () {
      final names = const SpeakerNames.empty().withColor(2, 0xFF000000);
      expect(names.withColor(2, null).colorOf(2), isNull);
      expect(names.withColor(2, null).encode(), isNull);
    });

    test('a chosen colour wins over the palette, and stays readable on paper', () {
      expect(
        SpeakerPalette.colorFor(0, fallback: Colors.white, custom: 0xFF123456),
        const Color(0xFF123456),
      );
      final pale = SpeakerPalette.textColorFor(
        0,
        brightness: Brightness.light,
        fallback: Colors.black,
        custom: 0xFFFFF59D,
      );
      expect(HSLColor.fromColor(pale).lightness, lessThanOrEqualTo(0.401));
    });
  });

  group('names on the video', () {
    final words = [
      _word('Hello', 0, 400, speaker: '0'),
      _word('there.', 400, 900, speaker: '0', position: 1),
    ];

    test('no label unless names are asked for', () {
      expect(exportCaptionsFor(words).single.label, isNull);
    });

    test('the custom name and colour reach the render', () {
      final names = const SpeakerNames.empty()
          .withName(0, 'Ana')
          .withColor(0, 0xFFE53935);
      final caption = exportCaptionsFor(
        words,
        names: names,
        speakerLabel: (speaker) => 'Speaker ${speaker + 1}',
      ).single;
      expect(caption.label, 'Ana');
      expect(caption.colorArgb, 0xFFE53935);
    });

    test('an unnamed speaker is labelled by number', () {
      final caption = exportCaptionsFor(
        words,
        speakerLabel: (speaker) => 'Speaker ${speaker + 1}',
      ).single;
      expect(caption.label, 'Speaker 1');
    });
  });

  group('ASS', () {
    final cues = [
      _cue('Hi {there}', 1230, 3450, 0),
      _cue('Hello', 4000, 5000, 1),
      _cue('Again', 6000, 7000, 0),
    ];
    final ass = formatSubtitles(
      cues,
      format: SubtitleFormat.ass,
      speakerLabel: (cue) => cue.speaker == 0 ? 'Ana' : 'Omar',
      colorOf: (cue) => cue.speaker == 0 ? 0xFFE53935 : 0xFF1E88E5,
    );

    test('one style per speaker colour, in BGR order', () {
      expect(ass, contains('[Script Info]'));
      expect(ass, contains('Style: Speaker1,Arial,54,&H003539E5,'));
      expect(ass, contains('Style: Speaker2,Arial,54,&H00E5881E,'));
      expect(RegExp(r'^Style: ', multiLine: true).allMatches(ass), hasLength(2));
    });

    test('dialogue carries the time, style, name and escaped text', () {
      expect(
        ass,
        contains('Dialogue: 0,0:00:01.23,0:00:03.45,Speaker1,Ana,0,0,0,,Hi (there)'),
      );
      expect(ass, contains('Dialogue: 0,0:00:04.00,0:00:05.00,Speaker2,Omar,'));
    });
  });
}
