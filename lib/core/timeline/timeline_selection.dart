/// What kind of thing on the timeline a selection refers to.
enum TimelineItemKind {
  clip,
  layer,
  text,
  sentence,
  audio,

  /// One translation line; its id is the line's row.
  translation,
  image,
}

/// One selected thing: which track it belongs to, and which row it is.
typedef TimelineItem = ({TimelineItemKind kind, String id});

/// What a tap on [item] leaves selected.
Set<TimelineItem> tapSelection(
  Set<TimelineItem> selection,
  TimelineItem item, {
  required bool multi,
}) {
  if (multi) return toggleSelection(selection, item);
  if (selection.length == 1 && selection.contains(item)) return const {};
  return {item};
}

/// What a long press on [item] leaves selected: it joins (or leaves) the set,
/// and the timeline enters multi-select, where taps keep adding.
Set<TimelineItem> longPressSelection(
  Set<TimelineItem> selection,
  TimelineItem item,
) =>
    toggleSelection(selection, item);

/// Toggles [item] in [selection] and returns the result.
Set<TimelineItem> toggleSelection(
  Set<TimelineItem> selection,
  TimelineItem item,
) {
  final next = {...selection};
  if (!next.remove(item)) next.add(item);
  return next;
}

/// Drops anything from [selection] that no longer exists.
Set<TimelineItem> prunedSelection(
  Set<TimelineItem> selection, {
  required Set<String> clipIds,
  required Set<String> layerIds,
  Set<String>? textIds,
  Set<String>? translationIds,
  Set<String>? imageIds,
}) {
  return {
    for (final item in selection)
      if (switch (item.kind) {
        TimelineItemKind.clip => clipIds.contains(item.id),
        TimelineItemKind.layer => layerIds.contains(item.id),
        // Unknown when the caller has not said: kept rather than dropped.
        TimelineItemKind.text => textIds?.contains(item.id) ?? true,
        // Derived from words, so there is no id list to check against; a
        // sentence that no longer exists simply matches nothing on screen.
        TimelineItemKind.sentence => true,
        // A clip's sound: its id is the clip's.
        TimelineItemKind.audio => clipIds.contains(item.id),
        TimelineItemKind.translation => translationIds?.contains(item.id) ?? true,
        TimelineItemKind.image => imageIds?.contains(item.id) ?? true,
      })
        item,
  };
}

/// The ids of one kind in [selection], in no particular order.
Set<String> idsOfKind(Set<TimelineItem> selection, TimelineItemKind kind) => {
      for (final item in selection)
        if (item.kind == kind) item.id,
    };

/// A sentence as a selectable item: which transcript, and which words.
TimelineItem sentenceItem({
  required String transcriptId,
  required int fromPosition,
  required int toPosition,
}) =>
    (
      kind: TimelineItemKind.sentence,
      id: '$transcriptId|$fromPosition|$toPosition',
    );

/// The parts of a [sentenceItem]'s id, or null for any other item.
({String transcriptId, int fromPosition, int toPosition})? sentenceOf(
  TimelineItem item,
) {
  if (item.kind != TimelineItemKind.sentence) return null;
  final parts = item.id.split('|');
  if (parts.length != 3) return null;
  final from = int.tryParse(parts[1]);
  final to = int.tryParse(parts[2]);
  if (from == null || to == null) return null;
  return (transcriptId: parts[0], fromPosition: from, toPosition: to);
}
