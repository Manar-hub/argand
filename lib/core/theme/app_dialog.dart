import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_surface.dart';
import 'app_theme.dart';

/// How much weight one of a dialog's buttons carries.
///
/// Three, not a boolean, because "get on with it", "back out" and "destroy
/// something" are three different promises and the style has to make them look
/// like three different promises.
enum AppDialogEmphasis {
  /// The action the window exists to offer. Filled with the theme's accent.
  primary,

  /// Backing out, or anything with no consequence. Card fill, same outline.
  secondary,

  /// Genuine destruction, in the one red the app reserves for it.
  danger,

  /// Buying Pro, in Pro's own gold.
  pro,
}

/// One button in a dialog's action row.
class AppDialogAction {
  const AppDialogAction({
    required this.label,
    required this.onPressed,
    this.emphasis = AppDialogEmphasis.secondary,
  });

  final String label;

  /// Null disables the button, which is how a dialog says "not yet" without
  /// the control moving or disappearing.
  final VoidCallback? onPressed;

  final AppDialogEmphasis emphasis;
}

/// The app's own dialog: flat fill, solid outline, **hard offset shadow**.
///
/// `AlertDialog` cannot carry this style. Its `shape` takes an outline but no
/// shadow that is not a blur, and its actions are text-only and crowded into
/// the bottom-right — which on a neo-brutalist page reads as a Material dialog
/// that wandered in from another app. That is exactly what the first version of
/// the export windows looked like.
///
/// **Actions are full-width and stacked**, primary first. A row of small text
/// buttons pushed to one corner gives the most important control the smallest
/// target on the screen; a stack gives each one the full width of the card and
/// puts the one being offered where the thumb already is.
///
/// The shadow comes from [AppSurface] rather than from elevation. Its action
/// buttons stand on the same hard shadow, as every action in the app does;
/// a secondary choice sits flat.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final String title;
  final Widget content;
  final List<AppDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;

    return Dialog(
      // The decoration below draws the whole card, so Material's own fill and
      // elevation would only sit behind it as a second, softer rectangle.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // No shape of its own: the theme's dialog shape carries the outline,
      // and on this transparent shell it drew a second frame round the card
      // *and* its shadow gutter -- a step at the top-right corner and the
      // shadow boxed into a thick band.
      shape: const RoundedRectangleBorder(),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: Padding(
        // Room for the shadow, so it is never clipped by the dialog's own box.
        padding: surface.shadowGutter,
        child: DecoratedBox(
          decoration: surface.decoration(
            fill: theme.colorScheme.surfaceContainerHighest,
            raised: true,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                content,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.sm),
                    AppDialogButton(action: action),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A dialog button, sized and coloured by its [AppDialogAction.emphasis].
///
/// Public so a bottom sheet can use the same control: the export options sheet
/// and the windows it leads to have to look like one flow, and a sheet with a
/// differently-shaped confirm button is where that falls apart.
class AppDialogButton extends StatelessWidget {
  const AppDialogButton({super.key, required this.action});

  final AppDialogAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (fill, ink) = switch (action.emphasis) {
      AppDialogEmphasis.primary => (scheme.primary, scheme.onPrimary),
      AppDialogEmphasis.secondary => (
          scheme.surfaceContainerHighest,
          scheme.onSurface,
        ),
      AppDialogEmphasis.danger => (AppTheme.danger, Colors.white),
      AppDialogEmphasis.pro => (
          AppTheme.proGold,
          AppTheme.inkOn(AppTheme.proGold),
        ),
    };

    final button = SizedBox(
      width: double.infinity,
      child: FilledButton(
        // Only the colours are overridden: the outline and the corner radius
        // come from the theme, so every button in the app stays one shape.
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: ink,
        ),
        onPressed: action.onPressed,
        child: Text(action.label),
      ),
    );
    // An action stands on the hard shadow; a secondary choice sits flat.
    return action.emphasis == AppDialogEmphasis.secondary ||
            action.onPressed == null
        ? button
        : AppRaised(child: button);
  }
}
