// Scores whisper-cli transcript dumps for decoder repetition loops.
//
// Engine parameter work is measured natively rather than on-device: a
// `flutter test` cycle reinstalls a 432MB debug APK for every run, which costs
// minutes, while `whisper-cli.exe` answers the same parameter question in
// seconds against the same whisper.cpp. This script closes that loop by scoring
// the CLI's output with the *same* detector the app uses, so a native
// measurement and an on-device one are directly comparable.
//
// Deliberately imports `lib/core/text/repetition.dart` rather than
// reimplementing the scan. A second copy of the rule would be free to drift,
// and then two runs could disagree for reasons that have nothing to do with
// whisper.
//
// Usage:
//   dart run tool/score_repetition.dart <file.txt> [more.txt ...]
//
// Input is whisper-cli's default stdout/`-otxt` form; leading `[hh:mm:ss.mmm
// --> hh:mm:ss.mmm]` stamps are stripped before scanning.

import 'dart:io';

import 'package:argand/core/text/repetition.dart';

final RegExp _timestamp = RegExp(r'\[[^\]]*\]');

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/score_repetition.dart <file.txt> ...');
    exitCode = 64;
    return;
  }

  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('${_name(path)}: missing');
      continue;
    }

    final words = file
        .readAsStringSync()
        .replaceAll(_timestamp, ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);

    // Both shapes, always. Scanning only across whitespace once reported a
    // clean score for a transcript whose loop was a single 273-character
    // token, so a one-sided scan here would silently pass a broken run.
    final report = analyzeRepetition(words);

    stdout.writeln('${_name(path).padRight(18)} '
        'words=${words.length.toString().padRight(5)} '
        '${report.hasLoop ? "LOOP " : "clean"} '
        'across=${report.acrossWords.length.toString().padRight(3)} '
        'within=${report.withinWords.length.toString().padRight(3)} '
        'loopedWords=${report.loopedWords.toString().padRight(5)} '
        'ratio=${report.ratio.toStringAsFixed(4)}');

    for (final run in [...report.acrossWords, ...report.withinWords]) {
      final phrase = run.phrase.join(' ');
      stdout.writeln('  ${" " * 16}$run'.replaceFirst(
        phrase,
        phrase.length > 50 ? '${phrase.substring(0, 50)}...' : phrase,
      ));
    }
  }
}

String _name(String path) => path.split(RegExp(r'[\\/]')).last;
