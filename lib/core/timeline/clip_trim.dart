import '../database/database.dart';

/// The stretch of a clip's media that actually plays.
typedef ClipWindow = ({int startMs, int endMs});

/// Shortest a clip may be trimmed to.
const int minimumClipMs = 300;

/// Where a clip begins and ends inside its media.
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
int trimmedDurationMs(MediaClip clip) {
  final window = clipWindow(clip);
  return window.endMs - window.startMs;
}

/// Which end of a clip a trim drag has hold of.
enum ClipEdge { start, end }

/// Applies a trim drag and returns where the window lands.
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
int? splitPointFor(MediaClip clip, int atClipMs) {
  final window = clipWindow(clip);
  final at = window.startMs + atClipMs;

  if (at - window.startMs < minimumClipMs) return null;
  if (window.endMs - at < minimumClipMs) return null;

  return at;
}

/// Two clips over one file, meeting at a cut.
typedef RolledCut = ({ClipWindow left, ClipWindow right});

/// Whether [left] and [right] are the two sides of one cut.
bool sharesACut(MediaClip left, MediaClip right) =>
    left.mediaPath == right.mediaPath &&
    clipWindow(left).endMs == clipWindow(right).startMs;

/// Moves the cut between two clips, instead of resizing one of them.
RolledCut rollCut({
  required MediaClip left,
  required MediaClip right,
  required int deltaMs,
}) {
  final leftWindow = clipWindow(left);
  final rightWindow = clipWindow(right);

  final at = (leftWindow.endMs + deltaMs).clamp(
    leftWindow.startMs + minimumClipMs,
    rightWindow.endMs - minimumClipMs,
  );

  return (
    left: (startMs: leftWindow.startMs, endMs: at),
    right: (startMs: at, endMs: rightWindow.endMs),
  );
}

/// What playback does on reaching the end of [current]'s window.
({bool stop, int? seekToMs}) playbackAfter(
  MediaClip current,
  List<MediaClip> clips,
) {
  final at = clips.indexWhere((clip) => clip.id == current.id);
  final next = at < 0 || at + 1 >= clips.length ? null : clips[at + 1];
  final end = clipWindow(current).endMs;
  if (next != null && next.mediaPath == current.mediaPath) {
    final start = clipWindow(next).startMs;
    if (start == end) return (stop: false, seekToMs: null);
    if (start > end) return (stop: false, seekToMs: start);
  }
  return (stop: true, seekToMs: null);
}
