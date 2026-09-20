import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../media/media_converter.dart';
import '../media/wav_header.dart';
import 'waveform.dart';

part 'waveform_service.g.dart';

/// Derives a clip's amplitude readings for the timeline's audio lane.
///
/// **Deliberately not `AudioDecoder.getWaveform`.** That helper exists and
/// would be one call, but `docs/engine-architecture.md` records that
/// `performGetWaveform` still carries the upstream resample-ratio flaw the
/// fork fixed only for `convertToWav` — the same bug that decoded HE-AAC at
/// half speed and produced fluent nonsense. Its readings would be stretched by
/// whatever factor the container misreported. Going through the corrected
/// 16kHz extraction and reducing the samples here inherits the fix instead of
/// re-opening the bug for a cosmetic feature.
///
/// **Extraction is serialized.** Decoding is minutes of native CPU on a long
/// clip, and a project with eight clips would otherwise start eight decoders
/// the moment the timeline opened. Lanes therefore fill in one after another.
class WaveformService {
  WaveformService(this._converter);

  final MediaConverter _converter;

  /// Chains every extraction onto the last, so only one decode runs at a time.
  Future<void> _queue = Future.value();

  /// Extracts [mediaPath]'s audio and reduces it to peak readings.
  ///
  /// Returns an empty list when the media cannot be decoded — a clip with no
  /// audio track, or a container the native decoder rejects. That is a flat
  /// lane, never a thrown error: a waveform is a navigation aid, and failing
  /// to draw one must not take the timeline down with it.
  Future<Uint8List> peaksFor(String mediaPath) {
    final result = _queue.then((_) => _extract(mediaPath));
    // The queue must survive a failure, or one undecodable clip would wedge
    // every lane behind it forever.
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Uint8List> _extract(String mediaPath) async {
    // Written to the cache directory rather than beside the media:
    // `discardClipMedia` enumerates a fixed list of files and would strand
    // this one, and `projectMediaBytes` would count it into the size the
    // library reports for the project.
    final dir = await getTemporaryDirectory();
    final scratch = File(p.join(
      dir.path,
      'waveform_${DateTime.now().microsecondsSinceEpoch}.wav',
    ));

    try {
      final wav = await _converter.extractWavForTranscription(
        mediaPath,
        destination: scratch.path,
      );

      final bytes = await wav.readAsBytes();
      final header = WavHeader.parse(bytes);
      // Never a constant 44 — `WavHeader` walks the chunks precisely because
      // encoders put `LIST` or `fact` ahead of `data`.
      final pcm = Uint8List.sublistView(
        bytes,
        header.dataOffset,
        header.dataOffset + header.dataBytes,
      );

      // Off the UI isolate: a ten-minute clip is ~19MB of samples, and
      // scanning it on the main thread drops frames on exactly the screen
      // this is drawn on.
      return await compute(
        _peaks,
        (pcm: pcm, sampleRate: header.sampleRate),
      );
    } catch (_) {
      return Uint8List(0);
    } finally {
      if (await scratch.exists()) {
        await scratch.delete();
      }
    }
  }
}

/// Top-level so it can cross an isolate boundary.
Uint8List _peaks(({Uint8List pcm, int sampleRate}) input) =>
    peaksFromPcm16(input.pcm, sampleRate: input.sampleRate);

@riverpod
WaveformService waveformService(Ref ref) =>
    WaveformService(ref.watch(mediaConverterProvider));
