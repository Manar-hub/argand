import 'dart:convert';

/// Which mutation an [EditEventPayload] records.
enum EditEventKind {
  wordText('wordText'),
  speaker('speaker'),
  sentence('sentence');

  const EditEventKind(this.code);

  final String code;

  static EditEventKind? fromCode(String code) {
    for (final kind in EditEventKind.values) {
      if (kind.code == code) return kind;
    }
    // An event written by a newer build than the one now reading it. Undo skips
    // it rather than crashing -- see [EditEventPayload.decode].
    return null;
  }
}

/// One reversible edit, carrying enough state to be applied in both directions.
sealed class EditEventPayload {
  const EditEventPayload();

  EditEventKind get kind;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  /// Rebuilds a payload from its stored [kind] and [json].
  static EditEventPayload? decode(String kind, String json) {
    final resolved = EditEventKind.fromCode(kind);
    if (resolved == null) return null;

    final Object? raw;
    try {
      raw = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (raw is! Map<String, Object?>) return null;

    return switch (resolved) {
      EditEventKind.wordText => WordTextEdit.fromJson(raw),
      EditEventKind.speaker => SpeakerEdit.fromJson(raw),
      EditEventKind.sentence => SentenceEdit.fromJson(raw),
    };
  }
}

/// One word row, captured whole.
class WordSnapshot {
  const WordSnapshot({
    required this.id,
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.speakerId,
  });

  static WordSnapshot? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final id = raw['id'];
    final text = raw['text'];
    final startMs = raw['startMs'];
    final endMs = raw['endMs'];
    final speakerId = raw['speakerId'];

    if (text is! String || startMs is! int || endMs is! int) return null;
    if (id != null && id is! String) return null;
    if (speakerId != null && speakerId is! String) return null;

    return WordSnapshot(
      id: id as String?,
      text: text,
      startMs: startMs,
      endMs: endMs,
      speakerId: speakerId as String?,
    );
  }

  /// Null for a word that did not exist yet when the snapshot was taken.
  final String? id;

  final String text;
  final int startMs;
  final int endMs;
  final String? speakerId;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'startMs': startMs,
        'endMs': endMs,
        'speakerId': speakerId,
      };
}

/// A whole sentence retyped.
class SentenceEdit extends EditEventPayload {
  const SentenceEdit({
    required this.fromPosition,
    required this.before,
    required this.after,
  });

  static SentenceEdit? fromJson(Map<String, Object?> json) {
    final from = json['from'];
    final before = json['before'];
    final after = json['after'];
    if (from is! int || before is! List || after is! List) return null;

    final restoredBefore = <WordSnapshot>[];
    for (final entry in before) {
      final snapshot = WordSnapshot.fromJson(entry);
      if (snapshot == null) return null;
      restoredBefore.add(snapshot);
    }

    final restoredAfter = <WordSnapshot>[];
    for (final entry in after) {
      final snapshot = WordSnapshot.fromJson(entry);
      if (snapshot == null) return null;
      restoredAfter.add(snapshot);
    }

    // A side with no words would mean the sentence vanished, which the planner
    // refuses to produce. Treated as corruption rather than applied.
    if (restoredBefore.isEmpty || restoredAfter.isEmpty) return null;

    return SentenceEdit(
      fromPosition: from,
      before: restoredBefore,
      after: restoredAfter,
    );
  }

  final int fromPosition;
  final List<WordSnapshot> before;
  final List<WordSnapshot> after;

  @override
  EditEventKind get kind => EditEventKind.sentence;

  @override
  Map<String, Object?> toJson() => {
        'from': fromPosition,
        'before': [for (final word in before) word.toJson()],
        'after': [for (final word in after) word.toJson()],
      };
}

/// A correction to one word's text.
class WordTextEdit extends EditEventPayload {
  const WordTextEdit({
    required this.wordId,
    required this.before,
    required this.after,
  });

  static WordTextEdit? fromJson(Map<String, Object?> json) {
    final wordId = json['wordId'];
    final before = json['before'];
    final after = json['after'];
    if (wordId is! String || before is! String || after is! String) return null;
    return WordTextEdit(wordId: wordId, before: before, after: after);
  }

  final String wordId;
  final String before;
  final String after;

  @override
  EditEventKind get kind => EditEventKind.wordText;

  @override
  Map<String, Object?> toJson() => {
    'wordId': wordId,
    'before': before,
    'after': after,
  };
}

/// A speaker reassignment over a contiguous run of positions.
class SpeakerEdit extends EditEventPayload {
  const SpeakerEdit({
    required this.fromPosition,
    required this.toPosition,
    required this.after,
    required this.before,
  });

  static SpeakerEdit? fromJson(Map<String, Object?> json) {
    final from = json['from'];
    final to = json['to'];
    final after = json['after'];
    final before = json['before'];
    if (from is! int || to is! int || after is! String) return null;
    if (before is! Map<String, Object?>) return null;

    final restored = <int, String?>{};
    for (final entry in before.entries) {
      final position = int.tryParse(entry.key);
      final value = entry.value;
      // A null value is meaningful (the word had no speaker), so only a
      // non-null non-String is a malformed row.
      if (position == null || (value != null && value is! String)) return null;
      restored[position] = value as String?;
    }

    return SpeakerEdit(
      fromPosition: from,
      toPosition: to,
      after: after,
      before: restored,
    );
  }

  final int fromPosition;
  final int toPosition;

  /// The `speakerId` written across the whole run.
  final String after;

  /// Position to the `speakerId` it held beforehand. Null values are real.
  final Map<int, String?> before;

  @override
  EditEventKind get kind => EditEventKind.speaker;

  @override
  Map<String, Object?> toJson() => {
    'from': fromPosition,
    'to': toPosition,
    'after': after,
    'before': {for (final entry in before.entries) '${entry.key}': entry.value},
  };
}
