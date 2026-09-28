import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_shine.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// The Get Pro button: always the cyber gold, whatever action colour the user
/// picked -- Pro is its own thing, and it should look like it wherever it is
/// offered. Raised, as every action is.
class ProButton extends StatelessWidget {
  const ProButton({super.key, required this.onPressed, this.label});

  final VoidCallback? onPressed;

  /// Defaults to "Get Pro".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.proGold,
        foregroundColor: AppTheme.inkOn(AppTheme.proGold),
      ),
      onPressed: onPressed,
      child: Text(label ?? l10n.exportGetPro),
    );
    // A glint across the gold, as on the settings banner.
    return onPressed == null
        ? button
        : AppRaised(child: AppShine(child: button));
  }
}

/// The Pro offer as a line: what it is, one line of why, and the gold button.
class ProOfferRow extends StatelessWidget {
  const ProOfferRow({super.key, required this.onGetPro});

  final VoidCallback onGetPro;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.exportProName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  l10n.exportProPitch,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ProButton(onPressed: onGetPro),
        ],
      ),
    );
  }
}

/// Get Pro as one big button, the offer written on it: full width, taller than
/// an ordinary button, the pitch inside rather than beside it.
class ProBanner extends StatelessWidget {
  const ProBanner({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ink = AppTheme.inkOn(AppTheme.proGold);

    // The glint rides inside the press, so it moves with the face and never
    // crosses onto the shadow.
    return AppRaised(
      child: AppShine(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.proGold,
              foregroundColor: ink,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
            ),
            onPressed: onPressed,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.exportGetPro,
                        style: theme.textTheme.titleLarge?.copyWith(color: ink),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.exportProPitch,
                        style: theme.textTheme.bodyMedium?.copyWith(color: ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.arrow_forward, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a Pro owner sees in place of Get Pro: a quiet thank-you under a slow,
/// twinkling night sky.
class SupporterBadge extends StatefulWidget {
  const SupporterBadge({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const Color midnight = Color(0xFF141A33);
  static const Color dusk = Color(0xFF1F2750);
  static const Color champagne = Color(0xFFEBDDB3);
  static const Color lavender = Color(0xFFB9B4E8);

  @override
  State<SupporterBadge> createState() => _SupporterBadgeState();
}

class _SupporterBadgeState extends State<SupporterBadge>
    with SingleTickerProviderStateMixin {
  /// One minute of sky, looped; every star keeps its own slower beat inside it.
  late final AnimationController _sky = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sky.stop();
    } else if (!_sky.isAnimating) {
      _sky.repeat();
    }
  }

  @override
  void dispose() {
    _sky.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const ink = SupporterBadge.champagne;

    return AppRaised(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: SupporterBadge.midnight,
            foregroundColor: ink,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
          ),
          onPressed: widget.onPressed,
          child: CustomPaint(
            painter: _NightSky(_sky),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.supporterTitle,
                          style: theme.textTheme.titleLarge?.copyWith(color: ink),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          l10n.supporterDetail,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.auto_awesome, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dusk gradient and fourteen stars, each fading in and out on its own slow
/// cycle of three to six seconds.
class _NightSky extends CustomPainter {
  _NightSky(this.sky) : super(repaint: sky);

  final Animation<double> sky;

  static final List<({double x, double y, double r, double period, double phase, bool warm})>
      _stars = () {
    final random = math.Random(7);
    return [
      for (var i = 0; i < 14; i++)
        (
          x: random.nextDouble(),
          y: random.nextDouble(),
          r: 0.8 + random.nextDouble() * 1.4,
          period: 3 + random.nextDouble() * 3,
          phase: random.nextDouble() * math.pi * 2,
          warm: i.isEven,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SupporterBadge.midnight, SupporterBadge.dusk],
        ).createShader(rect),
    );

    final seconds = sky.value * 60;
    for (final star in _stars) {
      final wave = 0.5 + 0.5 * math.sin(2 * math.pi * seconds / star.period + star.phase);
      final opacity = 0.15 + 0.75 * wave;
      final color = (star.warm ? SupporterBadge.champagne : SupporterBadge.lavender)
          .withValues(alpha: opacity);
      final centre = Offset(star.x * size.width, star.y * size.height);
      canvas.drawCircle(centre, star.r, Paint()..color = color);
      // The larger stars catch a faint cross of light at their brightest.
      if (star.r > 1.6) {
        final glint = Paint()
          ..color = color.withValues(alpha: opacity * 0.5)
          ..strokeWidth = 0.8;
        final arm = star.r * 3 * wave;
        canvas
          ..drawLine(centre - Offset(arm, 0), centre + Offset(arm, 0), glint)
          ..drawLine(centre - Offset(0, arm), centre + Offset(0, arm), glint);
      }
    }
  }

  @override
  bool shouldRepaint(_NightSky oldDelegate) => false;
}
