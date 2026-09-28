import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/monetization/purchases.dart';
import 'core/theme/accent_color_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/argand_logo.dart';
import 'core/theme/launcher_icon.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/theme/theme_reveal.dart';
import 'features/library/library_screen.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The saved look before the first frame.
  final container = ProviderContainer();
  try {
    await Future.wait([
      container.read(themeModeSettingProvider.future),
      container.read(accentColorSettingProvider.future),
    ]);
  } on Object {
    // A settings row that cannot be read is not a reason not to start: the
    // defaults stand, as they would for a first launch.
  }
  // The logo too: its SVGs decode asynchronously, so the top bar drew
  // without it for a few frames. In the cache, it is there on the first.
  await ArgandLogo.precache();

  // The launcher icon follows the action colour, as the logo's hand does.
  container.listen(accentColorSettingProvider, (_, next) {
    final accent = next.value;
    if (accent != null) LauncherIcon.matching(accent).apply();
  }, fireImmediately: true);

  // The two store SDKs, neither holding up the launch: AdMob loads the ad
  // that removes a watermark, RevenueCat reconciles Pro with the store (the
  // flag it keeps is what every Pro check reads, so Pro works offline).
  unawaited(MobileAds.instance.initialize());
  unawaited(
    container.read(proPurchasesProvider).start().catchError(
          (Object error) => debugPrint('Pro reconcile failed: $error'),
        ),
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const ArgandApp()),
  );
}

class ArgandApp extends ConsumerWidget {
  const ArgandApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loaded before `runApp` (see `main`); the fallbacks only cover a
    // settings read that failed.
    final mode = ref.watch(themeModeSettingProvider).value ?? ThemeMode.system;
    final accent =
        ref.watch(accentColorSettingProvider).value ?? AppTheme.defaultAccent;

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Both defined in one place and built together -- see AppTheme for why
      // dark cannot be an afterthought with this style.
      theme: AppTheme.light(accent: accent),
      darkTheme: AppTheme.dark(accent: accent),
      themeMode: mode,
      // Wraps the navigator, so a theme change can photograph whatever screen
      // is showing and wipe it away rather than cross-fading.
      builder: (context, child) => ThemeReveal(child: child ?? const SizedBox()),
      home: const LibraryScreen(),
    );
  }
}
