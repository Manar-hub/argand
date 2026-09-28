/// Downloadable content -- transcription models, translation languages -- as
/// asset packs, the unit Play Asset Delivery (Android) and Background Assets
/// (iOS) deliver in (CLAUDE.md §7).
library;

/// When a pack arrives, as Play Asset Delivery's delivery modes.
enum AssetPackMode {
  /// Installed with the app, always present, never removed: the bundled base
  /// model, the English translation model.
  installTime,

  /// Fetched when asked for, removable to free the space.
  onDemand,
}

/// What a pack carries, which decides where its files come from and go.
enum AssetPackKind { whisperModel, translationLanguage }

/// One deliverable pack.
class AssetPack {
  const AssetPack({
    required this.name,
    required this.kind,
    required this.mode,
    this.fileName,
    this.assetKey,
    this.languageCode,
  });

  /// Play's pack name: letters, digits and underscores, e.g.
  /// `whisper_small_q5_1`, `translate_de`.
  final String name;
  final AssetPackKind kind;
  final AssetPackMode mode;

  /// For a model: the file it installs, and where the fake's "server" copy
  /// sits in the app bundle.
  final String? fileName;
  final String? assetKey;

  /// For a translation language: its code.
  final String? languageCode;

  /// A transcription model: `ggml-<id>.bin` from `assets/models/`. The
  /// default model is install-time, as the release bundles it (CLAUDE.md §2);
  /// every other is on demand.
  factory AssetPack.whisperModel({
    required String id,
    required String fileName,
    required String assetKey,
    required bool installTime,
  }) =>
      AssetPack(
        name: nameFrom('whisper', id),
        kind: AssetPackKind.whisperModel,
        mode: installTime ? AssetPackMode.installTime : AssetPackMode.onDemand,
        fileName: fileName,
        assetKey: assetKey,
      );

  /// A translation language. English is install-time: the translator always
  /// has it, as the pivot every other language goes through.
  factory AssetPack.translationLanguage(String code) => AssetPack(
        name: nameFrom('translate', code),
        kind: AssetPackKind.translationLanguage,
        mode: code == 'en' ? AssetPackMode.installTime : AssetPackMode.onDemand,
        languageCode: code,
      );

  /// A pack name from anything: lower case, anything else an underscore.
  static String nameFrom(String prefix, String id) =>
      '${prefix}_${id.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '_')}';

  @override
  bool operator ==(Object other) => other is AssetPack && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Where a pack is, after Play's `AssetPackStatus`.
enum AssetPackStatus {
  notInstalled,
  pending,
  downloading,

  /// Downloaded, being moved into place.
  transferring,
  completed,
  failed,
}

class AssetPackState {
  const AssetPackState(
    this.status, {
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
  });

  final AssetPackStatus status;
  final int bytesDownloaded;

  /// Zero when the size is not known -- progress is then indeterminate.
  final int totalBytes;

  /// 0..1, or null while the size is unknown.
  double? get fraction =>
      totalBytes > 0 ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0) : null;

  bool get busy =>
      status == AssetPackStatus.pending ||
      status == AssetPackStatus.downloading ||
      status == AssetPackStatus.transferring;

  static const notInstalled = AssetPackState(AssetPackStatus.notInstalled);
  static const completed = AssetPackState(AssetPackStatus.completed);
}

/// Delivers [AssetPack]s. See the library comment.
abstract interface class AssetPackDelivery {
  /// Whether [pack] is on the device -- [AssetPackState.completed] -- or not.
  Future<AssetPackState> state(AssetPack pack);

  /// Fetches [pack], reporting every step; ends on
  /// [AssetPackStatus.completed] or [AssetPackStatus.failed].
  Stream<AssetPackState> fetch(AssetPack pack);

  /// Removes an on-demand [pack]. An install-time one cannot be removed.
  Future<void> remove(AssetPack pack);

  /// The installed file of a model pack, or null while it is not installed.
  Future<String?> location(AssetPack pack);
}
