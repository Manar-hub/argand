import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The launcher icon's variants: the Argand mark with its hand in each colour,
/// built into the app (android/app/src/main/res, one `<activity-alias>` each in
/// AndroidManifest.xml).
enum LauncherIcon {
  /// The default -- the logo's own blue -- and the icon for colours with no
  /// hue to match: white, pale greys.
  blue(Color(0xFF2F55C8)),
  violet(Color(0xFF9B6CFF)),
  teal(Color(0xFF00A3A3)),
  green(Color(0xFF2FA85A)),
  yellow(Color(0xFFFFD93D)),
  orange(Color(0xFFFF8A3D)),
  red(Color(0xFFE8485A)),

  /// Black and dark greys: the hand in the body's own ink.
  ink(Color(0xFF14151A));

  const LauncherIcon(this.hand);

  final Color hand;

  /// The variant nearest [accent]: by hue for a colour that has one, else
  /// ink for dark and the default for light.
  static LauncherIcon matching(Color accent) {
    final hsv = HSVColor.fromColor(accent);
    if (hsv.saturation < 0.2 || hsv.value < 0.2) {
      return hsv.value < 0.5 ? ink : blue;
    }
    LauncherIcon? best;
    var bestGap = double.infinity;
    for (final icon in values) {
      if (icon == ink) continue;
      final gap = (HSVColor.fromColor(icon.hand).hue - hsv.hue).abs();
      final around = gap > 180 ? 360 - gap : gap;
      if (around < bestGap) {
        bestGap = around;
        best = icon;
      }
    }
    return best!;
  }

  static const _channel = MethodChannel('argand/launcher_icon');

  /// Asks for this icon; Android shows it once the app is in the background.
  /// A no-op where there is no launcher to change (tests, other platforms).
  Future<void> apply() async {
    try {
      await _channel.invokeMethod<void>('set', {'variant': name});
    } on MissingPluginException {
      // No platform side: a host test, or a platform without launcher icons.
    } on PlatformException {
      // The icon is cosmetic; failing to change it must never surface.
    }
  }
}
