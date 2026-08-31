/// Reads the committed diarization ground truth and scores a run against it.
///
/// **Why this exists.** `test/fixtures/diarization/*.truth.json` were written as
/// the permanent scoring set for speaker attribution, but until now nothing read
/// them: the 24/24 and 14/16 figures in `docs/progress.md` were tallied by hand
/// from probe dumps. That made "did this change regress diarization?"
/// unanswerable without a manual re-count, which is exactly the question every
/// engine parameter change has to answer.
///
/// Pure Dart on purpose — no Flutter, no engine, no I/O beyond being handed a
/// string — so the scoring rules are host-testable and the on-device probe and a
/// host test cannot disagree about what a score means.
///
/// Lives under `integration_test/` rather than `lib/` because it is measurement
/// scaffolding, not app code, and should not ship in the APK.
library;

import 'dart:convert';

/// One labelled sentence from a truth file.
class TruthSentence {
  const TruthSentence({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.speaker,
    required this.text,
  });

  final int index;
  final int startMs;
  final int endMs;

  /// Truth cluster id. These are the labels a human assigned by listening, and
  /// carry no relationship to the ids diarization happens to emit — see
  /// [scoreAgainstTruth] for how the two are reconciled.
  final int speaker;

  final String text;
}

/// A failure already investigated and documented in the truth file.
///
/// Both fixtures carry these, under `unreachable` (alberta) and `known`
/// (two_speakers). They are the difference between "this run is as good as the
/// toolchain gets" and "this change broke something": re-failing a documented
/// case is the status quo, failing anything else is a regression.
class KnownIssue {
  const KnownIssue({required this.index, required this.why});

  final int index;
  final String why;
}

/// A parsed truth fixture.
class DiarizationTruth {
  const DiarizationTruth({
    required this.clip,
    required this.sentences,
    required this.known,
  });

  final String clip;
  final List<TruthSentence> sentences;
  final List<KnownIssue> known;

  Set<int> get knownIndices => {for (final issue in known) issue.index};

  /// Distinct speakers a human identified in this clip.
  Set<int> get speakers => {for (final s in sentences) s.speaker};
}

/// Parses a `*.truth.json` fixture.
DiarizationTruth parseDiarizationTruth(String jsonText) {
  final root = jsonDecode(jsonText) as Map<String, dynamic>;

  final sentences = [
    for (final entry in (root['sentences'] as List<dynamic>? ?? const []))
      if (entry is Map<String, dynamic>)
        TruthSentence(
          index: entry['i'] as int,
          startMs: entry['startMs'] as int,
          endMs: entry['endMs'] as int,
          speaker: entry['speaker'] as int,
          text: entry['text'] as String? ?? '',
        ),
  ];

  // The two fixtures name this list differently. Accept both rather than
  // normalising the files, which would invalidate their provenance.
  final known = <KnownIssue>[];
  for (final key in const ['known', 'unreachable']) {
    for (final entry in (root[key] as List<dynamic>? ?? const [])) {
      if (entry is Map<String, dynamic>) {
        known.add(KnownIssue(
          index: entry['i'] as int,
          why: entry['why'] as String? ?? '',
        ));
      }
    }
  }

  return DiarizationTruth(
    clip: root['clip'] as String? ?? 'unknown',
    sentences: sentences,
    known: known,
  );
}

/// The result of scoring one run against a truth fixture.
class TruthScore {
  const TruthScore({
    required this.matched,
    required this.total,
    required this.mismatched,
    required this.knownIndices,
    required this.mapping,
    required this.observedClusters,
    required this.comparable,
    this.incomparableReason,
  });

  final int matched;
  final int total;

  /// Sentence indices attributed to the wrong speaker.
  final List<int> mismatched;

  final Set<int> knownIndices;

  /// Chosen diarization-cluster to truth-speaker mapping.
  final Map<int, int> mapping;

  /// How many distinct clusters diarization produced. More than the truth has
  /// means it split a speaker, which the mapping can partly hide — so it is
  /// reported rather than folded into the score.
  final int observedClusters;

  /// False when the run cannot be scored against this fixture at all.
  final bool comparable;
  final String? incomparableReason;

  /// Wrong sentences that are *not* already documented in the fixture. This is
  /// the number that matters for a regression gate: documented failures are the
  /// measured status quo, anything else is new damage.
  List<int> get newMismatches =>
      [for (final i in mismatched) if (!knownIndices.contains(i)) i];

