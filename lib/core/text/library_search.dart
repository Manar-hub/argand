/// The text side of the library search: turning what was typed into tokens, and
/// deciding whether a run of transcript words says them.
library;

/// What [query] asks for, one entry per typed word, lower-cased.
List<String> searchTokens(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toList();

/// Whether [words], starting at [start], say [tokens] in order: each token
/// found inside the word at its place, so "hello wor" finds "Hello, world."
/// the way a typed prefix should.
bool phraseMatchesAt(List<String> words, int start, List<String> tokens) {
  if (tokens.isEmpty || start < 0 || start + tokens.length > words.length) {
    return false;
  }
  for (var i = 0; i < tokens.length; i++) {
    if (!words[start + i].toLowerCase().contains(tokens[i])) return false;
  }
  return true;
}

/// [text] made safe to embed in a `LIKE` pattern escaped with a backslash:
/// a typed `%` or `_` is looked for, not treated as a wildcard.
String escapeLike(String text) => text.replaceAllMapped(
      RegExp(r'[\\%_]'),
      (match) => '\\${match[0]}',
    );

/// Where a library search found a project's words: enough to show the line
/// under its title and to open the project on it.
class LibraryWordHit {
  const LibraryWordHit({
    required this.transcriptId,
    required this.clipId,
    required this.startMs,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
  });

  final String transcriptId;

  /// The clip the words were said in, whose player to seek. Null only for a
  /// transcript with no clip, which the library does not create.
  final String? clipId;

  /// When the first matched word starts, in its clip's own time.
  final int startMs;

  /// The words around the match, in order.
  final List<String> snippet;

  /// Which of [snippet] are the match.
  final int matchStart;
  final int matchLength;
}
