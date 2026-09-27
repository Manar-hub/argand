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

    test('every source gets a piece, even when the translator merged two',
        () {
      final placed = alignTranslation(
        source: [
          s('One two three.', 0, 1000, 0, 2),
          s('Four five six.', 1000, 2000, 3, 5),
          s('Seven eight nine.', 3000, 4000, 6, 8),
        ],
        translated: 'Uno dos tres, cuatro cinco seis. Siete ocho nueve.',
      );
      expect(placed.map((p) => p.text), [
        'Uno dos tres,',
        'cuatro cinco seis.',
        'Siete ocho nueve.',
      ]);
      // Each takes its source's time and words exactly.
      expect(placed[1].startMs, 1000);
      expect(placed[1].lastWord, 5);
    });

    test('splits on Arabic and CJK sentence marks too', () {
      expect(splitTranslatedSentences('مرحبا؟ نعم. 你好。好！'),
          ['مرحبا؟', 'نعم.', '你好。', '好！']);
      expect(splitTranslatedSentences('It costs 3.5 dollars. Fine'),
          ['It costs 3.5 dollars.', 'Fine']);
    });

    test('long transcripts go in runs cut at sentence ends', () {
      final sentences = [
        for (var i = 0; i < 5; i++) s('${'x' * 29}.', i, i + 1, i, i),
      ];
      final batches = translationBatches(sentences, maxCharacters: 70);
      expect(batches.map((b) => b.length), [2, 2, 1]);
    });
  });

  group('alignToSegments', () {
    // The demo's caption lines, as `groupIntoCues` cuts them.
    const demo = [
      "Hey, I'm potato",
      "Um, and I'm Verune.",
      'Oh, shoot.',
      "We're not building a company.",
      "We're building freedom.",
      "I'm a senior at MIT.",
    ];

    test('matching punctuation: each line its own sentence', () {
      final pieces = alignToSegments(
        sources: demo,
        translated: 'Hey, ich bin Potato. Äh, und ich bin Verune. Oh, Mist. '
            'Wir bauen keine Firma. Wir bauen Freiheit. '
            'Ich bin im letzten Jahr am MIT.',
      );
      expect(pieces, [
        'Hey, ich bin Potato.',
        'Äh, und ich bin Verune.',
        'Oh, Mist.',
        'Wir bauen keine Firma.',
        'Wir bauen Freiheit.',
        'Ich bin im letzten Jahr am MIT.',
      ]);
    });

    test('merged sentences are cut where the second one would start', () {
      final pieces = alignToSegments(
        sources: demo.sublist(3, 5),
        translated: 'Wir bauen keine Firma, wir bauen Freiheit.',
      );
      expect(pieces, ['Wir bauen keine Firma,', 'wir bauen Freiheit.']);
    });

    test('a sentence split in two stays with its line', () {
      final pieces = alignToSegments(
        sources: const ['Oh, shoot.', "We're not building a company."],
        translated: 'Oh. Mist. Wir bauen keine Firma.',
      );
      expect(pieces, ['Oh. Mist.', 'Wir bauen keine Firma.']);
    });

    test('Arabic, right to left, cuts at its own marks', () {
      final pieces = alignToSegments(
        sources: demo.sublist(2, 5),
        translated: 'أوه، تبا. نحن لا نبني شركة. نحن نبني الحرية.',
      );
      expect(pieces, ['أوه، تبا.', 'نحن لا نبني شركة.', 'نحن نبني الحرية.']);
    });

    test('a script without spaces is cut between characters', () {
      final pieces = alignToSegments(
        sources: demo.sublist(3, 5),
        translated: '我们不是在建立一家公司。我们在建立自由。',
      );
      expect(pieces, ['我们不是在建立一家公司。', '我们在建立自由。']);
    });

    test('no line is empty while there are words to go round', () {
      final pieces = alignToSegments(
        sources: demo,
        translated: 'Hallo zusammen, wir sind hier und wir bauen etwas.',
      );
      expect(pieces.every((p) => p.isNotEmpty), isTrue);
      expect(pieces.join(' '),
          'Hallo zusammen, wir sind hier und wir bauen etwas.');
    });

    test('too few words: the rest go empty, never repeated', () {
      final pieces = alignToSegments(sources: demo, translated: 'Ja. Nein.');
      expect(pieces.where((p) => p.isNotEmpty), ['Ja.', 'Nein.']);
      expect(pieces, hasLength(demo.length));
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

    test('a selection translates only its sentences, keeping the rest',
        () async {
      final t = await transcribed(['Hello.', 'Bye', 'now.', 'See', 'you.']);
      final translator = _FakeTranslator();
      await repository.translateAll(
        transcriptIds: [t.transcriptId],
        to: 'es',
        translator: translator,
      );

      // Only "Bye now." -- words 1..2 -- into English this time.
      translator.calls.clear();
      await repository.translateAll(
        transcriptIds: [t.transcriptId],
        to: 'en',
        translator: translator,
        ranges: {
          t.transcriptId: [(from: 1, to: 2)],
        },
      );

      expect(translator.calls, [
        ['Bye now.'],
      ]);
      final lines = await database.translationLinesFor(t.transcriptId);
      expect(lines.map((l) => l.content), [
        'es:HELLO.',
        'en:BYE NOW.',
        'SEE YOU.',
      ]);
    });

    test('a caption row is retyped, added and cleared on its own, each undone',
        () async {
      final t = await transcribed(['Hello.', 'Bye', 'now.']);
      await repository.translateAll(
        transcriptIds: [t.transcriptId],
        to: 'es',
        translator: _FakeTranslator(),
      );
      final project = (await repository.findTranscript(t.transcriptId))!
          .projectId;
      final first = (await database.translationLinesFor(t.transcriptId)).first;

      // Retyped: only the translation changes.
      await repository.setCueTranslation(
        transcriptId: t.transcriptId,
        lineIds: [first.id],
        firstWord: first.firstWord,
        lastWord: first.lastWord,
        startMs: first.startMs,
        endMs: first.endMs,
        content: 'Hola.',
      );
      expect((await database.findTranslationLine(first.id))!.content, 'Hola.');
      final words = await repository.watchWords(t.transcriptId).first;
      expect(words.map((w) => w.word), ['Hello.', 'Bye', 'now.']);
      await repository.undoProject(project);
      expect((await database.findTranslationLine(first.id))!.content,
          first.content);

      // Cleared: gone; undo brings it back.
      await repository.setCueTranslation(
        transcriptId: t.transcriptId,
        lineIds: [first.id],
        firstWord: first.firstWord,
        lastWord: first.lastWord,
        startMs: first.startMs,
        endMs: first.endMs,
        content: '  ',
      );
      expect(await database.translationLinesFor(t.transcriptId), hasLength(1));
      await repository.undoProject(project);
      expect(await database.translationLinesFor(t.transcriptId), hasLength(2));

      // Added where there was none, in the translation's language.
      await repository.removeTranslation(t.transcriptId);
      await repository.setCueTranslation(
        transcriptId: t.transcriptId,
        lineIds: const [],
        firstWord: 0,
        lastWord: 0,
        startMs: 0,
        endMs: 400,
        content: 'Hola.',
      );
      final added = await database.translationLinesFor(t.transcriptId);
      expect(added.single.content, 'Hola.');
      expect(added.single.trackId, isNotNull);
      await repository.undoProject(project);
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
