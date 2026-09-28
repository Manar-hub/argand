import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import 'app_theme.dart';

part 'accent_color_controller.g.dart';

/// The action colour: the fill of every call to action -- Create project,
/// Transcribe, Export, a dialog's confirm -- chosen by the user from a spectrum
/// in the settings sheet.
@Riverpod(keepAlive: true)
class AccentColorSetting extends _$AccentColorSetting {
  static const _key = 'app.accentColor';

  @override
  Future<Color> build() async {
    final stored = await ref.watch(appDatabaseProvider).readSetting(_key);
    return decode(stored);
  }

  /// Optimistic, as the theme toggle is: every button repaints on the next
  /// frame rather than after the disk write.
  Future<void> select(Color color) async {
    state = AsyncData(color);
    await ref
        .read(appDatabaseProvider)
        .writeSetting(_key, color.toARGB32().toString());
  }

  /// Back to [AppTheme.defaultAccent].
  Future<void> reset() => select(AppTheme.defaultAccent);

  /// The stored colour, fully opaque; the default for anything missing or
  /// unreadable -- nothing stored yet, a corrupted row, a value from a newer
  /// build.
  static Color decode(String? stored) {
    final argb = stored == null ? null : int.tryParse(stored);
    if (argb == null) return AppTheme.defaultAccent;
    // Opaque whatever was stored: a see-through button reads as disabled.
    return Color(argb | 0xFF000000);
  }
}
