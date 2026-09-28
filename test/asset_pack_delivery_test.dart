import 'dart:io';
import 'dart:typed_data';

import 'package:argand/core/delivery/asset_pack_delivery.dart';
import 'package:argand/core/delivery/fake_asset_pack_delivery.dart';
import 'package:argand/core/translation/translator.dart';
import 'package:argand/core/whisper/whisper_model_info.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A whisper.cpp header: the magic, then the eleven hyper-parameters.
Uint8List header(List<int> params, {int magic = 0x67676d6c}) {
  final data = ByteData(4 + params.length * 4)..setUint32(0, magic, Endian.little);
  for (final (i, value) in params.indexed) {
    data.setInt32(4 + i * 4, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

// As read from the bundled files.
const base = [51865, 1500, 512, 8, 6, 448, 512, 8, 6, 80, 1];
const smallQ51 = [51865, 1500, 768, 12, 12, 448, 768, 12, 12, 80, 1009];
const largeV3 = [51866, 1500, 1280, 20, 32, 448, 1280, 20, 32, 128, 1];

class _Bundle extends CachingAssetBundle {
  _Bundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('no asset $key');
    return ByteData.sublistView(bytes);
  }
}

class _Translator implements Translator {
  final downloaded = <String>{'en'};
  bool failNext = false;

  @override
  List<TranslationLanguage> get languages => const [];

  @override
  Future<bool> isDownloaded(String code) async => downloaded.contains(code);

  @override
  Future<void> download(String code) async {
    if (failNext) {
      throw const TranslationException(TranslationFailure.downloadFailed);
    }
    downloaded.add(code);
  }

  @override
  Future<void> delete(String code) async => downloaded.remove(code);

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
  }) async =>
      texts;
}

void main() {
  group('WhisperModelInfo', () {
    test('reads the bundled models as the engine does', () {
      final b = WhisperModelInfo.parse(header(base))!;
      expect((b.size, b.format, b.audioLayers, b.mels), ('base', 'f16', 6, 80));
      final s = WhisperModelInfo.parse(header(smallQ51))!;
      expect((s.size, s.format), ('small', 'q5_1'));
    });

    test('a large-v3 model, with its 128 mel bands, is ready too', () {
      final l = WhisperModelInfo.parse(header(largeV3))!;
      expect((l.size, l.mels), ('large', 128));
    });

    test('anything else is not a model', () {
      expect(WhisperModelInfo.parse(header(base, magic: 0x46554747)), isNull);
      expect(WhisperModelInfo.parse(Uint8List(10)), isNull);
      expect(WhisperModelInfo.parse(header([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])),
          isNull);
    });
  });

  group('FakeAssetPackDelivery', () {
    late Directory dir;
    late _Translator translator;
    late FakeAssetPackDelivery delivery;
    final model = Uint8List.fromList([
      ...header(smallQ51),
      ...List.filled(9 * 1024 * 1024, 7),
    ]);
    final pack = AssetPack.whisperModel(
      id: 'small-q5_1',
      fileName: 'ggml-small-q5_1.bin',
      assetKey: 'assets/models/ggml-small-q5_1.bin',
      installTime: false,
    );

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('packs');
      translator = _Translator();
      delivery = FakeAssetPackDelivery(
        translator: translator,
        modelDirectory: () async => dir,
        bundle: _Bundle({pack.assetKey!: model}),
        bytesPerSecond: 0,
      );
    });

    tearDown(() => dir.delete(recursive: true));

    test('a model is fetched with progress, then is installed and readable',
        () async {
      expect((await delivery.state(pack)).status, AssetPackStatus.notInstalled);
      final steps = await delivery.fetch(pack).toList();
      expect(steps.first.status, AssetPackStatus.pending);
      final downloads =
          steps.where((s) => s.status == AssetPackStatus.downloading).toList();
      expect(downloads.length, greaterThan(1));
      expect(downloads.last.fraction, 1.0);
      expect(steps.last.status, AssetPackStatus.completed);

      expect((await delivery.state(pack)).status, AssetPackStatus.completed);
      final path = await delivery.location(pack);
      expect(await File(path!).length(), model.length);
      expect((await WhisperModelInfo.read(path))!.size, 'small');
    });

    test('removing it deletes the file', () async {
      await delivery.fetch(pack).drain<void>();
      await delivery.remove(pack);
      expect((await delivery.state(pack)).status, AssetPackStatus.notInstalled);
      expect(await delivery.location(pack), isNull);
    });

    test('a failed fetch leaves nothing that looks like a model', () async {
      final missing = AssetPack.whisperModel(
        id: 'gone',
        fileName: 'ggml-gone.bin',
        assetKey: 'assets/models/ggml-gone.bin',
        installTime: false,
      );
      final steps = await delivery.fetch(missing).toList();
      expect(steps.last.status, AssetPackStatus.failed);
      expect(dir.listSync(), isEmpty);
    });

    test('the install-time model is always there and cannot be removed',
        () async {
      final base = AssetPack.whisperModel(
        id: 'base',
        fileName: 'ggml-base.bin',
        assetKey: 'assets/models/ggml-base.bin',
        installTime: true,
      );
      expect((await delivery.state(base)).status, AssetPackStatus.completed);
      expect(() => delivery.remove(base), throwsUnsupportedError);
    });

    test('a language is fetched and removed through the translator', () async {
      final german = AssetPack.translationLanguage('de');
      expect((await delivery.state(german)).status, AssetPackStatus.notInstalled);
      final steps = await delivery.fetch(german).toList();
      expect(steps.last.status, AssetPackStatus.completed);
      expect(translator.downloaded, contains('de'));
      await delivery.remove(german);
      expect(translator.downloaded, isNot(contains('de')));

      translator.failNext = true;
      expect((await delivery.fetch(german).toList()).last.status,
          AssetPackStatus.failed);
    });

    test('English is built in', () async {
      final english = AssetPack.translationLanguage('en');
      expect(english.mode, AssetPackMode.installTime);
      expect((await delivery.state(english)).status, AssetPackStatus.completed);
    });
  });
}
