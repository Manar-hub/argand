import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:argand/core/timeline/audio_window.dart';
import 'package:argand/core/timeline/clip_trim.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/core/video/video_export.dart';
import 'package:flutter_test/flutter_test.dart';

MediaClip _clip(
  String id, {
  int position = 0,
  int durationMs = 10000,
  int? trimStartMs,
  int? trimEndMs,
  int startOffset = 0,
  int endOffset = 0,
}) =>
    MediaClip(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: 'p',
      position: position,
      mediaPath: '/media/$id.mp4',
      durationMs: durationMs,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      title: id,
      scale: 1,
      rotation: 0,
      offsetX: 0,
      offsetY: 0,
      audioStartOffsetMs: startOffset,
      audioEndOffsetMs: endOffset,
      audioMuted: false,
    );

void main() {
  group('audioWindow', () {
    test('with no offsets, the sound is exactly the picture', () {
      final clip = _clip('a', trimStartMs: 2000, trimEndMs: 6000);
      expect(audioWindow(clip), (startMs: 2000, endMs: 6000));
    });

    test('offsets reach past the picture, held inside the file', () {
      final clip = _clip(
        'a',
        trimStartMs: 2000,
        trimEndMs: 6000,
        startOffset: -3000,
        endOffset: 9000,
      );
      expect(audioWindow(clip), (startMs: 0, endMs: 10000));
    });
  });

  group('audioSpan', () {
    test('an L-cut carries the sound under the next clip', () {
      final a = _clip('a', trimEndMs: 4000, endOffset: 1500);
      final b = _clip('b', position: 1, trimStartMs: 1000, trimEndMs: 5000);
      final timeline = ProjectTimeline.fromClips([a, b]);

      expect(audioSpan(timeline, a), (startMs: 0, endMs: 5500, mediaStartMs: 0));
      expect(
        audioSpan(timeline, b),
        (startMs: 4000, endMs: 8000, mediaStartMs: 1000),
      );
    });

    test('a J-cut on the first clip starts at zero, later in the media', () {
      final a = _clip('a', trimStartMs: 3000, startOffset: -2000);
      final timeline = ProjectTimeline.fromClips([a]);
      // Placed at 0, so the two seconds before it are cut off the front.
      expect(audioSpan(timeline, a)!.startMs, 0);
      expect(audioSpan(timeline, a)!.mediaStartMs, 3000);
    });
  });

  group('applyAudioTrim', () {
    test('an end drag extends into the next clip, no further than the file',
        () {
      final a = _clip('a', trimEndMs: 4000);
      final offsets = applyAudioTrim(
        clip: a,
        edge: ClipEdge.end,
        deltaMs: 60000,
        placementStartMs: 0,
        totalMs: 20000,
      );
      expect(offsets, (startOffsetMs: 0, endOffsetMs: 6000));
    });

    test('never off the front of the timeline, never too short', () {
      final b = _clip('b', trimStartMs: 5000);
      expect(
        applyAudioTrim(
          clip: b,
          edge: ClipEdge.start,
          deltaMs: -9000,
          placementStartMs: 2000,
          totalMs: 7000,
        ).startOffsetMs,
        -2000,
      );
      expect(
        applyAudioTrim(
          clip: b,
          edge: ClipEdge.start,
          deltaMs: 60000,
          placementStartMs: 2000,
          totalMs: 7000,
        ).startOffsetMs,
        5000 - minimumClipMs,
      );
    });
  });

  group('TranscriptRepository audio edits', () {
    late AppDatabase db;
    late TranscriptRepository repository;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TranscriptRepository(db, MediaConverter());
    });
    tearDown(() => db.close());

    Future<String> addClip() async {
      final projectId = await repository.createEmptyProject(title: 't');
      final clipId = repository.newId();
      await db.into(db.mediaClips).insert(MediaClipsCompanion.insert(
            id: clipId,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            projectId: projectId,
            position: 0,
            mediaPath: '/m.mp4',
            title: 'm',
          ));
      return clipId;
    }

    test('an audio trim undoes and redoes', () async {
      final clipId = await addClip();
      final projectId = (await db.findClip(clipId))!.projectId;

      await repository.trimAudio(
        clipId: clipId,
        offsets: (startOffsetMs: -500, endOffsetMs: 1200),
      );
      var clip = (await db.findClip(clipId))!;
      expect((clip.audioStartOffsetMs, clip.audioEndOffsetMs), (-500, 1200));

      await repository.undoProject(projectId);
      clip = (await db.findClip(clipId))!;
      expect((clip.audioStartOffsetMs, clip.audioEndOffsetMs), (0, 0));

      await repository.redoProject(projectId);
      clip = (await db.findClip(clipId))!;
      expect((clip.audioStartOffsetMs, clip.audioEndOffsetMs), (-500, 1200));
    });

    test('removing a sound undoes', () async {
      final clipId = await addClip();
      final projectId = (await db.findClip(clipId))!.projectId;

      await repository.setAudioMuted(
        projectId: projectId,
        clipIds: [clipId],
        muted: true,
      );
      expect((await db.findClip(clipId))!.audioMuted, isTrue);

      await repository.undoProject(projectId);
      expect((await db.findClip(clipId))!.audioMuted, isFalse);
    });

    test('a split cuts the sound where it cuts the picture', () async {
      final clipId = await addClip();
      await db.setAudioOffsets(
        clipId: clipId,
        startOffsetMs: -300,
        endOffsetMs: 900,
      );
      final right = await db.splitClip(
        clipId: clipId,
        atMediaMs: 1000,
        newId: repository.newId,
      );
      final l = (await db.findClip(clipId))!;
      final r = (await db.findClip(right!))!;
      expect((l.audioStartOffsetMs, l.audioEndOffsetMs), (-300, 0));
      expect((r.audioStartOffsetMs, r.audioEndOffsetMs), (0, 900));
    });
  });

  test('the export carries each sound where it plays', () {
    final a = _clip('a', trimEndMs: 4000, endOffset: 1500);
    final b = _clip('b', position: 1, trimStartMs: 1000, trimEndMs: 5000);
    final muted = _clip('c', position: 2, trimEndMs: 2000).copyWith(
      audioMuted: true,
    );
    final clips = [a, b, muted];
    final request = exportRequestFor(
      timeline: ProjectTimeline.fromClips(clips),
      clips: clips,
    )!;

    expect(
      request.clips.map((c) => c.audio).toList(),
      [
        (startMs: 0, endMs: 5500, projectStartMs: 0, inline: false),
        (startMs: 1000, endMs: 5000, projectStartMs: 4000, inline: true),
        null,
      ],
    );

    final silent = exportRequestFor(
      timeline: ProjectTimeline.fromClips(clips),
      clips: clips,
      withAudio: false,
    )!;
    expect(silent.clips.every((c) => c.audio == null), isTrue);
  });

  test('overlapping sounds pack into two rows', () {
    final lanes = packLanes<(int, int)>(
      [(0, 5500), (4000, 8000), (8000, 9000)],
      startOf: (s) => s.$1,
      endOf: (s) => s.$2,
    );
    expect(lanes, [
      [(0, 5500), (8000, 9000)],
      [(4000, 8000)],
    ]);
  });
}
