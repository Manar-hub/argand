import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/theme/launcher_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LauncherIcon.matching', () {
    test('every variant matches itself', () {
      for (final icon in LauncherIcon.values) {
        expect(LauncherIcon.matching(icon.hand), icon);
      }
    });

    test('the settings sheet presets each have their own variant', () {
      expect(LauncherIcon.matching(AppTheme.defaultAccent), LauncherIcon.violet);
      expect(LauncherIcon.matching(const Color(0xFF116DD6)), LauncherIcon.blue);
      expect(LauncherIcon.matching(const Color(0xFF00A3A3)), LauncherIcon.teal);
      expect(LauncherIcon.matching(const Color(0xFFFFD93D)), LauncherIcon.yellow);
      expect(LauncherIcon.matching(const Color(0xFFFF8A3D)), LauncherIcon.orange);
      expect(LauncherIcon.matching(const Color(0xFFE8485A)), LauncherIcon.red);
    });

    test('colours without a hue: black is ink, white keeps the default', () {
      expect(LauncherIcon.matching(Colors.black), LauncherIcon.ink);
      expect(LauncherIcon.matching(const Color(0xFF333333)), LauncherIcon.ink);
      expect(LauncherIcon.matching(Colors.white), LauncherIcon.blue);
      expect(LauncherIcon.matching(const Color(0xFFCCCCCC)), LauncherIcon.blue);
    });

    test('a hue between two goes to the nearer, across red', () {
      expect(LauncherIcon.matching(const Color(0xFFFF0040)), LauncherIcon.red);
      expect(LauncherIcon.matching(const Color(0xFF40FF60)), LauncherIcon.green);
    });
  });
}
