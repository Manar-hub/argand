// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'caption_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Captions for a transcript, grouped from its words.

@ProviderFor(captionCues)
final captionCuesProvider = CaptionCuesFamily._();

/// Captions for a transcript, grouped from its words.

final class CaptionCuesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CaptionCue>>,
          List<CaptionCue>,
          Stream<List<CaptionCue>>
        >
    with $FutureModifier<List<CaptionCue>>, $StreamProvider<List<CaptionCue>> {
  /// Captions for a transcript, grouped from its words.
  CaptionCuesProvider._({
    required CaptionCuesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'captionCuesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$captionCuesHash();

  @override
  String toString() {
    return r'captionCuesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<CaptionCue>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CaptionCue>> create(Ref ref) {
    final argument = this.argument as String;
    return captionCues(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CaptionCuesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$captionCuesHash() => r'ae9350531b2a825c822f12bbe17bebed89862c21';

/// Captions for a transcript, grouped from its words.

final class CaptionCuesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<CaptionCue>>, String> {
  CaptionCuesFamily._()
    : super(
        retry: null,
        name: r'captionCuesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Captions for a transcript, grouped from its words.

  CaptionCuesProvider call(String transcriptId) =>
      CaptionCuesProvider._(argument: transcriptId, from: this);

  @override
  String toString() => r'captionCuesProvider';
}
