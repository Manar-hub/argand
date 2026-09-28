import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import 'mlkit_translator.dart';

part 'translator.g.dart';

/// A language text can be translated into or out of.
class TranslationLanguage {
  const TranslationLanguage(this.code, this.name);

  /// Two-letter code, as Whisper reports a transcript's language.
  final String code;

  /// Its English name, for the picker.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is TranslationLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Why a translation could not run, for the sheet to say in words.
enum TranslationFailure {
  /// The transcript's language is not one the translator knows.
  unsupportedSource,

  /// A language pack could not be downloaded -- usually no connection.
  downloadFailed,

  /// The engine itself failed.
  failed,
}

class TranslationException implements Exception {
  const TranslationException(this.failure);

  final TranslationFailure failure;

  @override
  String toString() => 'TranslationException($failure)';
}

/// On-device translation, one downloadable pack per language.
abstract interface class Translator {
  /// Every language on offer, sorted by name.
  List<TranslationLanguage> get languages;

  Future<bool> isDownloaded(String code);

  /// Fetches [code]'s pack. Throws [TranslationException] when it cannot.
  Future<void> download(String code);

  Future<void> delete(String code);

  /// [texts] from [from] into [to], one result per input, in order. Both
  /// packs must be downloaded first.
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  });
}

@Riverpod(keepAlive: true)
Translator translator(Ref ref) => MlKitTranslator();

/// Settings key for the language the Transcribe sheet translates into.
const String translationTargetSetting = 'translation.target';

/// The language a new transcription is also translated into, or null for
/// none -- the Transcribe sheet's "Translate to". Also what the Translate
/// sheet offers first.
@Riverpod(keepAlive: true)
class TranslationTarget extends _$TranslationTarget {
  @override
  Future<String?> build() async {
    final stored = await ref
        .watch(appDatabaseProvider)
        .readSetting(translationTargetSetting);
    return stored == null || stored.isEmpty ? null : stored;
  }

  Future<void> select(String? code) async {
    await ref
        .read(appDatabaseProvider)
        .writeSetting(translationTargetSetting, code ?? '');
    state = AsyncData(code);
  }
}
