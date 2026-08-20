/// A stretch of audio attributed to one speaker.
///
/// This project's own type rather than sherpa-onnx's
/// `OfflineSpeakerDiarizationSegment`, deliberately. It is the seam that keeps
/// the diarization engine replaceable: today [SpeakerDiarizer] produces these
/// from a single whole-file pass, and if that is ever replaced by a chunked
/// pass with cross-chunk speaker re-identification, nothing outside
/// `lib/core/diarization/` has to change. It also converts sherpa's seconds to
/// the milliseconds the rest of the app already speaks in.
class SpeakerSpan {
  const SpeakerSpan({
    required this.startMs,
    required this.endMs,
    required this.speaker,
  });

  final int startMs;
  final int endMs;

  /// Cluster index from diarization, stable only *within one run over one
  /// file*. It carries no identity beyond that: speaker 0 in this project has
  /// nothing to do with speaker 0 in another, which is why cross-project voice
  /// profiles are a separate, later feature rather than a free consequence.
  final int speaker;

  int get durationMs => endMs - startMs;

  /// Milliseconds shared with the window [otherStartMs, otherEndMs).
  ///
  /// Zero when they do not touch, never negative — so callers can compare
  /// overlaps without special-casing disjoint spans.
  int overlapWith(int otherStartMs, int otherEndMs) {
    final start = startMs > otherStartMs ? startMs : otherStartMs;
    final end = endMs < otherEndMs ? endMs : otherEndMs;
    final overlap = end - start;
    return overlap > 0 ? overlap : 0;
  }

  /// Distance in milliseconds to the window, or zero if they overlap.
  int gapTo(int otherStartMs, int otherEndMs) {
    if (otherStartMs >= endMs) return otherStartMs - endMs;
    if (otherEndMs <= startMs) return startMs - otherEndMs;
    return 0;
  }

  @override
  String toString() => 'SpeakerSpan($startMs-${endMs}ms, speaker $speaker)';
}
