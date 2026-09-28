import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/whisper/whisper_model_catalog.dart';
import 'package:argand/core/whisper/whisper_model_controller.dart';
import 'package:argand/core/whisper/whisper_model_info.dart';
import 'package:argand/features/settings/asset_packs_controller.dart';
import 'package:argand/features/settings/pack_screens.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = WhisperModelDescriptor(
  id: 'base',
  fileName: 'ggml-base.bin',
  source: WhisperModelSource.bundledAsset,
);
const _small = WhisperModelDescriptor(
  id: 'small-q5_1',
  fileName: 'ggml-small-q5_1.bin',
  source: WhisperModelSource.bundledAsset,
);
const _medium = WhisperModelDescriptor(
  id: 'medium',
  fileName: 'ggml-medium.bin',
  source: WhisperModelSource.bundledAsset,
);

const _info = WhisperModelInfo(
  audioLayers: 6,
  audioState: 512,
  mels: 80,
  vocabulary: 51865,
  fileType: 1,
);

class _Selected extends SelectedWhisperModel {
  @override
  Future<WhisperModelDescriptor?> build() async => _base;

  @override
  Future<void> select(WhisperModelDescriptor model) async {
    state = AsyncData(model);
  }
}

void main() {
  Widget host() => ProviderScope(
        overrides: [
          modelPacksProvider.overrideWith(
            (ref) async => const [
              ModelPackEntry(
                model: _base,
                installed: true,
                onDevice: true,
                info: _info,
              ),
              ModelPackEntry(
                model: _small,
                installed: true,
                onDevice: true,
                info: _info,
              ),
              ModelPackEntry(model: _medium, installed: false, onDevice: false),
            ],
          ),
          selectedWhisperModelProvider.overrideWith(_Selected.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ModelPacksScreen(),
        ),
      );

  testWidgets('the model in use is filled and cannot be removed',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(
      find.text('Larger models are more accurate but consume more resources.'),
      findsOneWidget,
    );
    // One delete: Small's. Base is in use, and base is built in anyway.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    final base = tester.widget<AnimatedContainer>(
      find.ancestor(of: find.text('Base'), matching: find.byType(AnimatedContainer)),
    );
    expect(
      (base.decoration as BoxDecoration?)?.color,
      AppTheme.light().colorScheme.secondary,
    );
  });

  testWidgets('tapping a ready row chooses it; the chosen one loses delete',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Small (quantized)'));
    await tester.pumpAndSettle();
    // Base is no longer in use but is built in; Small is now in use.
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('a model not on the device asks before downloading',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    expect(find.text('Download Medium?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Download Medium?'), findsNothing);
  });
}
