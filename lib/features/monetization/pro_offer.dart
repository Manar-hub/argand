import 'package:flutter/material.dart';

import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Says Pro is on its way. The purchase flow is not built (CLAUDE.md §9: no
/// price, no store SDK yet), so Get Pro answers honestly rather than doing
/// nothing.
///
/// A dialog rather than a snackbar: a snackbar raised from inside a modal
/// sheet appears on the page underneath it, behind the sheet, where nobody
/// sees it.
Future<void> showProComingSoon(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AppDialog(
      title: l10n.exportProName,
      content: Text(l10n.exportProSoon),
      actions: [
        AppDialogAction(
          label: l10n.gotItAction,
          emphasis: AppDialogEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

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
    return onPressed == null ? button : AppRaised(child: button);
  }
}

/// The Pro offer as a line: what it is, one line of why, and the gold button.
///
/// Shared by the export sheet and the settings sheet so the offer reads the
/// same in both.
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

/// Get Pro as one big button, the offer written on it: full width, taller
/// than an ordinary button, the pitch inside rather than beside it. For the
/// main settings, where it is the only thing on offer; the export sheet keeps
/// the compact [ProOfferRow] beside its own Export button.
class ProBanner extends StatelessWidget {
  const ProBanner({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ink = AppTheme.inkOn(AppTheme.proGold);

    return AppRaised(
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
    );
  }
}
