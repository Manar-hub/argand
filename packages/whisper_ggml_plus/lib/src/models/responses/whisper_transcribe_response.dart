// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:whisper_ggml_plus/src/models/responses/whisper_transcribe_segment.dart';

part 'whisper_transcribe_response.freezed.dart';
part 'whisper_transcribe_response.g.dart';

/// Response model of whisper getVersion
@freezed
abstract class WhisperTranscribeResponse with _$WhisperTranscribeResponse {
  ///
  const factory WhisperTranscribeResponse({
    @JsonKey(name: '@type') required String type,
    required String text,
    @JsonKey(name: 'segments')
    required List<WhisperTranscribeSegment>? segments,

    /// FORK: the language whisper used, as an ISO code.
    ///
    /// Populated whether the caller pinned a language or asked for `auto` —
    /// whisper.cpp records the pinned code and the detected one in the same
    /// place, so this is "what was used" rather than "what was guessed".
    ///
    /// Null only when the native layer reported nothing: a platform whose
    /// entrypoint has not been patched (iOS carries none of this fork's
    /// changes yet), or a response predating the patch. Optional for exactly
    /// that reason — an unpatched build must still parse.
    @JsonKey(name: 'detected_language') String? detectedLanguage,
  }) = _WhisperTranscribeResponse;

  const WhisperTranscribeResponse._();

  /// Parse [json] to WhisperTranscribeResponse
  factory WhisperTranscribeResponse.fromJson(Map<String, dynamic> json) =>
      _$WhisperTranscribeResponseFromJson(json);
}
