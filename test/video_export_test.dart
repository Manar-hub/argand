import 'package:argand/core/timeline/item_transform.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:ui' show Color;

import 'package:argand/core/captions/speaker_palette.dart';
import 'package:argand/core/database/database.dart';
import 'package:argand/core/timeline/project_timeline.dart';
import 'package:argand/core/video/video_export.dart';
import 'package:flutter_test/flutter_test.dart';

MediaClip clip(String id, int durationMs, int position) => MediaClip(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      projectId: 'p',
      position: position,
      mediaPath: '/media/$id.mp4',
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


Word word(
  String text,
  int startMs,
  int endMs, {
  String? speaker,
  int position = 0,
}) =>
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

void main() {
  group('exportRequestFor', () {
    test('lists every clip path and the timeline total', () {
      final clips = [clip('a', 10000, 0), clip('b', 5000, 1)];
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(clips),
        clips: clips,
      );

      expect(request, isNotNull);
      expect(request!.clips.map((c) => c.path).toList(), ['/media/a.mp4', '/media/b.mp4']);
      expect(request.totalMs, 15000);
    });

    test('order comes from the timeline, not from the clip list', () {
      // The timeline is the single copy of the running sum; deriving order a
      // second way here is exactly the drift it exists to prevent. A caller
      // handing clips over in any order must still get timeline order back.
      final clips = [clip('a', 10000, 0), clip('b', 5000, 1)];
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(clips),
        clips: clips.reversed.toList(),
      );

      expect(request!.clips.map((c) => c.path).toList(), ['/media/a.mp4', '/media/b.mp4']);
    });

    test('an empty project has nothing to render', () {
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(const []),
        clips: const [],
      );

      expect(request, isNull);
    });

    test('refuses outright when a clip has gone missing', () {
      // Rendering only the clips still present would produce a video silently
      // shorter than the timeline, and nothing about that file would say a
      // clip had been dropped.
      final clips = [clip('a', 10000, 0), clip('b', 5000, 1)];
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(clips),
        clips: [clips.first],
      );

      expect(request, isNull);
    });

    test('skips a zero-length clip rather than handing it to the encoder', () {
      final clips = [
        clip('a', 10000, 0),
        clip('empty', 0, 1),
        clip('b', 5000, 2),
      ];
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(clips),
        clips: clips,
      );

      expect(request!.clips.map((c) => c.path).toList(), ['/media/a.mp4', '/media/b.mp4']);
    });

    test('a project of only zero-length clips has nothing to render', () {
      final clips = [clip('a', 0, 0), clip('b', 0, 1)];
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(clips),
        clips: clips,
      );

      expect(request, isNull);
    });

    test('a single clip is a valid export', () {
      final clips = [clip('only', 7000, 0)];
      final request = exportRequestFor(
        timeline: ProjectTimeline.fromClips(clips),
        clips: clips,
      );

      expect(request!.clips.map((c) => c.path).toList(), ['/media/only.mp4']);
      expect(request.totalMs, 7000);
    });
  });

  group('exportFileName', () {
    final at = DateTime(2026, 9, 20, 14, 5, 3);

    test('uses the project title and a sortable stamp', () {
      expect(
        exportFileName(projectTitle: 'Holiday', at: at),
        'Holiday 20260920-140503.mp4',
      );
    });

    test('strips characters Android will not accept in a name', () {
      // A colon or a slash is not a naming preference: the write fails, or
      // worse, the name is read as a path.
      final name = exportFileName(
        projectTitle: r'My/Holiday: "Part 2" <draft>',
        at: at,
      );

      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('"')));
      expect(name, isNot(contains('<')));
      expect(name, startsWith('My Holiday Part 2 draft'));
    });

    test('collapses the gaps left behind', () {
      expect(
        exportFileName(projectTitle: 'A   ///   B', at: at),
        'A B 20260920-140503.mp4',
      );
    });

    test('falls back when the title has nothing usable in it', () {
      expect(
        exportFileName(projectTitle: '   ///   ', at: at),
        'argand 20260920-140503.mp4',
      );
      expect(
        exportFileName(projectTitle: '', at: at),
        'argand 20260920-140503.mp4',
      );
    });

    test('never produces a hidden file', () {
      // A leading dot hides the file on Android, which for something the user
      // asked to be handed is precisely backwards.
      expect(
        exportFileName(projectTitle: '.secret', at: at),
        startsWith('secret'),
      );
    });

    test('caps a very long title but keeps the stamp', () {
      final name = exportFileName(projectTitle: 'x' * 300, at: at);

      expect(name.length, lessThan(maxExportStemLength + 30));
      expect(name, endsWith('20260920-140503.mp4'));
    });

    test('two renders a second apart do not collide', () {
      expect(
        exportFileName(projectTitle: 'p', at: at),
        isNot(exportFileName(
          projectTitle: 'p',
          at: at.add(const Duration(seconds: 1)),
        )),
      );
    });
  });

  group('exportCaptionsFor', () {
    test('an untranscribed clip contributes nothing', () {
      expect(exportCaptionsFor(const []), isEmpty);
    });

    test('carries the cue text and its span', () {
      final captions = exportCaptionsFor([
        word('Hello', 0, 500, position: 0),
        word('there.', 500, 1200, position: 1),
      ]);

      expect(captions, hasLength(1));
      expect(captions.first.text, 'Hello there.');
      expect(captions.first.startMs, 0);
      expect(captions.first.endMs, 1200);
    });

    test('colours the cue by its speaker', () {
      final first = exportCaptionsFor([
        word('One.', 0, 400, speaker: '0'),
      ]).first;
      final second = exportCaptionsFor([
        word('Two.', 0, 400, speaker: '1'),
      ]).first;

      expect(
        first.colorArgb,
        SpeakerPalette.colorFor(0, fallback: const Color(0xFFFFFFFF)).toARGB32(),
      );
      // The app's signature is that speakers are told apart by colour; two
      // speakers sharing one would quietly undo that.
      expect(first.colorArgb, isNot(second.colorArgb));
    });

    test('an undiarized cue falls back rather than failing', () {
      final caption = exportCaptionsFor([word('Alone.', 0, 400)]).first;

      expect(caption.colorArgb, const Color(0xFFFFFFFF).toARGB32());
    });

    test('words from two layers over one clip merge in time order', () {
      // A clip covered by two transcribe layers has two transcripts, and they
      // arrive concatenated rather than interleaved. Grouping them unsorted
      // would break a cue at the seam and emit captions out of order.
      final captions = exportCaptionsFor([
        word('Later.', 8000, 8600, position: 0),
        word('Earlier.', 1000, 1600, position: 0),
      ]);

      expect(captions.map((c) => c.text), ['Earlier.', 'Later.']);
      expect(captions.first.startMs, lessThan(captions.last.startMs));
    });

    test('cues never overlap, so one frame shows one caption', () {
      final captions = exportCaptionsFor([
        word('First.', 0, 900, position: 0),
        word('Second.', 900, 1800, position: 1),
        word('Third.', 1800, 2700, position: 2),
      ]);

      for (var i = 1; i < captions.length; i++) {
        expect(
          captions[i].startMs,
          greaterThanOrEqualTo(captions[i - 1].endMs),
          reason: 'overlapping cues would draw two captions at once',
        );
      }
    });
  });

  group('exportCaptionsFor with a trim window', () {
    test('drops words the trim cut away', () {
      final captions = exportCaptionsFor(
        [
          word('Before.', 0, 900, position: 0),
          word('Inside.', 5000, 5900, position: 1),
          word('After.', 20000, 20900, position: 2),
        ],
        window: (startMs: 4000, endMs: 10000),
      );

      expect(captions.map((c) => c.text), ['Inside.']);
    });

    test('rebases onto the in-point', () {
      // A trimmed item's clock starts at its in-point, so a caption five
      // seconds into the file but one second into the clip must be drawn at
      // one second or it appears at the wrong moment entirely.
      final captions = exportCaptionsFor(
        [word('Inside.', 5000, 5900, position: 0)],
        window: (startMs: 4000, endMs: 10000),
      );

      expect(captions.single.startMs, 1000);
      expect(captions.single.endMs, 1900);
    });

    test('a word straddling the in-point is kept and clamped', () {
      // Filtering happens before grouping, so a cue across the cut breaks at
      // the cut rather than being discarded whole -- and never starts before
      // zero, which would place it outside the item.
      final captions = exportCaptionsFor(
        [word('Straddling.', 3000, 5000, position: 0)],
        window: (startMs: 4000, endMs: 10000),
      );

      expect(captions.single.startMs, 0);
    });

    test('a word starting exactly on the out-point belongs to the next clip', () {
      final captions = exportCaptionsFor(
        [word('Next.', 10000, 10900, position: 0)],
        window: (startMs: 4000, endMs: 10000),
      );

      expect(captions, isEmpty);
    });

    test('without a window nothing is dropped or shifted', () {
      final captions = exportCaptionsFor([
        word('Whole.', 5000, 5900, position: 0),
      ]);

      expect(captions.single.startMs, 5000);
    });
  });

  group('exportTextsFor', () {
    TextLayer text(int startMs, int endMs) => TextLayer(
          id: 't',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          projectId: 'p',
          startMs: startMs,
          endMs: endMs,
          content: 'Title',
          x: 0.1,
          y: 0.2,
          scale: 1.5,
          rotation: 10,
          trackIndex: 0,
        );

    test("a text inside a clip keeps its time, on the clip's clock", () {
      final texts =
          exportTextsFor([text(3000, 5000)], startMs: 2000, durationMs: 4000);

      expect(texts.single.startMs, 1000);
      expect(texts.single.endMs, 3000);
      expect(texts.single.placement.scale, 1.5);
    });

    test('a text across a cut is shown in both clips', () {
      final title = [text(3000, 7000)];

      final before = exportTextsFor(title, startMs: 0, durationMs: 5000);
      final after = exportTextsFor(title, startMs: 5000, durationMs: 5000);

      expect((before.single.startMs, before.single.endMs), (3000, 5000));
      expect((after.single.startMs, after.single.endMs), (0, 2000));
    });

    test('a text elsewhere on the timeline is not on this clip', () {
      expect(
        exportTextsFor([text(8000, 9000)], startMs: 0, durationMs: 5000),
        isEmpty,
      );
    });
  });

  group('caption placement', () {
    test('a sentence placed on its own overrides its layer', () {
      final placed = [
        word('Hello', 0, 400, position: 0)
            .copyWith(captionX: const Value(0.3), captionY: const Value(0.5)),
        word('there.', 400, 800, position: 1)
            .copyWith(captionX: const Value(0.3), captionY: const Value(0.5)),
        word('Bye', 1200, 1600, position: 2),
        word('now.', 1600, 2000, position: 3),
      ];

      final captions = exportCaptionsFor(
        placed,
        placement: const ItemTransform(y: -0.6),
      );

      expect((captions.first.x, captions.first.y), (0.3, 0.5));
      expect((captions.last.x, captions.last.y), (0.0, -0.6),
          reason: 'the other sentence follows its layer');
    });
  });
}
