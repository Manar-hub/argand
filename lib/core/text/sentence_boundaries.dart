/// Where sentences and clauses end, judged from the punctuation the engine
/// already emits.
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
