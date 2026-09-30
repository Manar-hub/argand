/// [wanted], or -- when a project already has that name -- the same name with
/// the first free number after it: "Interview (1)", then "Interview (2)".
/// Names are compared without case or surrounding spaces, so "interview" is
/// taken by "Interview".
String uniqueTitle(String wanted, Iterable<String> taken) {
  final name = wanted.trim();
  String key(String title) => title.trim().toLowerCase();
  final used = {for (final title in taken) key(title)};
  if (!used.contains(key(name))) return name;

  // A copy of a copy counts on from the original, not "(1) (1)".
  final base = name.replaceFirst(RegExp(r'\s*\(\d+\)$'), '');
  for (var n = 1;; n++) {
    final candidate = '$base ($n)';
    if (!used.contains(key(candidate))) return candidate;
  }
}
