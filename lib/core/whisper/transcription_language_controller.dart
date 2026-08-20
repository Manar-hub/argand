import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'transcription_language_controller.g.dart';

/// Settings key holding the chosen language's whisper.cpp code.
///
/// Namespaced like every other key in the shared key/value store.
const String transcriptionLanguageSetting = 'whisper.language';

/// Which language whisper.cpp is told the audio is in.
///
/// **Not the same thing as `lib/l10n/app_en.arb`.** That file is interface
/// text and is single-locale by CLAUDE.md 4; this is a property of the media
/// being transcribed, and the two move independently — an English UI
/// transcribing Portuguese audio is an ordinary case.
///
/// Only two entries for Tier 1, which is the whole point of making this an
/// enum rather than a free-form code: whisper.cpp accepts ~99 languages, but
/// each one we expose is one we have to be able to claim works. Adding a
/// language later is one entry here plus one ARB string.
enum TranscriptionLanguage {
  /// Let whisper.cpp detect the language from the first window of audio.
  ///
  /// `"auto"` is whisper.cpp's own sentinel for detection, not something this
  /// app interprets. Detection reads only the opening ~30 seconds, so it can
  /// be wrong on a file that starts with music or silence — which is the
  /// reason an explicit choice is offered at all.
  auto('auto'),

  english('en');

  const TranscriptionLanguage(this.code);

  /// The value handed to the engine, and the value persisted. Stored as the
  /// code rather than the enum name so a later rename of a Dart identifier
  /// cannot invalidate what is already on a user's device.
  final String code;

  /// The language used when nothing has been chosen.
  ///
  /// Detection rather than English: before Phase 1.2 the engine was silently
  /// told every file was English, which is wrong for any other input and
  /// invisible when it happens. Whether `auto` also beats a pinned `en` on
  /// English audio is unmeasured — the picker exists partly to settle that.
  static const TranscriptionLanguage fallback = TranscriptionLanguage.auto;

  /// Resolves a persisted code, degrading to [fallback] rather than throwing.
  ///
  /// A stored value can outlive the entry it names if a later build drops a
  /// language; that must not leave the app unable to transcribe.
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
