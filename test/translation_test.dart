import 'package:argand/core/captions/caption_cue.dart';
import 'package:argand/core/captions/subtitle_export.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/core/timeline/translation_texts.dart';
import 'package:argand/core/transcript/translation_sentences.dart';
import 'package:argand/core/translation/translator.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart' show TextDirection;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Translates by upper-casing and tagging, so a test can see which sentence
/// went where. Knows English and Spanish; can be told to fail downloads.
class _FakeTranslator implements Translator {
  final downloaded = <String>{'en'};
  final calls = <List<String>>[];
  bool offline = false;

  @override
  List<TranslationLanguage> get languages => const [
        TranslationLanguage('en', 'English'),
        TranslationLanguage('es', 'Spanish'),
      ];

  @override
  Future<bool> isDownloaded(String code) async => downloaded.contains(code);

  @override
  Future<void> download(String code) async {
    if (offline) {
      throw const TranslationException(TranslationFailure.downloadFailed);
    }
    downloaded.add(code);
  }

  @override
  Future<void> delete(String code) async => downloaded.remove(code);

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async {
    calls.add(texts);
    return [for (final text in texts) '$to:${text.toUpperCase()}'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });
  tearDown(() => database.close());

  /// One project, one clip, saying [words] one per 500ms, in English.
  Future<({String clipId, String transcriptId})> transcribed(
    List<String> words,
  ) async {
    final projectId = repository.newId();
    final clipId = repository.newId();
    await repository.saveImport(
      projectId: projectId,
      clipId: clipId,
      title: 'talk',
      mediaPath: '/tmp/talk.mp4',
      duration: const Duration(seconds: 30),
      language: TranscriptionLanguage.english,
      speakerSpans: const [],
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: words.join(' '),
        segments: [
          for (final (i, word) in words.indexed)
            WhisperTranscribeSegment(
              fromTs: Duration(milliseconds: i * 500),
              toTs: Duration(milliseconds: i * 500 + 400),
              text: ' $word',
            ),
        ],
      ),
    );
    final transcript = (await repository.transcriptsForClip(clipId)).single;
    return (clipId: clipId, transcriptId: transcript.id);
  }

  group('translatableSentencesOf', () {
    test('cuts at sentence ends, keeping each sentence\'s time and words', () {
      final sentences = translatableSentencesOf([
        (text: 'Hello', startMs: 0, endMs: 400, position: 0),
        (text: 'there.', startMs: 500, endMs: 900, position: 1),
        (text: 'Bye', startMs: 1000, endMs: 1400, position: 2),
        (text: 'now', startMs: 1500, endMs: 1900, position: 3),
      ]);

      expect(sentences.map((s) => s.text), ['Hello there.', 'Bye now']);
      expect(sentences.first.startMs, 0);
      expect(sentences.first.endMs, 900);
      expect(sentences.last.firstWord, 2);
      expect(sentences.last.lastWord, 3);
    });
  });

  group('alignTranslation', () {
    TranslatableSentence s(String text, int start, int end, int first, int last) =>
        (text: text, startMs: start, endMs: end, firstWord: first, lastWord: last);

    test("as many sentences as the source: each takes its sentence's place",
        () {
      final placed = alignTranslation(
        source: [s('Hi there.', 0, 900, 0, 1), s('Bye now.', 2000, 2900, 2, 3)],
        translated: 'Hola. Adiós.',
      );
      expect(placed.map((p) => p.text), ['Hola.', 'Adiós.']);
      expect(placed.last.startMs, 2000);
      expect(placed.last.firstWord, 2);
    });

    test('fewer sentences are spread along the speech by their share of it',
        () {
      final placed = alignTranslation(
        source: [
          s('One two three.', 0, 1000, 0, 2),
          s('Four five six.', 1000, 2000, 3, 5),
          s('Seven eight nine.', 3000, 4000, 6, 8),
        ],
        translated: 'Uno dos tres cuatro cinco seis. Siete ocho nueve.',
      );
      expect(placed, hasLength(2));
      expect(placed.first.startMs, 0);
      // The second starts well into the source and ends where speech ends.
      expect(placed.last.startMs, greaterThan(1500));
      expect(placed.last.endMs, 4000);
      expect(placed.last.lastWord, 8);
      expect(placed.first.endMs, placed.last.startMs);
    });

    test('splits on Arabic and CJK sentence marks too', () {
      expect(splitTranslatedSentences('مرحبا؟ نعم. 你好。好！'),
          ['مرحبا؟', 'نعم.', '你好。', '好！']);
      expect(splitTranslatedSentences('It costs 3.5 dollars. Fine'),
          ['It costs 3.5 dollars.', 'Fine']);
    });

    test('long transcripts go in runs cut at sentence ends', () {
      final sentences = [for (var i = 0; i < 5; i++) s('x' * 30, i, i + 1, i, i)];
      final batches = translationBatches(sentences, maxCharacters: 70);
      expect(batches.map((b) => b.length), [2, 2, 1]);
    });
  });

  group('TranscriptRepository.translateAll', () {
    test('keeps one line per sentence beside the transcript', () async {
      final t = await transcribed(['Hello', 'there.', 'Bye', 'now.']);
      final translator = _FakeTranslator();

      final failure = await repository.translateAll(
        transcriptIds: [t.transcriptId],
        to: 'es',
        translator: translator,
      );

      expect(failure, isNull);
      expect(translator.downloaded, contains('es'));
      final lines = await database.translationLinesFor(t.transcriptId);
      // The whole text went in one call, and came back cut into sentences.
      expect(translator.calls, [
        ['Hello there. Bye now.'],
      ]);
      expect(lines.map((l) => l.content), ['es:HELLO THERE.', 'BYE NOW.']);
      expect(lines.map((l) => l.language).toSet(), {'es'});
      expect(lines.last.startMs, 1000);
      expect(lines.last.endMs, 1900);
      expect(lines.last.firstWord, 2);

      // The transcript is untouched.
      final words = await repository.watchWords(t.transcriptId).first;
      expect(words.map((w) => w.word), ['Hello', 'there.', 'Bye', 'now.']);
    });

    test('translating again replaces the lines', () async {
      final t = await transcribed(['Hello.']);
      final translator = _FakeTranslator();

      await repository.translateAll(
          transcriptIds: [t.transcriptId], to: 'es', translator: translator);
      await repository.translateAll(
          transcriptIds: [t.transcriptId], to: 'en', translator: translator);

      final lines = await database.translationLinesFor(t.transcriptId);
      expect(lines.map((l) => l.content), ['en:HELLO.']);
    });

    test('a pack that cannot download says so and writes nothing', () async {
      final t = await transcribed(['Hello.']);
      final translator = _FakeTranslator()..offline = true;

      final failure = await repository.translateAll(
        transcriptIds: [t.transcriptId],
        to: 'es',
        translator: translator,
      );

      expect(failure, TranslationFailure.downloadFailed);
      expect(await database.translationLinesFor(t.transcriptId), isEmpty);
    });

    test('removing the translation leaves the transcript', () async {
      final t = await transcribed(['Hello.']);
      await repository.translateAll(
        transcriptIds: [t.transcriptId],
        to: 'es',
        translator: _FakeTranslator(),
      );

      await repository.removeTranslation(t.transcriptId);

      expect(await database.translationLinesFor(t.transcriptId), isEmpty);
      expect(await repository.watchWords(t.transcriptId).first, hasLength(1));
    });
  });

  test('translation lines become texts in project time, above the captions',
      () async {
    final t = await transcribed(['Hello', 'there.', 'Bye.']);
    await repository.translateAll(
      transcriptIds: [t.transcriptId],
      to: 'es',
      translator: _FakeTranslator(),
    );
    final clips = await repository.clipsForProject(
      (await database.findTranscript(t.transcriptId))!.projectId,
    );

    final texts = translationTextsFor(
      timeline: ProjectTimeline.fromClips(clips),
      projectId: clips.single.projectId,
      clipId: t.clipId,
      lines: await database.translationLinesFor(t.transcriptId),
    );

    expect(texts.map((x) => x.content), ['es:HELLO THERE.', 'BYE.']);
    expect(texts.first.startMs, 0);
    expect(texts.last.startMs, 1000);
    expect(texts.first.y, closeTo(-0.82 + translationLift, 1e-9));
    expect(texts.first.id, startsWith(translationTextPrefix));
  });

  test('Arabic and Hebrew translations read right to left', () {
    expect(translationDirectionOf('مرحبا.'), TextDirection.rtl);
    expect(translationDirectionOf('"שלום"'), TextDirection.rtl);
    expect(translationDirectionOf('19 años'), TextDirection.ltr);
    expect(translationDirectionOf('...'), TextDirection.ltr);
  });

  test('a long translation is cut into caption-sized pieces', () {
    final chunks = translationChunks(
      'one two three four five six seven eight nine ten eleven twelve',
      maxCharacters: 20,
    );
    expect(chunks.map((c) => c.$1), [
      'one two three four',
      'five six seven eight',
      'nine ten eleven',
      'twelve',
    ]);
    expect(chunks.every((c) => c.$1.length <= 20), isTrue);
  });

  test('subtitles carry a translation on the line under the cue', () {
    final cue = CaptionCue(
      words: [],
      startMs: 0,
      endMs: 1000,
      text: 'Hello there.',
      speaker: null,
    );
    final srt = formatSubtitles(
      [cue],
      format: SubtitleFormat.srt,
      translation: (_) => 'Hola.',
    );
    expect(srt, contains('Hello there.\nHola.\n'));
  });
}
