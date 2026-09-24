import 'package:argand/core/timeline/timeline_event.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryStep step(HistoryLog log, String id, int minute) =>
    (log: log, id: id, at: DateTime(2026, 1, 1, 12, minute));

void main() {
  group('TimelineEventKind', () {
    test('a code this build does not know is skipped, not thrown on', () {
      // An event written by a newer build. One unreadable row must not wedge
      // the button for good.
      expect(TimelineEventKind.fromCode('somethingLater'), isNull);
    });

    test('every kind round-trips through its code', () {
      for (final kind in TimelineEventKind.values) {
        expect(TimelineEventKind.fromCode(kind.code), kind);
      }
    });

    test('codes are stable text, not positions', () {
      // Stored as text precisely so inserting a case cannot reinterpret rows
      // already on disk. If this ever needs updating, check the migration.
      expect(TimelineEventKind.clipSplit.code, 'clipSplit');
      expect(TimelineEventKind.layerRemove.code, 'layerRemove');
    });
  });

  group('TimelineEventPayload', () {
    test('carries both ends, so undo and redo are one operation', () {
      const payload = TimelineEventPayload(
        before: {'trimEndMs': 14000},
        after: {'trimEndMs': 6000},
      );

      final decoded = TimelineEventPayload.decode(payload.encode())!;

      expect(decoded.side(forward: false), {'trimEndMs': 14000});
      expect(decoded.side(forward: true), {'trimEndMs': 6000});
    });

    test('a new action needs no schema change, only a payload shape', () {
      // The scalability claim, asserted rather than described: an arbitrary
      // shape survives the round trip because the column is just JSON.
      const invented = TimelineEventPayload(
        before: {'anything': [1, 2, 3], 'nested': {'x': true}},
        after: {'anything': <int>[], 'nested': {'x': false}},
      );

      final decoded = TimelineEventPayload.decode(invented.encode())!;

      expect(decoded.before['anything'], [1, 2, 3]);
      expect((decoded.after['nested']! as Map)['x'], false);
    });

    test('malformed JSON decodes to null rather than throwing', () {
      expect(TimelineEventPayload.decode('not json'), isNull);
      expect(TimelineEventPayload.decode('[]'), isNull);
      expect(TimelineEventPayload.decode('{"before":1,"after":2}'), isNull);
    });
  });

  group('one history across both logs', () {
    final history = mergeHistory(
      transcript: [step(HistoryLog.transcript, 'word', 0)],
      timeline: [step(HistoryLog.timeline, 'split', 1)],
    );

    test('is ordered by when things happened, not by which log', () {
      expect(history.map((s) => s.id), ['word', 'split']);
    });

    test('undo takes the most recent, whichever log it came from', () {
      // **The bug two stacks would have.** Undoing the word while the later
      // split stands builds a document from two points in time.
      expect(nextUndo(history, const {})!.id, 'split');
      expect(nextUndo(history, const {'split'})!.id, 'word');
      expect(nextUndo(history, const {'split', 'word'}), isNull);
    });

    test('redo retraces the path undo took', () {
      // Oldest undone first, so redo walks back the way it came rather than
      // jumping to the far end.
      expect(nextRedo(history, const {'split', 'word'})!.id, 'word');
      expect(nextRedo(history, const {'split'})!.id, 'split');
      expect(nextRedo(history, const {}), isNull);
    });

    test('an empty history offers nothing in either direction', () {
      expect(nextUndo(const [], const {}), isNull);
      expect(nextRedo(const [], const {}), isNull);
    });
  });
}
