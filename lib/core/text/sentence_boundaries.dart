/// Where sentences and clauses end, judged from the punctuation the engine
/// already emits.
///
/// Shared because two unrelated features need the same judgement and must not
/// drift apart: caption grouping breaks lines at these boundaries, and speaker
/// assignment uses them to decide that a sentence belongs to one voice. If the
/// two disagreed, a caption could break where the speaker did not change, or
/// vice versa.
///
/// No parser and no model. Whisper punctuates its output, so this reads that
/// punctuation rather than re-deriving it.
library;

/// Trailing quotes and brackets sit outside the punctuation that matters, so
/// they are stripped before testing: `said."` still ends a sentence.
String stripTrailingWrappers(String text) {
  const wrappers = {'"', "'", '»', '”', '’', ')', ']', '}'};
  var end = text.length;
  while (end > 0 && wrappers.contains(text[end - 1])) {
    end--;
  }
  return text.substring(0, end);
}

/// Whether [word] carries sentence-ending punctuation.
///
/// Known limit, accepted: an abbreviation ending in a period ("Mr.", "Dr.")
/// reads as a sentence end. Telling them apart needs a lexicon, which is not
/// worth carrying for the two things this decides.
bool endsSentence(String word) {
  final trimmed = stripTrailingWrappers(word.trimRight());
  if (trimmed.isEmpty) return false;
  return const {'.', '!', '?', '…'}.contains(trimmed[trimmed.length - 1]);
}

/// Whether [word] carries clause-ending punctuation — a weaker break than
/// [endsSentence], and one callers may choose to ignore.
bool endsClause(String word) {
  final trimmed = stripTrailingWrappers(word.trimRight());
  if (trimmed.isEmpty) return false;
  return const {',', ';', ':', '—', '–'}.contains(trimmed[trimmed.length - 1]);
}
