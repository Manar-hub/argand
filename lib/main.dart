import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/theme/theme_reveal.dart';
import 'features/library/library_screen.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const ProviderScope(child: ArgandApp()));
}

class ArgandApp extends ConsumerWidget {
  const ArgandApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // System until the stored preference loads, which is one frame and is also
    // the correct answer if nothing was ever chosen.
    final mode = ref.watch(themeModeSettingProvider).value ?? ThemeMode.system;

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Both defined in one place and built together -- see AppTheme for why
      // dark cannot be an afterthought with this style.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      // Wraps the navigator, so a theme change can photograph whatever screen
      // is showing and wipe it away rather than cross-fading.
      builder: (context, child) => ThemeReveal(child: child ?? const SizedBox()),
      home: const LibraryScreen(),
    );
  }
}
