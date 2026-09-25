import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/item_transform.dart';
import '../../core/timeline/timeline_event.dart';
import '../../core/timeline/timeline_selection.dart';

/// Puts a timeline event's recorded state back into the database.
///
/// Given the half of the payload to move to — `before` when undoing, `after`
/// when redoing — this writes the rows that state describes. Undo and redo are
/// the same function with the two halves swapped, which is why there is no
/// separate redo stack anywhere in this design.
typedef TimelineInverse = Future<void> Function(
  AppDatabase db,
  Map<String, Object?> side,
);

/// How each kind of change is applied, in either direction.
///
/// **This map is the whole cost of making a new action undoable.** Add a code
/// to [TimelineEventKind], add an entry here, and record the event where the
/// action happens. No column, no migration, no change to the control — the
/// payload is JSON, so whatever shape the new action needs already fits.
///
/// Every entry writes *state*, never a delta. A delta would have to be applied
/// to whatever the row happens to hold now; state is true regardless of what
/// else has happened since, which is what lets these run in any order the
/// history asks for.
final Map<TimelineEventKind, TimelineInverse> timelineInverses = {
  // A split is two rows over one file. Undoing restores the first clip's
  // out-point and retires the second; redoing does the reverse. The second
  // clip is soft-deleted rather than dropped, so its id, its position and the
  // transcripts copied onto it all survive the round trip.
  TimelineEventKind.clipSplit: (db, side) async {
    final leftId = side['leftClipId'] as String?;
    final rightId = side['rightClipId'] as String?;
    if (leftId == null || rightId == null) return;

    await db.trimClip(
      clipId: leftId,
      startMs: (side['leftStartMs'] as num?)?.toInt() ?? 0,
      endMs: (side['leftEndMs'] as num?)?.toInt() ?? 0,
    );
    await db.setClipRetired(
      clipId: rightId,
      retired: side['rightRetired'] == true,
    );
  },

  // A layer is a request, and a pure row: restoring one is restoring its range
  // and whether it is retired.
  TimelineEventKind.layerAdd: (db, side) async {
    final layerId = side['layerId'] as String?;
    if (layerId == null) return;

    await db.setLayerRetired(
      layerId: layerId,
      retired: side['retired'] == true,
    );
  },

  // A transcription run is the transcripts it wrote, and nothing else.
  // Recorded separately from the layer that asked for it because they are two
  // actions: drawing a layer and running the engine over it happen at
  // different moments, and collapsing them means one undo takes back both.
  TimelineEventKind.transcribeRun: (db, side) async {
    final ids = (side['transcriptIds'] as List?)?.cast<String>();
    if (ids == null) return;

    await db.setTranscriptsRetired(
      transcriptIds: ids,
      retired: side['retired'] == true,
    );
  },

  TimelineEventKind.layerMove: (db, side) async {
    final layerId = side['layerId'] as String?;
    if (layerId == null) return;

    await db.moveLayer(
      layerId: layerId,
      startMs: (side['startMs'] as num?)?.toInt() ?? 0,
      endMs: (side['endMs'] as num?)?.toInt() ?? 0,
    );
  },

  TimelineEventKind.transformBatch: (db, side) async {
    final items = side['items'];
    if (items is! List) return;

    for (final entry in items.whereType<Map>()) {
      final kind = entry['kind'];
      final id = entry['id'];
      final placement = entry['transform'];
      if (id is! String) continue;

      await writePlacement(
        db,
        kind: TimelineItemKind.values.asNameMap()[kind],
        id: id,
        // Null is a sentence handed back to its layer.
        transform: placement is Map
            ? ItemTransform.fromJson(Map<String, Object?>.from(placement))
            : null,
      );
    }
  },

  TimelineEventKind.lookBatch: (db, side) async {
    final items = side['items'];
    if (items is List) {
      for (final entry in items.whereType<Map>()) {
        final id = entry['id'];
        if (id is! String) continue;
        await writeLook(
          db,
          kind: TimelineItemKind.values.asNameMap()[entry['kind']],
          id: id,
          look: ItemLook.decode(entry['look'] as String?),
        );
      }
    }
    // Sentences styled on their own that "all captions" handed back to their
    // layers: each word's own look, as it was on that side.
    final words = side['wordLooks'];
    if (words is Map) {
      await db.setWordLooks({
        for (final MapEntry(:key, :value) in words.entries)
          if (key is String) key: value as String?,
      });
    }
  },

  // Adding and removing a text are the same switch thrown opposite ways.
  TimelineEventKind.textAdd: _setTextRetired,
  TimelineEventKind.textRemove: _setTextRetired,

  TimelineEventKind.textEdit: (db, side) async {
    final id = side['id'] as String?;
    if (id == null) return;

    await db.updateTextLayer(
      id: id,
      content: side['content'] as String?,
      startMs: (side['startMs'] as num?)?.toInt(),
      endMs: (side['endMs'] as num?)?.toInt(),
    );
  },
};

