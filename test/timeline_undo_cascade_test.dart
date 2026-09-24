import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/clip_trim.dart';
import 'package:argand/core/timeline/timeline_event.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/timeline_history.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Undo has to take back what the user can see, not only what the timeline
/// draws. The bug these cover: undoing a transcribe track removed its row from
/// the track list and left the captions on the video, because the inverse
/// touched the layer and not the transcripts hanging off it.
void main() {
  late AppDatabase database;
  late TranscriptRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TranscriptRepository(database, MediaConverter());
  });

  tearDown(() => database.close());

  /// A project with one clip, one layer over it, and one transcript on that
  /// layer -- the state the user is in right after pressing Transcribe.
  Future<({String projectId, String layerId, String transcriptId})>
      transcribed() async {
    final projectId = repository.newId();
    final clipId = repository.newId();

    await database.createEmptyProject(projectId: projectId, title: 'project');
    await database.appendClip(
      clipId: clipId,
      projectId: projectId,
      mediaPath: '/tmp/german.mp4',
      title: 'german',
      duration: const Duration(seconds: 14),
    );

    final layerId = (await repository.addLayer(
      projectId: projectId,
      startMs: 0,
      endMs: 14000,
    ))!;

    final transcriptId = await repository.saveClipTranscript(
      projectId: projectId,
      clipId: clipId,
      language: TranscriptionLanguage.english,
      speakerSpans: const [],
      layerId: layerId,
      result: WhisperTranscribeResponse(
        type: 'transcribe',
        text: 'guten tag',
        segments: [
          WhisperTranscribeSegment(
            fromTs: Duration.zero,
            toTs: const Duration(milliseconds: 400),
            text: ' guten',
          ),
          WhisperTranscribeSegment(
            fromTs: const Duration(milliseconds: 400),
            toTs: const Duration(milliseconds: 800),
            text: ' tag',
          ),
        ],
      ),
    );

    // Recorded the way the controller records it once a run commits.
    await repository.recordTimelineEvent(
      projectId: projectId,
      kind: TimelineEventKind.transcribeRun,
      payload: transcribeRunPayload(transcriptIds: [transcriptId]),
    );

    return (
      projectId: projectId,
      layerId: layerId,
      transcriptId: transcriptId,
    );
  }

  Future<bool> transcriptIsLive(String transcriptId) async {
    final rows = await (database.select(database.transcripts)
          ..where((t) => t.id.equals(transcriptId)))
        .get();
    return rows.single.deletedAt == null;
  }

  group('undoing a transcription', () {
    test('takes the words back, not just the track', () async {
      final seeded = await transcribed();

      await repository.undoProject(seeded.projectId);

      // The whole point: the captions come off the video.
      expect(await transcriptIsLive(seeded.transcriptId), isFalse);
      // And the layer is untouched, because the run is its own action.
      expect(await repository.findLayer(seeded.layerId), isNotNull);
    });

    test('redo puts them back', () async {
      final seeded = await transcribed();

      await repository.undoProject(seeded.projectId);
      await repository.redoProject(seeded.projectId);

      expect(await transcriptIsLive(seeded.transcriptId), isTrue);
      expect(await repository.transcriptsForLayer(seeded.layerId), hasLength(1));
    });

    test('a second undo reaches the layer underneath it', () async {
      final seeded = await transcribed();

      await repository.undoProject(seeded.projectId);
      await repository.undoProject(seeded.projectId);

      expect(await repository.findLayer(seeded.layerId), isNull);
      expect(await transcriptIsLive(seeded.transcriptId), isFalse);
    });
  });

  group('undoing a split', () {
    /// A project with one six-second clip and nothing else.
    Future<({String projectId, String clipId})> oneClip() async {
      final projectId = repository.newId();
      final clipId = repository.newId();

      await database.createEmptyProject(projectId: projectId, title: 'split');
      await database.appendClip(
        clipId: clipId,
        projectId: projectId,
        mediaPath: '/tmp/square.mp4',
        title: 'square',
        duration: const Duration(seconds: 6),
      );

      return (projectId: projectId, clipId: clipId);
    }

    Future<int> liveClips(String projectId) async =>
        (await repository.clipsForProject(projectId)).length;

    test('puts the two halves back together', () async {
      final seeded = await oneClip();

      expect(
        await repository.splitClip(clipId: seeded.clipId, atClipMs: 2000),
        isNotNull,
      );
      expect(await liveClips(seeded.projectId), 2);

      await repository.undoProject(seeded.projectId);

      expect(await liveClips(seeded.projectId), 1);
    });

    test('and redo cuts it again', () async {
      final seeded = await oneClip();

      await repository.splitClip(clipId: seeded.clipId, atClipMs: 2000);
      await repository.undoProject(seeded.projectId);
      await repository.redoProject(seeded.projectId);

      expect(await liveClips(seeded.projectId), 2);
    });

    test('the restored clip reaches the full length again', () async {
      final seeded = await oneClip();

      await repository.splitClip(clipId: seeded.clipId, atClipMs: 2000);
      await repository.undoProject(seeded.projectId);

      final clip = (await repository.clipsForProject(seeded.projectId)).single;
      expect(clipWindow(clip).endMs, 6000);
    });
  });

  group('setLayerRetired', () {
    test('cascades to the layer transcripts, the way the real delete does',
        () async {
      final seeded = await transcribed();

      await database.setLayerRetired(layerId: seeded.layerId, retired: true);

      expect(await transcriptIsLive(seeded.transcriptId), isFalse);
    });

    test('restoring brings the same transcripts back', () async {
      final seeded = await transcribed();

      await database.setLayerRetired(layerId: seeded.layerId, retired: true);
      await database.setLayerRetired(layerId: seeded.layerId, retired: false);

      expect(await transcriptIsLive(seeded.transcriptId), isTrue);
    });

    test('does not resurrect words an earlier rerun discarded', () async {
      final seeded = await transcribed();

      // What rerun does: the old answer is put away, a new one replaces it.
      await repository.discardLayerTranscripts(seeded.layerId);
      await Future<void>.delayed(const Duration(seconds: 1));

      final fresh = await repository.saveClipTranscript(
        projectId: seeded.projectId,
        clipId: (await repository.clipsForProject(seeded.projectId)).first.id,
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        layerId: seeded.layerId,
        result: WhisperTranscribeResponse(
          type: 'transcribe',
          text: 'guten abend',
          segments: [
            WhisperTranscribeSegment(
              fromTs: Duration.zero,
              toTs: const Duration(milliseconds: 400),
              text: ' guten',
            ),
          ],
        ),
      );

      await database.setLayerRetired(layerId: seeded.layerId, retired: true);
      await database.setLayerRetired(layerId: seeded.layerId, retired: false);

      expect(await transcriptIsLive(fresh), isTrue);
      expect(await transcriptIsLive(seeded.transcriptId), isFalse);
    });
  });
}
