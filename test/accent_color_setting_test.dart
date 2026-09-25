import 'package:argand/core/theme/accent_color_controller.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccentColorSetting.decode', () {
    test('nothing stored is the default violet', () {
      expect(AccentColorSetting.decode(null), AppTheme.defaultAccent);
    });

    test('a stored colour comes back as it was saved', () {
      const teal = Color(0xFF00A3A3);
      expect(
        AccentColorSetting.decode(teal.toARGB32().toString()),
        teal,
      );
    });

    test('an unreadable value falls back rather than failing', () {
      expect(AccentColorSetting.decode('violet'), AppTheme.defaultAccent);
      expect(AccentColorSetting.decode(''), AppTheme.defaultAccent);
    });

    test('a see-through colour is made opaque', () {
      // A translucent button reads as disabled.
      expect(
        AccentColorSetting.decode(0x4000A3A3.toString()),
        const Color(0xFF00A3A3),
      );
    });
  });
}
