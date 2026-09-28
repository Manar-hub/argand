import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'transcription_language_controller.g.dart';

/// Settings key holding the chosen language's whisper.cpp code.
///
/// Namespaced like every other key in the shared key/value store.
const String transcriptionLanguageSetting = 'whisper.language';

/// Which language whisper.cpp is told the audio is in.
enum TranscriptionLanguage {
  /// Let whisper.cpp detect the language from the first window of audio.
  auto('auto'),

  english('en');

  const TranscriptionLanguage(this.code);

  /// The value handed to the engine, and the value persisted. Stored as the
  /// code rather than the enum name so a later rename of a Dart identifier
  /// cannot invalidate what is already on a user's device.
  final String code;

  /// The language used when nothing has been chosen.
  static const TranscriptionLanguage fallback = TranscriptionLanguage.auto;

  /// Resolves a persisted code, degrading to [fallback] rather than throwing.
  static TranscriptionLanguage fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return fallback;
  }
}

/// The language the next transcription will use, persisted across launches.
@Riverpod(keepAlive: true)
class SelectedTranscriptionLanguage extends _$SelectedTranscriptionLanguage {
  @override
  Future<TranscriptionLanguage> build() async {
    final stored = await ref
        .watch(appDatabaseProvider)
        .readSetting(transcriptionLanguageSetting);
    return TranscriptionLanguage.fromCode(stored);
  }

  Future<void> select(TranscriptionLanguage language) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(transcriptionLanguageSetting, language.code);
    state = AsyncData(language);
  }
}
