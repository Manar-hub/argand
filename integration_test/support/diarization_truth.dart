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
    this.explicitTurns,
    this.maxWordErrorRate,
  });

  final String clip;
  final List<TruthSentence> sentences;
  final List<KnownIssue> known;

  /// The worst word error rate this clip is allowed to score.
  ///
  /// Written into the fixture once measured, so the gate has something to fail
  /// against on every run rather than only when sentence counts happen to line
  /// up. Null means unmeasured — the gate then says so loudly instead of
  /// passing, because a gate that cannot fail is not a gate.
  final double? maxWordErrorRate;

  /// Turns stated outright by the fixture. Null means derive them.
  final List<TruthTurn>? explicitTurns;

  /// Time-anchored ground truth for this clip.
  ///
  /// A fixture may state `turns` directly — which is how a clip labelled from
  /// scratch should be written, since turns are the honest unit. Older fixtures
  /// carry only `sentences`, and those are merged into turns on read, so both
  /// generations score the same way and no file has to be rewritten to gain
  /// decoder independence.
  List<TruthTurn> get turns =>
      explicitTurns ?? turnsFromSentences(sentences);

  Set<int> get knownIndices => {for (final issue in known) issue.index};

  /// Distinct speakers a human identified in this clip.
  ///
  /// Read off [turns] rather than [sentences], so a fixture labelled purely as
  /// turns — the form a newly labelled clip should take — reports its speakers
  /// like any other. Merging never changes the set, so this is unchanged for
  /// sentence-labelled fixtures.
  Set<int> get speakers => {for (final t in turns) t.speaker};
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

  // A fixture may state turns outright. When it does they are authoritative and
  // sentences become provenance only; when it does not, `DiarizationTruth.turns`
  // derives them by merging same-speaker runs.
  final rawTurns = root['turns'] as List<dynamic>?;
  final turns = rawTurns == null
      ? null
      : [
          for (final entry in rawTurns)
            if (entry is Map<String, dynamic>)
              TruthTurn(
                startMs: entry['startMs'] as int,
                endMs: entry['endMs'] as int,
                speaker: entry['speaker'] as int,
              ),
        ];

  return DiarizationTruth(
    clip: root['clip'] as String? ?? 'unknown',
    sentences: sentences,
    known: known,
    explicitTurns: turns,
    maxWordErrorRate: (root['maxWordErrorRate'] as num?)?.toDouble(),
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

// ---------------------------------------------------------------------------
// Time-anchored truth
// ---------------------------------------------------------------------------

/// A contiguous stretch of one speaker, in milliseconds.
///
/// **Why this exists, and why it is the important type here.** Sentence indices
/// were the original unit of ground truth, and they carry a fatal property:
/// they belong to one segmentation. Change the decoder — beam search,
/// `suppress_nst`, a different model — and whisper re-cuts its sentences, so a
/// fixture labelled `i: 22` no longer refers to the same audio. `44ff53e`
/// records the consequence in full: a run was scored by mapping one
/// segmentation's sentences onto another's by time overlap, which averaged a
/// visibly wrong sentence away, and the conclusion drawn was "a model needs its
/// own labels".
///
/// A turn is anchored to *time*, which no decoder change can move. The same
/// labels therefore score any segmentation, which is what makes an accuracy
/// lever like beam search measurable at all rather than permanently blocked
/// behind a re-labelling nobody can face.
class TruthTurn {
  const TruthTurn({
    required this.startMs,
    required this.endMs,
    required this.speaker,
  });

  final int startMs;
  final int endMs;
  final int speaker;

  bool containsMs(int ms) => ms >= startMs && ms < endMs;

  /// Distance from [ms] to this turn, zero when inside it.
  int gapToMs(int ms) {
    if (ms < startMs) return startMs - ms;
    if (ms >= endMs) return ms - endMs + 1;
    return 0;
  }
}

/// Merges runs of consecutive same-speaker sentences into turns.
///
/// **This conversion adds no assumptions.** Merging only ever happens *within*
/// one speaker, so it cannot invent a boundary that the labels did not already
/// assert; the result is exactly as trustworthy as the sentence labels it came
/// from. That is what lets existing fixtures become decoder-independent with no
/// fresh listening — including `alberta.mp4`, whose labels went stale when one
/// labelled sentence later split in two. Both halves sit inside the same turn
/// and inherit the same speaker, which is the correct answer precisely because
/// the original label asserted one speaker across that whole time range.
List<TruthTurn> turnsFromSentences(List<TruthSentence> sentences) {
  final turns = <TruthTurn>[];
  for (final sentence in sentences) {
    if (turns.isNotEmpty && turns.last.speaker == sentence.speaker) {
      final open = turns.removeLast();
      turns.add(TruthTurn(
        startMs: open.startMs,
        endMs: sentence.endMs,
        speaker: open.speaker,
      ));
      continue;
    }
    turns.add(TruthTurn(
      startMs: sentence.startMs,
      endMs: sentence.endMs,
      speaker: sentence.speaker,
    ));
  }
  return turns;
}

/// The speaker labelled at [ms], or null when there are no turns at all.
///
/// Falls back to the nearest turn when [ms] lands in a gap between them, the
/// same shape as `speakerForWord`'s nearest-span fallback: gaps are an artifact
/// of sentence extents not quite abutting, not a claim that nobody is speaking,
/// and refusing to answer there would penalise a run for a labelling artifact.
int? speakerAtMs(List<TruthTurn> turns, int ms) {
  if (turns.isEmpty) return null;
  for (final turn in turns) {
    if (turn.containsMs(ms)) return turn.speaker;
  }

  TruthTurn? nearest;
  var nearestGap = -1;
  for (final turn in turns) {
    final gap = turn.gapToMs(ms);
    if (nearestGap < 0 || gap < nearestGap) {
      nearestGap = gap;
      nearest = turn;
    }
  }
  return nearest?.speaker;
}

/// A word as scoring needs to see it: when it was said.
typedef TruthWord = ({int startMs, int endMs});

/// The result of scoring a run's words against time-anchored truth.
class WordTruthScore {
  const WordTruthScore({
    required this.matchedWords,
    required this.scoredWords,
    required this.totalWords,
    required this.mapping,
    required this.observedClusters,
    required this.mismatchedIndices,
  });

  /// Words whose mapped speaker equals the labelled speaker.
  final int matchedWords;

  /// Words truth had an answer for. Equal to [totalWords] whenever the fixture
  /// covers the clip, which it should.
  final int scoredWords;

  final int totalWords;
  final Map<int, int> mapping;
  final int observedClusters;

  /// Indices into the word list that were attributed wrongly, in order.
  final List<int> mismatchedIndices;

  double get accuracy => scoredWords == 0 ? 0 : matchedWords / scoredWords;

  /// The headline number: the fraction of speech attributed to the wrong voice.
  double get errorRate => 1 - accuracy;

  @override
  String toString() => '$matchedWords/$scoredWords words '
      '(${(errorRate * 100).toStringAsFixed(1)}% wrong)'
      '${scoredWords == totalWords ? '' : ', $totalWords total'}';
}

/// Scores per-word attribution against time-anchored truth.
///
/// **Why words and not sentences.** A sentence score is all-or-nothing, so a
/// sentence that diarization splits between two speakers costs exactly as much
/// as one attributed wholly to the wrong person — and, worse, moves in whole
/// units when a decoder change re-cuts the sentences underneath it. Words are
/// the finest thing both the pipeline and the labels agree on, so a rule that
/// fixes half a split sentence shows up as progress rather than as nothing.
///
/// Cluster ids from diarization are arbitrary per run (`SpeakerSpan.speaker` is
/// documented as stable only within one run over one file), so the best
/// agreeing map from observed ids to truth ids is searched for, exactly as the
/// sentence scorer does. The mapping is not required to be injective — an
/// over-segmented run should still score what it got right — but ties prefer a
/// bijection, since a collapsing map that ties with one describes the run
/// dishonestly.
WordTruthScore scoreWordsAgainstTruth({
  required List<TruthWord> words,
  required List<int?> assigned,
  required DiarizationTruth truth,
}) {
  final turns = truth.turns;

  // Truth answer per word, by midpoint. The midpoint rather than either edge
  // because whisper's word times drift at the edges, which is exactly where the
  // neighbouring speaker is.
  final expected = <int, int>{};
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final mid = word.startMs + (word.endMs - word.startMs) ~/ 2;
    final speaker = speakerAtMs(turns, mid);
    if (speaker != null) expected[i] = speaker;
  }

  final observedIds = <int>{for (final a in assigned) ?a}.toList()..sort();
  final truthIds = truth.speakers.toList()..sort();

  if (observedIds.isEmpty || truthIds.isEmpty || observedIds.length > 6) {
    return WordTruthScore(
      matchedWords: 0,
      scoredWords: expected.length,
      totalWords: words.length,
      mapping: const {},
      observedClusters: observedIds.length,
      mismatchedIndices: expected.keys.toList()..sort(),
    );
  }

  var bestMatched = -1;
  var bestInjective = false;
  var bestMapping = <int, int>{};

  void consider(Map<int, int> mapping) {
    var matched = 0;
    for (final entry in expected.entries) {
      final observed = entry.key < assigned.length ? assigned[entry.key] : null;
      if (observed != null && mapping[observed] == entry.value) matched++;
    }
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
  for (final entry in expected.entries) {
    final observed = entry.key < assigned.length ? assigned[entry.key] : null;
    if (observed == null || bestMapping[observed] != entry.value) {
      mismatched.add(entry.key);
    }
  }
  mismatched.sort();

  return WordTruthScore(
    matchedWords: bestMatched < 0 ? 0 : bestMatched,
    scoredWords: expected.length,
    totalWords: words.length,
    mapping: bestMapping,
    observedClusters: observedIds.length,
    mismatchedIndices: mismatched,
  );
}
