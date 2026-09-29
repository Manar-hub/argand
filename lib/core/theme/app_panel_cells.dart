import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_surface.dart';

// The cells the inline panels and toolbars are built from -- the timeline
// toolbar, the video settings panel, the style panel, the export sheet --
// shared so none of them can drift apart in look or feel.

/// A row of cells in one box, with a rule between neighbours -- the same rule,
/// at the same thickness, as between the library's projects.
class AppStrip extends StatelessWidget {
  const AppStrip({
    super.key,
    required this.children,
    this.expand = true,
    this.onCard = false,
    this.edgeToEdge = false,
    this.bare = false,
    this.bottomOpening,
    this.flex,
    this.tees = true,
  });

  /// Whether the rules between cells end in a crossbar at the frame's line.
  /// Off for colour swatches, where a bar over a chosen colour's edge reads
  /// as a mark on the colour rather than as the frame.
  final bool tees;

  /// Leaves the bottom line open between these two points (from the strip's
  /// left), where a link from below meets it.
  final (double, double)? bottomOpening;

  /// Draws no box of its own -- only the rules between cells -- for a strip
  /// that fills an [AppLinkedPanel]'s frame, which is its box.
  final bool bare;

  final List<Widget> children;

  /// With [expand], each cell's share of the width -- a text cell beside a
  /// run of colour swatches needs more than one swatch's worth. Even when
  /// null.
  final List<int>? flex;
  final bool expand;
  final bool onCard;

  /// Runs the full width of the screen: lines above and below only, none at
  /// the ends, so the first and last cells -- and their chosen and pressed
  /// fills -- reach the screen's edges. The timeline toolbar.
  final bool edgeToEdge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final page = theme.colorScheme.surface;
    final card = theme.colorScheme.surfaceContainerHighest;

    final fill = surface.outlined ? card : (onCard ? page : card);
    final rule = appRuleColor(context, onCard: onCard);

    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            SizedBox(
              width: appRuleWidth(context),
              child: CustomPaint(
                painter: _RulePainter(
                  color: rule,
                  // On paper the rule runs on through the strip's edge line and
                  // ends in a short crossbar there -- lost in the line where
                  // the line is drawn, a T where a link leaves it open.
                  bar: surface.outlined && tees ? surface.borderWidth : 0,
                ),
              ),
            ),
          if (expand)
            Expanded(flex: flex?[index] ?? 1, child: child)
          else
            child,
        ],
      ],
    );

    final side = surface.side;
    final opening = bottomOpening;
    final framedByPainter = opening != null && surface.outlined && !bare;
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: !surface.outlined || bare || framedByPainter
            ? null
            : Border(
                top: side,
                bottom: side,
                left: edgeToEdge ? BorderSide.none : side,
                right: edgeToEdge ? BorderSide.none : side,
              ),
      ),
      child: Padding(
        // Inside the outline, so a chosen cell's fill never paints over it.
        padding: bare
            ? EdgeInsets.symmetric(vertical: surface.borderWidth)
            : EdgeInsets.fromLTRB(
                edgeToEdge ? 0 : surface.borderWidth,
                surface.borderWidth,
                edgeToEdge ? 0 : surface.borderWidth,
                surface.borderWidth,
              ),
        // The rules need a height to stretch to; one intrinsic pass on a
        // short row keeps them full-height at any text scale.
        child: IntrinsicHeight(child: row),
      ),
    );
    if (!framedByPainter) return box;
    return CustomPaint(
      foregroundPainter: AppOpenFramePainter(
        edges: (_) => opening,
        repaintKey: opening,
        openTop: false,
        line: surface.outline,
        width: surface.borderWidth,
      ),
      child: box,
    );
  }
}

/// A row of items with the chosen item's options beside it, linked like a
/// folder tab.
class AppLinkedPanel extends StatelessWidget {
  const AppLinkedPanel({
    super.key,
    required this.items,
    required this.selected,
    required this.child,
    this.gap = 12,
    this.upward = false,
    this.itemsOpening,
  });

  /// The cells of the items row.
  final List<Widget> items;

  /// Which of [items] is open.
  final int selected;

  final Widget child;

  /// The space between the items and the rectangle, which the lines cross.
  final double gap;

  final bool upward;

  final (double, double)? itemsOpening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    final count = items.length;
    final rule = appRuleWidth(context);
    final line = surface.outlined ? surface.outline : null;
    final tone = theme.colorScheme.surfaceContainerHighest;

