import 'speaker_span.dart';

/// Maps transcribed words onto diarized speaker spans.
///
/// Diarization and transcription are two independent passes over the same
/// audio, so their boundaries never line up exactly: whisper's word timings are
/// DTW-derived and known to drift, and diarization emits spans that start and
/// end on its own segmentation windows. This file is where those two views are
/// reconciled, and it is deliberately pure — no I/O, no FFI, no engine types —
/// so the reconciliation rules are testable on the host VM.

/// Speaker label for the word occupying [startMs, endMs), or null if there is
/// nothing to attribute it to.
///
/// **Most-overlap wins.** A word straddling a speaker change belongs to
/// whoever was talking for more of it, which is the only defensible reading
/// when a single word genuinely spans a turn boundary.
///
/// **A word touching no span falls back to the nearest one.** Returning null
/// there would be more literal but worse: word timings drift by tens of
/// milliseconds, so a word can sit just outside the span it obviously belongs
/// to, and scattering unattributed words through an otherwise-labelled
/// transcript reads as a bug rather than as honesty. Nearest-span is chosen
/// without a distance limit, because [spans] only covers regions diarization
/// already judged to be speech and the word came from that same speech.
///
/// Null is returned only when [spans] is empty — diarization did not run, was
/// skipped for length, or found nothing.
int? speakerForWord({
  required int startMs,
  required int endMs,
  required List<SpeakerSpan> spans,
}) {
  if (spans.isEmpty) return null;

  SpeakerSpan? best;
  var bestOverlap = 0;
  for (final span in spans) {
    final overlap = span.overlapWith(startMs, endMs);
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      best = span;
    }
  }
  if (best != null) return best.speaker;

  // No overlap anywhere: fall back to the closest span. Ties resolve to the
  // earlier one, so the result does not depend on list order.
  SpeakerSpan? nearest;
  var nearestGap = -1;
  for (final span in spans) {
    final gap = span.gapTo(startMs, endMs);
    if (nearestGap < 0 || gap < nearestGap) {
      nearestGap = gap;
      nearest = span;
    }
  }
  return nearest?.speaker;
}

/// How a speaker index is stored in `Words.speakerId`.
///
/// A plain decimal string. The column is text because a later phase will point
/// it at a real `Speakers` row with a UUID, a display name and a colour; until
/// that exists there is nothing to reference, and inventing a scheme now would
/// only have to be migrated. Kept in one function so the format has a single
/// definition rather than being spelled out at each call site.
String speakerIdFor(int speaker) => '$speaker';
