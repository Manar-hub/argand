import 'package:argand/core/database/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a clip row with only the fields the timeline reads.
MediaClip _clip(String id, int? durationMs, {int position = 0}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return MediaClip(
    id: id,
    createdAt: now,
    updatedAt: now,
    projectId: 'p1',
    position: position,
    mediaPath: '/media/p1/$id.mp4',
    durationMs: durationMs,
    title: id,
    scale: 1,
    rotation: 0,
    offsetX: 0,
    offsetY: 0,
    audioStartOffsetMs: 0,
    audioEndOffsetMs: 0,
    audioMuted: false,
  );
}

void main() {
  group('placement', () {
    test('clips lie end to end in the order given', () {
      final timeline = ProjectTimeline.fromClips([
        _clip('a', 5000, position: 0),
        _clip('b', 3000, position: 1),
        _clip('c', 2000, position: 2),
      ]);

      expect([for (final p in timeline.placements) p.startMs], [0, 5000, 8000]);
      expect(timeline.totalMs, 10000);
      expect(timeline.placementOf('b')!.durationMs, 3000);
      expect(timeline.placementOf('missing'), isNull);
    });

    test('a clip with no usable duration takes up no time but still exists',
        () {
      // Null and zero both mean "nobody has measured this yet" -- the clip
      // still plays and still shows on the track, it just cannot be laid out
      // until MediaPlayer repairs its duration.
      final timeline = ProjectTimeline.fromClips([
        _clip('a', 4000, position: 0),
        _clip('unmeasured', null, position: 1),
        _clip('zero', 0, position: 2),
        _clip('b', 1000, position: 3),
      ]);

      expect(timeline.totalMs, 5000);
      expect(timeline.placementOf('unmeasured')!.startMs, 4000);
      expect(timeline.placementOf('zero')!.startMs, 4000);
      expect(timeline.placementOf('b')!.startMs, 4000);
    });

    test('an empty project has no length and no placements', () {
      final timeline = ProjectTimeline.fromClips(const []);
      expect(timeline.isEmpty, isTrue);
      expect(timeline.totalMs, 0);
      expect(timeline.clipAt(0), isNull);
      expect(timeline.rangesFor(startMs: 0, endMs: 1000), isEmpty);
    });
  });

  group('converting between the two timebases', () {
    final timeline = ProjectTimeline.fromClips([
      _clip('a', 5000, position: 0),
      _clip('b', 3000, position: 1),
    ]);

    test('a clip position maps onto the project axis', () {
      expect(timeline.projectMsOf(clipId: 'a', clipMs: 1200), 1200);
      expect(timeline.projectMsOf(clipId: 'b', clipMs: 1200), 6200);
      expect(timeline.projectMsOf(clipId: 'gone', clipMs: 0), isNull);
    });

    test('a project position resolves to the clip under it', () {
      expect(timeline.clipAt(0), (clipId: 'a', clipMs: 0));
      expect(timeline.clipAt(4999), (clipId: 'a', clipMs: 4999));
      // Half-open: the boundary belongs to the clip that starts there.
      expect(timeline.clipAt(5000), (clipId: 'b', clipMs: 0));
      expect(timeline.clipAt(7999), (clipId: 'b', clipMs: 2999));
    });

    test('positions outside the project clamp to its ends', () {
      // The playhead can be dragged past the last frame; "the end of the last
      // clip" is a more useful answer there than "nowhere".
      expect(timeline.clipAt(-500), (clipId: 'a', clipMs: 0));
      expect(timeline.clipAt(99999), (clipId: 'b', clipMs: 3000));
    });
  });

  group('splitting a range into per-clip work', () {
    final timeline = ProjectTimeline.fromClips([
      _clip('a', 5000, position: 0),
      _clip('b', 3000, position: 1),
      _clip('c', 2000, position: 2),
    ]);

    test('a range inside one clip yields one range', () {
      final ranges = timeline.rangesFor(startMs: 1000, endMs: 2000);
      expect(ranges, hasLength(1));
      expect(ranges.single.clipId, 'a');
      expect(ranges.single.clipStartMs, 1000);
      expect(ranges.single.clipEndMs, 2000);
      expect(ranges.single.projectStartMs, 1000);
    });

    test('a range crossing a boundary splits, with clip-relative offsets', () {
      final ranges = timeline.rangesFor(startMs: 4000, endMs: 6000);
      expect(ranges, hasLength(2));

      expect(ranges[0].clipId, 'a');
      expect(ranges[0].clipStartMs, 4000);
      expect(ranges[0].clipEndMs, 5000);

      // The second clip's work starts at *its own* zero, not at 5000.
      expect(ranges[1].clipId, 'b');
      expect(ranges[1].clipStartMs, 0);
      expect(ranges[1].clipEndMs, 1000);
      expect(ranges[1].projectStartMs, 5000);
    });

    test('a range spanning three clips covers the middle one entirely', () {
      final ranges = timeline.rangesFor(startMs: 2000, endMs: 9000);
      expect([for (final r in ranges) r.clipId], ['a', 'b', 'c']);
      expect(ranges[1].clipStartMs, 0);
      expect(ranges[1].clipEndMs, 3000);
    });

    test('a range ending exactly on a boundary does not reach the next clip',
        () {
      // The rule that lets two adjacent ranges tile without both claiming the
      // same millisecond.
      final ranges = timeline.rangesFor(startMs: 3000, endMs: 5000);
      expect(ranges, hasLength(1));
      expect(ranges.single.clipId, 'a');
    });

    test('a range starting exactly on a boundary belongs to the later clip',
        () {
      final ranges = timeline.rangesFor(startMs: 5000, endMs: 5500);
      expect(ranges, hasLength(1));
      expect(ranges.single.clipId, 'b');
      expect(ranges.single.clipStartMs, 0);
    });

    test('a range past the end of the project is truncated', () {
      final ranges = timeline.rangesFor(startMs: 9000, endMs: 50000);
      expect(ranges, hasLength(1));
      expect(ranges.single.clipId, 'c');
      expect(ranges.single.clipEndMs, 2000);
    });

    test('an empty or inverted range yields nothing', () {
      expect(timeline.rangesFor(startMs: 1000, endMs: 1000), isEmpty);
      expect(timeline.rangesFor(startMs: 2000, endMs: 1000), isEmpty);
    });

    test('a zero-duration clip is never part of any range', () {
      final withGap = ProjectTimeline.fromClips([
        _clip('a', 1000, position: 0),
        _clip('zero', 0, position: 1),
        _clip('b', 1000, position: 2),
      ]);

      final ranges = withGap.rangesFor(startMs: 0, endMs: 2000);
      expect([for (final r in ranges) r.clipId], ['a', 'b']);
    });

    test('a sliver survives geometry, for the caller to filter', () {
      // Policy belongs to the engine, not here: a drawing of coverage wants
      // this sliver, and only the runner knows its own minimum.
      final ranges = timeline.rangesFor(startMs: 4940, endMs: 5000);
      expect(ranges, hasLength(1));
      expect(ranges.single.clipEndMs - ranges.single.clipStartMs, 60);
    });
  });

  group('a removed tail', () {
    // A 40 s file, cut at 15.5 s and the rest removed: one clip playing
    // 0-15.5 s, with the words still running to 38 s.
    final kept = _clip('a', 40000).copyWith(trimEndMs: const Value(15500));
    final timeline = ProjectTimeline.fromClips([kept]);

    test('the project runs on to where the words end', () {
      expect(timeline.totalMs, 15500);
      expect(
        timeline.runMsWith(contentEndMs: 38000, lastFileMs: 40000),
        38000,
      );
    });

    test('but no further than the file reaches', () {
      expect(
        timeline.runMsWith(contentEndMs: 55000, lastFileMs: 40000),
        40000,
      );
    });

    test('nothing past the clips: it ends with them', () {
      expect(
        timeline.runMsWith(contentEndMs: 12000, lastFileMs: 40000),
        15500,
      );
      expect(timeline.runMsWith(contentEndMs: 38000), 15500);
    });

    test('past the clips, the playhead lands in the file beyond the cut', () {
      expect(timeline.tailAt(20000, runMs: 38000),
          (clipId: 'a', clipMs: 20000));
      // Inside the clip, and from the end of the run on, it is not the tail.
      expect(timeline.tailAt(10000, runMs: 38000), isNull);
      expect(timeline.tailAt(38000, runMs: 38000), isNull);
    });

    test('behind an earlier clip, the tail is still the last clip\'s file',
        () {
      final two = ProjectTimeline.fromClips([
        _clip('x', 5000, position: 0),
        kept.copyWith(position: 1),
      ]);
      expect(two.totalMs, 20500);
      expect(two.runMsWith(contentEndMs: 43000, lastFileMs: 40000), 43000);
      // 25 s into the project is 20 s into a's file.
      expect(two.tailAt(25000, runMs: 43000), (clipId: 'a', clipMs: 20000));
    });
  });
}
