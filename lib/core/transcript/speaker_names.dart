import 'dart:convert';

/// Custom labels a user has given the speakers in one transcript.
///
/// Diarization produces cluster indices — 0, 1, 2 — and the app renders them as
/// `Speaker 1`, `Speaker 2`. That is correct and useless: the whole point of
/// separating voices is knowing whose they are, and only the person listening
/// can say. This is where their answer lives.
///
/// **Names are free and always will be** (CLAUDE.md §2). They are presentation
/// of the user's own output, which is the free side of the line.
///
/// Stored as JSON in `Transcripts.speakerNames`, shaped
/// `{"0": {"name": "Ana"}}` — an object per speaker rather than a bare string,
/// so a future editable colour is a new key rather than a data migration.
///
/// Absence is the normal state. A transcript nobody has renamed stores null and
/// renders exactly as it always did.
class SpeakerNames {
  const SpeakerNames(this._names);

  const SpeakerNames.empty() : _names = const {};

  /// Reads the stored column.
  ///
  /// **Never throws.** Malformed JSON, an unexpected shape, a key that is not a
  /// number, a name that is not a string — every one of them is skipped and the
  /// rest are kept, so one bad entry costs one label rather than the screen.
  /// A row written by a newer build must not break an older one; the same rule
  /// `EditEventPayload.decode` follows.
  factory SpeakerNames.decode(String? json) {
    if (json == null || json.trim().isEmpty) return const SpeakerNames.empty();

    final Object? raw;
    try {
      raw = jsonDecode(json);
    } on FormatException {
      return const SpeakerNames.empty();
    }
    if (raw is! Map<String, Object?>) return const SpeakerNames.empty();

    final names = <int, String>{};
    for (final entry in raw.entries) {
      final speaker = int.tryParse(entry.key);
      if (speaker == null) continue;

      final value = entry.value;
      if (value is! Map<String, Object?>) continue;

      final name = value['name'];
      if (name is! String) continue;

      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      names[speaker] = trimmed;
    }

    return SpeakerNames(Map.unmodifiable(names));
  }

  final Map<int, String> _names;

  bool get isEmpty => _names.isEmpty;

  /// The custom name for [speaker], or null if it has none.
  String? operator [](int speaker) => _names[speaker];

  /// The name to show for [speaker], falling back to [defaultLabel].
  ///
  /// [defaultLabel] is supplied rather than built here because `Speaker 1` is
  /// interface text and belongs to the localisation layer (CLAUDE.md §4).
  String labelFor(int speaker, {required String defaultLabel}) =>
      _names[speaker] ?? defaultLabel;

  /// This map with [speaker] renamed, or the name cleared when [name] is blank.
  ///
  /// Clearing rather than storing an empty string, so a user who wipes the field
  /// gets `Speaker 1` back instead of a nameless chip. Returns a new instance;
  /// nothing here mutates.
  SpeakerNames withName(int speaker, String? name) {
    final trimmed = name?.trim() ?? '';
    final next = Map<int, String>.from(_names);

    if (trimmed.isEmpty) {
      next.remove(speaker);
    } else {
      next[speaker] = trimmed;
    }

    return SpeakerNames(Map.unmodifiable(next));
  }

  /// The value to store, or **null when there is nothing to store**.
  ///
  /// Null rather than `{}` so an untouched transcript keeps a null column and
  /// a user who removes every name returns the row to that state, rather than
  /// leaving an empty object behind that reads as "renamed, to nothing".
  String? encode() {
    if (_names.isEmpty) return null;
    return jsonEncode({
      for (final entry in _names.entries) '${entry.key}': {'name': entry.value},
    });
  }
}
