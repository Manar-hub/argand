import 'package:argand/core/database/database.dart';
import 'package:argand/core/fonts/custom_fonts.dart';
import 'package:argand/core/monetization/monetization.dart';
import 'package:argand/core/theme/app_shine.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:argand/core/timeline/item_look.dart';
import 'package:argand/features/transcription/font_search_dialog.dart';
import 'package:argand/l10n/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a look with a custom font', () {
    const look = ItemLook(font: LookFont.anton, customFont: 'abc.ttf');

    test('draws in the added font and survives storage', () {
      expect(look.drawFamily, customFontFamily('abc.ttf'));
      expect(look.isDefaultFont, isFalse);
      expect(ItemLook.decode(look.encode()), look);
    });

    test('choosing a built-in font clears it', () {
      final back = look.copyWith(font: LookFont.poppins);
      expect(back.customFont, isNull);
      expect(back.drawFamily, LookFont.poppins.drawFamily);
    });

    test('other changes keep it', () {
      expect(look.copyWith(shadow: 0.9).customFont, 'abc.ttf');
    });

    test('looks saved before custom fonts read as built-in', () {
      final old = ItemLook.decode('{"font":"anton"}')!;
      expect(old.customFont, isNull);
      expect(old.font, LookFont.anton);
    });
  });

  group('the stored font list', () {
    test('round-trips, skipping what it cannot read', () {
      const fonts = [CustomFont(id: 'a.ttf', name: 'Alpha')];
      final read = CustomFonts.decode(CustomFonts.encode(fonts));
      expect(read.single.id, 'a.ttf');
      expect(read.single.name, 'Alpha');
      expect(CustomFonts.decode('[{"id":1},"x"]'), isEmpty);
      expect(CustomFonts.decode('not json'), isEmpty);
    });
  });

  group('font search', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => database.close());

    Future<ItemLook Function(ItemLook)? Function()> open(
      WidgetTester tester, {
      ItemLook current = ItemLook.defaults,
    }) async {
      ItemLook Function(ItemLook)? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      result = await showFontSearch(context, current: current),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return () => result;
    }

    testWidgets('filters by name and picks a font', (tester) async {
      final result = await open(tester);

      await tester.enterText(find.byType(TextField), 'pac');
      await tester.pump();
      expect(find.text('Pacifico'), findsOneWidget);
      expect(find.text('Anton'), findsNothing);

      await tester.tap(find.text('Pacifico'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(result()!(ItemLook.defaults).font, LookFont.pacifico);
    });

    Color inkOf(WidgetTester tester) =>
        tester.widget<Text>(find.text('Add custom font')).style!.color!;

    testWidgets('adding a font is gold and glints until Pro is owned',
        (tester) async {
      await open(tester);
      expect(inkOf(tester), AppTheme.proGoldText(Brightness.light));
      expect(
        find.ancestor(
          of: find.text('Add custom font'),
          matching: find.byType(AppShine),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with Pro, adding a font is a plain row', (tester) async {
      await database.writeSetting(proUnlockedKey, 'true');
      await open(tester);
      expect(inkOf(tester), isNot(AppTheme.proGoldText(Brightness.light)));
      expect(find.byType(AppShine), findsNothing);
    });

    test('the gold text reads on paper', () {
      final gold = AppTheme.proGoldText(Brightness.light).computeLuminance();
      final paper = AppTheme.light().colorScheme.surface.computeLuminance();
      expect((paper + 0.05) / (gold + 0.05), greaterThan(4.5));
    });
  });
}
