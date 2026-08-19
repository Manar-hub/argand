// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Argand';

  @override
  String get libraryEmptyTitle => 'No projects yet';

  @override
  String get libraryEmptyBody =>
      'Import a video or audio file to transcribe it on your device.';

  @override
  String get importAction => 'Import media';

  @override
  String get importCancelled => 'No file selected.';

  @override
  String get stagePreparingModel => 'Preparing model';

  @override
  String get stageCopyingMedia => 'Copying media';

  @override
  String get stageExtractingAudio => 'Extracting audio';

  @override
  String get stageTranscribing => 'Transcribing';

  @override
  String get stageSaving => 'Saving';

  @override
  String transcribingPercent(int percent) {
    return 'Transcribing… $percent%';
  }

  @override
  String get transcriptTitle => 'Transcript';

  @override
  String wordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
      zero: 'No words',
    );
    return '$_temp0';
  }

  @override
  String get transcriptEmpty => 'No speech was detected in this file.';

  @override
  String get playAction => 'Play';

  @override
  String get pauseAction => 'Pause';

  @override
  String get audioOnlyLabel => 'Audio only';

  @override
  String get playerUnavailable => 'This file can\'t be played back.';

  @override
  String get deleteAction => 'Delete';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get transcriptionModelTitle => 'Transcription model';

  @override
  String get modelNameBase => 'Base';

  @override
  String get modelNameSmallQ51 => 'Small (quantized)';

  @override
  String get modelHintFaster => 'Faster, less accurate';

  @override
  String get modelHintAccurate => 'Slower, more accurate';

  @override
  String modelSwitched(String model) {
    return 'Now transcribing with $model';
  }

  @override
  String get retryAction => 'Try again';
}
