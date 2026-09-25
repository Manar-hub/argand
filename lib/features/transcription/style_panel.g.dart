// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'style_panel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How a sentence looks: its own look, else its layer's, else the default.
///
/// Watches the sentence's words and the project's layers, so the panel shows
/// the change it just made.

@ProviderFor(sentenceLook)
final sentenceLookProvider = SentenceLookFamily._();

/// How a sentence looks: its own look, else its layer's, else the default.
///
/// Watches the sentence's words and the project's layers, so the panel shows
/// the change it just made.

final class SentenceLookProvider
    extends
        $FunctionalProvider<AsyncValue<ItemLook>, ItemLook, FutureOr<ItemLook>>
    with $FutureModifier<ItemLook>, $FutureProvider<ItemLook> {
  /// How a sentence looks: its own look, else its layer's, else the default.
  ///
  /// Watches the sentence's words and the project's layers, so the panel shows
  /// the change it just made.
  SentenceLookProvider._({
    required SentenceLookFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'sentenceLookProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sentenceLookHash();

  @override
  String toString() {
    return r'sentenceLookProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<ItemLook> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<ItemLook> create(Ref ref) {
    final argument = this.argument as (String, String);
    return sentenceLook(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is SentenceLookProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sentenceLookHash() => r'b12483dfe63cdca8781439e91e1c78e7f0485351';

/// How a sentence looks: its own look, else its layer's, else the default.
///
/// Watches the sentence's words and the project's layers, so the panel shows
/// the change it just made.

final class SentenceLookFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ItemLook>, (String, String)> {
  SentenceLookFamily._()
    : super(
        retry: null,
        name: r'sentenceLookProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// How a sentence looks: its own look, else its layer's, else the default.
  ///
  /// Watches the sentence's words and the project's layers, so the panel shows
  /// the change it just made.

  SentenceLookProvider call(String projectId, String sentenceId) =>
      SentenceLookProvider._(argument: (projectId, sentenceId), from: this);

  @override
  String toString() => r'sentenceLookProvider';
}
