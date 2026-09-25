import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_surface.dart';

/// The hairline the transcript screen rules everything with.
///
/// One value, used by the separator between two caption lines and by the edit
/// control's own borders. They sit within a few pixels of each other on the
/// page, so any difference between them reads as a mistake rather than as a
/// distinction.
Color appHairline(ThemeData theme) =>
    theme.colorScheme.outline.withValues(alpha: 0.18);

const double appHairlineWidth = 1;

/// A full-width row of choices, divided evenly.
///
/// **Replaces a `SegmentedButton` in a horizontal scroller**, which was the
/// wrong shape twice over: Material's pill sits in the middle of the page with
/// air either side, and the scroller meant the third choice could be off
/// screen with nothing saying so. Splitting the full width gives the control a
/// fixed, obvious extent, and a fourth choice costs a narrower column rather
/// than a layout decision. Labels ellipsize instead of scrolling, so a large
/// text scale shortens a word rather than hiding a whole option.
///
/// **Tabs as in the reference**: no box round the row and no dividers
/// between choices -- the chosen one is a solid square block of ink with the
/// page's colour for its label, the rest are plain labels on the page. The
/// block is the only thing drawn, so a row of three reads as one choice made
/// rather than three boxes.
///
/// Generic over the value so the next one of these is a map literal, not a
/// second copy of this widget.
class AppSegmentRow<T> extends StatelessWidget {
  const AppSegmentRow({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = items.entries.toList();

    // The row's height comes from its tallest label; one intrinsic pass on a
    // short row keeps every block full-height at any text scale.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            Expanded(
              child: _Segment(
                label: entry.value,
                selected: entry.key == selected,
                onTap: () => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressableSurface(
      selected: selected,
      // Selection is a block of ink, never the action colour: a chosen tab
      // and a button to press are always told apart.
      fill: selected ? theme.colorScheme.secondary : Colors.transparent,
      borderRadius: BorderRadius.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // `PressableSurface` already shows the press; Material's own
          // splash/highlight would be a second, conflicting kind of feedback
          // on top of it.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                // Bold, as the reference's tabs: the block carries the choice,
                // the label only names it.
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? theme.colorScheme.onSecondary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
