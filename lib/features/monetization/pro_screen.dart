import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/monetization/monetization.dart';
import '../../core/monetization/purchases.dart';
import '../../core/theme/app_shine.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/argand_logo.dart';
import '../../l10n/app_localizations.dart';

/// Opens the Pro page -- every Get Pro button leads here.
Future<void> showProScreen(BuildContext context) =>
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => const ProScreen()),
    );

/// Argand Pro: the paywall, and once Pro is owned, the thank-you.
class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

enum _Busy { none, buying, restoring }

class _ProScreenState extends ConsumerState<ProScreen> {
  ProOffer? _offer;
  bool _loading = true;
  bool _unreachable = false;
  _Busy _busy = _Busy.none;

  /// What went wrong with the last Buy or Restore, to say under the button.
  ProPurchaseResult? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _problem = null;
      });
    }
    ProOffer? offer;
    var unreachable = false;
    try {
      offer = await ref.read(proPurchasesProvider).offer();
    } on ProStoreException {
      unreachable = true;
    }
    if (!mounted) return;
    setState(() {
      _offer = offer;
      _loading = false;
      _unreachable = unreachable;
    });
  }

  Future<void> _run(_Busy kind, Future<ProPurchaseResult> Function() action) async {
    setState(() {
      _busy = kind;
      _problem = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = _Busy.none;
      _problem = switch (result) {
        ProPurchaseResult.owned || ProPurchaseResult.cancelled => null,
        _ => result,
      };
    });
  }

  void _home() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final owned = ref.watch(proUnlockedProvider).value ?? false;
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: owned
              ? _Thanks(key: const ValueKey('thanks'), onDone: _home)
              : _paywall(context),
        ),
      ),
    );
  }

  Widget _paywall(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final purchases = ref.read(proPurchasesProvider);
    final offer = _offer;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    final String? problem = switch (_problem) {
      ProPurchaseResult.notOwned => l10n.proRestoreNone,
      ProPurchaseResult.offline => l10n.proOffline,
      ProPurchaseResult.failed => l10n.proFailed,
      _ => !_loading && offer == null
          ? (_unreachable ? l10n.proUnavailable : l10n.proNotOnSale)
          : null,
    };

    return _Page(
      key: const ValueKey('paywall'),
      top: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          TextButton(
            onPressed: _busy != _Busy.none
                ? null
                : () => _run(_Busy.restoring, purchases.restore),
            child: _busy == _Busy.restoring
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.proRestoreShort,
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: [
        _Hero(
          fill: theme.colorScheme.onSurface,
          shadow: AppTheme.proGold,
          logoInk: theme.colorScheme.surface,
          logoHand: AppTheme.proGold,
          badge: _Badge(
            text: l10n.proHeroBadge,
            fill: AppTheme.proGold,
            ink: AppTheme.inkOn(AppTheme.proGold),
          ),
        ),
        const SizedBox(height: AppSpacing.xl + AppSpacing.xs),
        Text(l10n.proHeadline, style: _headline(theme, 32)),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.proLede, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        _List(
          rows: [
            for (final (glyph, title, detail) in [
              (_Glyph.heart, l10n.proSupportTitle, l10n.proSupportDetail),
              (_Glyph.noAds, l10n.proNoAdsTitle, l10n.proNoAdsDetail),
              (
                _Glyph.noWatermark,
                l10n.proNoWatermarkTitle,
                l10n.proNoWatermarkDetail,
              ),
              (_Glyph.future, l10n.proFutureTitle, l10n.proFutureDetail),
            ])
              _BenefitRow(glyph: glyph, title: title, detail: detail),
          ],
        ),
      ],
      bottom: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              offer?.price ?? '—',
              style: _headline(theme, 44).copyWith(height: 1),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                l10n.proOnce,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            Text(
              l10n.proForGood,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (problem != null) ...[
          Text(
            problem,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _GoldButton(
          label: _loading
              ? l10n.proBuyLoading
              : offer == null
                  ? l10n.proRetry
                  : l10n.proUnlock(offer.price),
          busy: _busy == _Busy.buying,
          onPressed: _loading || _busy != _Busy.none
              ? null
              : offer == null
                  ? _load
                  : () => _run(_Busy.buying, () => purchases.buy(offer)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.proFinePrint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

TextStyle _headline(ThemeData theme, double size) =>
    (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: AppTheme.displayFamily,
      fontWeight: FontWeight.w900,
      fontSize: size,
      height: 1.05,
      letterSpacing: -0.02 * size,
      color: theme.colorScheme.onSurface,
    );

/// Shown once Pro is owned: after buying, after restoring, or on opening
/// the Pro page with Pro already bought.
class _Thanks extends StatelessWidget {
  const _Thanks({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ink = AppTheme.inkOn(AppTheme.proGold);

    return _Page(
      top: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(Icons.close),
            onPressed: onDone,
          ),
        ],
      ),
      body: [
        _Hero(
          fill: AppTheme.proGold,
          shadow: theme.colorScheme.onSurface,
          logoInk: ink,
          logoHand: theme.colorScheme.surface,
          height: 196,
          badge: _Badge(
            text: l10n.proThanksBadge,
            fill: ink,
            ink: AppTheme.proGold,
          ),
        ),
        const SizedBox(height: AppSpacing.xl + AppSpacing.sm),
        Text(l10n.proThanksTitle, style: _headline(theme, 40)),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.proThanksBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        _List(
          rows: [
            for (final text in [
              l10n.proThanksAds,
              l10n.proThanksWatermark,
              l10n.proThanksFuture,
              l10n.proThanksRestore,
            ])
              _CheckRow(text: text),
          ],
        ),
      ],
      bottom: [
        _InkButton(label: l10n.proThanksBack, onPressed: onDone),
      ],
    );
  }
}

/// A full-height page: a top bar, content, and a foot pinned to the bottom
/// when it fits and scrolling with the rest when it does not.
class _Page extends StatelessWidget {
  const _Page({
    super.key,
    required this.top,
    required this.body,
    required this.bottom,
  });

  final Widget top;
  final List<Widget> body;
  final List<Widget> bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: top,
                  ),
                  ...body,
                  const Spacer(),
                  const SizedBox(height: AppSpacing.xl),
                  ...bottom,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The block at the top: the logo on a solid fill, on a hard shadow in the
/// opposite colour, with a badge under it.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.fill,
    required this.shadow,
    required this.logoInk,
    required this.logoHand,
    required this.badge,
    this.height = 176,
  });

  final Color fill;
  final Color shadow;
  final Color logoInk;
  final Color logoHand;
  final Widget badge;
  final double height;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Padding(
      padding: surface.shadowGutter,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: fill,
          border: surface.border,
          boxShadow: [
            BoxShadow(color: shadow, offset: surface.offset * 1.5),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ArgandLogo(
              semanticLabel: AppLocalizations.of(context).appTitle,
              height: 60,
              ink: logoInk,
              hand: logoHand,
            ),
            const SizedBox(height: AppSpacing.lg),
            badge,
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.fill, required this.ink});

  final String text;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: fill, border: context.surface.border),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// Rows in one outlined box, ruled between.
class _List extends StatelessWidget {
  const _List({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final rule = surface.outlined
        ? surface.outline
        : theme.colorScheme.onSurface.withValues(alpha: 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.outlined ? null : theme.colorScheme.surfaceContainerHighest,
        border: surface.border,
      ),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) ColoredBox(color: rule, child: const SizedBox(height: 1.5, width: double.infinity)),
            row,
          ],
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.glyph,
    required this.title,
    required this.detail,
  });

  final _Glyph glyph;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _GoldSquare(
            size: 40,
            child: CustomPaint(
              size: const Size.square(22),
              painter: _GlyphPainter(glyph, AppTheme.inkOn(AppTheme.proGold)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          _GoldSquare(
            size: 28,
            child: Icon(
              Icons.check,
              size: 18,
              color: AppTheme.inkOn(AppTheme.proGold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldSquare extends StatelessWidget {
  const _GoldSquare({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.proGold,
        border: context.surface.border,
      ),
      child: child,
    );
  }
}

/// Unlock, in Pro's gold, raised on the hard shadow and glinting.
class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = AppTheme.inkOn(AppTheme.proGold);
    final button = SizedBox(
      height: 60,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.proGold,
          foregroundColor: ink,
          disabledBackgroundColor: AppTheme.proGold.withValues(alpha: 0.55),
          disabledForegroundColor: ink.withValues(alpha: 0.7),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: ink),
              )
            : Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
      ),
    );
    return onPressed == null && !busy
        ? button
        : AppRaised(child: AppShine(child: button));
  }
}

/// The thank-you's way out: a block of ink on a gold shadow.
class _InkButton extends StatelessWidget {
  const _InkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final fill = theme.colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: AppTheme.proGold, offset: surface.offset)],
      ),
      child: AppPressDown(
        travel: surface.offset,
        child: SizedBox(
          height: 60,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: theme.colorScheme.surface,
            ),
            onPressed: onPressed,
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.surface,
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Glyph { heart, noAds, noWatermark, future }

/// The benefit icons, on a 24-unit grid in the app's line: square caps, mitred
/// corners.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.ink);

  final _Glyph glyph;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.miter;
    final solid = Paint()..color = ink;

    void strike() {
      canvas.drawLine(
        const Offset(3.5, 3.5),
        const Offset(20.5, 20.5),
        Paint()
          ..color = AppTheme.proGold
          ..strokeWidth = 5.5,
      );
      canvas.drawLine(
        const Offset(3.5, 3.5),
        const Offset(20.5, 20.5),
        Paint()
          ..color = ink
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.square,
      );
    }

    switch (glyph) {
      case _Glyph.heart:
        final heart = Path()
          ..moveTo(12, 20)
          ..cubicTo(12, 20, 4, 15.2, 4, 9.6)
          ..arcToPoint(const Offset(12, 7.4), radius: const Radius.circular(4.2))
          ..arcToPoint(const Offset(20, 9.6), radius: const Radius.circular(4.2))
          ..cubicTo(20, 15.2, 12, 20, 12, 20)
          ..close();
        canvas.drawPath(heart, line);

      case _Glyph.noAds:
        // An "AD" badge, left readable, with a prohibition sign on its
        // corner -- the sign cut out of the badge by a gold ring.
        canvas.drawRect(const Rect.fromLTRB(1.5, 3.5, 18.5, 15.5), line);
        final text = TextPainter(
          text: TextSpan(
            text: 'AD',
            style: TextStyle(
              color: ink,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              fontFamily: AppTheme.displayFamily,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          Offset(9 - text.width / 2, 9.5 - text.height / 2),
        );
        const sign = Offset(17.5, 17.5);
        canvas
          ..drawCircle(sign, 6.8, Paint()..color = AppTheme.proGold)
          ..drawCircle(sign, 5, line)
          ..drawLine(
            sign + const Offset(-3.5, -3.5),
            sign + const Offset(3.5, 3.5),
            line,
          );

      case _Glyph.noWatermark:
        canvas
          ..drawRect(const Rect.fromLTRB(3, 5, 21, 19), line)
          ..drawRect(const Rect.fromLTRB(13, 13, 18, 16), solid);
        strike();

      case _Glyph.future:
        // A large four-point spark and a small one: what is still to come.
        Path spark(Offset c, double r, double waist) {
          final path = Path();
          for (var i = 0; i < 8; i++) {
            final a = i * math.pi / 4 - math.pi / 2;
            final d = i.isEven ? r : waist;
            final p = c + Offset(math.cos(a), math.sin(a)) * d;
            i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
          }
          return path..close();
        }

        canvas
          ..drawPath(spark(const Offset(10, 13), 8, 2.2), line)
          ..drawPath(spark(const Offset(19, 5), 3.5, 1), solid);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.glyph != glyph || old.ink != ink;
}
