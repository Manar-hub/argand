import 'dart:convert';

/// The names and colours a user has given the speakers in one transcript.
class SpeakerNames {
  const SpeakerNames(this._names, [this._colors = const {}]);

  const SpeakerNames.empty()
      : _names = const {},
        _colors = const {};

  /// Reads the stored column: `{"0": {"name": "Ana", "color": 4294198070}}`.
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
    final colors = <int, int>{};
    for (final entry in raw.entries) {
      final speaker = int.tryParse(entry.key);
      if (speaker == null) continue;

      final value = entry.value;
      if (value is! Map<String, Object?>) continue;

      final name = value['name'];
      if (name is String && name.trim().isNotEmpty) names[speaker] = name.trim();

      final color = value['color'];
      if (color is int) colors[speaker] = color;
    }

    return SpeakerNames(Map.unmodifiable(names), Map.unmodifiable(colors));
  }

  final Map<int, String> _names;
  final Map<int, int> _colors;

  bool get isEmpty => _names.isEmpty && _colors.isEmpty;

  /// The custom name for [speaker], or null if it has none.
  String? operator [](int speaker) => _names[speaker];

  /// The name to show for [speaker], falling back to [defaultLabel].
  String labelFor(int speaker, {required String defaultLabel}) =>
      _names[speaker] ?? defaultLabel;

  /// The colour chosen for [speaker] as ARGB, or null for the palette's.
  int? colorOf(int? speaker) => speaker == null ? null : _colors[speaker];

  /// This map with [speaker] renamed, or the name cleared when [name] is blank.
  SpeakerNames withName(int speaker, String? name) {
    final trimmed = name?.trim() ?? '';
    final next = Map<int, String>.from(_names);
    if (trimmed.isEmpty) {
      next.remove(speaker);
    } else {
      next[speaker] = trimmed;
    }
    return SpeakerNames(Map.unmodifiable(next), _colors);
  }

  /// This map with [speaker] recoloured, or back to the palette when null.
  SpeakerNames withColor(int speaker, int? argb) {
    final next = Map<int, int>.from(_colors);
    if (argb == null) {
      next.remove(speaker);
    } else {
      next[speaker] = argb;
    }
    return SpeakerNames(_names, Map.unmodifiable(next));
  }

  /// The value to store, or null when there is nothing to store.
  String? encode() {
    if (isEmpty) return null;
    final speakers = {..._names.keys, ..._colors.keys}.toList()..sort();
    return jsonEncode({
      for (final speaker in speakers)
        '$speaker': {
          'name': ?_names[speaker],
          'color': ?_colors[speaker],
        },
    });
  }
}
