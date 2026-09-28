import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/delivery/asset_pack_delivery.dart';
import '../../core/delivery/delivery_providers.dart';
import '../../core/translation/translator.dart';
import '../../core/whisper/whisper_model_catalog.dart';
import '../../core/whisper/whisper_model_controller.dart';
import '../../core/whisper/whisper_model_info.dart';
import '../../core/whisper/whisper_service.dart';

part 'asset_packs_controller.g.dart';

/// A transcription model as the model screen lists it.
class ModelPackEntry {
  const ModelPackEntry({
    required this.model,
    required this.installed,
    required this.onDevice,
    this.info,
    this.sizeBytes,
  });

  final WhisperModelDescriptor model;
  final bool installed;

  /// Whether its file is on the device yet. The install-time model is
  /// installed before it is: it is copied out of the bundle on first use.
  final bool onDevice;

  /// Its header, when its file is on the device; null there means the file
  /// is not a whisper model the engine can load.
  final WhisperModelInfo? info;
  final int? sizeBytes;

  AssetPack get pack => model.pack;

  /// Installed and, if its file is there to read, a model the engine loads.
  bool get ready => installed && (!onDevice || info != null);
}

/// A translation language as the language screen lists it.
class LanguagePackEntry {
  const LanguagePackEntry({required this.language, required this.installed});

  final TranslationLanguage language;
  final bool installed;

  AssetPack get pack => AssetPack.translationLanguage(language.code);
}

/// Every model this build ships, installed or not, each with what its file says
/// about itself.
@riverpod
Future<List<ModelPackEntry>> modelPacks(Ref ref) async {
  final delivery = ref.watch(assetPackDeliveryProvider);
  final whisper = ref.watch(whisperServiceProvider);
  final models = await ref.watch(whisperModelCatalogProvider).available();
  return [
    for (final model in models)
      await () async {
        final installed = (await delivery.state(model.pack)).status ==
            AssetPackStatus.completed;
        final file = File(await whisper.modelPath(model));
        final exists = await file.exists();
        return ModelPackEntry(
          model: model,
          installed: installed,
          onDevice: exists,
          info: exists ? await WhisperModelInfo.read(file.path) : null,
          sizeBytes: exists ? await file.length() : null,
        );
      }(),
  ];
}

/// Every translation language, which are on the device first.
@riverpod
Future<List<LanguagePackEntry>> languagePacks(Ref ref) async {
  final delivery = ref.watch(assetPackDeliveryProvider);
  final languages = ref.watch(translatorProvider).languages;
  final states = await Future.wait([
    for (final language in languages)
      delivery.state(AssetPack.translationLanguage(language.code)),
  ]);
  final entries = [
    for (final (i, language) in languages.indexed)
      LanguagePackEntry(
        language: language,
        installed: states[i].status == AssetPackStatus.completed,
      ),
  ];
  // Installed first, each group by name (the translator sorts by name).
  return [
    ...entries.where((e) => e.installed),
    ...entries.where((e) => !e.installed),
  ];
}

/// Packs being fetched right now, by name -- what the screens draw progress
/// from. Kept alive, so a download carries on when its screen is left, as a
/// real store download does.
@Riverpod(keepAlive: true)
class AssetPackProgress extends _$AssetPackProgress {
  @override
  Map<String, AssetPackState> build() => const {};

  /// Fetches [pack]; true once it is installed. A second call while one is
  /// running does nothing.
  Future<bool> fetch(AssetPack pack) async {
    if (state[pack.name]?.busy ?? false) return false;
    var last = AssetPackState.notInstalled;
    await for (final step in ref.read(assetPackDeliveryProvider).fetch(pack)) {
      last = step;
      state = {...state, pack.name: step};
    }
    final installed = last.status == AssetPackStatus.completed;
    // A failure stays on screen until tried again; success hands over to the
    // lists, which now read it as installed.
    state = installed ? ({...state}..remove(pack.name)) : state;
    _refresh(pack);
    return installed;
  }

  Future<void> remove(AssetPack pack) async {
    await ref.read(assetPackDeliveryProvider).remove(pack);
    state = {...state}..remove(pack.name);
    _refresh(pack);
    if (pack.kind == AssetPackKind.whisperModel) {
      // The model in use was removed: the choice falls back to the default,
      // and that is saved -- otherwise adding the model again later would
      // quietly make it the one in use again.
      final chosen = ref.read(selectedWhisperModelProvider.notifier);
      final fallback = await ref.read(selectedWhisperModelProvider.future);
      if (fallback != null) await chosen.select(fallback);
    }
  }

  void _refresh(AssetPack pack) {
    switch (pack.kind) {
      case AssetPackKind.whisperModel:
        ref
          ..invalidate(modelPacksProvider)
          // The picker, and through it the chosen model, which falls back to
          // the default if the one removed was chosen.
          ..invalidate(availableWhisperModelsProvider);
      case AssetPackKind.translationLanguage:
        ref.invalidate(languagePacksProvider);
    }
  }
}
