import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/item_look.dart';
import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/timeline_history.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  group('ItemLook', () {
    test('round-trips through storage', () {
      const look = ItemLook(
        font: LookFont.anton,
        colorArgb: 0xFF00FF00,
        mode: CaptionMode.karaoke,
        highlightArgb: 0xFFFF0000,
        highlightBox: false,
        backgroundArgb: 0x80000000,
        shadow: 0.75,
      );
      expect(ItemLook.decode(look.encode()), look);
    });

    test('by default, plain words over a soft shadow', () {
      expect(ItemLook.defaults.backgroundArgb, isNull);
      expect(ItemLook.defaults.shadow, greaterThan(0));
    });

    test('a look saved before shadows existed gets the default one', () {
      final look = ItemLook.decode('{"font":"anton","mode":"standard"}')!;
      expect(look.shadow, ItemLook.defaultShadow);
      expect(look.backgroundArgb, isNull);
    });

    test('a background can be set back to none', () {
      const boxed = ItemLook(backgroundArgb: 0xFF000000);
      expect(boxed.copyWith(backgroundArgb: () => null).backgroundArgb, isNull);
    });

    test('nothing stored is no look of its own', () {
      expect(ItemLook.decode(null), isNull);
    });

    test('an unknown value falls back rather than failing', () {
      final look = ItemLook.decode('{"font":"comicSans","mode":"karaoke"}')!;
      expect(look.font, LookFont.standard);
      expect(look.mode, CaptionMode.karaoke);
    });

    test('a colour can be set back to the default', () {
      const red = ItemLook(colorArgb: 0xFFFF0000);
      expect(red.copyWith(colorArgb: () => null).colorArgb, isNull);
    });
  });

  group('captionShadowFor', () {
    test('none at zero', () {
      expect(captionShadowFor(0, 40), isNull);
    });

    test('stronger is darker and wider, and scales with the words', () {
      final soft = captionShadowFor(0.2, 40)!;
      final strong = captionShadowFor(1, 40)!;
      expect(strong.argb >>> 24, greaterThan(soft.argb >>> 24));
      expect(strong.blur, greaterThan(soft.blur));
      expect(captionShadowFor(1, 80)!.blur, closeTo(strong.blur * 2, 1e-9));
      // Full strength is opaque black, never beyond it.
      expect(captionShadowFor(5, 40)!.argb, 0xFF000000);
    });
  });

  group('captionRunsAt', () {
    const words = <TimedText>[
      (text: 'one', startMs: 0, endMs: 400),
      (text: 'two', startMs: 500, endMs: 900),
      (text: 'three', startMs: 1000, endMs: 1400),
    ];

    test('standard shows the line, unmarked', () {
      expect(captionRunsAt(words, 600, CaptionMode.standard), [
        (text: 'one two three', marked: false),
      ]);
    });

    test('karaoke marks what has been said', () {
      final runs = captionRunsAt(words, 600, CaptionMode.karaoke);
      expect(runs.map((r) => r.marked), [true, true, false]);
    });

    test('highlight marks only the word being said', () {
      final runs = captionRunsAt(words, 600, CaptionMode.highlight);
      expect(runs.map((r) => r.marked), [false, true, false]);

      // In the pause between words, nothing is being said.
      final gap = captionRunsAt(words, 950, CaptionMode.highlight);
      expect(gap.every((r) => !r.marked), isTrue);
    });

    test('word by word shows one word, holding it through a pause', () {
      expect(captionRunsAt(words, 600, CaptionMode.wordByWord).single.text,
          'two');
      expect(captionRunsAt(words, 950, CaptionMode.wordByWord).single.text,
          'two', reason: 'the caption must not blink off between words');
      expect(captionRunsAt(words, 0, CaptionMode.wordByWord).single.text,
          'one');
    });
  });

  group('restyling', () {
    late AppDatabase database;
    late TranscriptRepository repository;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TranscriptRepository(database, MediaConverter());
    });

    tearDown(() => database.close());

    /// A project whose one layer holds "Hello there. Bye now."
    Future<({String projectId, String layerId, String transcriptId})>
        seeded() async {
      final projectId = repository.newId();
      final clipId = repository.newId();
      await database.createEmptyProject(projectId: projectId, title: 'p');
      await database.appendClip(
        clipId: clipId,
        projectId: projectId,
        mediaPath: '/tmp/a.mp4',
        title: 'a',
        duration: const Duration(seconds: 10),
      );
      final layerId = (await repository.addLayer(
        projectId: projectId,
        startMs: 0,
        endMs: 10000,
      ))!;

      WhisperTranscribeSegment segment(int from, int to, String text) =>
          WhisperTranscribeSegment(
            fromTs: Duration(milliseconds: from),
            toTs: Duration(milliseconds: to),
            text: text,
          );
      final transcriptId = await repository.saveClipTranscript(
        projectId: projectId,
        clipId: clipId,
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        layerId: layerId,
        result: WhisperTranscribeResponse(
          type: 'transcribe',
          text: 'Hello there. Bye now.',
          segments: [
            segment(0, 400, ' Hello'),
            segment(400, 800, ' there.'),
            segment(1200, 1600, ' Bye'),
            segment(1600, 2000, ' now.'),
          ],
        ),
      );
      return (
        projectId: projectId,
        layerId: layerId,
        transcriptId: transcriptId,
      );
    }

    test('one sentence styled alone, then undone back to its layer',
        () async {
      final ids = await seeded();
      final first = sentenceItem(
        transcriptId: ids.transcriptId,
        fromPosition: 0,
        toPosition: 1,
      );
      const karaoke = ItemLook(mode: CaptionMode.karaoke);

      await repository.applyLooks(
        projectId: ids.projectId,
        changes: [
          (kind: first.kind, id: first.id, before: null, after: karaoke),
        ],
      );

      final words = await repository.watchWords(ids.transcriptId).first;
      expect(words[0].ownLook, karaoke);
      expect(words[1].ownLook, karaoke);
      expect(words[2].ownLook, isNull, reason: 'the other sentence');

      await repository.undoProject(ids.projectId);
      expect(
        (await repository.watchWords(ids.transcriptId).first)[0].ownLook,
        isNull,
      );
    });

    test('all captions restyles the layer and brings every sentence into line',
        () async {
      final ids = await seeded();
      final first = sentenceItem(
        transcriptId: ids.transcriptId,
        fromPosition: 0,
        toPosition: 1,
      );
      await repository.applyLooks(
        projectId: ids.projectId,
        changes: [
          (
            kind: first.kind,
            id: first.id,
            before: null,
            after: const ItemLook(font: LookFont.bangers),
          ),
        ],
      );

      const anton = ItemLook(font: LookFont.anton);
      await repository.applyLooks(
        projectId: ids.projectId,
        changes: [
          (
            kind: TimelineItemKind.layer,
            id: ids.layerId,
            before: null,
            after: anton,
          ),
        ],
        resetSentencesIn: [ids.transcriptId],
      );

      expect((await database.findLayer(ids.layerId))!.look, anton);
      var words = await repository.watchWords(ids.transcriptId).first;
      expect(words.every((w) => w.ownLook == null), isTrue);

      // One undo puts back both the layer and the sentence's own look.
      await repository.undoProject(ids.projectId);
      expect((await database.findLayer(ids.layerId))!.look, isNull);
      words = await repository.watchWords(ids.transcriptId).first;
      expect(words[0].ownLook, const ItemLook(font: LookFont.bangers));
    });

    test('a retyped sentence keeps its look', () async {
      final ids = await seeded();
      final first = sentenceItem(
        transcriptId: ids.transcriptId,
        fromPosition: 0,
        toPosition: 1,
      );
      const look = ItemLook(colorArgb: 0xFF00FFFF);
      await repository.applyLooks(
        projectId: ids.projectId,
        changes: [(kind: first.kind, id: first.id, before: null, after: look)],
      );

      await repository.replaceSentence(
        transcriptId: ids.transcriptId,
        fromPosition: 0,
        toPosition: 1,
        text: 'Hi there friend.',
      );

      final words = await repository.watchWords(ids.transcriptId).first;
      expect(words.take(3).every((w) => w.ownLook == look), isTrue);
    });
  });
}
