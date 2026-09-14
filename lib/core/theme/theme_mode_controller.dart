import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'theme_mode_controller.g.dart';

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
@Riverpod(keepAlive: true)
class ThemeModeSetting extends _$ThemeModeSetting {
  static const _key = 'app.themeMode';

  @override
  Future<ThemeMode> build() async {
    final stored = await ref.watch(appDatabaseProvider).readSetting(_key);
    return _decode(stored);
  }

  /// What the device is doing right now, used only until a choice is stored.
  static ThemeMode get _deviceDefault =>
      PlatformDispatcher.instance.platformBrightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;

  Future<void> select(ThemeMode mode) async {
    // Optimistic: the theme flips on the next frame rather than after a disk
    // write, because a visible lag between tapping "Dark" and the screen going
    // dark reads as the control being broken.
    state = AsyncData(mode);
    await ref.read(appDatabaseProvider).writeSetting(_key, mode.name);
  }

  /// Falls back to the device's brightness for anything unrecognised — nothing
  /// stored yet, a value from a newer build, or a corrupted row.
  static ThemeMode _decode(String? stored) {
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => _deviceDefault,
    };
  }
}
