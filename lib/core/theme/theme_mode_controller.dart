import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';

part 'theme_mode_controller.g.dart';

/// Which theme the app uses, independent of the system setting.
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
