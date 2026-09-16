// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(thumbnailService)
final thumbnailServiceProvider = ThumbnailServiceProvider._();

final class ThumbnailServiceProvider
    extends
        $FunctionalProvider<
          ThumbnailService,
          ThumbnailService,
          ThumbnailService
        >
    with $Provider<ThumbnailService> {
  ThumbnailServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'thumbnailServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$thumbnailServiceHash();

  @$internal
  @override
  $ProviderElement<ThumbnailService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThumbnailService create(Ref ref) {
    return thumbnailService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThumbnailService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThumbnailService>(value),
    );
  }
}

String _$thumbnailServiceHash() => r'95e78a52021d29d006a584d3fe1ccadd03da9313';

/// The frame images for one clip, keyed so two clips never share a strip.
///
/// `keepAlive` is deliberately *not* set: a filmstrip scrolled off screen has
/// no reason to pin its paths in memory, and regenerating is a directory
/// listing once the JPEGs exist.

@ProviderFor(clipFrames)
final clipFramesProvider = ClipFramesFamily._();

/// The frame images for one clip, keyed so two clips never share a strip.
///
/// `keepAlive` is deliberately *not* set: a filmstrip scrolled off screen has
/// no reason to pin its paths in memory, and regenerating is a directory
/// listing once the JPEGs exist.

final class ClipFramesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  /// The frame images for one clip, keyed so two clips never share a strip.
  ///
  /// `keepAlive` is deliberately *not* set: a filmstrip scrolled off screen has
  /// no reason to pin its paths in memory, and regenerating is a directory
  /// listing once the JPEGs exist.
  ClipFramesProvider._({
    required ClipFramesFamily super.from,
    required ({String mediaPath, String cacheDir, int count}) super.argument,
  }) : super(
         retry: null,
         name: r'clipFramesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$clipFramesHash();

  @override
  String toString() {
    return r'clipFramesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    final argument =
        this.argument as ({String mediaPath, String cacheDir, int count});
    return clipFrames(
      ref,
      mediaPath: argument.mediaPath,
      cacheDir: argument.cacheDir,
      count: argument.count,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipFramesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$clipFramesHash() => r'879947053581ea344174cec6394df5fe186bcc32';

/// The frame images for one clip, keyed so two clips never share a strip.
///
/// `keepAlive` is deliberately *not* set: a filmstrip scrolled off screen has
/// no reason to pin its paths in memory, and regenerating is a directory
/// listing once the JPEGs exist.

final class ClipFramesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<String>>,
          ({String mediaPath, String cacheDir, int count})
        > {
  ClipFramesFamily._()
    : super(
        retry: null,
        name: r'clipFramesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The frame images for one clip, keyed so two clips never share a strip.
  ///
  /// `keepAlive` is deliberately *not* set: a filmstrip scrolled off screen has
  /// no reason to pin its paths in memory, and regenerating is a directory
  /// listing once the JPEGs exist.

  ClipFramesProvider call({
    required String mediaPath,
    required String cacheDir,
    required int count,
  }) => ClipFramesProvider._(
    argument: (mediaPath: mediaPath, cacheDir: cacheDir, count: count),
    from: this,
  );

  @override
  String toString() => r'clipFramesProvider';
}
