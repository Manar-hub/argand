import 'package:argand/core/transcript/speaker_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decode', () {
    test('a null or blank column is simply no names', () {
      expect(SpeakerNames.decode(null).isEmpty, isTrue);
      expect(SpeakerNames.decode('').isEmpty, isTrue);
      expect(SpeakerNames.decode('   ').isEmpty, isTrue);
    });

    test('reads the stored shape', () {
      final names = SpeakerNames.decode(
        '{"0":{"name":"Ana"},"1":{"name":"Bo"}}',
      );

      expect(names[0], 'Ana');
      expect(names[1], 'Bo');
      expect(names[2], isNull);
    });

    test('never throws on a row it cannot read', () {
      // Each of these is something a corruption or a newer build could leave
      // behind. None may be allowed to take down the transcript view.
      for (final json in [
        'not json',
        '[]',
        '"a string"',
        '{"0":"Ana"}',
        '{"0":{"name":42}}',
        '{"0":{}}',
        '{"notanumber":{"name":"Ana"}}',
      ]) {
        expect(SpeakerNames.decode(json).isEmpty, isTrue, reason: json);
      }
    });

    test('keeps the good entries when one is bad', () {
      // One unreadable speaker costs one label, not the whole map.
      final names = SpeakerNames.decode(
        '{"0":{"name":"Ana"},"1":"broken","2":{"name":"Cy"}}',
      );

      expect(names[0], 'Ana');
      expect(names[1], isNull);
      expect(names[2], 'Cy');
    });

    test('ignores a name that is only whitespace', () {
      expect(SpeakerNames.decode('{"0":{"name":"   "}}').isEmpty, isTrue);
    });
  });

  group('labelFor', () {
    test('prefers the stored name and falls back to the default', () {
      final names = SpeakerNames.decode('{"1":{"name":"Ana"}}');

      expect(names.labelFor(1, defaultLabel: 'Speaker 2'), 'Ana');
      expect(names.labelFor(0, defaultLabel: 'Speaker 1'), 'Speaker 1');
    });
  });

  group('withName and encode', () {
    test('round-trips through the column', () {
      final stored = const SpeakerNames.empty()
          .withName(0, 'Ana')
          .withName(1, 'Bo')
          .encode();

      final read = SpeakerNames.decode(stored);
      expect(read[0], 'Ana');
      expect(read[1], 'Bo');
    });

    test('trims what the user typed', () {
      expect(const SpeakerNames.empty().withName(0, '  Ana  ')[0], 'Ana');
    });

    test('an empty name clears rather than storing a blank', () {
      // So a user who wipes the field gets `Speaker 1` back, not a nameless
      // chip.
      final names = const SpeakerNames.empty().withName(0, 'Ana');
      expect(names.withName(0, '')[0], isNull);
      expect(names.withName(0, '   ')[0], isNull);
      expect(names.withName(0, null)[0], isNull);
    });

    test('encodes to null when nothing is named', () {
      expect(const SpeakerNames.empty().encode(), isNull);
      // And clearing the last name returns the column to that state, rather
      // than leaving `{}` behind, which would read as "renamed, to nothing".
      expect(
        const SpeakerNames.empty().withName(0, 'Ana').withName(0, '').encode(),
        isNull,
      );
    });

    test('does not mutate the instance it was called on', () {
      final original = const SpeakerNames.empty().withName(0, 'Ana');
      original.withName(0, 'Changed');

      expect(original[0], 'Ana');
    });
  });
}
