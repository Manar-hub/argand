// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accent_color_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The action colour: the fill of every call to action -- Create project,
/// Transcribe, Export, a dialog's confirm -- chosen by the user from a spectrum
/// in the settings sheet.

@ProviderFor(AccentColorSetting)
final accentColorSettingProvider = AccentColorSettingProvider._();

/// The action colour: the fill of every call to action -- Create project,
/// Transcribe, Export, a dialog's confirm -- chosen by the user from a spectrum
/// in the settings sheet.
final class AccentColorSettingProvider
    extends $AsyncNotifierProvider<AccentColorSetting, Color> {
  /// The action colour: the fill of every call to action -- Create project,
  /// Transcribe, Export, a dialog's confirm -- chosen by the user from a spectrum
  /// in the settings sheet.
  AccentColorSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accentColorSettingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accentColorSettingHash();

  @$internal
  @override
  AccentColorSetting create() => AccentColorSetting();
}

String _$accentColorSettingHash() =>
    r'7947798b241e646ae43000e1d3ff17e983809dd7';

/// The action colour: the fill of every call to action -- Create project,
/// Transcribe, Export, a dialog's confirm -- chosen by the user from a spectrum
/// in the settings sheet.

abstract class _$AccentColorSetting extends $AsyncNotifier<Color> {
  FutureOr<Color> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Color>, Color>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Color>, Color>,
              AsyncValue<Color>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// A colour tried in the settings sheet without Pro: worn app-wide while the
/// sheet is open, never stored.

@ProviderFor(AccentPreview)
final accentPreviewProvider = AccentPreviewProvider._();

/// A colour tried in the settings sheet without Pro: worn app-wide while the
/// sheet is open, never stored.
final class AccentPreviewProvider
    extends $NotifierProvider<AccentPreview, Color?> {
  /// A colour tried in the settings sheet without Pro: worn app-wide while the
  /// sheet is open, never stored.
  AccentPreviewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accentPreviewProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accentPreviewHash();

  @$internal
  @override
  AccentPreview create() => AccentPreview();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Color? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Color?>(value),
    );
  }
}

String _$accentPreviewHash() => r'844c0b76e41e1089b1f3d2056b88ae43f28efac6';

/// A colour tried in the settings sheet without Pro: worn app-wide while the
/// sheet is open, never stored.

abstract class _$AccentPreview extends $Notifier<Color?> {
  Color? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Color?, Color?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Color?, Color?>,
              Color?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The action colour the app wears: a colour being previewed, else the saved
/// one with Pro, else the default.

@ProviderFor(appAccent)
final appAccentProvider = AppAccentProvider._();

/// The action colour the app wears: a colour being previewed, else the saved
/// one with Pro, else the default.

final class AppAccentProvider extends $FunctionalProvider<Color, Color, Color>
    with $Provider<Color> {
  /// The action colour the app wears: a colour being previewed, else the saved
  /// one with Pro, else the default.
  AppAccentProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appAccentProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appAccentHash();

  @$internal
  @override
  $ProviderElement<Color> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Color create(Ref ref) {
    return appAccent(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Color value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Color>(value),
    );
  }
}

String _$appAccentHash() => r'8797390a2d4d88072e67900a9e7d098b243ed1a4';

/// The action colour outside a preview. Choosing one is a Pro feature.

@ProviderFor(committedAccent)
final committedAccentProvider = CommittedAccentProvider._();

/// The action colour outside a preview. Choosing one is a Pro feature.

final class CommittedAccentProvider
    extends $FunctionalProvider<Color, Color, Color>
    with $Provider<Color> {
  /// The action colour outside a preview. Choosing one is a Pro feature.
  CommittedAccentProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'committedAccentProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$committedAccentHash();

  @$internal
  @override
  $ProviderElement<Color> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Color create(Ref ref) {
    return committedAccent(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Color value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Color>(value),
    );
  }
}

String _$committedAccentHash() => r'6d1f1ae6e81234644a66c3431c5270836c9ce5c7';
