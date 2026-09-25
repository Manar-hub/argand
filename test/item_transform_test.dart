import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/timeline/item_transform.dart';
import 'package:argand/core/timeline/timeline_selection.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/features/transcription/timeline_history.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// Maps an NDC point through [transform]'s frame matrix.
(double, double) mapped(
  ItemTransform transform,
  double x,
  double y, {
  double width = 100,
  double height = 100,
}) {
  final (a, b, c, d, tx, ty) =
      transform.ndcMatrix(frameWidth: width, frameHeight: height);
  return (a * x + c * y + tx, b * x + d * y + ty);
}

Matcher near((double, double) point) => predicate<(double, double)>(
      (value) =>
          (value.$1 - point.$1).abs() < 1e-9 &&
          (value.$2 - point.$2).abs() < 1e-9,
      'close to $point',
    );

void main() {
  group('ItemTransform gestures', () {
    test('a drag moves by the share of the frame it crossed', () {
      final moved = ItemTransform.identity.afterGesture(
        frameWidth: 200,
        frameHeight: 100,
        panX: 50,
        panY: 25,
      );

      // Half the half-width across; half the half-height down, which is
      // negative because up is positive.
      expect(moved.x, closeTo(0.5, 1e-9));
      expect(moved.y, closeTo(-0.5, 1e-9));
    });

    test('a pinch scales, within bounds', () {
      const start = ItemTransform(scale: 2);

      expect(
        start.afterGesture(frameWidth: 1, frameHeight: 1, pinch: 1.5).scale,
        3,
      );
      expect(
        start.afterGesture(frameWidth: 1, frameHeight: 1, pinch: 10).scale,
        ItemTransform.maxScale,
      );
      expect(
        start.afterGesture(frameWidth: 1, frameHeight: 1, pinch: 0.01).scale,
        ItemTransform.minScale,
      );
    });

    test('a twist near a quarter turn lands on it', () {
      expect(ItemTransform.snapRotation(88), 90);
      expect(ItemTransform.snapRotation(-3), 0);
      expect(ItemTransform.snapRotation(47), 47);
    });

    test('rotation stays within one turn either way', () {
      expect(ItemTransform.snapRotation(270), -90);
      expect(ItemTransform.snapRotation(-180), 180);
      expect(ItemTransform.snapRotation(725), 5);
    });

    test('four quarter turns come back upright', () {
      var turned = ItemTransform.identity;
      for (var i = 0; i < 4; i++) {
        turned = turned.quarterTurned();
      }
      expect(turned.rotation, 0);
    });

    test('round-trips through the event log', () {
      const transform = ItemTransform(x: 0.2, y: -0.4, scale: 1.5, rotation: 30);
      expect(ItemTransform.fromJson(transform.toJson()), transform);
    });
  });

  group('the render matrix', () {
    test('the identity leaves the frame alone', () {
      expect(mapped(ItemTransform.identity, 0.3, -0.7), near((0.3, -0.7)));
    });

    test('a clockwise quarter turn sends the right edge to the bottom', () {
      const turned = ItemTransform(rotation: 90);

      expect(mapped(turned, 1, 0), near((0, -1)));
      expect(mapped(turned, 0, 1), near((1, 0)));
    });

    test('turning a wide frame does not skew the picture', () {
      // On a 200x100 frame the right edge's midpoint is 100px from the
      // centre. Turned clockwise it must still be 100px away -- straight
      // down, which is two full half-heights, so NDC y = -2.
      const turned = ItemTransform(rotation: 90);

      expect(
        mapped(turned, 1, 0, width: 200, height: 100),
        near((0, -2)),
      );
    });

    test('scale and move apply after the turn', () {
      const transform = ItemTransform(x: 0.5, y: 0.25, scale: 2);

      expect(mapped(transform, 0.1, 0.1), near((0.7, 0.45)));
    });
  });

  group('placement undo', () {
    late AppDatabase database;
    late TranscriptRepository repository;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TranscriptRepository(database, MediaConverter());
    });

    tearDown(() => database.close());

    Future<({String projectId, String clipId, String layerId})> seeded() async {
      final projectId = repository.newId();
      final clipId = repository.newId();
      await database.createEmptyProject(projectId: projectId, title: 'p');
      await database.appendClip(
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

    test('one gesture over two items undoes in one step', () async {
      final ids = await seeded();
      const moved = ItemTransform(x: 0.3, scale: 1.4, rotation: 90);

      await repository.applyPlacements(
        projectId: ids.projectId,
        changes: [
          (
            kind: TimelineItemKind.clip,
            id: ids.clipId,
            before: ItemTransform.identity,
            after: moved,
          ),
          (
            kind: TimelineItemKind.layer,
            id: ids.layerId,
            before: ItemTransform.captionDefault,
            after: const ItemTransform(y: 0.5, scale: 1.2),
          ),
        ],
      );

      expect((await database.findClip(ids.clipId))!.framing, moved);
      expect(
        (await database.findLayer(ids.layerId))!.captionPlacement,
        const ItemTransform(y: 0.5, scale: 1.2),
      );

      await repository.undoProject(ids.projectId);

      expect(
        (await database.findClip(ids.clipId))!.framing,
        ItemTransform.identity,
      );
      expect(
        (await database.findLayer(ids.layerId))!.captionPlacement,
        ItemTransform.captionDefault,
      );

      await repository.redoProject(ids.projectId);
      expect((await database.findClip(ids.clipId))!.framing, moved);
    });

    test('a gesture that changed nothing records nothing', () async {
      final ids = await seeded();

      await repository.applyPlacements(
        projectId: ids.projectId,
        changes: [
          (
            kind: TimelineItemKind.clip,
            id: ids.clipId,
            before: ItemTransform.identity,
            after: ItemTransform.identity,
          ),
        ],
      );
      // The only thing left to undo is the layer that was added.
      await repository.undoProject(ids.projectId);

      expect(await database.findLayer(ids.layerId), isNull);
    });

    test('a text can be added, edited, and taken back', () async {
      final ids = await seeded();

      final textId = (await repository.addTextLayer(
        projectId: ids.projectId,
        startMs: 1000,
        endMs: 4000,
        content: '  Hello  ',
      ))!;
      await repository.editTextLayer(id: textId, content: 'Hello world');

      var texts = await repository.textLayersForProject(ids.projectId);
      expect(texts.single.content, 'Hello world');

      await repository.undoProject(ids.projectId);
      texts = await repository.textLayersForProject(ids.projectId);
      expect(texts.single.content, 'Hello', reason: 'trimmed when added');

      await repository.undoProject(ids.projectId);
      expect(await repository.textLayersForProject(ids.projectId), isEmpty);

      await repository.redoProject(ids.projectId);
      expect(await repository.textLayersForProject(ids.projectId), hasLength(1));
    });

    test('texts at the same moment go on separate rows', () async {
      final ids = await seeded();
      Future<int> rowOf(int start, int end) async {
        final id = (await repository.addTextLayer(
          projectId: ids.projectId,
          startMs: start,
          endMs: end,
          content: 'T',
        ))!;
        final texts = await repository.textLayersForProject(ids.projectId);
        return texts.firstWhere((t) => t.id == id).trackIndex;
      }

      expect(await rowOf(0, 3000), 0);
      expect(await rowOf(1000, 4000), 1, reason: 'overlaps the first');
      expect(await rowOf(2000, 2500), 2, reason: 'overlaps both');
      expect(await rowOf(5000, 6000), 0, reason: 'clear of everything');
    });

    /// Two sentences on the seeded layer: "Hello there." and "Bye now."
    Future<String> transcribed(({String projectId, String clipId, String layerId}) ids) {
      WhisperTranscribeSegment segment(int from, int to, String text) =>
          WhisperTranscribeSegment(
            fromTs: Duration(milliseconds: from),
            toTs: Duration(milliseconds: to),
            text: text,
          );
      return repository.saveClipTranscript(
        projectId: ids.projectId,
        clipId: ids.clipId,
        language: TranscriptionLanguage.english,
        speakerSpans: const [],
        layerId: ids.layerId,
        result: WhisperTranscribeResponse(
          type: 'transcribe',
          text: 'Hello there. Bye now.',
          segments: [
            segment(0, 400, ' Hello'),
            segment(400, 800, ' there.'),
            segment(1200, 1600, ' Bye'),
            segment(1600, 2000, ' now.'),
          ],
        ),
      );
    }

    Future<List<Word>> wordsOf(String transcriptId) =>
        repository.watchWords(transcriptId).first;

    test('a sentence placed alone moves without its neighbour', () async {
      final ids = await seeded();
      final transcriptId = await transcribed(ids);
      final first = sentenceItem(
        transcriptId: transcriptId,
        fromPosition: 0,
        toPosition: 1,
      );

      await repository.applyPlacements(
        projectId: ids.projectId,
        changes: [
          (
            kind: TimelineItemKind.sentence,
            id: first.id,
            before: null,
            after: const ItemTransform(y: 0.5, scale: 1.3),
          ),
        ],
      );

      final words = await wordsOf(transcriptId);
      expect(words[0].captionPlacement, const ItemTransform(y: 0.5, scale: 1.3));
      expect(words[1].captionPlacement, const ItemTransform(y: 0.5, scale: 1.3));
      expect(words[2].captionPlacement, isNull, reason: 'the next sentence');

      // Undo hands it back to its layer rather than pinning it anywhere.
      await repository.undoProject(ids.projectId);
      expect((await wordsOf(transcriptId))[0].captionPlacement, isNull);
    });

    test('retyping a placed sentence keeps it where it was put', () async {
      final ids = await seeded();
      final transcriptId = await transcribed(ids);
      await repository.applyPlacements(
        projectId: ids.projectId,
        changes: [
          (
            kind: TimelineItemKind.sentence,
            id: sentenceItem(
              transcriptId: transcriptId,
              fromPosition: 0,
              toPosition: 1,
            ).id,
            before: null,
            after: const ItemTransform(y: 0.4),
          ),
        ],
      );

      await repository.replaceSentence(
        transcriptId: transcriptId,
        fromPosition: 0,
        toPosition: 1,
        text: 'Hi there friend.',
      );

      final words = await wordsOf(transcriptId);
      expect(words.take(3).map((w) => w.word), ['Hi', 'there', 'friend.']);
      for (final word in words.take(3)) {
        expect(word.captionPlacement, const ItemTransform(y: 0.4));
      }
      expect(words[3].captionPlacement, isNull);
    });

    test('removing a text can be undone', () async {
      final ids = await seeded();
      final textId = (await repository.addTextLayer(
        projectId: ids.projectId,
        startMs: 0,
        endMs: 3000,
        content: 'Title',
      ))!;

      await repository.removeTextLayer(textId);
      expect(await repository.textLayersForProject(ids.projectId), isEmpty);

      await repository.undoProject(ids.projectId);
      expect(await repository.textLayersForProject(ids.projectId), hasLength(1));
    });

    test('a duplicate carries framing, caption placement and texts', () async {
      final ids = await seeded();
      await repository.applyPlacements(
        projectId: ids.projectId,
        changes: [
          (
            kind: TimelineItemKind.clip,
            id: ids.clipId,
            before: ItemTransform.identity,
            after: const ItemTransform(scale: 2),
          ),
          (
            kind: TimelineItemKind.layer,
            id: ids.layerId,
            before: ItemTransform.captionDefault,
            after: const ItemTransform(y: 0.6),
          ),
        ],
      );
      await repository.addTextLayer(
        projectId: ids.projectId,
        startMs: 0,
        endMs: 2000,
        content: 'Copy me',
      );

      final copyId = await repository.duplicateProject(
        projectId: ids.projectId,
        title: 'copy',
      );

      final clip = (await database.clipsForProject(copyId)).single;
      final layer = (await database.layersForProject(copyId)).single;
      final text = (await repository.textLayersForProject(copyId)).single;
      expect(clip.scale, 2);
      expect(layer.captionY, 0.6);
      expect(text.content, 'Copy me');
    });
  });
}