Future<void> _setTextRetired(AppDatabase db, Map<String, Object?> side) async {
  final id = side['id'] as String?;
  if (id == null) return;
  await db.setTextLayerRetired(id: id, retired: side['retired'] == true);
}

/// Writes [transform] onto the row it belongs to: a clip's framing, a
/// layer's caption placement, or a text's placement.
///
/// **One writer for every kind**, used by the gesture that commits a change
/// and by undo replaying it, so the two can never write different columns.
///
/// A null [transform] means "no placement of its own", which only a sentence
/// can have -- it then follows its layer again. Every other kind always has
/// one, so null leaves it untouched.
Future<void> writePlacement(
  AppDatabase db, {
  required TimelineItemKind? kind,
  required String id,
  required ItemTransform? transform,
}) async {
  if (kind == TimelineItemKind.sentence) {
    final sentence = sentenceOf((kind: kind!, id: id));
    if (sentence == null) return;
    await db.setSentencePlacement(
      transcriptId: sentence.transcriptId,
      fromPosition: sentence.fromPosition,
      toPosition: sentence.toPosition,
      x: transform?.x,
      y: transform?.y,
      // Captions keep upright, as on the layer.
      scale: transform?.scale,
    );
    return;
  }
  if (transform == null) return;

  switch (kind) {
    case TimelineItemKind.clip:
      await db.setClipFraming(
        clipId: id,
        x: transform.x,
        y: transform.y,
        scale: transform.scale,
        rotation: transform.rotation,
      );
    case TimelineItemKind.layer:
      // Captions keep upright: a turned subtitle is a puzzle, not a style.
      await db.setLayerCaptionPlacement(
        layerId: id,
        x: transform.x,
        y: transform.y,
        scale: transform.scale,
      );
    case TimelineItemKind.text:
      await db.updateTextLayer(
        id: id,
        x: transform.x,
        y: transform.y,
        scale: transform.scale,
        rotation: transform.rotation,
      );
    case TimelineItemKind.sentence:
      // Handled above.
      break;
    case null:
      // A kind written by a newer build; nothing this one can place.
      break;
  }
}

/// Writes [look] onto the row it belongs to. Null clears it: a layer back to
/// the default look, a sentence back to its layer's, a text back to plain.
///
/// One writer for the change and for undo replaying it, as [writePlacement].
Future<void> writeLook(
  AppDatabase db, {
  required TimelineItemKind? kind,
  required String id,
  required ItemLook? look,
}) async {
  final json = look?.encode();
  switch (kind) {
    case TimelineItemKind.layer:
      await db.setLayerCaptionLook(layerId: id, look: json);
    case TimelineItemKind.sentence:
      final sentence = sentenceOf((kind: kind!, id: id));
      if (sentence == null) return;
      await db.setSentenceLook(
        transcriptId: sentence.transcriptId,
        fromPosition: sentence.fromPosition,
        toPosition: sentence.toPosition,
        look: json,
      );
    case TimelineItemKind.text:
      await db.setTextLook(id: id, look: json);
    case TimelineItemKind.clip:
    case null:
      // A clip has no words to style; a kind from a newer build is skipped.
      break;
  }
}

/// One item's look before and after a restyle; null is "none of its own".
typedef LookChange = ({
  TimelineItemKind kind,
  String id,
  ItemLook? before,
  ItemLook? after,
});

/// The payload for one restyle, with [wordLooks] carrying the per-word looks
/// an "all captions" restyle cleared -- before as they were, after as null.
TimelineEventPayload lookBatchPayload(
  List<LookChange> changes, {
  Map<String, String?> wordLooks = const {},
}) {
  List<Map<String, Object?>> side(bool after) => [
        for (final change in changes)
          {
            'kind': change.kind.name,
            'id': change.id,
            'look': (after ? change.after : change.before)?.encode(),
          },
      ];

  return TimelineEventPayload(
    before: {'items': side(false), 'wordLooks': wordLooks},
    after: {
      'items': side(true),
      'wordLooks': {for (final id in wordLooks.keys) id: null},
    },
  );
}

/// One item's placement before and after a gesture.
///
/// Null on either side means "no placement of its own", which only a sentence
/// can be: it follows its layer.
typedef PlacementChange = ({
  TimelineItemKind kind,
  String id,
  ItemTransform? before,
  ItemTransform? after,
});

/// The payload for a gesture over one or more items.
TimelineEventPayload transformBatchPayload(List<PlacementChange> changes) {
  List<Map<String, Object?>> side(bool after) => [
        for (final change in changes)
          {
            'kind': change.kind.name,
            'id': change.id,
            'transform': (after ? change.after : change.before)?.toJson(),
          },
      ];

  return TimelineEventPayload(
    before: {'items': side(false)},
    after: {'items': side(true)},
  );
}

