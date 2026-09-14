// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_mode_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which theme the app uses, independent of the system setting.
///
/// **Persisted, unlike edit mode or edit scope.** Those are picked for a task
/// and forgotten; a theme preference is a standing choice about the device, and
/// re-asking on every launch would be the surprise.
///
/// Defaults to [ThemeMode.system], which is the right default and also the
/// reason this control has to exist: without it there is no way to look at the
/// theme the device is not currently in.
///
/// Stored in the existing `Settings` key/value table — no migration.

@ProviderFor(ThemeModeSetting)
final themeModeSettingProvider = ThemeModeSettingProvider._();

/// Which theme the app uses, independent of the system setting.
///
/// **Persisted, unlike edit mode or edit scope.** Those are picked for a task
/// and forgotten; a theme preference is a standing choice about the device, and
/// re-asking on every launch would be the surprise.
///
/// Defaults to [ThemeMode.system], which is the right default and also the
/// reason this control has to exist: without it there is no way to look at the
/// theme the device is not currently in.
///
/// Stored in the existing `Settings` key/value table — no migration.
final class ThemeModeSettingProvider
    extends $AsyncNotifierProvider<ThemeModeSetting, ThemeMode> {
  /// Which theme the app uses, independent of the system setting.
  ///
  /// **Persisted, unlike edit mode or edit scope.** Those are picked for a task
  /// and forgotten; a theme preference is a standing choice about the device, and
  /// re-asking on every launch would be the surprise.
  ///
  /// Defaults to [ThemeMode.system], which is the right default and also the
  /// reason this control has to exist: without it there is no way to look at the
  /// theme the device is not currently in.
  ///
  /// Stored in the existing `Settings` key/value table — no migration.
  ThemeModeSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeSettingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeSettingHash();

  @$internal
  @override
  ThemeModeSetting create() => ThemeModeSetting();
}

String _$themeModeSettingHash() => r'3b07706ae27096b8d9c44713867a6c07a93b878b';

/// Which theme the app uses, independent of the system setting.
///
/// **Persisted, unlike edit mode or edit scope.** Those are picked for a task
/// and forgotten; a theme preference is a standing choice about the device, and
/// re-asking on every launch would be the surprise.
///
/// Defaults to [ThemeMode.system], which is the right default and also the
/// reason this control has to exist: without it there is no way to look at the
/// theme the device is not currently in.
///
/// Stored in the existing `Settings` key/value table — no migration.

abstract class _$ThemeModeSetting extends $AsyncNotifier<ThemeMode> {
  FutureOr<ThemeMode> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ThemeMode>, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ThemeMode>, ThemeMode>,
              AsyncValue<ThemeMode>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
