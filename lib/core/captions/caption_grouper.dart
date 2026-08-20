import '../database/database.dart';
import '../text/sentence_boundaries.dart';
import 'caption_cue.dart';

/// Limits that shape a caption line.
///
/// The character and duration numbers follow long-standing subtitling practice
/// (roughly two lines of ~42 characters, and a line held for at most a few
/// seconds) rather than anything specific to this app. They are a class instead
/// of bare constants because Tier 2 turns grouping into a user-selectable set —
/// word-by-word, breath-grouped, grammatically-grouped — and those modes are
/// mostly different numbers fed to the same pass.
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
///
/// This is Tier 1's single grouping mode. "Grammatically-grouped" here means
/// punctuation-led, not parsed: the engine already emits sentence and clause
/// punctuation, so cues break where a reader would pause. There is no parser
/// and no model involved, deliberately — the alternative is running an NLP pass
/// over every transcript for a result that punctuation approximates well.
///
/// Breaks are applied in this order of authority:
///
///  1. **Speaker change** — always, and before anything else. A caption
///     attributed to two people is wrong in a way no length rule can excuse,
///     and speaker-coloured captions depend on one cue meaning one voice.
///  2. **Sentence end** (`.`, `!`, `?`, `…`) — break after the word.
///  3. **Clause end** (`,`, `;`, `:`, `—`) — break after the word, but only
///     once the cue has enough text to stand alone.
///  4. **A silence** of [CaptionStyle.gapBreakMs] or more.
///  5. **Length**, by characters or duration, as the backstop for speech that
///     arrives with no punctuation at all.
///
/// Known limit: an abbreviation ending in a period ("Mr.", "Dr.") reads as a
/// sentence end and splits the cue early. Detecting that needs a lexicon, which
/// is not worth carrying for a cosmetic break; it is recorded rather than
/// worked around.
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
///
/// A binary search would be tidier, but cue counts are in the hundreds and a
/// linear scan keeps the tie-breaking obvious: the *first* cue containing the
/// position wins, so overlapping cues produced by drifting timestamps cannot
/// make the caption flicker between two candidates.
CaptionCue? cueAt(List<CaptionCue> cues, int positionMs) {
  for (final cue in cues) {
    if (cue.containsMs(positionMs)) return cue;
    // Cues are ordered, so once one starts after the playhead there is no
    // point looking further.
    if (cue.startMs > positionMs) break;
  }
  return null;
}
