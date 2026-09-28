import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/timeline/item_look.dart';
import '../../core/timeline/item_transform.dart';
import '../../core/timeline/timeline_event.dart';
import '../../core/timeline/timeline_selection.dart';

/// Puts a timeline event's recorded state back into the database.
typedef TimelineInverse = Future<void> Function(
  AppDatabase db,
  Map<String, Object?> side,
);

/// How each kind of change is applied, in either direction.
final Map<TimelineEventKind, TimelineInverse> timelineInverses = {
  // A split is two rows over one file. Undoing restores the first clip's
  // out-point and retires the second; redoing does the reverse.
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
  TimelineEventKind.transcribeRun: (db, side) async {
    final ids = (side['transcriptIds'] as List?)?.cast<String>();
    if (ids == null) return;

    await db.setTranscriptsRetired(
      transcriptIds: ids,
      retired: side['retired'] == true,
    );
  },

  TimelineEventKind.audioTrim: (db, side) async {
    final clipId = side['clipId'] as String?;
    if (clipId == null) return;
    await db.setAudioOffsets(
      clipId: clipId,
      startOffsetMs: (side['startOffsetMs'] as num?)?.toInt() ?? 0,
      endOffsetMs: (side['endOffsetMs'] as num?)?.toInt() ?? 0,
    );
  },

  TimelineEventKind.audioMute: (db, side) async {
    final clipIds = side['clipIds'];
    if (clipIds is! List) return;
    final muted = side['muted'] == true;
    for (final id in clipIds.whereType<String>()) {
      await db.setAudioMuted(id, muted);
    }
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

  TimelineEventKind.itemsPlace: _applyPlacement,

  // A clip taken off the timeline is retired, not deleted; its media stays.
  TimelineEventKind.clipRemove: (db, side) async {
    final id = side['clipId'] as String?;
    if (id == null) return;
    await db.setClipRetired(clipId: id, retired: side['retired'] == true);
  },
  TimelineEventKind.imageAdd: _setImageRetired,
  TimelineEventKind.imageRemove: _setImageRetired,

  TimelineEventKind.translationEdit: (db, side) async {
    final id = side['id'] as String?;
    final content = side['content'] as String?;
    if (id == null || content == null) return;
    await db.updateTranslationLine(id: id, content: content);
  },
  TimelineEventKind.translationSet: (db, side) async {
    final lines = side['lines'];
    if (lines is! List) return;
    for (final entry in lines.whereType<Map>()) {
      final id = entry['id'];
      if (id is! String) continue;
      final content = entry['content'] as String?;
      if (content != null) {
        await db.updateTranslationLine(id: id, content: content);
      }
      await db.setTranslationLineRetired(
        id: id,
        retired: entry['retired'] == true,
      );
    }
  },
  TimelineEventKind.translationRemove: (db, side) async {
    final ids = side['ids'];
    if (ids is! List) return;
    for (final id in ids.whereType<String>()) {
      await db.setTranslationLineRetired(
        id: id,
        retired: side['retired'] == true,
      );
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

Future<void> _setImageRetired(AppDatabase db, Map<String, Object?> side) async {
  final id = side['id'] as String?;
  if (id == null) return;
  await db.setImageLayerRetired(id: id, retired: side['retired'] == true);
}

int? _int(Object? value) => (value as num?)?.toInt();

/// Where each item sits on the timeline, as one side of an `itemsPlace`
/// event recorded it. Values are the rows' own: a translation line's times
/// are in its clip's time, like its words'.
Future<void> _applyPlacement(AppDatabase db, Map<String, Object?> side) async {
  // Tracks first, so the items below have somewhere to be.
  final tracks = side['tracks'];
  if (tracks is List) {
    for (final entry in tracks.whereType<Map>()) {
      final id = entry['id'];
      if (id is! String) continue;
      await db.setTrackRetired(id: id, retired: entry['retired'] == true);
    }
  }
  final trackOrder = side['trackOrder'];
  if (trackOrder is List) {
    await db.setTrackOrder(trackOrder.whereType<String>().toList());
  }

  final items = side['items'];
  if (items is List) {
    for (final entry in items.whereType<Map>()) {
      final id = entry['id'];
      if (id is! String) continue;
      final start = _int(entry['startMs']);
      final end = _int(entry['endMs']);
      final trackId = entry['trackId'] as String?;
      switch (TimelineItemKind.values.asNameMap()[entry['kind']]) {
        case TimelineItemKind.layer:
          if (start != null && end != null) {
            await db.moveLayer(layerId: id, startMs: start, endMs: end);
          }
          if (trackId != null) {
            await db.setLayerTrack(layerId: id, trackId: trackId);
          }
        case TimelineItemKind.text:
          await db.updateTextLayer(
            id: id,
            startMs: start,
            endMs: end,
            trackId: trackId,
          );
        case TimelineItemKind.translation:
          await db.updateTranslationLine(
            id: id,
            startMs: start,
            endMs: end,
            trackId: trackId,
          );
        case TimelineItemKind.image:
          await db.updateImageLayer(
            id: id,
            startMs: start,
            endMs: end,
            trackId: trackId,
          );
        case TimelineItemKind.clip:
        case TimelineItemKind.sentence:
        case TimelineItemKind.audio:
        case null:
          // Clips move by the clip order, sentences by their words, sounds by
          // their offsets -- all below.
          break;
      }
    }
  }

  final words = side['words'];
  if (words is List) {
    await db.setWordPlacements([
      for (final entry in words.whereType<Map>())
        if (entry['id'] case final String id)
          (
            id: id,
            startMs: _int(entry['startMs']) ?? 0,
            endMs: _int(entry['endMs']) ?? 0,
            trackId: entry['trackId'] as String?,
          ),
    ]);
  }

  final audio = side['audio'];
  if (audio is List) {
    for (final entry in audio.whereType<Map>()) {
      final clipId = entry['clipId'];
      if (clipId is! String) continue;
      await db.setAudioOffsets(
        clipId: clipId,
        startOffsetMs: _int(entry['startOffsetMs']) ?? 0,
        endOffsetMs: _int(entry['endOffsetMs']) ?? 0,
      );
    }
  }

  final clipOrder = side['clipOrder'];
  final projectId = side['projectId'];
  if (clipOrder is List && projectId is String) {
    await db.reorderClips(
      projectId: projectId,
      orderedIds: clipOrder.whereType<String>().toList(),
    );
  }
}

Future<void> _setTextRetired(AppDatabase db, Map<String, Object?> side) async {
  final id = side['id'] as String?;
  if (id == null) return;
  await db.setTextLayerRetired(id: id, retired: side['retired'] == true);
}

/// Writes [transform] onto the row it belongs to: a clip's framing, a layer's
/// caption placement, or a text's placement.
Future<void> writePlacement(
  AppDatabase db, {
  required TimelineItemKind? kind,
  required String id,
  required ItemTransform? transform,
}) async {
  if (kind == TimelineItemKind.translation) {
    // Null hands it back to its layer, like a sentence.
    await db.setTranslationLinePlacement(
      id: id,
      x: transform?.x,
      y: transform?.y,
      scale: transform?.scale,
    );
    return;
  }
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
    case TimelineItemKind.image:
      await db.updateImageLayer(
        id: id,
        x: transform.x,
        y: transform.y,
        scale: transform.scale,
        rotation: transform.rotation,
      );
    case TimelineItemKind.sentence:
    case TimelineItemKind.translation:
      // Handled above.
      break;
    case TimelineItemKind.audio:
      // Sound has no place on the picture.
      break;
    case null:
      // A kind written by a newer build; nothing this one can place.
      break;
  }
}

/// Writes [look] onto the row it belongs to. Null clears it: a layer back to
/// the default look, a sentence back to its layer's, a text back to plain.
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
    case TimelineItemKind.translation:
      await db.setTranslationLineLook(id: id, look: json);
    case TimelineItemKind.clip:
    case TimelineItemKind.audio:
    case TimelineItemKind.image:
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

extension ImagePlacement on ImageLayer {
  ItemTransform get placement =>
      ItemTransform(x: x, y: y, scale: scale, rotation: rotation);
}

/// The payload for a split, in both directions.
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
TimelineEventPayload transcribeRunPayload({
  required List<String> transcriptIds,
}) {
  return TimelineEventPayload(
    before: {'transcriptIds': transcriptIds, 'retired': true},
    after: {'transcriptIds': transcriptIds, 'retired': false},
  );
}

/// The payload for moving or resizing a layer.
/// A clip's sound moved against its picture, from one pair of offsets to
/// another.
TimelineEventPayload audioTrimPayload({
  required String clipId,
  required ({int startOffsetMs, int endOffsetMs}) from,
  required ({int startOffsetMs, int endOffsetMs}) to,
}) {
  return TimelineEventPayload(
    before: {
      'clipId': clipId,
      'startOffsetMs': from.startOffsetMs,
      'endOffsetMs': from.endOffsetMs,
    },
    after: {
      'clipId': clipId,
      'startOffsetMs': to.startOffsetMs,
      'endOffsetMs': to.endOffsetMs,
    },
  );
}

/// The sound of [clipIds] removed ([muted]) or put back, in one step.
TimelineEventPayload audioMutePayload({
  required List<String> clipIds,
  required bool muted,
}) {
  return TimelineEventPayload(
    before: {'clipIds': clipIds, 'muted': !muted},
    after: {'clipIds': clipIds, 'muted': muted},
  );
}

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
