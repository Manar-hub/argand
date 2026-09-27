import 'package:argand/core/database/database.dart' show TrackKind;
import 'package:argand/core/timeline/layer_drag.dart';
import 'package:argand/core/timeline/timeline_items.dart';
import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineBlock _block(
  TimelineItemKind kind,
  String id,
  String track,
  int start,
  int end, {
  int min = 0,
  int max = 60000,
  bool canChangeTrack = true,
  String? layerId,
  bool follows = false,
}) =>
    (
      item: (kind: kind, id: id),
      trackId: track,
      startMs: start,
      endMs: end,
      minStartMs: min,
      maxEndMs: max,
      canChangeTrack: canChangeTrack,
      layerId: layerId,
      follows: follows,
    );

const _tracks = <TrackSlot>[
  (id: 'm1', kind: TrackKind.media),
  (id: 'm2', kind: TrackKind.media),
  (id: 'v', kind: TrackKind.video),
  (id: 'a', kind: TrackKind.audio),
];

void main() {
  final text = _block(TimelineItemKind.text, 't', 'm1', 1000, 3000);
  final image = _block(TimelineItemKind.image, 'i', 'm2', 5000, 8000);

  group('planMove', () {
    test('a rigid group stops at the start of the project', () {
      final plan = planMove(
        blocks: [text, image],
        moving: {text.item, image.item},
        deltaMs: -4000,
        deltaRows: 0,
        tracks: _tracks,
      );
      // The text can go back one second, so the image goes back one too.
      expect(plan.deltaMs, -1000);
      expect(plan.blocks.map((b) => b.startMs), [0, 4000]);
      expect(plan.valid, isTrue);
    });

    test('dragging up past the top track is held at the top', () {
      final plan = planMove(
        blocks: [text, image],
        moving: {image.item},
        deltaMs: 0,
        deltaRows: -5,
        tracks: _tracks,
      );
      expect(plan.deltaRows, -1);
      expect(plan.blocks.single.trackId, 'm1');
      expect(plan.valid, isTrue, reason: 'nothing on m1 at 5-8s');
    });

    test('rows past the last track make new tracks', () {
      final plan = planMove(
        blocks: [text],
        moving: {text.item},
        deltaMs: 0,
        deltaRows: 4,
        tracks: _tracks,
      );
      expect(plan.newTracks, 1);
      expect(plan.blocks.single.newTrack, 0);
      expect(plan.blocks.single.trackId, isNull);
      expect(plan.valid, isTrue);
    });

    test('media is refused on the video and the audio tracks', () {
      for (final rows in [2, 3]) {
        final plan = planMove(
          blocks: [text],
          moving: {text.item},
          deltaMs: 0,
          deltaRows: rows,
          tracks: _tracks,
        );
        expect(plan.valid, isFalse, reason: 'row +$rows');
      }
    });

    test('a drop on top of something is refused', () {
      final plan = planMove(
        blocks: [text, image],
        moving: {text.item},
        deltaMs: 4500,
        deltaRows: 1,
        tracks: _tracks,
      );
      expect(plan.valid, isFalse);
    });

    test('a sentence may not pass its neighbours', () {
      final sentence = _block(
        TimelineItemKind.sentence,
        's',
        'm1',
        4000,
        5000,
        min: 3500,
        max: 6000,
        layerId: 'L',
        follows: true,
      );
      final plan = planMove(
        blocks: [sentence],
        moving: {sentence.item},
        deltaMs: 5000,
        deltaRows: 0,
        tracks: _tracks,
      );
      expect(plan.deltaMs, 1000);
    });

    test('a layer carries its sentences to another track, not in time', () {
      final layer = _block(
        TimelineItemKind.layer,
        'L',
        'm2',
        0,
        10000,
        layerId: 'L',
      );
      final sentence = _block(
        TimelineItemKind.sentence,
        's',
        'm2',
        2000,
        3000,
        layerId: 'L',
        follows: true,
      );
      final plan = planMove(
        blocks: [layer, sentence, text],
        moving: {layer.item},
        deltaMs: 500,
        deltaRows: -1,
        tracks: _tracks,
      );
      final carried =
          plan.blocks.firstWhere((b) => b.item == sentence.item);
      expect(carried.trackId, 'm1');
      expect(carried.startMs, 2000);
      expect(plan.valid, isFalse, reason: 'the text is on m1 at 1-3s');
    });

    test("a layer's own sentences never collide with it", () {
      final layer = _block(
        TimelineItemKind.layer,
        'L',
        'm2',
        0,
        10000,
        layerId: 'L',
      );
      final sentence = _block(
        TimelineItemKind.sentence,
        's',
        'm1',
        2000,
        3000,
        layerId: 'L',
      );
      final plan = planMove(
        blocks: [layer, sentence],
        moving: {sentence.item},
        deltaMs: 0,
        deltaRows: 1,
        tracks: _tracks,
      );
      expect(plan.valid, isTrue);
    });

    test('a sound slides in time and stays on its track', () {
      final sound = _block(
        TimelineItemKind.audio,
        'c',
        'a',
        0,
        4000,
        max: 5000,
        canChangeTrack: false,
      );
      final plan = planMove(
        blocks: [sound],
        moving: {sound.item},
        deltaMs: 3000,
        deltaRows: -2,
        tracks: _tracks,
      );
      expect(plan.deltaMs, 1000, reason: 'the file ends a second later');
      expect(plan.blocks.single.trackId, 'a');
      expect(plan.valid, isTrue);
    });
  });

  group('planResize', () {
    test('an end stops at the next item on its track', () {
      final other = _block(TimelineItemKind.text, 'o', 'm1', 4000, 5000);
      final bounds = planResize(
        block: text,
        blocks: [text, other, image],
        grip: LayerGrip.end,
        deltaMs: 10000,
        pixelsPerSecond: 100,
      );
      expect(bounds, (startMs: 1000, endMs: 4000));
    });
  });

  test('retimeWords stretches each word by its share', () {
    final words = retimeWords(
      [
        (id: 'a', startMs: 1000, endMs: 1500),
        (id: 'b', startMs: 1500, endMs: 3000),
      ],
      startMs: 2000,
      endMs: 6000,
    );
    expect(words, [
      (id: 'a', startMs: 2000, endMs: 3000),
      (id: 'b', startMs: 3000, endMs: 6000),
    ]);
  });
}
