import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'transcript_edit_controller.g.dart';

/// Whether the transcript is being read or corrected.
///
/// **Why a mode rather than a menu on every tap.** In playback a tap on a word
/// means "seek there", which is the transcript's primary gesture and the reason
/// it is worth scrolling. Putting a chooser in front of that would slow down the
/// common action to serve the rare one. A single toggle keeps both intents
/// unambiguous: reading seeks, editing edits.
///
/// It also keeps the layout free of per-line controls. In edit mode the two
/// things already on screen become the two controls — a word edits its text, a
/// speaker label reassigns its turn — so nothing is added to the page.
///
/// Deliberately not persisted. Editing is something you do deliberately and
/// then leave; reopening a project in edit mode would be a surprise, and an
/// accidental tap on a word would rewrite text rather than seek.
@riverpod
class TranscriptEditMode extends _$TranscriptEditMode {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void leave() => state = false;
}

/// How much of the transcript one tap opens for editing.
///
/// **This is the accuracy control.** A retyped run keeps the outer span of what
/// it replaced and divides the inside between the new words, so the smaller the
/// run, the less any single correction can move. Editing one word confines the
/// change to that word's own timing; editing the line spreads it across the
/// line. Measured drift for the wider case is in `docs/engineering-notes.md`,
/// "Sentence editing".
///
/// So the choice is not a preference about typing — it is the user deciding how
/// much they are willing to have re-estimated, which is something only they can
/// judge for the correction they are making.
enum TranscriptEditScope {
  /// The sentence containing the tapped word, within its speaker turn.
  line,

  /// The tapped word alone.
  word,

  /// Not text at all: taps pick a range of words and give them a speaker.
  ///
  /// The one correction the other two cannot make. Reassigning by turn can only
  /// **merge** — a block wrongly given to one person cannot be split when a
  /// second person's words sit inside it, because nothing can express "these
  /// words, not the whole turn".
  speakers,
}

/// Whether a tap edits a whole line or a single word.
///
/// Defaults to [TranscriptEditScope.line] because the common correction is a
/// phrase — "brainbeats" for "praying beads" spans a word boundary and cannot
/// be typed one word at a time. Word is the deliberate choice for when the
/// timing matters more than the convenience.
///
/// Not persisted, for the same reason [TranscriptEditMode] is not: it is picked
/// for a task, and inheriting it on a later launch would surprise.
@riverpod
class TranscriptEditScopeSetting extends _$TranscriptEditScopeSetting {
  @override
  TranscriptEditScope build() => TranscriptEditScope.line;

  void select(TranscriptEditScope scope) => state = scope;
}

/// Which speaker a tap assigns while [TranscriptEditScope.speakers] is active.
///
/// Defaults to speaker 0 rather than to nothing: a palette with no selection
/// makes the first tap do nothing, which reads as the control being broken.
@riverpod
class SelectedSpeaker extends _$SelectedSpeaker {
  @override
  int build() => 0;

  void select(int speaker) => state = speaker;
}

/// The first word of a range being picked, as a `Words.position`.
///
/// Null when no range is in progress. Two taps rather than a drag because the
/// transcript scrolls vertically and a paint stroke would fight the scroll
/// gesture — so this holds the state between them.
///
/// **Must be cleared when the mode changes.** A pending anchor that outlived
/// Speakers scope would silently turn a later, unrelated tap into a range
/// assignment; `project_screen.dart` clears it on leaving the scope and on
/// leaving edit mode.
@riverpod
class SpeakerRangeAnchor extends _$SpeakerRangeAnchor {
  @override
  int? build() => null;

  void set(int position) => state = position;

  void clear() => state = null;
}
