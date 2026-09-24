import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/timeline/timeline_event.dart';

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
};

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
