import 'package:argand/core/database/database.dart';
import 'package:argand/core/media/media_converter.dart';
import 'package:argand/core/text/unique_title.dart';
import 'package:argand/features/transcription/transcript_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('uniqueTitle', () {
    test('a free name is kept as typed, trimmed', () {
      expect(uniqueTitle(' Interview ', ['Talk']), 'Interview');
    });

    test('a taken name gets the first free number', () {
      expect(uniqueTitle('Interview', ['Interview']), 'Interview (1)');
      expect(
        uniqueTitle('Interview', ['Interview', 'Interview (1)']),
        'Interview (2)',
      );
      expect(
        uniqueTitle('Interview', ['Interview', 'Interview (2)']),
        'Interview (1)',
      );
    });

    test('case and spaces do not make a name different', () {
      expect(uniqueTitle('interview', ['Interview ']), 'interview (1)');
    });

    test('a copy of a copy counts on from the original', () {
      expect(
        uniqueTitle('Interview (1)', ['Interview', 'Interview (1)']),
        'Interview (2)',
      );
    });
  });

  group('projects', () {
    late AppDatabase database;
    late TranscriptRepository repository;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TranscriptRepository(database, MediaConverter());
    });

    tearDown(() => database.close());

    Future<String> titleOf(String id) async =>
        (await repository.findProject(id))!.title;

    test('a new project with a taken name is numbered', () async {
      final first = await repository.createEmptyProject(title: 'Demo');
      final second = await repository.createEmptyProject(title: 'Demo');
      expect(await titleOf(first), 'Demo');
      expect(await titleOf(second), 'Demo (1)');
    });

    test('duplicates are numbered in turn', () async {
      final source = await repository.createEmptyProject(title: 'Demo');
      final one = await repository.duplicateProject(
        projectId: source,
        title: 'Demo',
      );
      final two = await repository.duplicateProject(
        projectId: source,
        title: 'Demo',
      );
      expect(await titleOf(one), 'Demo (1)');
      expect(await titleOf(two), 'Demo (2)');
    });

    test('a rename is numbered only against other projects', () async {
      final a = await repository.createEmptyProject(title: 'Demo');
      final b = await repository.createEmptyProject(title: 'Talk');
      await repository.renameProject(a, 'Demo');
      expect(await titleOf(a), 'Demo');
      await repository.renameProject(b, 'demo');
      expect(await titleOf(b), 'demo (1)');
    });

    test('a deleted project frees its name', () async {
      final first = await repository.createEmptyProject(title: 'Demo');
      await repository.deleteProject(first);
      final again = await repository.createEmptyProject(title: 'Demo');
      expect(await titleOf(again), 'Demo');
    });
  });
}
