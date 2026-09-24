/// What kind of thing on the timeline a selection refers to.
///
/// Deliberately open to growth: audio, text and image items are planned tracks
/// and will be selectable the same way. The editing tools switch on this, so
/// adding a kind is what makes a new track editable.
enum TimelineItemKind { clip, layer }

/// One selected thing: which track it belongs to, and which row it is.
typedef TimelineItem = ({TimelineItemKind kind, String id});

/// Toggles [item] in [selection] and returns the result.
///
/// **Tap adds, tap again removes**, rather than tap replacing the selection.
/// The point of a set is to act on several things at once -- cutting a clip and
/// the transcribe layer over it in the same stroke -- and a tap that cleared
/// everything else would make building that selection impossible.
Set<TimelineItem> toggleSelection(
  Set<TimelineItem> selection,
  TimelineItem item,
) {
  final next = {...selection};
  if (!next.remove(item)) next.add(item);
  return next;
}

/// Drops anything from [selection] that no longer exists.
///
/// A clip can be removed, a layer deleted, a split can replace rows. A
/// selection holding an id that is gone would have the tools operate on
/// nothing and report success, which is worse than the item quietly leaving the
/// selection.
Set<TimelineItem> prunedSelection(
  Set<TimelineItem> selection, {
  required Set<String> clipIds,
  required Set<String> layerIds,
}) {
  return {
    for (final item in selection)
      if (switch (item.kind) {
        TimelineItemKind.clip => clipIds.contains(item.id),
        TimelineItemKind.layer => layerIds.contains(item.id),
      })
        item,
  };
}

/// The ids of one kind in [selection], in no particular order.
Set<String> idsOfKind(Set<TimelineItem> selection, TimelineItemKind kind) => {
      for (final item in selection)
        if (item.kind == kind) item.id,
    };
