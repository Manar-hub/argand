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
