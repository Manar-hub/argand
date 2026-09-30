import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../timeline/item_look.dart' show customFontFamily;

part 'custom_fonts.g.dart';

/// A font the user added (a Pro feature): a file in app storage, and the name
/// the picker shows for it.
class CustomFont {
  const CustomFont({required this.id, required this.name});

  /// The file's name in [customFontsDirectory]; looks refer to it by this.
  final String id;
  final String name;

  String get family => customFontFamily(id);
}

/// Font files the picker accepts.
const customFontExtensions = ['ttf', 'otf'];

/// Where added fonts are kept. The export reads them from here too.
Future<Directory> customFontsDirectory() async => Directory(
      p.join((await getApplicationSupportDirectory()).path, 'fonts'),
    );

/// The fonts the user has added, each loaded and ready to draw.
@Riverpod(keepAlive: true)
class CustomFonts extends _$CustomFonts {
  static const _key = 'fonts.custom';

  @override
  Future<List<CustomFont>> build() async {
    final stored = decode(
      await ref.watch(appDatabaseProvider).readSetting(_key),
    );
    if (stored.isEmpty) return const [];

    final dir = await customFontsDirectory();
    final loaded = <CustomFont>[];
    for (final font in stored) {
      final file = File(p.join(dir.path, font.id));
      if (!await file.exists()) continue;
      try {
        await _register(font, await file.readAsBytes());
        loaded.add(font);
      } on Object catch (error) {
        debugPrint('Custom font ${font.name} did not load: $error');
      }
    }
    return loaded;
  }

  /// Copies a picked font in, loads it and lists it. Null when the file is not
  /// a font that can be read.
  Future<CustomFont?> add({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final extension = p.extension(fileName).toLowerCase();
    if (!customFontExtensions.contains(extension.replaceFirst('.', ''))) {
      return null;
    }
    final font = CustomFont(
      id: '${const Uuid().v4()}$extension',
      name: p.basenameWithoutExtension(fileName),
    );
    try {
      await _register(font, bytes);
    } on Object catch (error) {
      debugPrint('Custom font $fileName did not load: $error');
      return null;
    }

    final dir = await customFontsDirectory();
    await dir.create(recursive: true);
    await File(p.join(dir.path, font.id)).writeAsBytes(bytes, flush: true);

    final fonts = [...state.value ?? const <CustomFont>[], font];
    state = AsyncData(fonts);
    await ref.read(appDatabaseProvider).writeSetting(_key, encode(fonts));
    return font;
  }

  static Future<void> _register(CustomFont font, Uint8List bytes) =>
      (FontLoader(font.family)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();

  static String encode(List<CustomFont> fonts) => jsonEncode([
        for (final font in fonts) {'id': font.id, 'name': font.name},
      ]);

  /// Unreadable entries are skipped rather than failing the list.
  static List<CustomFont> decode(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final entry in list)
          if (entry is Map && entry['id'] is String && entry['name'] is String)
            CustomFont(id: entry['id'] as String, name: entry['name'] as String),
      ];
    } on FormatException {
      return const [];
    }
  }
}