    final strip = AppStrip(bottomOpening: itemsOpening, children: items);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected.toDouble()),
      duration: motion,
      curve: Curves.easeOutCubic,
      child: DecoratedBox(
        // Filled, so nothing the panel floats over shows through the
        // opening: the page's colour on paper, the card's tone on dark,
        // where the tone is the rectangle's only edge.
        decoration: BoxDecoration(
          color: line == null ? tone : theme.colorScheme.surface,
        ),
        child: Padding(
          // Sides only: a row inside owns the top and bottom bands the
          // frame's line runs along (see `AppStrip.bare`).
          padding: EdgeInsets.symmetric(horizontal: surface.borderWidth),
          child: child,
        ),
      ),
      builder: (context, at, framed) {
        (double, double) edges(double width) => appLinkEdgesAt(
              width: width,
              count: count,
              at: at,
              border: surface.borderWidth,
              rule: rule,
            );
        final channel = AppLinkChannel(
          height: gap,
          edges: edges,
          repaintKey: at,
        );
        final rectangle = CustomPaint(
          foregroundPainter: line == null
              ? null
              : AppOpenFramePainter(
                  edges: edges,
                  repaintKey: at,
                  openTop: !upward,
                  line: line,
                  width: surface.borderWidth,
                ),
          child: framed,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: upward
              ? [rectangle, channel, strip]
              : [strip, channel, rectangle],
        );
      },
    );
  }
}

/// Where cell [index] of a row of [count] cells has its two edges, across a row
/// [width] wide: the centres of the lines either side of it, as [AppStrip] lays
/// its cells out -- its outer line at the ends ([border]).
(double, double) appLinkEdges({
  required double width,
  required int count,
  required int index,
  required double border,
  required double rule,
}) {
  final cell = (width - 2 * border - (count - 1) * rule) / count;
  final start = border + index * (cell + rule);
  final left = index == 0 ? border / 2 : start - rule / 2;
  final right =
      index == count - 1 ? width - border / 2 : start + cell + rule / 2;
  return (left, right);
}

/// [appLinkEdges] at a fractional index, between two cells while the link
/// glides from one to the next.
(double, double) appLinkEdgesAt({
  required double width,
  required int count,
  required double at,
  required double border,
  required double rule,
}) {
  final from = at.floor().clamp(0, count - 1);
  final to = at.ceil().clamp(0, count - 1);
  final t = at - at.floor();
  final a = appLinkEdges(
    width: width,
    count: count,
    index: from,
    border: border,
    rule: rule,
  );
  final b = appLinkEdges(
    width: width,
    count: count,
    index: to,
    border: border,
    rule: rule,
  );
  return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
}

/// The gap a link crosses: two lines at [edges] -- or, on dark, the channel
/// between them filled with the card's tone -- on the page's colour, so
/// nothing behind shows through.
class AppLinkChannel extends StatelessWidget {
  const AppLinkChannel({
    super.key,
    required this.height,
    required this.edges,
    required this.repaintKey,
  });

  final double height;

  /// Where the two lines fall, given the channel's width.
  final (double, double) Function(double width) edges;

