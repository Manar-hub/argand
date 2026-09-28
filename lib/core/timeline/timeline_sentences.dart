import '../text/sentence_units.dart';
import 'project_timeline.dart';

/// A word as this library needs it: text, timing, and who said it.
typedef SentenceWord = ({
  String text,
  int startMs,
  int endMs,
  String? speakerId,
  int position,

  /// The track the word's sentence was moved onto; null follows its layer.
  String? trackId,
});

/// One sentence of a transcript, placed on the project's shared time axis.
typedef TimelineSentence = ({
  String transcriptId,
  String clipId,
  int projectStartMs,
  int projectEndMs,
  String text,
  int? speaker,
  int fromPosition,
  int toPosition,

  /// The transcription it came from, and the track it was moved onto -- null
  /// when it sits on that transcription's own track.
  String? layerId,
  String? trackId,
});

/// Cuts [words] into sentences and places each on the project timeline.
List<TimelineSentence> sentencesForClip({
  required ProjectTimeline timeline,
  required String clipId,
  required String transcriptId,
  required List<SentenceWord> words,
  String? layerId,
}) {
  if (words.isEmpty) return const [];

  final units = sentenceUnitsOf([
    for (final word in words)
      (text: word.text, startMs: word.startMs, endMs: word.endMs),
  ]);

  final sentences = <TimelineSentence>[];
  for (final unit in units) {
    final start = timeline.projectMsOf(clipId: clipId, clipMs: unit.startMs);
    final end = timeline.projectMsOf(clipId: clipId, clipMs: unit.endMs);
    if (start == null || end == null) continue;

    sentences.add((
      transcriptId: transcriptId,
      clipId: clipId,
      projectStartMs: start,
      projectEndMs: end,
      text: [
        for (var i = unit.first; i <= unit.last; i++) words[i].text.trim(),
      ].where((word) => word.isNotEmpty).join(' '),
      // The palette indexes by diarization's own speaker number, taken from the
      // sentence's first word: a sentence that straddles a handover is
      // attributed to whoever began it.
      speaker: int.tryParse(words[unit.first].speakerId ?? ''),
      fromPosition: words[unit.first].position,
      toPosition: words[unit.last].position,
      layerId: layerId,
      // Moved as one, so every word carries the same; the first speaks for
      // the sentence, as it does for the speaker.
      trackId: words[unit.first].trackId,
    ));
  }

  return sentences;
}
