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
/// **Drawn as part of the page, not as a card on top of it.** It takes the
/// page's own background and the same hairline the transcript separates its
/// lines with — an earlier pass gave it the card fill and the full 2pt outline
/// every raised surface uses, which made a control sitting inside a list of
/// text look like a slab dropped onto it. Nothing here is raised, so nothing
/// here gets a raised surface's weight.
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
    final rule = appHairline(theme);
    final entries = items.entries.toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: rule, width: appHairlineWidth),
        borderRadius: BorderRadius.circular(context.surface.radius),
      ),
      // Without this the selected segment's fill is a plain rectangle that
      // overruns the rounded border at the ends, so choosing Line or Speakers
      // squares off that corner. A `DecoratedBox` cannot clip, which is how it
      // was lost.
      clipBehavior: Clip.antiAlias,
      // The dividers need a height to stretch to, and the row's height comes
      // from its tallest label. One intrinsic pass on a three-item row is
      // cheap and it is what keeps the rules full-height at any text scale.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, entry) in entries.indexed) ...[
              if (index > 0)
                SizedBox(
                  width: appHairlineWidth,
                  child: ColoredBox(color: rule),
                ),
              Expanded(
                child: _Segment(
                  label: entry.value,
                  selected: entry.key == selected,
                  onTap: () => onSelected(entry.key),
                ),
              ),
            ],
          ],
        ),
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
      // The theme's own call to action: yellow on paper, blue on near-black.
      // Selection used `secondary`, which is the pair the other way round and
      // put blue on the light theme where yellow leads.
      fill: selected ? theme.colorScheme.primary : Colors.transparent,
      // No rounding here: `AppSegmentRow` clips the whole row to its own
      // corners, and a segment is a rectangular slice of it, not a card of
      // its own.
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
                // Plain weight. The transcript beside it is set for reading, and
                // a bold control next to body text claims a priority it does not
                // have.
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
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
