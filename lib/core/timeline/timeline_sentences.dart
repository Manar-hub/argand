import '../text/sentence_units.dart';
import 'project_timeline.dart';

/// A word as this library needs it: text, timing, and who said it.
///
/// Deliberately not the database row. The row carries a dozen columns that
/// have nothing to do with placing a sentence, and depending on it would make
/// this untestable without a database.
typedef SentenceWord = ({
  String text,
  int startMs,
  int endMs,
  String? speakerId,
});

/// One sentence of a transcript, placed on the project's shared time axis.
typedef TimelineSentence = ({
  String transcriptId,
  String clipId,
  int projectStartMs,
  int projectEndMs,
  String text,
  int? speaker,
});

/// Cuts [words] into sentences and places each on the project timeline.
///
/// **Derived, never stored.** Sentences come from the word rows through
/// [sentenceUnitsOf] — the same function Script mode reads them with — so a
/// sentence merged or retyped there is already merged or retyped here. A
/// second stored copy is what would let the two disagree, and a "sync" step is
/// only ever needed once they can.
///
/// Word timings are relative to the clip's own media, so each is lifted onto
/// the project axis through [timeline], which is what the clips, the ruler and
/// the playhead all measure with. A sentence therefore lands over the audio
/// that produced it rather than near it.
///
/// A sentence whose clip is not on the timeline is **dropped rather than
/// placed at zero**, where it would sit over some other clip's audio and claim
/// to describe it.
List<TimelineSentence> sentencesForClip({
  required ProjectTimeline timeline,
  required String clipId,
  required String transcriptId,
  required List<SentenceWord> words,
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
      // The palette indexes by diarization's own speaker number, taken from
      // the sentence's first word: a sentence that straddles a handover is
      // attributed to whoever began it, which is the same call the caption
      // grouper makes.
      speaker: int.tryParse(words[unit.first].speakerId ?? ''),
    ));
  }

  return sentences;
}
