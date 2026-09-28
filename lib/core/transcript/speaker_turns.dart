import '../database/database.dart';

/// A run of consecutive words sharing one speaker.
class SpeakerTurn {
  const SpeakerTurn({
    required this.speaker,
    required this.startIndex,
    required this.words,
    required this.startMs,
    required this.endMs,
  });

  /// Builds a turn from the words it covers. [words] must not be empty and must
  /// already be in transcript order.
  factory SpeakerTurn.fromWords(List<Word> words, {required int startIndex}) {
    assert(words.isNotEmpty, 'A turn with no words has no speaker and no span');

    return SpeakerTurn(
      speaker: int.tryParse(words.first.speakerId ?? ''),
      startIndex: startIndex,
      words: List.unmodifiable(words),
      startMs: words.first.startMs,
      // Not `words.last.endMs`: DTW timestamps occasionally place one word's
      // end before an earlier word's, which would yield a negative duration.
      // `CaptionCue.fromWords` guards the same way for the same reason.
      endMs: words.map((word) => word.endMs).reduce((a, b) => a > b ? a : b),
    );
  }

  /// Null when the transcript carries no speaker information at all.
  final int? speaker;

  /// Where this run begins in the flat word list, so the active-word highlight
  /// keeps working across turns.
  final int startIndex;

  final List<Word> words;

  final int startMs;
  final int endMs;

  /// Clamped at zero: see the note on [SpeakerTurn.fromWords] about timestamps
  /// that run backwards.
  int get durationMs => endMs > startMs ? endMs - startMs : 0;

  int get wordCount => words.length;
}

/// Splits [words] wherever the speaker changes.
List<SpeakerTurn> groupIntoSpeakerTurns(List<Word> words) {
  final turns = <SpeakerTurn>[];
  final buffer = <Word>[];
  String? currentId;
  var startIndex = 0;

  void flush() {
    if (buffer.isEmpty) return;
    turns.add(SpeakerTurn.fromWords(buffer, startIndex: startIndex));
    buffer.clear();
  }

  for (final (index, word) in words.indexed) {
    // Compares the raw `speakerId` string rather than the parsed int, so an
    // unparseable id still separates turns instead of silently merging into a
    // neighbouring null run.
    if (buffer.isNotEmpty && word.speakerId != currentId) flush();
    if (buffer.isEmpty) {
      currentId = word.speakerId;
      startIndex = index;
    }
    buffer.add(word);
  }
  flush();

  return turns;
}
