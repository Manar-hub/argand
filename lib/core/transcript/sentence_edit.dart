import '../text/transcript_diff.dart';

/// A word as the retimer needs to see it: what it says, when, and which row it
/// came from.
///
/// [id] is null for a word the user has just typed and that has no row yet.
typedef EditableWord = ({String? id, String text, int startMs, int endMs});

/// The result of retyping a sentence: the words it should now contain, with
/// timings assigned.
class SentenceEditPlan {
  const SentenceEditPlan({required this.words, required this.changed});

  /// The sentence as it should be stored, in order. Entries carrying an [id]
  /// are existing rows to keep or amend; entries without one are new.
  final List<EditableWord> words;

  /// False when the retyped text is word-for-word what was already there, so
  /// the caller can skip the write and avoid spending an undo slot on nothing.
  final bool changed;
}

/// The shortest span an inserted word may be squeezed into before the planner
/// borrows time from a neighbour instead.
///
/// Well under any real word — the measured median word duration on the labelled
/// clips is 190–240ms — because this is a floor for "did this word get any time
/// at all", not an opinion about how long a word should be held.
const int _minWordMs = 50;

/// Works out how a retyped sentence maps onto the words it replaces.
///
/// **The rule the whole feature rests on: the sentence keeps its own span.**
/// Whatever the user types, the first word still starts where the sentence
/// started and the last still ends where it ended. Word timings are what
/// tap-to-seek, the playback highlight, caption grouping and every exported cue
/// are built on, so an edit that shifted them would desynchronise all four from
/// the audio — and the user correcting a misheard word is not telling us
/// *when* it was said.
///
/// Within that span, three things happen:
///
///  - A word the user did not touch keeps its **exact** original timings. This
///    is why the alignment matters: a naive re-spread would nudge every word in
///    the sentence because one of them changed.
///  - A run of changed words shares the span of the original words it replaces,
///    divided in proportion to how long each new word is. One word becoming two
///    — "brainbeats" heard for "praying beads" — splits that one word's span
///    between them rather than borrowing from a neighbour.
///  - Words inserted where nothing was removed take the gap between their
///    neighbours, which may be nothing at all. They are given whatever is there
///    rather than pushing a kept word aside.
///
/// Returns null when [text] has no words in it. Deleting speech is not what
/// correcting a transcript means, and an empty sentence would leave a hole in
/// the timeline that nothing else in the app expects; cutting content is
/// Phase 9's job, through the media editor.
SentenceEditPlan? planSentenceEdit({
  required List<EditableWord> original,
  required String text,
}) {
  final tokens = text
      .split(RegExp(r'\s+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  if (tokens.isEmpty || original.isEmpty) return null;

  final before = [for (final word in original) word.text];
  if (_sameWords(before, tokens)) {
    return SentenceEditPlan(words: original, changed: false);
  }

  final sentenceStart = original.first.startMs;
  // Not `original.last.endMs`: DTW timestamps occasionally place one word's end
  // before an earlier word's, the same drift `CaptionCue` guards against.
  final sentenceEnd = original
      .map((word) => word.endMs)
      .reduce((a, b) => a > b ? a : b);

  final steps = alignWords(before, tokens);
  final planned = <EditableWord>[];

  // Walked as runs rather than step by step: a substitution followed by an
  // insertion is one edit to a reader ("brainbeats" -> "praying beads"), and
  // timing it as two would give the inserted word a span of nothing.
  var index = 0;
  while (index < steps.length) {
    final step = steps[index];

    if (step.matched) {
      final source = original[step.reference!];
      planned.add((
        id: source.id,
        text: tokens[step.candidate!],
        startMs: source.startMs,
        endMs: source.endMs,
      ));
      index++;
      continue;
    }

    // Collect the whole changed run.
    final originals = <EditableWord>[];
    final replacements = <String>[];
    while (index < steps.length && !steps[index].matched) {
      final current = steps[index];
      if (current.reference != null) originals.add(original[current.reference!]);
      if (current.candidate != null) replacements.add(tokens[current.candidate!]);
      index++;
    }

    // A pure insertion has no original span of its own, so it borrows the gap
    // between the words on either side of it.
    var fallbackStart = planned.isEmpty ? sentenceStart : planned.last.endMs;
    final fallbackEnd = _nextKeptStart(steps, index, original) ?? sentenceEnd;

    // When there is no usable gap, borrow from a neighbour instead.
    //
    // Words added at the very start of a line have nothing before them, and
    // words added between two the engine ran together have nothing between
    // them — in both cases the range above is empty, and every inserted word
    // would come out with no duration at all. That is not a cosmetic problem:
    // a zero-width word can never be the one `_activeWordIndex` highlights, and
    // the caption cue containing it starts in the wrong place.
    //
    // The time can only come from an adjacent word, and taking it is defensible
    // precisely here: the user has just said that word's span covered more
    // speech than was transcribed. The neighbour is pulled into the run and the
    // combined span divided, so exactly one kept word gives up its exact
    // timing, and only when the alternative is a word with none.
    if (originals.isEmpty &&
        fallbackEnd - fallbackStart < replacements.length * _minWordMs) {
      if (index < steps.length && steps[index].matched) {
        final absorbed = steps[index];
        originals.add(original[absorbed.reference!]);
        replacements.add(tokens[absorbed.candidate!]);
        index++;
      } else if (planned.isNotEmpty) {
        // Nothing ahead to borrow from — an insertion at the end of the line.
        final previous = planned.removeLast();
        originals.add(previous);
        replacements.insert(0, previous.text);
        fallbackStart = previous.startMs;
      }
    }

    planned.addAll(
      _retime(
        replacements: replacements,
        originals: originals,
        fallbackStart: fallbackStart,
        fallbackEnd: fallbackEnd,
      ),
    );
  }

  if (planned.isEmpty) return null;

  // The invariant, restated at the end rather than trusted: however the middle
  // was divided, the sentence still occupies exactly the time it did before.
  planned[0] = (
    id: planned.first.id,
    text: planned.first.text,
    startMs: sentenceStart,
    endMs: planned.first.endMs < sentenceStart
        ? sentenceStart
        : planned.first.endMs,
  );
  planned[planned.length - 1] = (
    id: planned.last.id,
    text: planned.last.text,
    startMs: planned.last.startMs > sentenceEnd
        ? sentenceEnd
        : planned.last.startMs,
    endMs: sentenceEnd,
  );

  return SentenceEditPlan(words: planned, changed: true);
}

/// Where the next kept word begins, so an insertion knows what it may not
/// overrun.
int? _nextKeptStart(
  List<WordAlignment> steps,
  int from,
  List<EditableWord> original,
) {
  for (var i = from; i < steps.length; i++) {
    final step = steps[i];
    if (step.matched) return original[step.reference!].startMs;
  }
  return null;
}

/// Divides [startMs]..[endMs] between [words], one span each.
///
/// **This is the estimate, and it is the only part of a sentence edit that is
/// not measured.** Proportional to word length: "praying beads" reads better
/// with the longer word holding the screen longer, and the same rule keeps a
/// long word replacing a short one from looking clipped.
///
/// Character count is a proxy for how long a word takes to say, and a rough
/// one — it knows nothing about syllables, stress or pace. Nothing consumes
/// these boundaries at word granularity yet (word-by-word caption grouping is
/// a Tier 2 mode), but that mode will, so the error is worth knowing rather
/// than assuming. `integration_test/retiming_probe_test.dart` measures it
/// against whisper's own DTW boundaries on the labelled clips.
///
/// Public for that probe. Measuring a copy of this rule would measure the copy.
List<(int, int)> distributeSpan({
  required List<String> words,
  required int startMs,
  required int endMs,
}) {
  if (words.isEmpty) return const [];

  final span = endMs > startMs ? endMs - startMs : 0;
  final total = words.fold<int>(0, (sum, word) => sum + word.length);

  final result = <(int, int)>[];
  var cursor = startMs;

  for (final (index, word) in words.indexed) {
    final last = index == words.length - 1;
    final share = total == 0 ? 0 : (span * word.length) ~/ total;
    // The last word absorbs the rounding, so the run ends exactly where it
    // should rather than a millisecond or two short.
    final wordEnd = last ? endMs : cursor + share;

    result.add((cursor, wordEnd < cursor ? cursor : wordEnd));
    cursor = wordEnd;
  }

  return result;
}

/// Spreads [replacements] across the span [originals] occupied.
List<EditableWord> _retime({
  required List<String> replacements,
  required List<EditableWord> originals,
  required int fallbackStart,
  required int fallbackEnd,
}) {
  if (replacements.isEmpty) return const [];

  final start = originals.isEmpty ? fallbackStart : originals.first.startMs;
  final end = originals.isEmpty
      ? (fallbackEnd < fallbackStart ? fallbackStart : fallbackEnd)
      : originals.map((w) => w.endMs).reduce((a, b) => a > b ? a : b);

  final spans = distributeSpan(
    words: replacements,
    startMs: start,
    endMs: end,
  );

  // Existing ids are reused positionally where the run replaced something, so
  // a substitution amends its row instead of deleting one and inserting
  // another. That keeps an older undo event that addresses the word by id
  // resolvable after this edit is undone.
  return [
    for (final (index, word) in replacements.indexed)
      (
        id: index < originals.length ? originals[index].id : null,
        text: word,
        startMs: spans[index].$1,
        endMs: spans[index].$2,
      ),
  ];
}

bool _sameWords(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The text of [words] as the editor should present it for retyping.
String sentenceTextOf(List<EditableWord> words) =>
    words.map((word) => word.text).join(' ');
