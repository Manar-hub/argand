/// Controls how amplitude values returned by `getWaveform` / `getWaveformBytes`
/// are scaled into the 0.0–1.0 range.
///
/// Choose [perFile] for single-track visualizations where you want the
/// waveform to fill the available height regardless of how loud the source is.
/// Choose [absolute] when you need to compare loudness across multiple tracks
/// — a quiet recording will then visibly look quieter than a loud one.
enum WaveformNormalization {
  /// Each waveform is rescaled so its loudest window equals 1.0.
  ///
  /// This is the default and matches the behavior of audio_decoder up to and
  /// including 0.7.x. Best for showing a single track in isolation: voice
  /// memos, podcast previews, chat voice messages, etc.
  perFile('perFile'),

  /// Amplitudes are scaled so absolute loudness is preserved across files.
  ///
  /// Two recordings of different loudness will visually differ in height.
  /// Best for music apps that show several tracks side by side.
  absolute('absolute')
  ;

  const WaveformNormalization(this.wireValue);

  /// Stable identifier used to communicate the chosen mode to the native
  /// platform implementations. Pinned so it survives Dart-side renames of the
  /// enum constants.
  final String wireValue;
}
