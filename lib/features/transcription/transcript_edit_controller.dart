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
