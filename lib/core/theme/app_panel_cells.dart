import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_surface.dart';

// The cells the inline panels and toolbars are built from -- the timeline
// toolbar, the video settings panel, the style panel, the export sheet --
// shared so none of them can drift apart in look or feel.

/// A row of cells in **one** box, with a rule between neighbours -- the same
/// rule, at the same thickness, as between the library's projects.
///
/// Cells draw no frame of their own: a box round every choice made a row of
/// five look like five unrelated things. The chosen cell fills its own area
/// instead.
///
/// [expand] shares the width out evenly; off, each cell takes its own width,
/// for a strip inside a horizontal scroller. [onCard] says what the strip
/// sits on, which decides its tones on dark: there is no outline there, so
/// the cells take whichever tone the background is not, and the rules are cut
/// in the background's.
class AppStrip extends StatelessWidget {
  const AppStrip({
    super.key,
    required this.children,
    this.expand = true,
    this.onCard = false,
  });

  final List<Widget> children;
  final bool expand;
  final bool onCard;

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
              child: ColoredBox(color: rule),
            ),
          if (expand) Expanded(child: child) else child,
        ],
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(color: fill, border: surface.border),
      child: Padding(
        // Inside the outline, so a chosen cell's fill never paints over it.
        padding: EdgeInsets.all(surface.borderWidth),
        // The rules need a height to stretch to; one intrinsic pass on a
        // short row keeps them full-height at any text scale.
        child: IntrinsicHeight(child: row),
      ),
    );
  }
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
      child: PressableSurface(
        selected: selected,
        fill: selected ? theme.colorScheme.secondary : Colors.transparent,
        borderRadius: BorderRadius.zero,
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
        child: PressableSurface(
          selected: selected,
          fill: selected
              ? selectedFill ?? theme.colorScheme.secondary
              : Colors.transparent,
          borderRadius: BorderRadius.zero,
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
    );
  }
}
