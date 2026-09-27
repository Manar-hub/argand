import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Argand logo: a phasor -- a circle with a hand from its centre -- whose
/// wave runs on into the line under the name.
///
/// **Two layers, one box.** The body (circle, wave, name) and the hand are
/// separate single-colour SVGs sharing a viewBox, so stacked at one size they
/// line up exactly and each takes its own colour: the body the page's ink,
/// the hand the user's action colour ([ColorScheme.primary], set in the
/// settings sheet) -- so the logo changes with every button the user
/// recolours, fading to the new colour rather than jumping.
///
/// The name is outlined paths, not text: the line under it is drawn to those
/// exact outlines, so it is never re-typed in a font.
class ArgandLogo extends StatelessWidget {
  const ArgandLogo({
    super.key,
    required this.semanticLabel,
    this.height = 32,
    this.markOnly = false,
  });

  final String semanticLabel;
  final double height;

  /// The square mark alone, without the name.
  final bool markOnly;

  /// The lockup's viewBox, `565.3 x 129.7`.
  static const _lockupAspect = 565.3 / 129.7;

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
              colorFilter: ColorFilter.mode(scheme.onSurface, BlendMode.srcIn),
            ),
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: scheme.primary),
              duration: const Duration(milliseconds: 300),
              builder: (context, color, _) => SvgPicture.asset(
                'assets/brand/${prefix}_hand.svg',
                colorFilter: ColorFilter.mode(
                  color ?? scheme.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
