// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_fonts.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The fonts the user has added, each loaded and ready to draw.

@ProviderFor(CustomFonts)
final customFontsProvider = CustomFontsProvider._();

/// The fonts the user has added, each loaded and ready to draw.
final class CustomFontsProvider
    extends $AsyncNotifierProvider<CustomFonts, List<CustomFont>> {
  /// The fonts the user has added, each loaded and ready to draw.
  CustomFontsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'customFontsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$customFontsHash();

  @$internal
  @override
  CustomFonts create() => CustomFonts();
}

String _$customFontsHash() => r'c2500e53fde51b0be599a5b10c53ab351cebffcd';

/// The fonts the user has added, each loaded and ready to draw.

abstract class _$CustomFonts extends $AsyncNotifier<List<CustomFont>> {
  FutureOr<List<CustomFont>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<CustomFont>>, List<CustomFont>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<CustomFont>>, List<CustomFont>>,
              AsyncValue<List<CustomFont>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
