import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/transcription/transcript_repository.dart';
import 'caption_cue.dart';
import 'caption_grouper.dart';

part 'caption_controller.g.dart';

/// Captions for a transcript, grouped from its words.
///
/// Derived rather than stored, and derived *here* rather than in a widget, so
/// the rule that widgets hold no logic (CLAUDE.md 4) still holds for the
/// caption overlay. Watching the same word stream the transcript view uses
/// means an edit to a word reflows the captions with no invalidation step —
/// there is no cached copy that could go stale.
@riverpod
Stream<List<CaptionCue>> captionCues(Ref ref, String transcriptId) {
  return ref
      .watch(transcriptRepositoryProvider)
      .watchWords(transcriptId)
      .map(groupIntoCues);
}
