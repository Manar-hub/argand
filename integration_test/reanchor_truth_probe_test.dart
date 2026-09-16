import 'dart:io';
import 'dart:math' as math;

import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/text/sentence_units.dart';
import 'package:argand/core/whisper/transcription_language_controller.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_service.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/diarization_truth.dart';

/// Re-anchors a fixture's time references to a current run, printing a `turns`
/// block to paste back in.
///
/// **Why this is needed.** `scoreWordsAgainstTruth` asks "who was speaking at
/// millisecond X", which is decoder-independent *as a method*. But a fixture
/// with no explicit `turns` derives its anchors from `sentences[].startMs/endMs`
/// — times captured when the labels were written. Decoder changes since then
/// (`noFallback: false`, flash attention) moved whisper's word timings, so those
/// anchors no longer line up with any run. On `two_speakers.wav` sentence 14 had
/// drifted 520ms, far enough that its midpoint landed in the previous speaker's
/// turn, and the scorer marked the base model **wrong** on a sentence it
/// attributes exactly as labelled — reporting base at 5.8% word error against
/// small-q5_1's 2.0% and inverting the two models.
///
/// **Alignment is by text, never by position.** An earlier version paired run
/// sentence *i* with label sentence *i* and refused whenever the counts
/// differed, which made `alberta.mp4` (25 sentences against 24 labels)
/// unscoreable. That refusal was wrong: two models legitimately cut the same
/// speech differently, and a label sentence that comes back as two run
/// sentences is a correct transcription either way. Diarization scoring must be
/// agnostic to that. So this aligns the two **word streams** with an edit
/// distance and lets each run word inherit the speaker of the label word it
/// matches; a split label maps to both halves and both inherit its speaker.
///
/// **What this changes, and what it must not.** Only the *times* are
/// re-measured. Every speaker comes from the human labels, and consecutive
/// same-speaker words are merged into turns, so merging happens strictly within
/// one speaker and cannot invent a boundary the labels did not already assert.
///
/// Anchors come from the **base** model deliberately: it is the release model
/// and the one the labels were authored against.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const tmp = '/data/local/tmp';
  final converter = MediaConverter();

  void log(String message) => debugPrint('ANCHOR $message');

  String normalize(String word) {
    final buffer = StringBuffer();
    for (final rune in word.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// For each candidate word, the index of the reference word it aligns to, or
  /// null where it matched nothing (an insertion).
  ///
  /// Plain Levenshtein alignment with a backtrace. Both streams are a couple of
  /// hundred words, so the quadratic table costs nothing.
  List<int?> alignToReference(List<String> reference, List<String> candidate) {
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
        final same = reference[i - 1] == candidate[j - 1];
        cost[i][j] = math.min(
          same ? cost[i - 1][j - 1] : cost[i - 1][j - 1] + 1,
          math.min(cost[i - 1][j] + 1, cost[i][j - 1] + 1),
        );
      }
    }

    final mapped = List<int?>.filled(m, null);
    var i = n;
    var j = m;
    while (i > 0 && j > 0) {
      final same = reference[i - 1] == candidate[j - 1];
      final diagonal = same ? cost[i - 1][j - 1] : cost[i - 1][j - 1] + 1;
      if (cost[i][j] == diagonal) {
        // Substitutions still carry an alignment: a misrecognised word sits in
        // the same place in the conversation as the word it replaced.
        mapped[j - 1] = i - 1;
        i--;
        j--;
      } else if (cost[i][j] == cost[i - 1][j] + 1) {
        i--;
      } else {
        j--;
      }
    }
    return mapped;
  }

  for (final (clip, truthFile) in const [
    ('two_speakers.wav', 'two_speakers.truth.json'),
    ('alberta.mp4', 'alberta.truth.json'),
  ]) {
    testWidgets('re-anchor $clip', (tester) async {
      final media = File('$tmp/$clip');
      final labels = File('$tmp/$truthFile');
      expect(await media.exists(), isTrue, reason: 'adb push $clip first');
      expect(await labels.exists(), isTrue, reason: 'adb push $truthFile first');

      final truth = parseDiarizationTruth(await labels.readAsString());

      final imported = await converter.importToAppStorage(
        projectId: 'reanchor-probe',
        clipId: 'clip',
        fileName: clip,
        bytes: media.openRead(),
      );
      final wav = clip.toLowerCase().endsWith('.wav')
          ? imported
          : await converter.extractWavForTranscription(imported.path);

      final model = (await const WhisperModelCatalog().available())
          .firstWhere((m) => m.id == 'base');

      final result = await WhisperService().transcribeWav(
        wav.path,
        model: model,
        language: TranscriptionLanguage.auto,
        skipSilence: true,
      );
      final words = wordTimingsOf(result);
      final sentences = sentenceUnitsOf(words);

      // The labelled word stream: every word of every label sentence, carrying
      // that sentence's human-assigned speaker.
      final labelWords = <String>[];
      final labelSpeakers = <int>[];
      for (final sentence in truth.sentences) {
        for (final raw in sentence.text.split(RegExp(r'\s+'))) {
          final word = normalize(raw);
          if (word.isEmpty) continue;
          labelWords.add(word);
          labelSpeakers.add(sentence.speaker);
        }
      }

      final runWords = [for (final word in words) normalize(word.text)];
      final mapped = alignToReference(labelWords, runWords);

      log('$clip run=${words.length} words / ${sentences.length} sentences, '
          'labels=${labelWords.length} words / ${truth.sentences.length} '
          'sentences');

      // Each run word takes the speaker of the label word it aligned to.
      // Unaligned words (whisper heard something the labels do not contain)
      // inherit the previous decided speaker, which keeps a turn contiguous
      // rather than punching a hole in it.
      final perWord = <int?>[];
      int? previous;
      var aligned = 0;
      for (var i = 0; i < words.length; i++) {
        final target = mapped[i];
        if (target != null) {
          previous = labelSpeakers[target];
          aligned++;
        }
        perWord.add(previous);
      }
      // A leading run of unaligned words has no previous speaker; backfill from
      // the first decided one.
      final firstDecided = perWord.firstWhere((s) => s != null, orElse: () => null);
      for (var i = 0; i < perWord.length; i++) {
        if (perWord[i] == null) {
          perWord[i] = firstDecided;
        } else {
          break;
        }
      }
      log('$clip aligned $aligned of ${words.length} run words to labels');

      // Merge consecutive same-speaker words into turns, using the run's own
      // times. Merging only happens within one speaker.
      final turns = <({int startMs, int endMs, int speaker})>[];
      for (var i = 0; i < words.length; i++) {
        final speaker = perWord[i];
        if (speaker == null) continue;
        final start = words[i].startMs;
        final end = words[i].endMs;
        if (turns.isNotEmpty && turns.last.speaker == speaker) {
          final last = turns.removeLast();
          turns.add((
            startMs: last.startMs,
            endMs: math.max(last.endMs, end),
            speaker: speaker,
          ));
        } else {
          turns.add((startMs: start, endMs: end, speaker: speaker));
        }
      }

      // Printed so the inherited speakers can be eyeballed against the audio
      // before the block is trusted.
      for (var i = 0; i < sentences.length; i++) {
        final s = sentences[i];
        final speakers = {
          for (var j = s.first; j <= s.last; j++) perWord[j],
        };
        final text = [
          for (var j = s.first; j <= s.last; j++) words[j].text,
        ].join(' ');
        log('$clip  ${i.toString().padLeft(2)} ${s.startMs}-${s.endMs} '
            '${speakers.length == 1 ? 'spk${speakers.first}' : 'MIXED $speakers'}'
            '  "$text"');
      }

      log('$clip ---- paste into $truthFile as "turns" ----');
      log('$clip   "turns": [');
      for (var i = 0; i < turns.length; i++) {
        final t = turns[i];
        final comma = i == turns.length - 1 ? '' : ',';
        log('$clip     {"startMs": ${t.startMs}, "endMs": ${t.endMs}, '
            '"speaker": ${t.speaker}}$comma');
      }
      log('$clip   ],');
      log('$clip ---- end, ${turns.length} turns ----');
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
