/// Detects decoder repetition loops in a run of transcribed words.
///
/// whisper.cpp can fall into a degenerate decode where it emits the same
/// phrase over and over until the window's token budget runs out — taking the
/// real speech in that window with it. The engine already has a detector for
/// this (an entropy check on the decoded sequence) but its verdict is only
/// consulted on the temperature-fallback path, so with fallback disabled a
/// loop reaches the transcript intact.
///
/// This module exists so that failure stops being judged by eye. Every earlier
/// report of it was "I watched the video and the transcript looked wrong",
/// which cannot be compared across two runs. A loop has a shape — a short
/// phrase repeated consecutively — and that shape is countable.
///
/// Pure and host-testable, in the style of [sentence_boundaries.dart]: no
/// engine, no I/O, no timing data. Callers that have timings can map the
/// returned indices back onto their own word list.
library;

/// One run of consecutive repetitions found in a word list.
class RepetitionRun {
  const RepetitionRun({
    required this.startIndex,
    required this.phrase,
    required this.repeats,
    this.withinWord = false,
  });

  /// True when the whole loop sits inside a single word, so [startIndex] names
  /// that word and [wordCount] is 1 however many times the unit repeats.
  final bool withinWord;

  /// Index into the caller's word list where the run begins, inclusive.
  final int startIndex;

  /// The repeated unit, normalised. One word for a `"ha ha ha"` loop, several
  /// for the longer phrase loops this engine also produces.
  final List<String> phrase;

  /// How many consecutive copies of [phrase] appear. Always >= 2.
  final int repeats;

  /// Total words the run covers. A within-word loop covers exactly one.
  int get wordCount => withinWord ? 1 : phrase.length * repeats;

  /// Index one past the last word of the run.
  int get endIndex => startIndex + wordCount;

  @override
  String toString() => withinWord
      ? '"${phrase.single}" x$repeats inside word $startIndex'
      : '"${phrase.join(' ')}" x$repeats at $startIndex-$endIndex';
}

/// Strips case and punctuation so `"Ha,"`, `"ha."` and `"HA"` are one token.
///
/// A loop is a loop whether or not whisper punctuated it, and it frequently
/// punctuates the last copy differently from the rest.
String normalizeForRepetition(String word) =>
    word.toLowerCase().replaceAll(_notLetterOrDigit, '');

/// Letters and digits are kept, everything else dropped. Deliberately
/// permissive about scripts — this must not silently stop working on non-Latin
/// output, which the language picker makes reachable.
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Every non-overlapping repetition run in [words], left to right.
///
/// [maxPhraseWords] defaults to 8 because this engine has produced both
/// extremes: a single-word `"ha ha ha"` loop on laughter, and a seven-word
/// `"I am the director of the project"` loop that ran to 183 words. A limit of
/// 4 would have missed the second entirely.
///
/// [minRepeats] defaults to 3. Two consecutive copies is ordinary English
/// ("that that", "had had"); three is already unusual and a loop is typically
/// far more.
///
/// Where several phrase lengths describe the same stretch, the one covering
/// the most words wins — so `"ha"` x6 is preferred over `"ha ha"` x3, which
/// reports the loop at its true extent rather than an arbitrary factor of it.
List<RepetitionRun> findRepetitions(
  List<String> words, {
  int maxPhraseWords = 8,
  int minRepeats = 3,
}) {
  final normalized = words.map(normalizeForRepetition).toList(growable: false);
  final runs = <RepetitionRun>[];

  var i = 0;
  while (i < normalized.length) {
    RepetitionRun? best;

    for (var n = 1; n <= maxPhraseWords; n++) {
      if (i + n * minRepeats > normalized.length) break;

      // An empty token is punctuation the engine emitted as a word. It matches
      // nothing, so a phrase containing one cannot be a loop.
      var phraseUsable = true;
      for (var k = 0; k < n; k++) {
        if (normalized[i + k].isEmpty) {
          phraseUsable = false;
          break;
        }
      }
      if (!phraseUsable) continue;

      var repeats = 1;
      while (true) {
        final next = i + repeats * n;
        if (next + n > normalized.length) break;
        var matches = true;
        for (var k = 0; k < n; k++) {
          if (normalized[next + k] != normalized[i + k]) {
            matches = false;
            break;
          }
        }
        if (!matches) break;
        repeats++;
      }

      if (repeats < minRepeats) continue;
      final candidate = RepetitionRun(
        startIndex: i,
        phrase: normalized.sublist(i, i + n),
        repeats: repeats,
      );
      if (best == null || candidate.wordCount > best.wordCount) {
        best = candidate;
      }
    }

    if (best == null) {
      i++;
    } else {
      runs.add(best);
      i = best.endIndex;
    }
  }

  return runs;
}

/// The run covering the most words, or null if [words] holds no loop.
RepetitionRun? findWorstRepetition(
  List<String> words, {
  int maxPhraseWords = 8,
  int minRepeats = 3,
}) {
  final runs = findRepetitions(
    words,
    maxPhraseWords: maxPhraseWords,
    minRepeats: minRepeats,
  );
  if (runs.isEmpty) return null;
  return runs.reduce((a, b) => b.wordCount > a.wordCount ? b : a);
}

