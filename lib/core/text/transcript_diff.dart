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
///
/// The distinction is load-bearing, not cosmetic. A normalized comparison
/// answers "did the engine hear the right word"; a verbatim one also asks
/// whether it wrote that word the same way. The two can disagree completely —
/// a run scoring 0.0% normalized can still differ from its reference in case
/// and punctuation across most sentences, which is how a configuration came to
/// be recorded as reproducing the reference "exactly" while a word-for-word
/// reading plainly did not agree.
enum TranscriptTokenization {
  /// Case folded, punctuation stripped. `"Chlamydia,"` and `"chlamydia"` are
  /// the same result; `"Climidial"` is not.
  normalized,

  /// Exactly as written, split on whitespace only. Case and punctuation count
  /// as differences.
  verbatim,
}

/// Splits a transcript into comparable words.
///
/// [tokenization] chooses whether case and punctuation are differences.
///
/// [stripBracketedTags] removes non-timestamp brackets such as `[BLANK_AUDIO]`
/// and `[LAUGHTER]`. It defaults to true because that is what this function has
/// always done and the recorded numbers assume it — but it must be **false**
/// when measuring `suppress_non_speech_tokens`, whose entire effect is whether
/// those tags are emitted. Scoring that flag with them stripped measures it
/// with an instrument that cannot see it.
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
///
/// Deliberately narrow. The previous pattern matched *any* bracketed run, so it
/// silently deleted `[BLANK_AUDIO]` and `[LAUGHTER]` before scoring — removing
/// the only tokens `suppress_nst` governs from every comparison that judged it.
final RegExp _timestamp = RegExp(r'\[[\d:.,\s]*-->[\d:.,\s]*\]');

/// Any other bracketed tag, removed only when the caller asks for it.
final RegExp _bracketedTag = RegExp(r'\[[^\]]*\]');

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

/// How a candidate's punctuation compares to a reference's.
///
/// Reported separately from word error rate because punctuation is not
/// cosmetic in this app. `sentence_boundaries.dart` turns it into the sentence
/// units that caption grouping breaks on and that speaker assignment attributes
/// as a whole — so a decoder change that improves word accuracy while moving
/// sentence terminators would leave WER looking better and diarization quietly
/// worse. That failure is invisible to a normalized comparison, and this is the
/// number that surfaces it.
///
/// It is deliberately computed with the *same* `endsSentence`/`endsClause`
/// predicates the diarization path uses, rather than a private copy: agreement
/// here therefore means the sentence units themselves agree, which is the
/// property that actually matters.
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
  ///
  /// This is the count that moves diarization: one extra terminator is one more
  /// sentence unit, which re-cuts every downstream attribution decision.
  int get sentenceEndDelta => candidateSentenceEnds - referenceSentenceEnds;

  int get clauseEndDelta => candidateClauseEnds - referenceClauseEnds;

  /// Whether the candidate would produce the same number of sentence units.
  ///
  /// Not proof the boundaries land in the same places — only that the count
  /// agrees — but a disagreement here is enough on its own to explain a
  /// diarization score moving after a decoder change.
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
