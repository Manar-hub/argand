import 'package:argand/core/database/database.dart';
import 'package:argand/core/timeline/clip_trim.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

MediaClip clip({
  String id = 'c',
  int? durationMs = 30000,
  int? trimStartMs,
  int? trimEndMs,
  int position = 0,
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
    );

void main() {
  group('clipWindow', () {
    test('an untrimmed clip is the whole file', () {
      expect(clipWindow(clip()), (startMs: 0, endMs: 30000));
    });

    test('resolves each end independently', () {
      expect(
        clipWindow(clip(trimStartMs: 5000)),
        (startMs: 5000, endMs: 30000),
      );
      expect(
        clipWindow(clip(trimEndMs: 20000)),
        (startMs: 0, endMs: 20000),
      );
    });

    test('a clip whose media could not be probed has no length', () {
      // `durationMs` is nullable because `probeDuration` can fail. A null end
      // resolving to null duration must not become a negative window.
      expect(clipWindow(clip(durationMs: null)), (startMs: 0, endMs: 0));
    });

    test('stored values outside the media are held inside it', () {
      // The file can be replaced by a shorter one; asking the player or the
      // encoder for time that does not exist is how that becomes a crash
      // rather than a short clip.
      expect(
        clipWindow(clip(durationMs: 10000, trimStartMs: 99000)),
        (startMs: 10000, endMs: 10000),
      );
      expect(
        clipWindow(clip(durationMs: 10000, trimEndMs: 99000)).endMs,
        10000,
      );
    });
  });

  group('trimmedDurationMs', () {
    test('is the window, not the file', () {
      expect(
        trimmedDurationMs(clip(trimStartMs: 5000, trimEndMs: 12000)),
        7000,
      );
    });

    test('the timeline measures trimmed clips', () {
      // The reason this module exists: an untrimmed 30s clip followed by one
      // trimmed to 7s is a 37s project, and the second clip starts at 30s.
      final timeline = ProjectTimeline.fromClips([
        clip(id: 'a', position: 0),
        clip(id: 'b', position: 1, trimStartMs: 5000, trimEndMs: 12000),
      ]);

      expect(timeline.totalMs, 37000);
      expect(timeline.placements.last.startMs, 30000);
      expect(timeline.placements.last.durationMs, 7000);
    });
  });

  group('applyTrim', () {
    test('dragging the in-point shortens from the front', () {
      final window = applyTrim(
        clip: clip(),
        edge: ClipEdge.start,
        deltaMs: 4000,
      );

      expect(window, (startMs: 4000, endMs: 30000));
    });

    test('dragging the out-point shortens from the back', () {
      final window = applyTrim(
        clip: clip(),
        edge: ClipEdge.end,
        deltaMs: -6000,
      );

      expect(window, (startMs: 0, endMs: 24000));
    });

    test('cannot be dragged past the ends of its own media', () {
      expect(
        applyTrim(clip: clip(), edge: ClipEdge.start, deltaMs: -99000).startMs,
        0,
      );
      expect(
        applyTrim(clip: clip(), edge: ClipEdge.end, deltaMs: 99000).endMs,
        30000,
      );
    });

    test('cannot be collapsed below what will play', () {
      final fromStart =
          applyTrim(clip: clip(), edge: ClipEdge.start, deltaMs: 99000);
      final fromEnd =
          applyTrim(clip: clip(), edge: ClipEdge.end, deltaMs: -99000);

      expect(fromStart.endMs - fromStart.startMs, minimumClipMs);
      expect(fromEnd.endMs - fromEnd.startMs, minimumClipMs);
    });

    test('trimming one edge leaves the other alone', () {
      // A trim shortens the clip; it does not slide the clip along its media.
      final window = applyTrim(
        clip: clip(trimStartMs: 3000, trimEndMs: 20000),
        edge: ClipEdge.end,
        deltaMs: -2000,
      );

      expect(window.startMs, 3000);
    });

    test('a file shorter than the floor is left untouched', () {
      final tiny = clip(durationMs: 100);

      expect(
        applyTrim(clip: tiny, edge: ClipEdge.end, deltaMs: -50),
        clipWindow(tiny),
      );
    });
  });

  group('splitPointFor', () {
    test('returns the point in media time, not clip time', () {
      // The playhead knows where it is inside what the clip *plays*; the rows
      // have to store where that falls in the file.
      expect(splitPointFor(clip(trimStartMs: 4000), 5000), 9000);
    });

    test('refuses a split that would leave a sliver', () {
      expect(splitPointFor(clip(), 10), isNull);
      expect(splitPointFor(clip(), 29990), isNull);
    });

    test('refuses rather than producing something unplayable', () {
      expect(splitPointFor(clip(durationMs: 400), 200), isNull);
    });

    test('a split in the middle is allowed', () {
      expect(splitPointFor(clip(), 15000), 15000);
    });
  });
}