  /// Changes whenever [edges] would answer differently.
  final Object repaintKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    return Container(
      height: height,
      color: theme.colorScheme.surface,
      child: CustomPaint(
        painter: _ChannelPainter(
          edges: edges,
          repaintKey: repaintKey,
          line: surface.outlined ? surface.outline : null,
          width: surface.borderWidth,
          tone: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class _ChannelPainter extends CustomPainter {
  _ChannelPainter({
    required this.edges,
    required this.repaintKey,
    required this.line,
    required this.width,
    required this.tone,
  });

  final (double, double) Function(double width) edges;
  final Object repaintKey;
  final Color? line;
  final double width;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final (left, right) = edges(size.width);
    if (line == null) {
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = tone,
      );
      return;
    }
    final paint = Paint()
      ..color = line!
      ..strokeWidth = width;
    canvas.drawLine(Offset(left, 0), Offset(left, size.height), paint);
    canvas.drawLine(Offset(right, 0), Offset(right, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _ChannelPainter old) =>
      old.repaintKey != repaintKey || old.line != line || old.tone != tone;
}

/// A rectangle's outline with one edge -- the top when [openTop], else the
/// bottom -- open between the two points [edges] gives, where a link's lines
/// meet it.
class AppOpenFramePainter extends CustomPainter {
  AppOpenFramePainter({
    required this.edges,
    required this.repaintKey,
    required this.openTop,
    required this.line,
    required this.width,
  });

  final (double, double) Function(double width) edges;
  final Object repaintKey;
  final bool openTop;
  final Color line;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final (left, right) = edges(size.width);
    final half = width / 2;
    final paint = Paint()
      ..color = line
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final near = openTop ? half : size.height - half;
    final far = openTop ? size.height - half : half;
    // From the first link line out round the rectangle and back along the
    // open edge to the second: everything but the opening.
    final path = Path()
      ..moveTo(left, near)
      ..lineTo(half, near)
      ..lineTo(half, far)
      ..lineTo(size.width - half, far)
      ..lineTo(size.width - half, near)
      ..lineTo(right, near);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant AppOpenFramePainter old) =>
      old.repaintKey != repaintKey ||
      old.line != line ||
      old.openTop != openTop;
}

/// A rule between two cells, and -- when [bar] is set -- its ends carried out
/// through the strip's edge line, each finished with a short crossbar as thick
/// as that line.
class _RulePainter extends CustomPainter {
  _RulePainter({required this.color, required this.bar});

  final Color color;

  /// The edge line's thickness, or 0 for a plain rule.
  final double bar;

  static const double _barHalf = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (bar == 0) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }
    canvas.drawRect(
      Rect.fromLTRB(0, -bar, size.width, size.height + bar),
      paint,
    );
    final centre = size.width / 2;
    canvas.drawRect(
      Rect.fromLTRB(centre - _barHalf, -bar, centre + _barHalf, 0),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        centre - _barHalf,
        size.height,
        centre + _barHalf,
        size.height + bar,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RulePainter old) =>
      old.color != color || old.bar != bar;
}

/// A horizontal scroller that clips only at its sides, so a strip inside it
/// can still draw on the edge line just above and below it (its rules' bars).
class AppSideClippedScroller extends StatelessWidget {
  const AppSideClippedScroller({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      clipper: const AppSideClipper(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: child,
      ),
    );
  }
}

/// Clips at the sides only, letting [bleed] through above and below -- for a
/// strip's rules to reach an edge line just outside the clipped box.
class AppSideClipper extends CustomClipper<Rect> {
  const AppSideClipper({this.bleed = 8});

  final double bleed;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -bleed, size.width, size.height + bleed);

  @override
  bool shouldReclip(covariant AppSideClipper old) => old.bleed != bleed;
}

/// The thickness of the rule between two rows or cells: a hairline of ink on
/// paper, a slightly wider cut on dark so the gap reads.
double appRuleWidth(BuildContext context) =>
    context.surface.outlined ? 1 : 2;

/// The rule's colour: the outline's ink on paper; on dark, which draws no
/// light lines, a cut in the colour of whatever is behind.
Color appRuleColor(BuildContext context, {bool onCard = false}) {
  final surface = context.surface;
  final scheme = Theme.of(context).colorScheme;
  if (surface.outlined) return surface.outline;
  return onCard ? scheme.surfaceContainerHighest : scheme.surface;
}

/// One of a panel's items, in the bottom toolbar's own style: icon over
/// label, a block of ink when selected. Meant to sit in an [AppStrip].
class AppPanelItem extends StatelessWidget {
  const AppPanelItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink =
        selected ? theme.colorScheme.onSecondary : theme.colorScheme.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      child: AppSelectedBleed(
        selected: selected,
        color: theme.colorScheme.secondary,
        // A flat fill in the action colour, eased in: a choice, not a press.
        child: AnimatedContainer(
          duration: _fillMotion(context),
          curve: Curves.easeOut,
          color: selected ? theme.colorScheme.secondary : Colors.transparent,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: ink, size: 22),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(color: ink),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice inside an item's options, a block of ink when chosen. Meant to
/// sit in an [AppStrip], which draws the box and the rules.
class AppChoice extends StatelessWidget {
  const AppChoice({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.selectedFill,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.sm,
    ),
  });

  final bool selected;

  /// Null when the choice is not available, which greys it out.
  final VoidCallback? onTap;

  final Widget child;

  /// What a chosen cell fills with; the selection ink by default.
  final Color? selectedFill;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final ink =
        selected ? theme.colorScheme.onSecondary : theme.colorScheme.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.38,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        child: AppSelectedBleed(
          selected: selected,
          color: selectedFill ?? theme.colorScheme.secondary,
          child: AnimatedContainer(
            duration: _fillMotion(context),
            curve: Curves.easeOut,
            color: selected
                ? selectedFill ?? theme.colorScheme.secondary
                : Colors.transparent,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: onTap,
                child: Padding(
                  padding: padding,
                  child: Center(
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.labelMedium?.copyWith(color: ink),
                      child: IconTheme.merge(
                        data: IconThemeData(color: ink),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chosen cell's fill carried out over the frame's line above and below it --
/// the band the row owns for that line -- so the choice fills the whole frame
/// rather than stopping short of it.
class AppSelectedBleed extends StatelessWidget {
  const AppSelectedBleed({
    super.key,
    required this.selected,
    required this.color,
    required this.child,
  });

  final bool selected;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final bleed = surface.outlined ? surface.borderWidth : 0.0;
    if (!selected || bleed == 0) return child;
    return CustomPaint(
      painter: _BleedPainter(color: color, bleed: bleed),
      child: child,
    );
  }
}

class _BleedPainter extends CustomPainter {
  _BleedPainter({required this.color, required this.bleed});

  final Color color;
  final double bleed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTRB(0, -bleed, size.width, size.height + bleed),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BleedPainter old) =>
      old.color != color || old.bleed != bleed;
}

/// How fast a chosen cell fills: quick, and instant without animations.
Duration _fillMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
