import 'dart:convert';

/// What happened to a project's arrangement.
///
/// **Adding a kind is the whole cost of making a new action undoable.** The
/// code is stored rather than the index, so inserting a case here cannot
/// reinterpret rows already written — and anything specific to an action lives
/// in its payload, so no column and no migration is involved.
enum TimelineEventKind {
  clipSplit('clipSplit'),
  clipTrim('clipTrim'),
  cutRoll('cutRoll'),
  clipReorder('clipReorder'),
  clipRemove('clipRemove'),
  layerAdd('layerAdd'),
  transcribeRun('transcribeRun'),
  layerMove('layerMove'),
  layerRemove('layerRemove');

  const TimelineEventKind(this.code);

  final String code;

  /// Null for a code this build does not know.
  ///
  /// An event written by a newer build is skipped rather than crashed on, the
  /// same tolerance `EditEventKind` already has — one unreadable row must not
  /// wedge the button for good.
  static TimelineEventKind? fromCode(String code) {
    for (final kind in TimelineEventKind.values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// One reversible change, carrying enough state to be applied either way.
///
/// **Before and after, not a diff.** Storing what changed would mean replaying
/// the arrangement from the beginning to know what a value used to be; storing
/// both ends means undo and redo are the same operation with the two halves
/// swapped, which is why this needs no separate redo stack.
class TimelineEventPayload {
  const TimelineEventPayload({required this.before, required this.after});

  /// The state to return to when this event is undone.
  final Map<String, Object?> before;

  /// The state to return to when it is redone.
  final Map<String, Object?> after;

  String encode() => jsonEncode({'before': before, 'after': after});

  /// Null when the JSON is not the shape this build expects.
  ///
  /// Corrupt or newer-format rows are dropped by the caller rather than
  /// throwing, for the same reason an unknown kind is.
  static TimelineEventPayload? decode(String json) {
    try {
      final map = jsonDecode(json);
      if (map is! Map) return null;

      final before = map['before'];
      final after = map['after'];
      if (before is! Map || after is! Map) return null;

      return TimelineEventPayload(
        before: Map<String, Object?>.from(before),
        after: Map<String, Object?>.from(after),
      );
    } on FormatException {
      return null;
    }
  }

  /// The half to apply when stepping in this direction.
  Map<String, Object?> side({required bool forward}) => forward ? after : before;
}

/// Where one undo step should land, whichever log it came from.
///
/// The transcript log and the timeline log are read as one history ordered by
/// time, so the button does not need to know which table answered.
enum HistoryLog { transcript, timeline }

/// One entry in the merged history.
typedef HistoryStep = ({
  HistoryLog log,
  String id,
  DateTime at,
});

/// Merges two logs into the single history the user actually made.
///
/// **Ordered by when things happened, not by which table they live in.** A
/// history split by kind lets undo skip a more recent change and rebuild a
/// state that never existed — a word restored while a later cut stays.
///
/// [transcript] and [timeline] must each already be in their own order;
/// this only interleaves them.
List<HistoryStep> mergeHistory({
  required List<HistoryStep> transcript,
  required List<HistoryStep> timeline,
}) {
  final merged = [...transcript, ...timeline]
    ..sort((a, b) => a.at.compareTo(b.at));
  return merged;
}

/// The most recent step not yet undone, or null when there is nothing to undo.
HistoryStep? nextUndo(List<HistoryStep> history, Set<String> undone) {
  for (final step in history.reversed) {
    if (!undone.contains(step.id)) return step;
  }
  return null;
}

/// The oldest undone step, or null when there is nothing to redo.
///
/// Oldest rather than newest so redo retraces the path undo took, instead of
/// jumping to the far end of it.
HistoryStep? nextRedo(List<HistoryStep> history, Set<String> undone) {
  for (final step in history) {
    if (undone.contains(step.id)) return step;
  }
  return null;
}
