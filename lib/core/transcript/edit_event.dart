import 'dart:convert';

/// Which mutation an [EditEventPayload] records.
///
/// The [code] is what gets stored, so these strings are part of the on-disk
/// format: renaming one silently orphans every event already written on a
/// user's device. Add cases, never rename them.
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
///
/// **Each payload stores its own inverse.** Undo could instead re-derive the
/// prior state from the transcript, but that only works while the edit is the
/// most recent thing that touched those rows -- and it is exactly *not*, once a
/// second edit lands on the same word. Storing `before` alongside `after` makes
/// an event self-contained, which is what lets the log be replayed in either
/// direction from any position.
///
/// This is the event log `docs/engine-architecture.md` prescribes: discrete
/// operations rather than whole-document snapshots, so the cost per edit is
/// bytes rather than the size of the transcript.
sealed class EditEventPayload {
  const EditEventPayload();

  EditEventKind get kind;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  /// Rebuilds a payload from its stored [kind] and [json].
  ///
  /// Returns null rather than throwing when either is unusable -- an unknown
  /// kind from a newer build, malformed JSON, a field of the wrong type. A
  /// corrupt row must not be able to take down the editor; the caller drops the
  /// event and carries on with the rest of the log.
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
///
/// A sentence edit can add and remove words, not just change their text, so its
/// inverse cannot be described as a field-level delta the way a
/// [WordTextEdit] can. The whole row goes in, both sides.
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
///
/// Unlike the other two kinds this can change how many words exist, which is
/// why both sides are full row snapshots rather than a description of the
/// difference: applying it in either direction is the same operation with the
/// two lists swapped.
///
/// [fromPosition] is where the run starts. Its end is implied by whichever list
/// is currently in place, so undo and redo each compute their own — the run
/// gets longer or shorter as the edit is applied and reversed.
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
///
/// Timings are deliberately absent. `updateWordText` writes `word` and nothing
/// else, so there is no timestamp to restore -- and an undo that "helpfully"
/// reset `startMs`/`endMs` would desynchronise tap-to-seek, the playback
/// highlight and every caption boundary from the audio.
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
///
/// [before] is a per-position map rather than a single value, for two reasons.
/// A run reassigned today is uniform by construction -- turns *are* runs of one
/// speaker -- but an undiarized transcript carries nulls, and a future caller
/// that reassigns an arbitrary selection would span several speakers. A map
/// round-trips all three cases; a scalar would silently flatten the last two.
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
