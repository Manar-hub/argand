import '../database/database.dart';
import '../timeline/clip_trim.dart';
import '../timeline/project_timeline.dart';
import 'caption_cue.dart';
import 'caption_grouper.dart';

/// One clip's captions, grouped from its words and put on the clip's own clock.
List<CaptionCue> clipCuesFor(List<Word> words, {ClipWindow? window}) {
  if (words.isEmpty) return const [];

  final from = window?.startMs ?? 0;
  final to = window?.endMs;

  final kept = [
    for (final word in words)
      // Half-open against the end, matching every other interval here: a word
      // starting exactly on the out-point belongs to the next clip.
      if (word.endMs > from && (to == null || word.startMs < to)) word,
  ];
  if (kept.isEmpty) return const [];

  kept.sort((a, b) => a.startMs.compareTo(b.startMs));

  return [for (final cue in groupIntoCues(kept)) cue.shiftedBy(-from)];
}

/// Every clip's captions on the project's clock, in timeline order.
List<CaptionCue> projectSubtitleCues({
  required ProjectTimeline timeline,
  required List<MediaClip> clips,
  required Map<String, List<Word>> wordsByClip,
}) {
  final byId = {for (final clip in clips) clip.id: clip};
  final cues = <CaptionCue>[];

  for (final placement in timeline.placements) {
    final clip = byId[placement.clipId];
    if (clip == null || placement.durationMs <= 0) continue;

    final clipEnd = placement.startMs + placement.durationMs;

    for (final cue in clipCuesFor(
      wordsByClip[clip.id] ?? const [],
      window: clipWindow(clip),
    )) {
      final placed = cue.shiftedBy(placement.startMs);
      if (placed.startMs >= clipEnd) continue;

      cues.add(
        placed.endMs <= clipEnd ? placed : placed.withEnd(clipEnd),
      );
    }
  }

  return cues;
}