/// Fraction of [words] consumed by repetition runs, 0.0 to 1.0.
///
/// The single number to compare two configurations by: it moves when a loop
/// gets longer or when a new one appears, and it is comparable across files of
/// different lengths.
double repetitionRatio(
  List<String> words, {
  int maxPhraseWords = 8,
  int minRepeats = 3,
}) {
  if (words.isEmpty) return 0.0;
  final runs = findRepetitions(
    words,
    maxPhraseWords: maxPhraseWords,
    minRepeats: minRepeats,
  );
  final looped = runs.fold<int>(0, (sum, run) => sum + run.wordCount);
  return looped / words.length;
}

/// A loop that never crosses a space, and so is invisible to
/// [findRepetitions].
///
/// **Found by measurement, not by design.** A real failing decode emitted its
/// loop as one 273-character token — `"Peek-a-peek-a-peek-a-..."` — because
/// whisper glued the repeats together with hyphens rather than spaces. Word
/// scanning reported zero loops on a transcript that was visibly broken. Any
/// detector that only splits on whitespace will make the same mistake, and the
/// commonly reported `"ha ha ha"` failure has exactly this shape when the
/// engine writes it as `"hahaha"`.
///
/// Returns the shortest repeating unit, so `"peekapeekapeeka"` reports `peeka`
/// rather than `peekapeeka`. A trailing partial unit is allowed: a loop cut off
/// mid-phrase by the end of a window is still a loop.
///
/// **The loop need not start at the beginning of the token.** Requiring that
/// was a second false-clean: a real failing decode produced
/// `"Peek-a-boo-boo-boo-boo-..."`, where a non-repeating lead-in precedes the
/// loop, and a whole-token periodicity test called it clean. The scan therefore
/// looks for the longest periodic *suffix*.
///
/// [minLength] guards against flagging ordinary words, and applies to the
/// looping part rather than the whole token. Without it `"hahaha"` and
/// `"bonbon"` qualify on their own, which says nothing about the decoder.
RepetitionRun? findWithinWordRepetition(
  String word,
  int index, {
  int minRepeats = 3,
  int minLength = 10,
}) {
  final normalized = normalizeForRepetition(word);

  // Ascending start = longest loop first, so a lead-in is skipped but the loop
  // is still reported at its full extent.
  for (var start = 0; start + minLength <= normalized.length; start++) {
    final tail = normalized.substring(start);
    for (var period = 1; period <= tail.length ~/ minRepeats; period++) {
      var repeating = true;
      for (var i = period; i < tail.length; i++) {
        if (tail[i] != tail[i % period]) {
          repeating = false;
          break;
        }
      }
      if (!repeating) continue;

      final repeats = tail.length ~/ period;
      if (repeats < minRepeats) continue;
      return RepetitionRun(
        startIndex: index,
        phrase: [tail.substring(0, period)],
        repeats: repeats,
        withinWord: true,
      );
    }
  }
  return null;
}

/// Every within-word loop in [words].
List<RepetitionRun> findWithinWordRepetitions(
  List<String> words, {
  int minRepeats = 3,
  int minLength = 10,
}) {
  final runs = <RepetitionRun>[];
  for (var i = 0; i < words.length; i++) {
    final run = findWithinWordRepetition(
      words[i],
      i,
      minRepeats: minRepeats,
      minLength: minLength,
    );
    if (run != null) runs.add(run);
  }
  return runs;
}

/// Both kinds of loop in one pass, which is the only safe way to ask.
///
/// Reporting a single number here would be a trap: a within-word loop occupies
/// one word slot no matter how long it runs, so folding it into
/// [repetitionRatio] would score a transcript that is half garbage as barely
/// affected. [hasLoop] is the honest summary; the two lists carry the detail.
class RepetitionReport {
  const RepetitionReport({
    required this.acrossWords,
    required this.withinWords,
    required this.wordCount,
  });

  final List<RepetitionRun> acrossWords;
  final List<RepetitionRun> withinWords;
  final int wordCount;

  bool get hasLoop => acrossWords.isNotEmpty || withinWords.isNotEmpty;

  /// Words consumed by loops that span several words.
  int get loopedWords =>
      acrossWords.fold<int>(0, (sum, run) => sum + run.wordCount);

  /// Total repeats across every within-word loop — the severity a word count
  /// cannot express.
  int get withinWordRepeats =>
      withinWords.fold<int>(0, (sum, run) => sum + run.repeats);

  double get ratio => wordCount == 0 ? 0.0 : loopedWords / wordCount;

  @override
  String toString() => hasLoop
      ? 'loops across=${acrossWords.length} (${loopedWords}w, '
          'ratio ${ratio.toStringAsFixed(3)}) '
          'within=${withinWords.length} ($withinWordRepeats repeats)'
      : 'no loops';
}

/// Scans [words] for both loop shapes.
RepetitionReport analyzeRepetition(
  List<String> words, {
  int maxPhraseWords = 8,
  int minRepeats = 3,
  int minLength = 10,
}) =>
    RepetitionReport(
      acrossWords: findRepetitions(
        words,
        maxPhraseWords: maxPhraseWords,
        minRepeats: minRepeats,
      ),
      withinWords: findWithinWordRepetitions(
        words,
        minRepeats: minRepeats,
        minLength: minLength,
      ),
      wordCount: words.length,
    );
