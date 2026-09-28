import 'dart:convert';

/// Custom labels a user has given the speakers in one transcript.
class SpeakerNames {
  const SpeakerNames(this._names);

  const SpeakerNames.empty() : _names = const {};

  /// Reads the stored column.
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
  String labelFor(int speaker, {required String defaultLabel}) =>
      _names[speaker] ?? defaultLabel;

  /// This map with [speaker] renamed, or the name cleared when [name] is blank.
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

  /// The value to store, or null when there is nothing to store.
  String? encode() {
    if (_names.isEmpty) return null;
    return jsonEncode({
      for (final entry in _names.entries) '${entry.key}': {'name': entry.value},
    });
  }
}
