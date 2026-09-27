import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'translator.dart';

/// [Translator] on Google's ML Kit: about 30 MB per language, fetched on first
/// use, translating any listed language into any other on the device.
class MlKitTranslator implements Translator {
  MlKitTranslator();

  final _models = OnDeviceTranslatorModelManager();

  @override
  late final List<TranslationLanguage> languages = [
    for (final language in TranslateLanguage.values)
      TranslationLanguage(language.bcpCode, _nameOf(language)),
  ]..sort((a, b) => a.name.compareTo(b.name));

  static String _nameOf(TranslateLanguage language) =>
      language.name[0].toUpperCase() + language.name.substring(1);

  static TranslateLanguage? _languageOf(String code) => TranslateLanguage
      .values
      .where((language) => language.bcpCode == code)
      .firstOrNull;

  @override
  Future<bool> isDownloaded(String code) => _models.isModelDownloaded(code);

  @override
  Future<void> download(String code) async {
    final bool ok;
    try {
      ok = await _models.downloadModel(code, isWifiRequired: false);
    } on Exception {
      throw const TranslationException(TranslationFailure.downloadFailed);
    }
    if (!ok) {
      throw const TranslationException(TranslationFailure.downloadFailed);
    }
  }

  @override
  Future<void> delete(String code) async {
    await _models.deleteModel(code);
  }

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async {
    final source = _languageOf(from);
    final target = _languageOf(to);
    if (source == null || target == null) {
      throw const TranslationException(TranslationFailure.unsupportedSource);
    }
    if (source == target) return List.of(texts);

    final engine = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      return [for (final text in texts) await engine.translateText(text)];
    } on Exception {
      throw const TranslationException(TranslationFailure.failed);
    } finally {
      await engine.close();
    }
  }
}
