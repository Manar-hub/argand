import '../database/database.dart';

/// The stretch of a clip's media that actually plays.
typedef ClipWindow = ({int startMs, int endMs});

/// Shortest a clip may be trimmed to.
///
/// Below about a third of a second a clip is a flicker rather than a shot, and
/// several codecs cannot open a GOP that short. Stopping the drag here is
/// kinder than allowing a clip that cannot be played or rendered.
const int minimumClipMs = 300;

/// Where a clip begins and ends inside its media.
///
/// **Null means untrimmed, and resolves to the whole file.** Both ends are
/// resolved in this one place so no caller has to remember that a null end
/// falls back to the duration, which is itself nullable when the container
/// could not be probed.
ClipWindow clipWindow(MediaClip clip) {
  final media = clip.durationMs ?? 0;
  final safeMedia = media < 0 ? 0 : media;

  var start = clip.trimStartMs ?? 0;
  var end = clip.trimEndMs ?? safeMedia;

  // Held inside the media even if the stored values are nonsense: a clip whose
  // file was replaced by a shorter one would otherwise ask the player and the
  // encoder for time that does not exist.
  start = start.clamp(0, safeMedia);
  end = end.clamp(start, safeMedia);

  return (startMs: start, endMs: end);
}

/// How long a clip occupies on the timeline.
///
/// This, not `durationMs`, is what the ruler measures and what the export
/// renders. `durationMs` is the length of the *file*; once a clip can be
/// trimmed the two stop being the same number.
int trimmedDurationMs(MediaClip clip) {
  final window = clipWindow(clip);
  return window.endMs - window.startMs;
}

/// Which end of a clip a trim drag has hold of.
enum ClipEdge { start, end }

/// Applies a trim drag and returns where the window lands.
///
/// **Pure, and clamped every frame rather than on release.** A clip that could
/// be dragged past its own media and then snapped back would read as broken
/// while it was happening -- the same reasoning as `applyLayerDrag`, which this
/// deliberately mirrors so the two gestures behave alike.
///
/// Trimming moves one edge only. The other stays put, so a trim shortens the
/// clip rather than sliding it along its own media.
ClipWindow applyTrim({
  required MediaClip clip,
  required ClipEdge edge,
  required int deltaMs,
}) {
  final media = clip.durationMs ?? 0;
  final safeMedia = media < 0 ? 0 : media;
  final window = clipWindow(clip);

  // A clip already shorter than the floor -- a very short file -- must not be
  // made longer or shorter by a drag it cannot satisfy.
  if (safeMedia < minimumClipMs) return window;

  switch (edge) {
    case ClipEdge.start:
      final start = (window.startMs + deltaMs)
          .clamp(0, window.endMs - minimumClipMs);
      return (startMs: start, endMs: window.endMs);

    case ClipEdge.end:
      final end = (window.endMs + deltaMs)
          .clamp(window.startMs + minimumClipMs, safeMedia);
      return (startMs: window.startMs, endMs: end);
  }
}

/// Where a split would fall inside a clip's media, or null if it cannot.
///
/// [atClipMs] is measured from the start of what the clip *plays*, not from the
/// start of its file -- that is what the playhead knows. The returned value is
/// in media time, which is what the two new rows have to store.
///
/// Null when the split would leave either side below [minimumClipMs]. Refusing
/// is better than producing a sliver that cannot be played, and the caller can
/// say so rather than silently making something unusable.
int? splitPointFor(MediaClip clip, int atClipMs) {
  final window = clipWindow(clip);
  final at = window.startMs + atClipMs;

  if (at - window.startMs < minimumClipMs) return null;
  if (window.endMs - at < minimumClipMs) return null;

  return at;
}
