import '../database/database.dart';
import '../text/sentence_boundaries.dart';
import 'caption_cue.dart';

/// Limits that shape a caption line.
class CaptionStyle {
  const CaptionStyle({
    this.maxCharacters = 84,
    this.maxDurationMs = 6000,
    this.gapBreakMs = 700,
    this.minCharactersForClauseBreak = 30,
  });

  /// Two lines of about 42 characters, the conventional readable maximum.
  final int maxCharacters;

  /// Longest a single caption stays on screen.
  final int maxDurationMs;

  /// A silence at least this long is treated as a natural boundary. Below it,
  /// pauses are just speech rhythm and breaking there produces choppy captions.
  final int gapBreakMs;

  /// A comma only ends a cue once the cue is already worth reading on its own.
  /// Without this, "Yeah," becomes its own caption and the result flickers.
  final int minCharactersForClauseBreak;
}

/// Splits [words] into grammatically-grouped captions.
List<CaptionCue> groupIntoCues(
  List<Word> words, {
  CaptionStyle style = const CaptionStyle(),
}) {
  final cues = <CaptionCue>[];
  var current = <Word>[];
  var currentChars = 0;

  void flush() {
    if (current.isEmpty) return;
    cues.add(CaptionCue.fromWords(current));
    current = [];
    currentChars = 0;
  }

  for (final word in words) {
    if (current.isNotEmpty) {
      final previous = current.last;
      // +1 for the space this word would need.
      final projectedChars = currentChars + 1 + word.word.length;
      final projectedDuration = word.endMs - current.first.startMs;

      final speakerChanged = word.speakerId != previous.speakerId;
      final gapMs = word.startMs - previous.endMs;

      if (speakerChanged ||
          gapMs >= style.gapBreakMs ||
          projectedChars > style.maxCharacters ||
          projectedDuration > style.maxDurationMs) {
        flush();
      }
    }

    currentChars += (current.isEmpty ? 0 : 1) + word.word.length;
    current.add(word);

    // Punctuation breaks apply *after* the word that carries them, so the
    // full stop stays on the line it terminates.
    if (endsSentence(word.word)) {
      flush();
    } else if (endsClause(word.word) &&
        currentChars >= style.minCharactersForClauseBreak) {
      flush();
    }
  }

  flush();
  return cues;
}

/// The cue playing at [positionMs], or null between cues.
CaptionCue? cueAt(List<CaptionCue> cues, int positionMs) {
  for (final cue in cues) {
    if (cue.containsMs(positionMs)) return cue;
    // Cues are ordered, so once one starts after the playhead there is no
    // point looking further.
    if (cue.startMs > positionMs) break;
  }
  return null;
}
