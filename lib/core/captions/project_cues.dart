import '../database/database.dart';
import '../timeline/clip_trim.dart';
import '../timeline/project_timeline.dart';
import 'caption_cue.dart';
import 'caption_grouper.dart';

/// One clip's captions, grouped from its words and put on the clip's own clock.
///
/// **The single place a clip's cues are made for anything that leaves the
/// app.** The burned-in captions and the SRT/VTT files both start here, so the
/// two break their lines at exactly the same words. An SRT uploaded beside the
/// exported video shows the same captions the video already has in it.
///
/// Words may come from several transcripts when more than one transcribe layer
/// covers the clip, so they are sorted before grouping; `groupIntoCues`
/// expects transcript order and would otherwise break cues at the seam.
///
/// [window] is the clip's trim range in media time. Words outside it are
/// dropped and the rest are rebased onto it, because a trimmed clip's clock
/// starts at its in-point rather than at the start of the file. Filtering
/// **before** grouping rather than after is deliberate: a cue straddling the
/// trim point then breaks at the cut instead of being discarded whole or
/// hanging past the end.
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
///
/// **What a subtitle file has to be.** The exported video is the arrangement,
/// not any one clip, so a subtitle file written from one clip's transcript in
/// that clip's own time stops lining up the moment anything is split, trimmed
/// or added -- which is what the first subtitle export did.
///
/// Order and offsets come from [ProjectTimeline], the same source the video
/// export reads, so the two cannot disagree about where a clip begins.
///
/// A cue is cut short at its clip's out-point. Without that, a line spoken
/// across a cut would carry on over the start of the next clip and push that
/// clip's first caption late, since players refuse overlapping cues.
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
