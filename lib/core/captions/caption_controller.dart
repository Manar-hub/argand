import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/transcription/transcript_repository.dart';
import 'caption_cue.dart';
import 'caption_grouper.dart';

part 'caption_controller.g.dart';

/// Captions for a transcript, grouped from its words.
@riverpod
Stream<List<CaptionCue>> captionCues(Ref ref, String transcriptId) {
  return ref
      .watch(transcriptRepositoryProvider)
      .watchWords(transcriptId)
      .map(groupIntoCues);
}
