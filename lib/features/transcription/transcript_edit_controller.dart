import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcript_edit_controller.g.dart';

/// Whether the transcript is being read or corrected.
@riverpod
class TranscriptEditMode extends _$TranscriptEditMode {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void leave() => state = false;
}

/// How much of the transcript one tap opens for editing.
enum TranscriptEditScope {
  /// The sentence containing the tapped word, within its speaker turn.
  line,

  /// The tapped word alone.
  word,

  /// Not text at all: taps pick a range of words and give them a speaker.
  speakers,
}

/// Whether a tap edits a whole line or a single word.
@riverpod
class TranscriptEditScopeSetting extends _$TranscriptEditScopeSetting {
  @override
  TranscriptEditScope build() => TranscriptEditScope.line;

  void select(TranscriptEditScope scope) => state = scope;
}

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
@riverpod
class SelectedSpeaker extends _$SelectedSpeaker {
  @override
  int build() => 0;

  void select(int speaker) => state = speaker;
}

/// The first word of a range being picked, as a `Words.position`.
@riverpod
class SpeakerRangeAnchor extends _$SpeakerRangeAnchor {
  @override
  int? build() => null;

  void set(int position) => state = position;

  void clear() => state = null;
}

/// The span of words currently open for retyping, or null when none is.
@riverpod
class InlineEdit extends _$InlineEdit {
  @override
  ({int from, int to})? build() => null;

  void open({required int from, required int to}) =>
      state = (from: from, to: to);

  void close() => state = null;

  /// Whether [position] falls inside the open span.
  bool covers(int position) {
    final open = state;
    return open != null && position >= open.from && position <= open.to;
  }
}
