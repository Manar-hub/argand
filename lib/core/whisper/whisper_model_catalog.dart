import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../delivery/asset_pack_delivery.dart';
import '../delivery/delivery_providers.dart';
import 'whisper_model_info.dart';

part 'whisper_model_catalog.g.dart';

/// Where a model came from, which is also how far it is trusted.
enum WhisperModelSource {
  /// Compiled into the app bundle.
  bundledAsset,

  /// Delivered after install via Play Asset Delivery / Background Assets.
  delivered,
}

/// One selectable transcription model.
class WhisperModelDescriptor {
  const WhisperModelDescriptor({
    required this.id,
    required this.fileName,
    required this.source,
  });

  /// Stable identifier, derived from the filename ([modelIdOf]):
  /// `ggml-small-q5_1.bin` -> `small-q5_1`. This is what gets persisted as the user's choice, so it
  /// must not change for a given model.
  final String id;

  /// Filename both in `assets/models/` and on disk once copied out.
  final String fileName;

  final WhisperModelSource source;

  String get assetKey => '${WhisperModelCatalog.assetDirectory}$fileName';

  /// The asset pack that delivers it: install-time for the default, on
  /// demand for every other.
  AssetPack get pack => AssetPack.whisperModel(
        id: id,
        fileName: fileName,
        assetKey: assetKey,
        installTime: id == WhisperModelCatalog.defaultModelId,
      );

  @override
  bool operator ==(Object other) =>
      other is WhisperModelDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'WhisperModelDescriptor($id)';
}

/// Discovers which transcription models this build can actually run.
class WhisperModelCatalog {
  const WhisperModelCatalog();

  static const String assetDirectory = 'assets/models/';

  /// What a whisper model's file is called, as the models are published:
  /// whisper.cpp's own `ggml-<size>.bin`, and the `whisper-<size>.gguf` /
  /// `.bin` names other converters give the same GGML weights.
  static const List<String> _filePrefixes = ['ggml-', 'whisper-'];
  static const List<String> _fileSuffixes = ['.bin', '.gguf'];

  /// The id a model file is listed under, or null when [fileName] is not a
  /// whisper model's: `ggml-small-q5_1.bin` -> `small-q5_1`,
  /// `whisper-medium-q4_0.gguf` -> `medium-q4_0`.
  static String? modelIdOf(String fileName) {
    if (fileName.contains('/')) return null;
    final suffix =
        _fileSuffixes.where((s) => fileName.endsWith(s)).firstOrNull;
    final prefix =
        _filePrefixes.where((p) => fileName.startsWith(p)).firstOrNull;
    if (suffix == null || prefix == null) return null;
    final id =
        fileName.substring(prefix.length, fileName.length - suffix.length);
    return id.isEmpty ? null : id;
  }

  /// The model used when nothing has been chosen, or when a previously chosen
  /// one is no longer present. CLAUDE.md 2 pins the bundled base model as the
  /// Tier 1 default.
  static const String defaultModelId = 'base';

  /// Every model this build can run, ordered so the listing is stable.
  Future<List<WhisperModelDescriptor>> available() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    final models = <String, WhisperModelDescriptor>{};
    for (final key in manifest.listAssets()) {
      if (!key.startsWith(assetDirectory)) continue;
      final fileName = key.substring(assetDirectory.length);
      final id = modelIdOf(fileName);
      // Two files naming the same model: the first listed is kept, so the
      // choice stays stable rather than flipping between builds.
      if (id == null || models.containsKey(id)) continue;
      models[id] = WhisperModelDescriptor(
        id: id,
        fileName: fileName,
        source: WhisperModelSource.bundledAsset,
      );
    }
    return models.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Resolves [id] against what is actually available, falling back to the
  /// default and then to whatever exists.
  Future<WhisperModelDescriptor?> resolve(String? id) async =>
      pick(await available(), id);

  /// [id] among [models], else the default, else the first; null for none.
  static WhisperModelDescriptor? pick(
    List<WhisperModelDescriptor> models,
    String? id,
  ) {
    if (models.isEmpty) return null;

    for (final candidate in [id, defaultModelId]) {
      if (candidate == null) continue;
      for (final model in models) {
        if (model.id == candidate) return model;
      }
    }
    return models.first;
  }
}

@Riverpod(keepAlive: true)
WhisperModelCatalog whisperModelCatalog(Ref ref) => const WhisperModelCatalog();

/// Models offered in the picker: the ones this build ships and that are on the
/// device -- the install-time default, and any on-demand model added in
/// Settings -> Transcription models.
@riverpod
Future<List<WhisperModelDescriptor>> availableWhisperModels(Ref ref) async {
  final delivery = ref.watch(assetPackDeliveryProvider);
  final models = await ref.watch(whisperModelCatalogProvider).available();
  final states = await Future.wait([
    for (final model in models) delivery.state(model.pack),
  ]);
  return [
    for (final (i, model) in models.indexed)
      if (states[i].status == AssetPackStatus.completed &&
          await _loadable(delivery, model))
        model,
  ];
}

/// Whether an installed model's file is one the engine can load. A delivered
/// file that is not a whisper model would fail inside the native loader, so
/// it is never offered; the model screen says why.
Future<bool> _loadable(
  AssetPackDelivery delivery,
  WhisperModelDescriptor model,
) async {
  final path = await delivery.location(model.pack);
  // Install-time, not copied out yet: it is the bundled default.
  if (path == null) return true;
  return await WhisperModelInfo.read(path) != null;
}
