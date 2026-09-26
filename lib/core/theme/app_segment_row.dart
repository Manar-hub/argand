import 'package:flutter/material.dart';

import 'app_spacing.dart';

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
/// **The block slides.** Choosing another tab moves the one block of ink
/// across to it, rather than one fading out and another fading in, so the eye
/// follows the choice from where it was to where it is.
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
    final theme = Theme.of(context);
    final entries = items.entries.toList();
    final count = entries.length;
    final index = entries.indexWhere((entry) => entry.key == selected);
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);

    return Stack(
      children: [
        // The block, behind the labels, gliding to whichever is chosen.
        if (index >= 0)
          Positioned.fill(
            child: AnimatedAlign(
              duration: motion,
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                count == 1 ? 0 : -1 + 2 * index / (count - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: ColoredBox(color: theme.colorScheme.secondary),
              ),
            ),
          ),
        Row(
          children: [
            for (final entry in entries)
              Expanded(
                child: _Segment(
                  label: entry.value,
                  selected: entry.key == selected,
                  motion: motion,
                  onTap: () => onSelected(entry.key),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.motion,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Duration motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        // The sliding block is the feedback; Material's splash on top of it
        // would be a second, conflicting kind.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Center(
            // The label's colour crosses over as the block arrives under it.
            child: AnimatedDefaultTextStyle(
              duration: motion,
              curve: Curves.easeOutCubic,
              style: theme.textTheme.labelLarge!.copyWith(
                color: selected
                    ? theme.colorScheme.onSecondary
                    : theme.colorScheme.onSurface,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
