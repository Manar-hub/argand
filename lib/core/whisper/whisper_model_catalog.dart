import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'whisper_model_catalog.g.dart';

/// Where a model came from, which is also how far it is trusted.
enum WhisperModelSource {
  /// Compiled into the app bundle.
  ///
  /// Trustworthy by construction: assets live inside the signed APK/IPA, so
  /// anything listed in the asset manifest is something we shipped. It cannot
  /// be added to or altered on device without breaking the package signature.
  bundledAsset,

  /// Delivered after install via Play Asset Delivery / Background Assets.
  ///
  /// Tier 2, not built yet. Listed here so the distinction exists in the type
  /// system before anything depends on it.
  delivered,
}

/// One selectable transcription model.
class WhisperModelDescriptor {
  const WhisperModelDescriptor({
    required this.id,
    required this.fileName,
    required this.source,
  });

  /// Stable identifier, derived from the filename: `ggml-small-q5_1.bin` ->
  /// `small-q5_1`. This is what gets persisted as the user's choice, so it
  /// must not change for a given model.
  final String id;

  /// Filename both in `assets/models/` and on disk once copied out.
  final String fileName;

  final WhisperModelSource source;

  String get assetKey => '${WhisperModelCatalog.assetDirectory}$fileName';

  @override
  bool operator ==(Object other) =>
      other is WhisperModelDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'WhisperModelDescriptor($id)';
}

/// Discovers which transcription models this build can actually run.
///
/// **Why this reads the asset manifest and not a directory.** Listing a
/// directory on disk would be the obvious way to "show whatever models are
/// present", and it is the wrong way: the app's model directory is also where
/// Tier 2 will deposit downloaded weights, and on a rooted or debuggable
/// device it is writable from outside the app. A directory scan would
/// therefore let an arbitrary file become a selectable model, handing
/// unvetted input straight to whisper.cpp's native GGML parser and bypassing
/// any future licensing constraint (Tier 4, see docs/marketplace-and-licensing.md).
///
/// The asset manifest has neither problem. It is generated at build time from
/// `pubspec.yaml` and sealed inside the signed package, so every entry is one
/// we shipped — while still being discovered rather than hardcoded. Dropping
/// a `.bin` into `assets/models/` makes it appear in the picker with no code
/// change; dropping one onto the device does not.
///
/// When Tier 2 adds delivered models, they must be resolved the same way:
/// matched against a declared allowlist, never discovered by scanning. See
/// docs/engine-architecture.md.
class WhisperModelCatalog {
  const WhisperModelCatalog();

  static const String assetDirectory = 'assets/models/';
  static const String _filePrefix = 'ggml-';
  static const String _fileSuffix = '.bin';

  /// The model used when nothing has been chosen, or when a previously chosen
  /// one is no longer present. CLAUDE.md 2 pins the bundled base model as the
  /// Tier 1 default.
  static const String defaultModelId = 'base';

  /// Every model this build can run, ordered so the listing is stable.
  Future<List<WhisperModelDescriptor>> available() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    final models = <WhisperModelDescriptor>[
      for (final key in manifest.listAssets())
        if (_isModelAsset(key))
          WhisperModelDescriptor(
            id: _idFromAssetKey(key),
            fileName: key.substring(assetDirectory.length),
            source: WhisperModelSource.bundledAsset,
          ),
    ]..sort((a, b) => a.id.compareTo(b.id));

    return models;
  }

  /// Resolves [id] against what is actually available, falling back to the
  /// default and then to whatever exists.
  ///
  /// The fallback matters: a persisted choice can outlive the model it names,
  /// for instance when a build drops a model from the bundle. That must not
  /// leave the app unable to transcribe.
  Future<WhisperModelDescriptor?> resolve(String? id) async {
    final models = await available();
    if (models.isEmpty) return null;

    for (final candidate in [id, defaultModelId]) {
      if (candidate == null) continue;
      for (final model in models) {
        if (model.id == candidate) return model;
      }
    }
    return models.first;
  }

  bool _isModelAsset(String key) =>
      key.startsWith('$assetDirectory$_filePrefix') && key.endsWith(_fileSuffix);

  String _idFromAssetKey(String key) => key.substring(
        assetDirectory.length + _filePrefix.length,
        key.length - _fileSuffix.length,
      );
}

@Riverpod(keepAlive: true)
WhisperModelCatalog whisperModelCatalog(Ref ref) => const WhisperModelCatalog();

/// Models offered in the picker.
@riverpod
Future<List<WhisperModelDescriptor>> availableWhisperModels(Ref ref) =>
    ref.watch(whisperModelCatalogProvider).available();
