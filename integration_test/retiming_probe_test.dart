import 'dart:io';

import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/text/sentence_units.dart';
import 'package:argand/core/transcript/sentence_edit.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// How far a sentence edit moves a word boundary.
///
/// **The question.** When a line is retyped, `planSentenceEdit` keeps the
/// untouched words on their exact timestamps and keeps the edited run's outer
/// span exact, but divides the *inside* of that run by
/// [distributeSpan] — proportional to word length, never measured against
/// audio. A word-by-word caption style (a Tier 2 grouping mode) reads those
/// boundaries directly, so the estimate would be what it highlights on.
///
/// Nothing consumes them at word granularity yet, which makes this the cheap
/// moment to find out how wrong they are.
///
/// **How it is measured.** Whisper's own DTW word timings are taken as the
/// reference. They are not truth — they are the same estimator the app already
/// relies on everywhere else, and `MediaPlayer._seekLeadIn` exists at 60ms
/// because they land mid-word. The number produced is therefore "how far an
/// edit moves a boundary away from what the app would otherwise have shown",
/// which is exactly the question for caption sync, and not accuracy against the
/// actual speech.
///
/// Two shapes are measured, both against real boundaries:
///
///  - **Pair** — two consecutive words, their combined span re-divided. This is
///    the reported case's geometry: one span, two words, where does the split
///    fall. "brainbeats" becoming "praying beads" asks precisely this.
///  - **Sentence** — every internal boundary of a whole line re-derived, i.e.
///    the user retyped all of it. The worst case, since a real edit touches one
///    or two words.
///
/// Read-only: it changes nothing and asserts nothing about quality. The
/// thresholds are printed beside the result so the numbers can be read against
/// a bar fixed before the run.
///
/// ```
/// adb push alberta.mp4      /data/local/tmp/alberta.mp4
/// adb push two_speakers.wav /data/local/tmp/two_speakers.wav
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('RETIME $message');

  /// Percentile of an already-sorted list, by nearest rank.
  int percentile(List<int> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    final rank = (fraction * sorted.length).ceil() - 1;
    return sorted[rank.clamp(0, sorted.length - 1)];
  }

  void report(String label, List<int> errors) {
    if (errors.isEmpty) {
      log('$label: no samples');
      return;
    }
    final sorted = [...errors]..sort();
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;

    log('$label  n=${sorted.length}  '
        'mean=${mean.toStringAsFixed(1)}ms  '
        'median=${percentile(sorted, 0.5)}ms  '
        'p95=${percentile(sorted, 0.95)}ms  '
        'max=${sorted.last}ms');
  }

  testWidgets('boundary error introduced by re-dividing a span', (tester) async {
    final catalog = const WhisperModelCatalog();
    final models = await catalog.available();

    for (final clip in ['two_speakers.wav', 'alberta.mp4']) {
      final source = File('$tmp/$clip');
      expect(await source.exists(), isTrue, reason: 'adb push $clip first');

      final imported = await converter.importToAppStorage(
        projectId: 'retiming-${clip.hashCode}',
        fileName: clip,
        bytes: source.openRead(),
      );
      final wav = await converter.extractWavForTranscription(imported.path);

      for (final model in models) {
        final result = await WhisperService().transcribeWav(
          wav.path,
          model: model,
          language: TranscriptionLanguage.auto,
          skipSilence: true,
        );
        final words = wordTimingsOf(result);
        if (words.length < 2) {
          log('$clip / ${model.id}: too few words to measure');
          continue;
        }

        final durations = [
          for (final word in words)
            if (word.endMs > word.startMs) word.endMs - word.startMs,
        ]..sort();
        final meanDuration = durations.isEmpty
            ? 0.0
            : durations.reduce((a, b) => a + b) / durations.length;

        log('');
        log('=== $clip / ${model.id} — ${words.length} words, '
            'mean word ${meanDuration.toStringAsFixed(0)}ms, '
            'median ${percentile(durations, 0.5)}ms ===');

        // Which sentence each word belongs to, so a pair that straddles a
        // sentence boundary can be told apart from one inside a line.
        final sentenceOf = <int, int>{};
        final units = sentenceUnitsOf(words);
        for (final (index, unit) in units.indexed) {
          for (var w = unit.first; w <= unit.last; w++) {
            sentenceOf[w] = index;
          }
        }

        // --- Pair: the reported case's geometry. ---
        //
        // Reported twice. `replaceSentence` only ever redistributes inside one
        // sentence, so a cross-sentence pair is a case the code cannot produce
        // — and those pairs span a speaker handover or a full stop, where the
        // silence between utterances dominates and the split lands in the
        // middle of nothing. The all-pairs figure is kept beside it so the
        // narrowing is visible rather than a quiet filter on a bad result.
        final pairErrors = <int>[];
        final withinErrors = <int>[];
        final worstPairs = <({int error, String text})>[];
        final worstWithin = <({int error, String text})>[];

        for (var i = 0; i + 1 < words.length; i++) {
          final a = words[i];
          final b = words[i + 1];
          if (b.startMs != a.endMs) continue;
          if (b.endMs <= a.startMs) continue;

          final predicted = distributeSpan(
            words: [a.text, b.text],
            startMs: a.startMs,
            endMs: b.endMs,
          );
          final error = (predicted.first.$2 - a.endMs).abs();
          pairErrors.add(error);
          worstPairs.add((error: error, text: '${a.text} | ${b.text}'));

          if (sentenceOf[i] != null && sentenceOf[i] == sentenceOf[i + 1]) {
            withinErrors.add(error);
            worstWithin.add((error: error, text: '${a.text} | ${b.text}'));
          }
        }

        report('  pair all  ', pairErrors);
        report('  pair in-sn', withinErrors);

        // --- Sentence: every internal boundary re-derived. ---
        final sentenceErrors = <int>[];
        final worstSentences = <({int error, String text})>[];

        for (final unit in units) {
          if (unit.wordCount < 2) continue;
          final slice = words.sublist(unit.first, unit.last + 1);

          final predicted = distributeSpan(
            words: [for (final word in slice) word.text],
            startMs: unit.startMs,
            endMs: unit.endMs,
          );

          var worst = 0;
          for (var i = 0; i + 1 < slice.length; i++) {
            final error = (predicted[i].$2 - slice[i].endMs).abs();
            sentenceErrors.add(error);
            if (error > worst) worst = error;
          }
          worstSentences.add((
            error: worst,
            text: [for (final word in slice) word.text].join(' '),
          ));
        }

        report('  sentence', sentenceErrors);

        worstPairs.sort((a, b) => b.error.compareTo(a.error));
        for (final entry in worstPairs.take(5)) {
          log('  worst pair    ${entry.error}ms  "${entry.text}"');
        }

        worstWithin.sort((a, b) => b.error.compareTo(a.error));
        for (final entry in worstWithin.take(5)) {
          log('  worst in-sent ${entry.error}ms  "${entry.text}"');
        }

        worstSentences.sort((a, b) => b.error.compareTo(a.error));
        for (final entry in worstSentences.take(5)) {
          final text = entry.text.length > 70
              ? '${entry.text.substring(0, 70)}…'
              : entry.text;
          log('  worst line  ${entry.error}ms  "$text"');
        }
      }

      await converter.discardProjectMedia('retiming-${clip.hashCode}');
    }

    log('');
    log('thresholds fixed before the run: p95 under 50ms reads as in sync; '
        'above 120ms a highlight visibly leads or trails.');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
