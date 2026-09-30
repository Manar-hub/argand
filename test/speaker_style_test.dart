import 'package:argand/core/captions/caption_cue.dart';
import 'package:argand/core/captions/speaker_palette.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/transcript/speaker_names.dart';
import 'package:argand/core/timeline/translation_texts.dart';
import 'package:argand/core/video/video_export.dart';
import 'package:argand/features/transcription/video_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

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

  group('XML formats', () {
    final cues = [
      _cue('Tom & <Jerry>', 1000, 2500, 0),
      _cue('Hello', 3000, 4000, 1),
    ];
    String write(SubtitleFormat format) => formatSubtitles(
          cues,
          format: format,
          title: 'My "clip"',
          language: 'en',
          speakerLabel: (cue) => cue.speaker == 0 ? 'Ana' : 'Omar',
          colorOf: (cue) => cue.speaker == 0 ? 0xFFE53935 : 0xFF1E88E5,
          translation: (cue) => cue.speaker == 1 ? 'Hallo' : null,
        );

    test('every one is well formed', () {
      for (final format in [
        SubtitleFormat.ttml,
        SubtitleFormat.fcpxml,
        SubtitleFormat.premiereXml,
      ]) {
        expect(() => XmlDocument.parse(write(format)), returnsNormally,
            reason: format.name);
      }
    });

    test('TTML: times, colours, speakers and translation', () {
      final doc = XmlDocument.parse(write(SubtitleFormat.ttml));
      final ps = doc.findAllElements('p').toList();
      expect(ps, hasLength(2));
      expect(ps[0].getAttribute('begin'), '00:00:01.000');
      expect(ps[0].getAttribute('end'), '00:00:02.500');
      expect(ps[0].innerText, 'Tom & <Jerry>');
      expect(ps[1].findElements('br'), hasLength(1));
      expect(ps[1].innerText, 'HelloHallo');
      final styles = doc.findAllElements('style').toList();
      expect(styles.map((s) => s.getAttribute('tts:color')),
          ['#E53935', '#1E88E5']);
      expect(doc.findAllElements('ttm:name').map((n) => n.innerText),
          ['Ana', 'Omar']);
    });

    test('FCPXML: captions on frames, named and coloured', () {
      final doc = XmlDocument.parse(write(SubtitleFormat.fcpxml));
      expect(doc.findAllElements('project').single.getAttribute('name'),
          'My "clip"');
      final captions = doc.findAllElements('caption').toList();
      expect(captions, hasLength(2));
      expect(captions[0].getAttribute('offset'), '3000/3000s');
      expect(captions[0].getAttribute('duration'), '4500/3000s');
      expect(captions[0].getAttribute('name'), 'Ana');
      expect(captions[0].getAttribute('role'), 'iTT?captionFormat=ITT.en');
      expect(
        captions[1].findAllElements('text-style').first.innerText,
        'Hello\nHallo',
      );
      expect(
        captions[1].findAllElements('text-style').last.getAttribute('fontColor'),
        '0.118 0.533 0.898 1',
      );
    });

    test('Premiere XML: text clips at frame positions', () {
      final doc = XmlDocument.parse(write(SubtitleFormat.premiereXml));
      final clips = doc.findAllElements('generatoritem').toList();
      expect(clips, hasLength(2));
      expect(clips[0].getElement('start')!.innerText, '30');
      expect(clips[0].getElement('end')!.innerText, '75');
      expect(clips[1].getElement('name')!.innerText, 'Omar');
      final text = clips[0]
          .findAllElements('parameter')
          .firstWhere((p) => p.getElement('parameterid')!.innerText == 'str');
      expect(text.getElement('value')!.innerText, 'Tom & <Jerry>');
    });

    test('only SRT and VTT are free', () {
      expect(
        SubtitleFormat.values.where((f) => !f.isPro),
        [SubtitleFormat.srt, SubtitleFormat.vtt],
      );
    });
  });

  group('translation lines', () {
    test('are spoken by whoever says their first word', () {
      final words = [
        _word('Hi', 0, 300, speaker: '0'),
        _word('there', 300, 600, speaker: '2', position: 1),
      ];
      final line = TranslationLine(
        id: 'l',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        transcriptId: 't',
        language: 'de',
        position: 0,
        firstWord: 1,
        lastWord: 1,
        startMs: 300,
        endMs: 600,
        content: 'da',
      );
      expect(speakerOfTranslation(line, words), 2);
    });
  });

  group('safe zone', () {
    test('matches the 1080x1920 template', () {
      final rects = unsafeRects(const Size(1080, 1920));
      expect(rects[0], const Rect.fromLTRB(0, 0, 1080, 254));
      expect(rects[1], const Rect.fromLTRB(0, 1539, 1080, 1920));
      expect(rects[2], const Rect.fromLTRB(0, 254, 120, 1539));
      expect(rects[3], const Rect.fromLTRB(951, 254, 1080, 720));
      expect(rects[4], const Rect.fromLTRB(879, 720, 1080, 1539));
    });

    test('scales with the stage', () {
      final rects = unsafeRects(const Size(108, 192));
      expect(rects[0].height, closeTo(25.4, 0.01));
      expect(rects[2].width, closeTo(12, 0.01));
    });
  });
}
