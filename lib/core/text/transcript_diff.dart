/// Compares two transcripts word by word.
///
/// Repetition detection answers "did the decoder break?". This answers the
/// separate question "did it hear the right words?" — the failure mode where
/// `whisper-cli` produces "Chlamydia" and "Yours is creeper from Minecraft"
/// while the same model in the app produces "Climidial" and "Here's his creeper
/// for Minecraft". Nothing loops; the words are simply wrong, and no loop metric
/// can see it.
///
/// Word error rate is the standard measure and is what this computes:
/// `(substitutions + insertions + deletions) / reference words`. It is reported
/// alongside the actual substitutions, because a bare rate is not reviewable —
/// a change that trades one wrong word for a different wrong word can move the
/// number without improving anything.
///
/// Pure and host-testable, in the style of `sentence_boundaries.dart` and
/// `repetition.dart`: no engine, no I/O.
library;

import 'repetition.dart' show normalizeForRepetition;

/// One aligned difference between a reference and a candidate transcript.
enum EditKind { substitution, insertion, deletion }

/// A single edit in the alignment.
class TranscriptEdit {
  const TranscriptEdit({
    required this.kind,
    required this.referenceIndex,
    this.reference,
    this.candidate,
  });

  final EditKind kind;

  /// Position in the reference this edit sits at, so edits can be read in
  /// transcript order.
  final int referenceIndex;

  /// The reference word. Null for an insertion.
  final String? reference;

  /// The candidate word. Null for a deletion.
  final String? candidate;

  @override
  String toString() => switch (kind) {
        EditKind.substitution => '$reference -> $candidate',
        EditKind.insertion => '+$candidate',
        EditKind.deletion => '-$reference',
      };
}

/// The result of comparing a candidate transcript against a reference.
class TranscriptComparison {
  const TranscriptComparison({
    required this.referenceWords,
    required this.candidateWords,
    required this.edits,
  });

  final int referenceWords;
  final int candidateWords;
  final List<TranscriptEdit> edits;

  int get substitutions =>
      edits.where((e) => e.kind == EditKind.substitution).length;
  int get insertions => edits.where((e) => e.kind == EditKind.insertion).length;
  int get deletions => edits.where((e) => e.kind == EditKind.deletion).length;

  /// Word error rate. Can exceed 1.0 when the candidate invents more words than
  /// the reference contains — which is exactly what a repetition loop does, so
  /// the metric is not clamped.
  double get wer => referenceWords == 0
      ? (candidateWords == 0 ? 0.0 : 1.0)
      : edits.length / referenceWords;

  @override
  String toString() => 'WER ${(wer * 100).toStringAsFixed(1)}% '
      '(${substitutions}S ${insertions}I ${deletions}D '
      'over $referenceWords words)';
}

/// Splits a transcript into comparable words.
///
/// Normalises case and punctuation, because the question is whether the engine
/// heard the right word — `"Chlamydia,"` and `"chlamydia"` are the same result,
/// while `"Climidial"` is not. Tokens that normalise to nothing (stray `-`, `♪`)
/// are dropped rather than counted as errors.
List<String> transcriptWords(String text) => text
    .replaceAll(_timestamp, ' ')
    .split(RegExp(r'\s+'))
    .map(normalizeForRepetition)
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

final RegExp _timestamp = RegExp(r'\[[^\]]*\]');

/// Aligns [candidate] against [reference] and reports every difference.
///
/// Standard Levenshtein alignment with backtracking. Kept O(n*m) in memory
/// because transcripts here are hundreds of words, not millions, and the
/// backtrace is what makes the result reviewable rather than just a number.
TranscriptComparison compareTranscripts(
  List<String> reference,
  List<String> candidate,
) {
  final n = reference.length;
  final m = candidate.length;

  final cost = List.generate(
    n + 1,
    (_) => List<int>.filled(m + 1, 0),
    growable: false,
  );
  for (var i = 0; i <= n; i++) {
    cost[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    cost[0][j] = j;
  }

  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      if (reference[i - 1] == candidate[j - 1]) {
        cost[i][j] = cost[i - 1][j - 1];
        continue;
      }
      final substitute = cost[i - 1][j - 1];
      final delete = cost[i - 1][j];
      final insert = cost[i][j - 1];
      var best = substitute;
      if (delete < best) best = delete;
      if (insert < best) best = insert;
      cost[i][j] = best + 1;
    }
  }

  // Walk back from the corner. Matches are skipped; every other step is an
  // edit, recorded with the reference position so the list reads in order.
  final edits = <TranscriptEdit>[];
  var i = n;
  var j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && reference[i - 1] == candidate[j - 1]) {
      i--;
      j--;
      continue;
    }
    if (i > 0 && j > 0 && cost[i][j] == cost[i - 1][j - 1] + 1) {
      edits.add(TranscriptEdit(
        kind: EditKind.substitution,
        referenceIndex: i - 1,
        reference: reference[i - 1],
        candidate: candidate[j - 1],
      ));
      i--;
      j--;
    } else if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
      edits.add(TranscriptEdit(
        kind: EditKind.deletion,
        referenceIndex: i - 1,
        reference: reference[i - 1],
      ));
      i--;
    } else {
      edits.add(TranscriptEdit(
        kind: EditKind.insertion,
        referenceIndex: i,
        candidate: candidate[j - 1],
      ));
      j--;
    }
  }

  return TranscriptComparison(
    referenceWords: n,
    candidateWords: m,
    edits: edits.reversed.toList(growable: false),
  );
}