  /// Documented failures this run reproduced.
  List<int> get expectedMismatches =>
      [for (final i in mismatched) if (knownIndices.contains(i)) i];

  @override
  String toString() => comparable
      ? '$matched/$total'
          '${newMismatches.isEmpty ? "" : "  NEW FAILURES: $newMismatches"}'
          '${expectedMismatches.isEmpty ? "" : "  (known: $expectedMismatches)"}'
      : 'not comparable: $incomparableReason';
}

/// Scores [observed] — one speaker id per sentence, in the same order as the
/// truth file — against [truth].
///
/// **Cluster ids are arbitrary.** Diarization numbers its clusters by the order
/// it happens to find them, so "cluster 0" carries no meaning and comparing it
/// to truth speaker 0 directly would score a perfect run at chance. Every
/// mapping from observed clusters to truth speakers is tried and the best is
/// used, which is the standard treatment for unsupervised labels.
///
/// **A run with a different sentence count is not scored.** The fixtures say so
/// themselves — "sentence indices are over whisper's output with silence
/// skipping ON and the bundled base model" — and the project already recorded
/// the trap of mapping one segmentation's sentences onto another's by time
/// overlap, which averaged away a sentence that was visibly on the wrong
/// speaker. Rather than silently produce a meaningless number, this returns
/// [TruthScore.comparable] false.
TruthScore scoreAgainstTruth({
  required List<int?> observed,
  required DiarizationTruth truth,
}) {
  final total = truth.sentences.length;

  if (observed.length != total) {
    return TruthScore(
      matched: 0,
      total: total,
      mismatched: const [],
      knownIndices: truth.knownIndices,
      mapping: const {},
      observedClusters: {for (final o in observed) ?o}.length,
      comparable: false,
      incomparableReason: 'run has ${observed.length} sentences, truth has '
          '$total -- ground truth belongs to one segmentation and does not '
          'transfer',
    );
  }

  final observedIds = <int>{for (final o in observed) ?o}.toList()
    ..sort();
  final truthIds = truth.speakers.toList()..sort();

  if (observedIds.isEmpty) {
    return TruthScore(
      matched: 0,
      total: total,
      mismatched: [for (var i = 0; i < total; i++) i],
      knownIndices: truth.knownIndices,
      mapping: const {},
      observedClusters: 0,
      comparable: true,
    );
  }

  // Bounded so a pathological over-segmentation cannot make this explode; the
  // clips this scores have two speakers.
  if (observedIds.length > 6 || truthIds.length > 6) {
    return TruthScore(
      matched: 0,
      total: total,
      mismatched: const [],
      knownIndices: truth.knownIndices,
      mapping: const {},
      observedClusters: observedIds.length,
      comparable: false,
      incomparableReason: 'too many clusters to map '
          '(${observedIds.length} observed, ${truthIds.length} truth)',
    );
  }

  var bestMatched = -1;
  var bestInjective = false;
  var bestMapping = <int, int>{};

  void consider(Map<int, int> mapping) {
    var matched = 0;
    for (var i = 0; i < total; i++) {
      final o = observed[i];
      if (o != null && mapping[o] == truth.sentences[i].speaker) matched++;
    }

    // On a tie, prefer a mapping that keeps distinct clusters distinct. A
    // collapsing mapping can tie with a bijection while describing the run
    // dishonestly -- "both clusters are the same person" -- so it should only
    // win when it genuinely scores higher.
    final injective = mapping.values.toSet().length == mapping.length;
    if (matched > bestMatched ||
        (matched == bestMatched && injective && !bestInjective)) {
      bestMatched = matched;
      bestInjective = injective;
      bestMapping = Map.of(mapping);
    }
  }

  void recurse(int at, Map<int, int> current) {
    if (at == observedIds.length) {
      consider(current);
      return;
    }
    for (final t in truthIds) {
      current[observedIds[at]] = t;
      recurse(at + 1, current);
      current.remove(observedIds[at]);
    }
  }

  recurse(0, {});

  final mismatched = <int>[];
  for (var i = 0; i < total; i++) {
    final o = observed[i];
    if (o == null || bestMapping[o] != truth.sentences[i].speaker) {
      mismatched.add(i);
    }
  }

  return TruthScore(
    matched: bestMatched,
    total: total,
    mismatched: mismatched,
    knownIndices: truth.knownIndices,
    mapping: bestMapping,
    observedClusters: observedIds.length,
    comparable: true,
  );
}
