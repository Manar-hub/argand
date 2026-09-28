import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path/path.dart' as p;

import '../translation/translator.dart';
import 'asset_pack_delivery.dart';

/// [AssetPackDelivery] without the store: what the app runs until it is
/// published and real Play Asset Delivery has packs to serve.
class FakeAssetPackDelivery implements AssetPackDelivery {
  FakeAssetPackDelivery({
    required this.translator,
    required this.modelDirectory,
    AssetBundle? bundle,
    this.bytesPerSecond = 80 * 1024 * 1024,
  }) : _bundle = bundle ?? rootBundle;

  final Translator translator;
  /// Where model packs land: `WhisperService.modelPath`'s directory.
  final Future<Directory> Function() modelDirectory;
  final AssetBundle _bundle;

  /// The simulated download speed; zero for no pacing at all.
  final int bytesPerSecond;

  static const _chunk = 4 * 1024 * 1024;

  Future<File> _modelFile(AssetPack pack) async =>
      File(p.join((await modelDirectory()).path, pack.fileName!));

  @override
  Future<AssetPackState> state(AssetPack pack) async {
    switch (pack.kind) {
      case AssetPackKind.whisperModel:
        // Install-time is there by definition; its file is copied out of the
        // bundle on first use, as it always was.
        if (pack.mode == AssetPackMode.installTime) {
          return AssetPackState.completed;
        }
        return await (await _modelFile(pack)).exists()
            ? AssetPackState.completed
            : AssetPackState.notInstalled;
      case AssetPackKind.translationLanguage:
        return await translator.isDownloaded(pack.languageCode!)
            ? AssetPackState.completed
            : AssetPackState.notInstalled;
    }
  }

  @override
  Stream<AssetPackState> fetch(AssetPack pack) async* {
    yield const AssetPackState(AssetPackStatus.pending);
    switch (pack.kind) {
      case AssetPackKind.whisperModel:
        yield* _fetchModel(pack);
      case AssetPackKind.translationLanguage:
        // No byte count from ML Kit: indeterminate until it is done.
        yield const AssetPackState(AssetPackStatus.downloading);
        try {
          await translator.download(pack.languageCode!);
          yield AssetPackState.completed;
        } on Object {
          yield const AssetPackState(AssetPackStatus.failed);
        }
    }
  }

  Stream<AssetPackState> _fetchModel(AssetPack pack) async* {
    final file = await _modelFile(pack);
    if (await file.exists()) {
      yield AssetPackState.completed;
      return;
    }
    final part = File('${file.path}.part');
    IOSink? sink;
    var installed = false;
    var failed = false;
    try {
      // The whole model at once: Flutter has no streaming asset read (see
      // `WhisperService.ensureModelReady`), so this peaks at one model in
      // memory -- as the first-use copy always has.
      final data = await _bundle.load(pack.assetKey!);
      final total = data.lengthInBytes;
      await file.parent.create(recursive: true);
      sink = part.openWrite();
      final watch = Stopwatch()..start();
      for (var offset = 0; offset < total; offset += _chunk) {
        final length = (total - offset).clamp(0, _chunk);
        sink.add(Uint8List.view(data.buffer, data.offsetInBytes + offset, length));
        await sink.flush();
        final done = offset + length;
        yield AssetPackState(
          AssetPackStatus.downloading,
          bytesDownloaded: done,
          totalBytes: total,
        );
        if (bytesPerSecond > 0) {
          final due = Duration(microseconds: done * 1000000 ~/ bytesPerSecond);
          if (due > watch.elapsed) await Future<void>.delayed(due - watch.elapsed);
        }
      }
      await sink.close();
      sink = null;
      yield AssetPackState(
        AssetPackStatus.transferring,
        bytesDownloaded: total,
        totalBytes: total,
      );
      await part.rename(file.path);
      installed = true;
    } on Object {
      failed = true;
    } finally {
      // Failed or abandoned part-way (the listener cancelled): nothing half
      // written is left to look like a model.
      if (!installed) {
        await sink?.close();
        if (await part.exists()) await part.delete();
      }
    }
    yield failed
        ? const AssetPackState(AssetPackStatus.failed)
        : AssetPackState.completed;
  }

  @override
  Future<void> remove(AssetPack pack) async {
    if (pack.mode == AssetPackMode.installTime) {
      throw UnsupportedError('${pack.name} is installed with the app');
    }
    switch (pack.kind) {
      case AssetPackKind.whisperModel:
        final file = await _modelFile(pack);
        if (await file.exists()) await file.delete();
      case AssetPackKind.translationLanguage:
        await translator.delete(pack.languageCode!);
    }
  }

  @override
  Future<String?> location(AssetPack pack) async {
    if (pack.kind != AssetPackKind.whisperModel) return null;
    final file = await _modelFile(pack);
    return await file.exists() ? file.path : null;
  }
}
