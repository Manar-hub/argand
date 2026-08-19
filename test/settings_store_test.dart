import 'package:argand/core/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  group('settings store', () {
    test('returns null before anything is written', () async {
      expect(await database.readSetting('whisper.selected_model'), isNull);
    });

    test('writes then reads a value back', () async {
      await database.writeSetting('whisper.selected_model', 'small-q5_1');
      expect(await database.readSetting('whisper.selected_model'), 'small-q5_1');
    });

    test('updates in place rather than accumulating rows', () async {
      await database.writeSetting('whisper.selected_model', 'base');
      await database.writeSetting('whisper.selected_model', 'small-q5_1');

      expect(await database.readSetting('whisper.selected_model'), 'small-q5_1');
      // The unique index on `key` would reject a duplicate, so more than one
      // row here means writeSetting inserted when it should have updated.
      final rows = await database.select(database.settings).get();
      expect(rows, hasLength(1));
    });

    test('keys do not leak into each other', () async {
      await database.writeSetting('a', '1');
      await database.writeSetting('b', '2');

      expect(await database.readSetting('a'), '1');
      expect(await database.readSetting('b'), '2');
    });
  });
}
