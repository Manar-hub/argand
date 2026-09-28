/// Compares two transcripts word by word.
library;

import 'repetition.dart' show normalizeForRepetition;
import 'sentence_boundaries.dart';

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

/// How a transcript is split into comparable tokens.
enum TranscriptTokenization {
  /// Case folded, punctuation stripped. `"Chlamydia,"` and `"chlamydia"` are
  /// the same result; `"Climidial"` is not.
  normalized,

  /// Exactly as written, split on whitespace only. Case and punctuation count
  /// as differences.
  verbatim,
}

/// Splits a transcript into comparable words.
List<String> transcriptWords(
  String text, {
  TranscriptTokenization tokenization = TranscriptTokenization.normalized,
  bool stripBracketedTags = true,
}) {
  var cleaned = text.replaceAll(_timestamp, ' ');
  if (stripBracketedTags) {
    cleaned = cleaned.replaceAll(_bracketedTag, ' ');
  }

  final tokens = cleaned.split(RegExp(r'\s+'));
  final mapped = switch (tokenization) {
    TranscriptTokenization.normalized => tokens.map(normalizeForRepetition),
    TranscriptTokenization.verbatim => tokens.map((token) => token.trim()),
  };
  return mapped.where((word) => word.isNotEmpty).toList(growable: false);
}

/// An actual `[hh:mm:ss.mmm --> hh:mm:ss.mmm]` stamp, and only that.
final RegExp _timestamp = RegExp(r'\[[\d:.,\s]*-->[\d:.,\s]*\]');

/// Any other bracketed tag, removed only when the caller asks for it.
final RegExp _bracketedTag = RegExp(r'\[[^\]]*\]');

/// Aligns [candidate] against [reference] and reports every difference.
TranscriptComparison compareTranscripts(
  List<String> reference,
  List<String> candidate,
) {
  final n = reference.length;
  final m = candidate.length;
  final cost = _costMatrix(reference, candidate);

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

/// The Levenshtein cost table for [reference] against [candidate].
List<List<int>> _costMatrix(List<String> reference, List<String> candidate) {
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

  return cost;
}

/// One step of an alignment: which index on each side it consumes.
typedef WordAlignment = ({int? reference, int? candidate, bool matched});

/// Pairs [reference] against [candidate] word for word, in order.
List<WordAlignment> alignWords(
  List<String> reference,
  List<String> candidate,
) {
  final cost = _costMatrix(reference, candidate);
  final steps = <WordAlignment>[];

  var i = reference.length;
  var j = candidate.length;

  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && reference[i - 1] == candidate[j - 1]) {
      steps.add((reference: i - 1, candidate: j - 1, matched: true));
      i--;
      j--;
    } else if (i > 0 && j > 0 && cost[i][j] == cost[i - 1][j - 1] + 1) {
      steps.add((reference: i - 1, candidate: j - 1, matched: false));
      i--;
      j--;
    } else if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
      steps.add((reference: i - 1, candidate: null, matched: false));
      i--;
    } else {
      steps.add((reference: null, candidate: j - 1, matched: false));
      j--;
    }
  }

  return steps.reversed.toList(growable: false);
}

/// How a candidate's punctuation compares to a reference's.
class PunctuationDelta {
  const PunctuationDelta({
    required this.referenceSentenceEnds,
    required this.candidateSentenceEnds,
    required this.referenceClauseEnds,
    required this.candidateClauseEnds,
  });

  final int referenceSentenceEnds;
  final int candidateSentenceEnds;
  final int referenceClauseEnds;
  final int candidateClauseEnds;

  /// Positive when the candidate ends more sentences than the reference.
  int get sentenceEndDelta => candidateSentenceEnds - referenceSentenceEnds;

  int get clauseEndDelta => candidateClauseEnds - referenceClauseEnds;

  /// Whether the candidate would produce the same number of sentence units.
  bool get sentenceCountMatches => sentenceEndDelta == 0;

  @override
  String toString() => 'sentences $candidateSentenceEnds vs '
      '$referenceSentenceEnds (${sentenceEndDelta >= 0 ? '+' : ''}'
      '$sentenceEndDelta), clauses $candidateClauseEnds vs '
      '$referenceClauseEnds (${clauseEndDelta >= 0 ? '+' : ''}$clauseEndDelta)';
}

/// Counts sentence and clause terminators in both transcripts.
PunctuationDelta comparePunctuation(String reference, String candidate) {
  final referenceWords = transcriptWords(
    reference,
    tokenization: TranscriptTokenization.verbatim,
  );
  final candidateWords = transcriptWords(
    candidate,
    tokenization: TranscriptTokenization.verbatim,
  );

  return PunctuationDelta(
    referenceSentenceEnds: referenceWords.where(endsSentence).length,
    candidateSentenceEnds: candidateWords.where(endsSentence).length,
    referenceClauseEnds: referenceWords.where(endsClause).length,
    candidateClauseEnds: candidateWords.where(endsClause).length,
  );
}
