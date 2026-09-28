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