/// The payload for adding a text layer.
TimelineEventPayload textAddPayload({required String id}) {
  return TimelineEventPayload(
    before: {'id': id, 'retired': true},
    after: {'id': id, 'retired': false},
  );
}

/// The payload for removing a text layer.
TimelineEventPayload textRemovePayload({required String id}) {
  return TimelineEventPayload(
    before: {'id': id, 'retired': false},
    after: {'id': id, 'retired': true},
  );
}

/// The payload for changing a text's words or timing.
TimelineEventPayload textEditPayload({
  required TextLayer before,
  required String content,
  required int startMs,
  required int endMs,
}) {
  return TimelineEventPayload(
    before: {
      'id': before.id,
      'content': before.content,
      'startMs': before.startMs,
      'endMs': before.endMs,
    },
    after: {
      'id': before.id,
      'content': content,
      'startMs': startMs,
      'endMs': endMs,
    },
  );
}

/// The placement stored on each kind of row.
extension ClipFraming on MediaClip {
  ItemTransform get framing =>
      ItemTransform(x: offsetX, y: offsetY, scale: scale, rotation: rotation);
}

extension WordCaptionPlacement on Word {
  /// The placement of this word's sentence, or null when it follows its
  /// layer.
  ItemTransform? get captionPlacement => captionX == null
      ? null
      : ItemTransform(
          x: captionX!,
          y: captionY ?? ItemTransform.captionDefault.y,
          scale: captionScale ?? 1,
        );
}

extension LayerCaptionLook on TranscribeLayer {
  /// This layer's own look, or null for the default.
  ItemLook? get look => ItemLook.decode(captionLook);
}

extension TextLook on TextLayer {
  ItemLook? get itemLook => ItemLook.decode(look);
}

extension WordCaptionLook on Word {
  /// The look of this word's sentence when styled on its own.
  ItemLook? get ownLook => ItemLook.decode(captionLook);
}

extension LayerCaptionPlacement on TranscribeLayer {
  ItemTransform get captionPlacement =>
      ItemTransform(x: captionX, y: captionY, scale: captionScale);
}

extension TextPlacement on TextLayer {
  ItemTransform get placement =>
      ItemTransform(x: x, y: y, scale: scale, rotation: rotation);
}

/// The payload for a split, in both directions.
///
/// Written here rather than at the call site so the shape and the inverse that
/// reads it stay in one place — they are the two halves of one contract, and
/// splitting them across files is how a payload key quietly stops matching.
TimelineEventPayload splitPayload({
  required String leftClipId,
  required String rightClipId,
  required int wholeStartMs,
  required int wholeEndMs,
  required int atMs,
}) {
  return TimelineEventPayload(
    before: {
      'leftClipId': leftClipId,
      'rightClipId': rightClipId,
      'leftStartMs': wholeStartMs,
      'leftEndMs': wholeEndMs,
      'rightRetired': true,
    },
    after: {
      'leftClipId': leftClipId,
      'rightClipId': rightClipId,
      'leftStartMs': wholeStartMs,
      'leftEndMs': atMs,
      'rightRetired': false,
    },
  );
}

/// The payload for adding a layer.
TimelineEventPayload layerAddPayload({required String layerId}) {
  return TimelineEventPayload(
    before: {'layerId': layerId, 'retired': true},
    after: {'layerId': layerId, 'retired': false},
  );
}

/// The payload for one transcription run.
///
/// Carries the ids the run actually wrote rather than the layer it ran over,
/// so undoing a rerun retires the new words without resurrecting the ones that
/// rerun replaced.
TimelineEventPayload transcribeRunPayload({
  required List<String> transcriptIds,
}) {
  return TimelineEventPayload(
    before: {'transcriptIds': transcriptIds, 'retired': true},
    after: {'transcriptIds': transcriptIds, 'retired': false},
  );
}

/// The payload for moving or resizing a layer.
TimelineEventPayload layerMovePayload({
  required String layerId,
  required int fromStartMs,
  required int fromEndMs,
  required int toStartMs,
  required int toEndMs,
}) {
  return TimelineEventPayload(
    before: {
      'layerId': layerId,
      'startMs': fromStartMs,
      'endMs': fromEndMs,
    },
    after: {'layerId': layerId, 'startMs': toStartMs, 'endMs': toEndMs},
  );
}

/// Turns a stored row into a step the merged history can order.
HistoryStep stepOf(TimelineEvent event) =>
    (log: HistoryLog.timeline, id: event.id, at: event.createdAt);

/// Turns a stored transcript row into the same shape.
HistoryStep stepOfEdit(EditEvent event) =>
    (log: HistoryLog.transcript, id: event.id, at: event.createdAt);

/// Drift needs a [Value] even to write null; kept here so the inverses above
/// read as plain data rather than as database plumbing.
Value<T> valueOf<T>(T value) => Value(value);
