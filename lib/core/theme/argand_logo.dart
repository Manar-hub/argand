import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Argand logo: a phasor -- a circle with a hand from its centre -- whose
/// wave runs on into the line under the name.
class ArgandLogo extends StatelessWidget {
  const ArgandLogo({
    super.key,
    required this.semanticLabel,
    this.height = 32,
    this.markOnly = false,
    this.ink,
    this.hand,
  });

  final String semanticLabel;
  final double height;

  /// The square mark alone, without the name.
  final bool markOnly;

  /// Overrides for a logo set on a coloured block (the Pro pages): the body
  /// defaults to the page's ink, the hand to the action colour.
  final Color? ink;
  final Color? hand;

  /// Loads every layer into flutter_svg's cache, so the logo draws on its
  /// first frame; called before `runApp`. Never fails the launch.
  static Future<void> precache() async {
    for (final prefix in ['argand_lockup', 'argand_mark']) {
      for (final layer in ['body', 'hand']) {
        final loader = SvgAssetLoader('assets/brand/${prefix}_$layer.svg');
        try {
          await svg.cache.putIfAbsent(
            loader.cacheKey(null),
            () => loader.loadBytes(null),
          );
        } on Object {
          // Drawn when it loads instead, as before.
        }
      }
    }
  }

  /// The lockup's viewBox, `565.3 x 129.7`.
  static const _lockupAspect = 565.3 / 129.7;

  /// The watermark as the render burns it: the lockup, [body] and [hand]
  /// coloured, on a translucent plate padded by [padFraction] of its height.
  static Future<Uint8List?> watermarkPng({
    required Color body,
    required Color hand,
    required Color plate,
    required double padFraction,
    double logoHeight = 120,
  }) async {
    try {
      final pad = logoHeight * padFraction;
      final width = logoHeight * _lockupAspect + pad * 2;
      final height = logoHeight + pad * 2;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = plate);
      for (final (layer, color) in [('body', body), ('hand', hand)]) {
        final info = await vg.loadPicture(
          SvgAssetLoader('assets/brand/argand_lockup_$layer.svg'),
          null,
        );
        final scale = logoHeight / info.size.height;
        final bounds = Rect.fromLTWH(pad, pad, width - pad * 2, logoHeight);
        canvas
          ..saveLayer(
            bounds,
            Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
          )
          ..translate(pad, pad)
          ..scale(scale)
          ..drawPicture(info.picture)
          ..restore();
        info.picture.dispose();
      }
      final image = await recorder
          .endRecording()
          .toImage(width.ceil(), height.ceil());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes?.buffer.asUint8List();
    } on Object catch (error) {
      debugPrint('Could not draw the watermark logo: $error');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefix = markOnly ? 'argand_mark' : 'argand_lockup';

    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: markOnly ? height : height * _lockupAspect,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.asset(
              'assets/brand/${prefix}_body.svg',
              colorFilter:
                  ColorFilter.mode(ink ?? scheme.onSurface, BlendMode.srcIn),
            ),
            SvgPicture.asset(
              'assets/brand/${prefix}_hand.svg',
              colorFilter:
                  ColorFilter.mode(hand ?? scheme.primary, BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }
}
