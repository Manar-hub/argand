import 'package:argand/core/database/database.dart';
import 'package:argand/core/monetization/monetization.dart';
import 'package:argand/core/theme/accent_color_controller.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccentColorSetting.decode', () {
    test('nothing stored is the default', () {
      expect(AccentColorSetting.decode(null), AppTheme.defaultAccent);
    });

    test('a stored colour comes back as it was saved', () {
      const teal = Color(0xFF00A3A3);
      expect(
        AccentColorSetting.decode(teal.toARGB32().toString()),
        teal,
      );
    });

    test('an unreadable value falls back rather than failing', () {
      expect(AccentColorSetting.decode('violet'), AppTheme.defaultAccent);
      expect(AccentColorSetting.decode(''), AppTheme.defaultAccent);
    });

    test('a see-through colour is made opaque', () {
      // A translucent button reads as disabled.
      expect(
        AccentColorSetting.decode(0x4000A3A3.toString()),
        const Color(0xFF00A3A3),
      );
    });
  });

  group('the action colour is Pro', () {
    const teal = Color(0xFF00A3A3);
    late AppDatabase db;
    late ProviderContainer container;

    Future<void> start({required bool pro}) async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.writeSetting('app.accentColor', teal.toARGB32().toString());
      if (pro) await db.writeSetting(proUnlockedKey, 'true');
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      container.listen(appAccentProvider, (_, _) {});
      await container.read(accentColorSettingProvider.future);
      await container.read(proUnlockedProvider.future);
    }

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('without Pro, a saved colour is not worn', () async {
      await start(pro: false);
      expect(container.read(appAccentProvider), AppTheme.defaultAccent);
    });

    test('with Pro, it is', () async {
      await start(pro: true);
      expect(container.read(appAccentProvider), teal);
    });

    test('a preview is worn until it is cleared, and never stored', () async {
      await start(pro: false);
      const red = Color(0xFFE8485A);
      container.read(accentPreviewProvider.notifier).show(red);
      expect(container.read(appAccentProvider), red);

      container.read(accentPreviewProvider.notifier).show(null);
      expect(container.read(appAccentProvider), AppTheme.defaultAccent);
      expect(await db.readSetting('app.accentColor'), '${teal.toARGB32()}');
    });
  });
}
