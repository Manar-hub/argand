// Scores whisper transcript dumps for word accuracy against a reference.
//
// Companion to `tool/score_repetition.dart`. That one answers "did the decoder
// break?"; this one answers "did it hear the right words?" — the failure where
// nothing loops but the app produces "Climidial" where whisper-cli produces
// "Chlamydia".
//
// **The reference is a proxy, not ground truth.** It is normally a `whisper-cli`
// run under a configuration judged better by inspection, so WER here measures
// distance from that configuration rather than distance from what was actually
// said. Read it as "closer to the good result", and always read the printed
// substitutions rather than the rate alone.
//
// **Three numbers, because one was misleading.** A normalized comparison folds
// case and drops punctuation, which is right for "did it hear the word" and
// wrong for everything else — a run reported as reproducing the reference
// "exactly, 0.0% WER" can still differ word-for-word on case and punctuation
// across most of the transcript. So this prints:
//
//   WER   normalized: content only, case and punctuation discarded
//   VERB  verbatim:   the word-for-word number, differences included
//   PUNCT sentence and clause terminator counts against the reference
//
// The punctuation line is not decoration. `sentence_boundaries.dart` turns
// those terminators into the sentence units that speaker assignment attributes
// as a whole, so a lever that improves WER while moving terminators makes
// diarization worse in a way the rate alone cannot show.
//
// Imports `lib/core/text/transcript_diff.dart` rather than reimplementing the
// alignment, so a native measurement and an on-device one cannot disagree for
// reasons unrelated to whisper.
//
// Usage:
//   dart run tool/score_transcript.dart --reference ref.txt run1.txt [run2.txt ...]
//   dart run tool/score_transcript.dart --reference ref.txt --edits 30 run1.txt
//   dart run tool/score_transcript.dart --reference ref.txt --keep-tags run1.txt
//
// `--keep-tags` stops `[BLANK_AUDIO]` and `[LAUGHTER]` being stripped before
// scoring. Required when measuring `suppress_non_speech_tokens`, whose whole
// effect is whether those tags appear: with them stripped the flag is being
// judged by an instrument that cannot see it.

import 'dart:io';

import 'package:argand/core/text/transcript_diff.dart';

void main(List<String> args) {
  String? referencePath;
  var maxEdits = 12;
  var keepTags = false;
  final candidates = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--reference' || '-r':
        if (++i >= args.length) return _usage('--reference needs a path');
        referencePath = args[i];
      case '--edits' || '-e':
        if (++i >= args.length) return _usage('--edits needs a number');
        maxEdits = int.tryParse(args[i]) ?? maxEdits;
      case '--keep-tags':
        keepTags = true;
      default:
        candidates.add(args[i]);
    }
  }

  if (referencePath == null || candidates.isEmpty) {
    return _usage('need --reference <path> and at least one candidate');
  }

  final referenceFile = File(referencePath);
  if (!referenceFile.existsSync()) {
    return _usage('reference not found: $referencePath');
  }

  final referenceText = referenceFile.readAsStringSync();
  final reference = transcriptWords(
    referenceText,
    stripBracketedTags: !keepTags,
  );
  final referenceVerbatim = transcriptWords(
    referenceText,
    tokenization: TranscriptTokenization.verbatim,
    stripBracketedTags: !keepTags,
  );

  stdout.writeln('reference ${_name(referencePath)}: '
      '${reference.length} words${keepTags ? '  (tags kept)' : ''}');

  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('${_name(path).padRight(22)} missing');
      continue;
    }

    final candidateText = file.readAsStringSync();
    final normalized = compareTranscripts(
      reference,
      transcriptWords(candidateText, stripBracketedTags: !keepTags),
    );
    final verbatim = compareTranscripts(
      referenceVerbatim,
      transcriptWords(
        candidateText,
        tokenization: TranscriptTokenization.verbatim,
        stripBracketedTags: !keepTags,
      ),
    );
    final punctuation = comparePunctuation(referenceText, candidateText);

    stdout.writeln('${_name(path).padRight(22)} '
        'WER=${_pct(normalized.wer)}  '
        'VERB=${_pct(verbatim.wer)}  '
        'words=${normalized.candidateWords.toString().padRight(5)} '
        'S=${normalized.substitutions.toString().padRight(4)} '
        'I=${normalized.insertions.toString().padRight(4)} '
        'D=${normalized.deletions}');

    // Flagged rather than merely printed: an unequal sentence count is on its
    // own enough to move every diarization score measured against this run.
    final marker = punctuation.sentenceCountMatches ? ' ' : '!';
    stdout.writeln('  ${" " * 20}${marker}PUNCT $punctuation');

    for (final edit in normalized.edits.take(maxEdits)) {
      stdout.writeln('  ${" " * 20}@${edit.referenceIndex} $edit');
    }
    if (normalized.edits.length > maxEdits) {
      stdout.writeln(
        '  ${" " * 20}... ${normalized.edits.length - maxEdits} more',
      );
    }
  }
}

String _pct(double rate) => '${(rate * 100).toStringAsFixed(1).padLeft(6)}%';

void _usage(String message) {
  stderr.writeln('score_transcript: $message');
  stderr.writeln('usage: dart run tool/score_transcript.dart '
      '--reference <ref.txt> [--edits N] [--keep-tags] <run.txt> ...');
  exitCode = 64;
}

String _name(String path) => path.split(RegExp(r'[\/]')).last;
