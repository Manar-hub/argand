/// A stretch of audio attributed to one speaker.
class SpeakerSpan {
  const SpeakerSpan({
    required this.startMs,
    required this.endMs,
    required this.speaker,
  });

  final int startMs;
  final int endMs;

  /// Cluster index from diarization, stable only *within one run over one
  /// file*.
  final int speaker;

  int get durationMs => endMs - startMs;

  /// Milliseconds shared with the window [otherStartMs, otherEndMs).
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
