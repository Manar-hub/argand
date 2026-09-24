import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/monetization/monetization.dart';
import '../../core/theme/app_dialog.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_surface.dart';
import '../../l10n/app_localizations.dart';

part 'placeholder_ad_screen.g.dart';

/// Where rewarded ads come from.
///
/// The placeholder until an ad SDK is chosen. Kept alive because it holds no
/// state worth rebuilding and is asked for on every export.
@Riverpod(keepAlive: true)
RewardedAds rewardedAds(Ref ref) =>
    PlaceholderRewardedAds(present: presentPlaceholderAd);

/// Shows the placeholder ad and answers whether it was watched to the end.
Future<bool> presentPlaceholderAd(BuildContext context) async {
  final watched = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const PlaceholderAdScreen(),
    ),
  );
  // Null is a back gesture, which is closing the ad early.
  return watched ?? false;
}

/// Stands where a rewarded ad will play, and behaves like one.
///
/// **Plainly a placeholder, and says so.** Nothing here imitates a real
/// advert. What it does imitate is the contract: a few seconds must pass
/// before the reward can be claimed, and closing early claims nothing. That is
/// what lets the flow around it -- the ad before the export, the export only
/// after the ad -- be tested now rather than after an ad SDK arrives.
class PlaceholderAdScreen extends StatefulWidget {
  const PlaceholderAdScreen({super.key});

  /// Long enough to read as an ad break, short enough not to punish testing.
  static const int seconds = 5;

  @override
  State<PlaceholderAdScreen> createState() => _PlaceholderAdScreenState();
}

class _PlaceholderAdScreenState extends State<PlaceholderAdScreen> {
  int _remaining = PlaceholderAdScreen.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final finished = _remaining <= 0;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.adPlaceholderLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.adPlaceholderClose,
            // Always available. A rewarded ad the user cannot leave is an ad
            // that blocks the app, which CLAUDE.md §2 rules out; leaving just
            // means no reward.
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: surface.shadowGutter,
                  child: DecoratedBox(
                    decoration: surface.decoration(
                      fill: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: finished
                          ? Icon(
                              Icons.check_circle_outline,
                              size: 72,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : Text(
                              l10n.adPlaceholderSeconds(_remaining),
                              style: theme.textTheme.displayLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.adPlaceholderBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppDialogButton(
                action: AppDialogAction(
                  label: l10n.adPlaceholderContinue,
                  emphasis: AppDialogEmphasis.primary,
                  // Disabled rather than hidden until the time is up, so the
                  // button does not appear under a thumb that was already
                  // reaching for the screen.
                  onPressed:
                      finished ? () => Navigator.of(context).pop(true) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
