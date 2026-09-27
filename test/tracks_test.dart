import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

void main() {
  late AppDatabase db;
  late TranscriptRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(db, MediaConverter());
  });
  tearDown(() => db.close());

  Future<({String projectId, String clipId, String layerId})> seeded() async {
    final projectId = repository.newId();
    final clipId = repository.newId();
    await db.createEmptyProject(projectId: projectId, title: 'p');
    await db.appendClip(
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
    return (projectId: projectId, clipId: clipId, layerId: layerId);
  }

  test('a new project gets a video and an audio track', () async {
    final ids = await seeded();
    final tracks = await repository.ensureTracks(ids.projectId);
    expect(tracks.map((t) => t.kind), ['media', 'video', 'audio']);
    final layer = await db.findLayer(ids.layerId);
    expect(layer!.trackId, tracks.first.id, reason: 'above the video');
  });

  test('a drop below the last track makes one, and undo takes it away',
      () async {
    final ids = await seeded();
    final textId = (await repository.addTextLayer(
      projectId: ids.projectId,
      startMs: 1000,
      endMs: 3000,
      content: 'Hi',
    ))!;
    final before = (await db.findTextLayer(textId))!;

    await repository.placeItems(
      projectId: ids.projectId,
      newTracks: 1,
      placements: [
        (
          item: (kind: TimelineItemKind.text, id: textId),
          fromStartMs: 1000,
          fromEndMs: 3000,
          toStartMs: 2000,
          toEndMs: 4000,
          trackId: null,
          newTrack: 0,
        ),
      ],
    );
    final tracks = await db.tracksForProject(ids.projectId);
    final moved = (await db.findTextLayer(textId))!;
    expect(moved.trackId, tracks.last.id, reason: 'made at the bottom');
    expect((moved.startMs, moved.endMs), (2000, 4000));

    await repository.undoProject(ids.projectId);
    final back = (await db.findTextLayer(textId))!;
    expect(back.trackId, before.trackId);
    expect((back.startMs, back.endMs), (1000, 3000));
    expect(
      (await db.tracksForProject(ids.projectId)).map((t) => t.id),
      isNot(contains(moved.trackId)),
    );

    await repository.redoProject(ids.projectId);
    expect((await db.findTextLayer(textId))!.trackId, moved.trackId);
  });

  test('a sentence retimes its words, and undo puts them back', () async {
    final ids = await seeded();
    final transcriptId = await repository.saveClipTranscript(
      projectId: ids.projectId,
      clipId: ids.clipId,
      language: TranscriptionLanguage.english,
      speakerSpans: const [],
      layerId: ids.layerId,
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: 'Hello there.',
        segments: [
          WhisperTranscribeSegment(
            fromTs: const Duration(milliseconds: 1000),
            toTs: const Duration(milliseconds: 1500),
            text: ' Hello',
          ),
          WhisperTranscribeSegment(
            fromTs: const Duration(milliseconds: 1500),
            toTs: const Duration(milliseconds: 2000),
            text: ' there.',
          ),
        ],
      ),
    );
    final item = sentenceItem(
      transcriptId: transcriptId,
      fromPosition: 0,
      toPosition: 1,
    );

    await repository.placeItems(
      projectId: ids.projectId,
      placements: [
        (
          item: item,
          fromStartMs: 1000,
          fromEndMs: 2000,
          toStartMs: 3000,
          toEndMs: 5000,
          trackId: null,
          newTrack: null,
        ),
      ],
    );
    var words = await db.watchWords(transcriptId).first;
    expect(
      words.map((w) => (w.startMs, w.endMs)),
      [(3000, 4000), (4000, 5000)],
    );

    await repository.undoProject(ids.projectId);
    words = await db.watchWords(transcriptId).first;
    expect(
      words.map((w) => (w.startMs, w.endMs)),
      [(1000, 1500), (1500, 2000)],
    );
  });

  test('a translation line retyped and removed undoes', () async {
    final ids = await seeded();
    final transcriptId = repository.newId();
    await db.into(db.transcripts).insert(TranscriptsCompanion.insert(
          id: transcriptId,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          projectId: ids.projectId,
          clipId: Value(ids.clipId),
          fullText: 'x',
        ));
    const lineId = 'line';
    await db.into(db.translationLines).insert(
          TranslationLinesCompanion.insert(
            id: lineId,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            transcriptId: transcriptId,
            language: 'de',
            position: 0,
            firstWord: 0,
            lastWord: 0,
            startMs: 0,
            endMs: 1000,
            content: 'Hallo',
          ),
        );

    await repository.editTranslationLine(
      projectId: ids.projectId,
      id: lineId,
      content: 'Guten Tag',
    );
    expect((await db.findTranslationLine(lineId))!.content, 'Guten Tag');
    await repository.removeTranslationLines(
      projectId: ids.projectId,
      ids: [lineId],
    );
    expect((await db.findTranslationLine(lineId))!.deletedAt, isNotNull);

    await repository.undoProject(ids.projectId);
    expect((await db.findTranslationLine(lineId))!.deletedAt, isNull);
    await repository.undoProject(ids.projectId);
    expect((await db.findTranslationLine(lineId))!.content, 'Hallo');
  });

  test('an image removed comes back with undo, and counts as shared media',
      () async {
    final ids = await seeded();
    final tracks = await repository.ensureTracks(ids.projectId);
    await db.insertImageLayer(ImageLayersCompanion.insert(
      id: 'img',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: ids.projectId,
      trackId: tracks.first.id,
      startMs: 0,
      endMs: 1000,
      path: '/media/p/img.png',
      widthPx: 40,
      heightPx: 20,
    ));
    expect(
      await db.projectsSharingMedia('/media/p/img.png', excluding: 'other'),
      1,
    );

    await repository.removeImages(ids.projectId, ['img']);
    expect(await db.imageLayersForProject(ids.projectId), isEmpty);
    await repository.undoProject(ids.projectId);
    expect(await db.imageLayersForProject(ids.projectId), hasLength(1));
  });

  test('a duplicate carries its tracks, images and translation', () async {
    final ids = await seeded();
    await repository.addTextLayer(
      projectId: ids.projectId,
      startMs: 0,
      endMs: 1000,
      content: 'Hi',
    );
    final tracks = await repository.ensureTracks(ids.projectId);
    await db.insertImageLayer(ImageLayersCompanion.insert(
      id: 'img',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: ids.projectId,
      trackId: tracks.first.id,
      startMs: 0,
      endMs: 1000,
      path: '/media/p/img.png',
      widthPx: 40,
      heightPx: 20,
    ));

    final copy = await repository.duplicateProject(
      projectId: ids.projectId,
      title: 'copy',
    );
    final copied = await db.tracksForProject(copy);
    expect(copied.map((t) => t.kind), tracks.map((t) => t.kind));
    final copiedIds = {for (final t in copied) t.id};
    expect(copiedIds.intersection({for (final t in tracks) t.id}), isEmpty);

    final text = (await db.textLayersForProject(copy)).single;
    expect(copiedIds, contains(text.trackId));
    final image = (await db.imageLayersForProject(copy)).single;
    expect(copiedIds, contains(image.trackId));
    final layer = (await db.layersForProject(copy)).single;
    expect(copiedIds, contains(layer.trackId));
  });
}
