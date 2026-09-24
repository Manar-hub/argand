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
  String? mediaPath,
}) =>
    MediaClip(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: 'p',
      position: position,
      mediaPath: mediaPath ?? '/media/\$id.mp4',
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

  group('media time survives a trim', () {
    // **The property that broke silently.** Measuring trimmed clips changed
    // what `clipAt` returned without changing what its callers expected, so
    // scrubbing over a trimmed clip seeked to the wrong frame and its
    // sentences drew in the wrong place. Both conversions speak media time.
    final timeline = ProjectTimeline.fromClips([
      clip(id: 'a', position: 0, trimStartMs: 4000, trimEndMs: 10000),
      clip(id: 'b', position: 1),
    ]);

    test('clipAt answers in media time, past the in-point', () {
      // The very start of the project is 4s into the first clip's file.
      expect(timeline.clipAt(0), (clipId: 'a', clipMs: 4000));
      expect(timeline.clipAt(1000), (clipId: 'a', clipMs: 5000));
    });

    test('the second clip starts where the first one stops playing', () {
      // The first contributes 6s, not its full 30.
      expect(timeline.clipAt(6000), (clipId: 'b', clipMs: 0));
    });

    test('projectMsOf takes media time back', () {
      expect(timeline.projectMsOf(clipId: 'a', clipMs: 4000), 0);
      expect(timeline.projectMsOf(clipId: 'a', clipMs: 7000), 3000);
    });

    test('the two round-trip', () {
      for (final projectMs in [0, 1, 2500, 5999, 6000, 20000]) {
        final at = timeline.clipAt(projectMs)!;
        expect(
          timeline.projectMsOf(clipId: at.clipId, clipMs: at.clipMs),
          projectMs,
          reason: 'round trip failed at ${projectMs}ms',
        );
      }
    });

    test('a transcribe range addresses the file, not the window', () {
      // This feeds the WAV slicer and `saveClipTranscript`'s offset, both of
      // which address the media file. A window-relative number here would
      // transcribe the wrong audio and file the words at the wrong times.
      final ranges = timeline.rangesFor(startMs: 0, endMs: 3000);

      expect(ranges.single.clipId, 'a');
      expect(ranges.single.clipStartMs, 4000);
      expect(ranges.single.clipEndMs, 7000);
    });

    test('an untrimmed clip is unaffected', () {
      final plain = ProjectTimeline.fromClips([clip(id: 'a')]);

      expect(plain.clipAt(5000), (clipId: 'a', clipMs: 5000));
      expect(plain.projectMsOf(clipId: 'a', clipMs: 5000), 5000);
    });
  });

  group('rolling the cut between two halves of a split', () {
    // **The 14s file that became a 22s project.** Splitting german.mp4 at 6s
    // and dragging one half outward re-covered footage the other half already
    // played: 14 + 8 = 22, with the overlap playing twice. Rolling gives one
    // side exactly what the other gives up.
    const german = '/media/german.mp4';
    MediaClip left({int end = 6000}) => clip(
          id: 'L',
          durationMs: 14000,
          trimEndMs: end,
          position: 0,
          mediaPath: german,
        );
    MediaClip right({int start = 6000}) => clip(
          id: 'R',
          durationMs: 14000,
          trimStartMs: start,
          position: 1,
          mediaPath: german,
        );

    test('the halves of a split are recognised as one cut', () {
      expect(sharesACut(left(), right()), isTrue);
    });

    test('a gap or a different file is not a cut', () {
      expect(sharesACut(left(), right(start: 9000)), isFalse);

      final other = MediaClip(
        id: 'X',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        projectId: 'p',
        position: 1,
        mediaPath: '/media/other.mp4',
        durationMs: 14000,
        trimStartMs: 6000,
        title: 'X',
      );
      expect(sharesACut(left(), other), isFalse);
    });

    test('the project never gets longer than its source', () {
      for (final delta in [-5000, -1000, 0, 1000, 5000, 99000, -99000]) {
        final rolled = rollCut(left: left(), right: right(), deltaMs: delta);
        final total = (rolled.left.endMs - rolled.left.startMs) +
            (rolled.right.endMs - rolled.right.startMs);

        expect(
          total,
          14000,
          reason: 'rolling by ${delta}ms changed the total length',
        );
      }
    });

    test('the two sides always still meet', () {
      final rolled = rollCut(left: left(), right: right(), deltaMs: 3000);

      expect(rolled.left.endMs, rolled.right.startMs);
      expect(rolled.left.endMs, 9000);
    });

    test('the cut cannot be pushed off either end', () {
      final far = rollCut(left: left(), right: right(), deltaMs: 99000);
      expect(far.right.endMs - far.right.startMs, minimumClipMs);

      final back = rollCut(left: left(), right: right(), deltaMs: -99000);
      expect(back.left.endMs - back.left.startMs, minimumClipMs);
    });

    test('a rolled pair still tiles the timeline exactly', () {
      final rolled = rollCut(left: left(), right: right(), deltaMs: 2000);
      final timeline = ProjectTimeline.fromClips([
        clip(
          id: 'L',
          durationMs: 14000,
          trimStartMs: rolled.left.startMs,
          trimEndMs: rolled.left.endMs,
          position: 0,
          mediaPath: german,
        ),
        clip(
          id: 'R',
          durationMs: 14000,
          trimStartMs: rolled.right.startMs,
          trimEndMs: rolled.right.endMs,
          position: 1,
          mediaPath: german,
        ),
      ]);

      expect(timeline.totalMs, 14000);
    });
  });
}
