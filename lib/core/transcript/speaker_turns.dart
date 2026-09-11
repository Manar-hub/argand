import '../database/database.dart';

/// A run of consecutive words sharing one speaker.
///
/// **Derived, never stored**, for the same reason as `CaptionCue`: turns are a
/// view over the `speakerId` already on each word, so reassigning a speaker
/// reflows them on the next rebuild with nothing to invalidate.
///
/// This lived as a private `_Turn` inside `project_screen.dart` until speaker
/// analytics needed the same grouping. It is lifted here rather than copied —
/// the same move `sentence_boundaries.dart` and `sentence_units.dart` record,
/// where two copies of one boundary rule was judged one copy too many.
///
/// Named `SpeakerTurn`, not `Turn`, because "turn" means two different things
/// in this pipeline: a stretch of *audio* that diarization attributes to one
/// speaker, and a run of *words* that carry the same `speakerId` once
/// attribution has been written. This type is strictly the second.
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
      // `CaptionCue.fromWords` guards the same way for the same reason. The
      // private `_Turn` this replaces never computed a span, so it never met
      // this; analytics computes nothing *but* spans.
      endMs: words.map((word) => word.endMs).reduce((a, b) => a > b ? a : b),
    );
  }

  /// Null when the transcript carries no speaker information at all.
  final int? speaker;

  /// Where this run begins in the flat word list, so the active-word highlight
  /// keeps working across turns.
  ///
  /// This is an index into the list passed to [groupIntoSpeakerTurns] — **not**
  /// `Word.position`. The two agree today because positions are assigned
  /// contiguously at import, but they are different things: the reassign path
  /// in `project_screen.dart` addresses words by `position`, while the playback
  /// highlight counts by index. Collapsing them would break the highlight the
  /// first time a word is deleted.
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
///
/// A transcript with no diarization yields exactly one unlabelled turn, so the
/// rendering path is shared rather than branched.
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
