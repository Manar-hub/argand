import '../database/database.dart';

/// One caption as it would appear on screen: a short run of words, the span
/// they occupy, and who said them.
class CaptionCue {
  CaptionCue({
    required this.words,
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.speaker,
  });

  /// Builds a cue from the words it covers. [words] must not be empty and must
  /// already be in transcript order.
  factory CaptionCue.fromWords(List<Word> words) {
    assert(words.isNotEmpty, 'A cue with no words has nothing to display');

    return CaptionCue(
      words: List.unmodifiable(words),
      startMs: words.first.startMs,
      // Not `words.last.endMs` alone: DTW timestamps occasionally place a
      // word's end before an earlier word's, and a cue that ends before it
      // starts would never match the playhead.
      endMs: words.map((w) => w.endMs).reduce((a, b) => a > b ? a : b),
      text: words.map((w) => w.word).join(' '),
      speaker: int.tryParse(words.first.speakerId ?? ''),
    );
  }

  /// The words behind this cue, kept so the caption stays *structured text*
  /// rather than a flattened string — per-word timing is what tap-to-seek,
  /// karaoke-style highlighting and non-destructive editing all need.
  final List<Word> words;

  final int startMs;
  final int endMs;

  /// The joined text, for the common case where a caller just wants to render
  /// the line.
  final String text;

  /// Diarization's speaker index, or null when the transcript carries no
  /// speaker information.
  final int? speaker;

  int get durationMs => endMs - startMs;

  /// The same cue moved along the clock by [deltaMs], never before zero.
  CaptionCue shiftedBy(int deltaMs) => CaptionCue(
        words: words,
        startMs: startMs + deltaMs < 0 ? 0 : startMs + deltaMs,
        endMs: endMs + deltaMs < 0 ? 0 : endMs + deltaMs,
        text: text,
        speaker: speaker,
      );

  /// The same cue, ending at [endMs] instead.
  CaptionCue withEnd(int endMs) => CaptionCue(
        words: words,
        startMs: startMs,
        endMs: endMs,
        text: text,
        speaker: speaker,
      );

  bool containsMs(int positionMs) =>
      positionMs >= startMs && positionMs < endMs;

  @override
  String toString() => 'CaptionCue($startMs-${endMs}ms, spk $speaker, "$text")';
}
