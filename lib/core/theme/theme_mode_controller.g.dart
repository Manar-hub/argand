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
/// Light or dark, with no "follow the system" option.
///
/// System was offered and removed: with only two themes it is a third control
/// that answers a question the other two already answer, and it leaves the
/// toggle showing neither of the things it can actually be. What replaces it is
/// **first-run behaviour** — before anything is stored, the device's own
/// brightness decides, so a phone in dark mode still opens dark. The moment a
/// choice is made it is that choice, permanently.
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
/// Light or dark, with no "follow the system" option.
///
/// System was offered and removed: with only two themes it is a third control
/// that answers a question the other two already answer, and it leaves the
/// toggle showing neither of the things it can actually be. What replaces it is
/// **first-run behaviour** — before anything is stored, the device's own
/// brightness decides, so a phone in dark mode still opens dark. The moment a
/// choice is made it is that choice, permanently.
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
  /// Light or dark, with no "follow the system" option.
  ///
  /// System was offered and removed: with only two themes it is a third control
  /// that answers a question the other two already answer, and it leaves the
  /// toggle showing neither of the things it can actually be. What replaces it is
  /// **first-run behaviour** — before anything is stored, the device's own
  /// brightness decides, so a phone in dark mode still opens dark. The moment a
  /// choice is made it is that choice, permanently.
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

String _$themeModeSettingHash() => r'ce89989fa4923d87078e3c40227b039b9d929696';

/// Which theme the app uses, independent of the system setting.
///
/// **Persisted, unlike edit mode or edit scope.** Those are picked for a task
/// and forgotten; a theme preference is a standing choice about the device, and
/// re-asking on every launch would be the surprise.
///
/// Light or dark, with no "follow the system" option.
///
/// System was offered and removed: with only two themes it is a third control
/// that answers a question the other two already answer, and it leaves the
/// toggle showing neither of the things it can actually be. What replaces it is
/// **first-run behaviour** — before anything is stored, the device's own
/// brightness decides, so a phone in dark mode still opens dark. The moment a
/// choice is made it is that choice, permanently.
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
