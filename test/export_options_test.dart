import 'package:argand/core/monetization/monetization.dart';
import 'package:argand/core/video/export_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExportOptions.encode', () {
    test('sends the ratio the way Presentation wants it: width over height',
        () {
      expect(
        const ExportOptions(aspect: ExportAspect.portrait9x16).encode(),
        containsPair('aspectRatio', closeTo(0.5625, 0.0001)),
      );
      expect(
        const ExportOptions(aspect: ExportAspect.landscape16x9).encode(),
        containsPair('aspectRatio', closeTo(1.7778, 0.0001)),
      );
      expect(
        const ExportOptions(aspect: ExportAspect.portrait4x5).encode(),
        containsPair('aspectRatio', closeTo(0.8, 0.0001)),
      );
      expect(
        const ExportOptions(aspect: ExportAspect.square1x1).encode(),
        containsPair('aspectRatio', 1.0),
      );
    });

    test('source is a null, sent rather than omitted', () {
      const options = ExportOptions(
        aspect: ExportAspect.source,
        quality: ExportQuality.source,
      );

      final encoded = options.encode();

      expect(encoded.containsKey('aspectRatio'), isTrue);
      expect(encoded['aspectRatio'], isNull);
      expect(encoded.containsKey('shortEdge'), isTrue);
      expect(encoded['shortEdge'], isNull);
    });

    test('is branded unless a waiver was earned', () {
      // No waiver, no way to ask for an unbranded render: the flag the channel
      // reads is derived, not set.
      expect(
        ExportOptions.defaults.encode(),
        containsPair('watermark', true),
      );
      expect(
        ExportOptions.defaults
            .withWaiver(const WatermarkWaiver.forTesting())
            .encode(),
        containsPair('watermark', false),
      );
    });

    test('changing the framing drops the waiver', () {
      // One ad pays for the export the user was looking at, not for whatever
      // they choose after it.
      final waived = ExportOptions.defaults
          .withWaiver(const WatermarkWaiver.forTesting());

      expect(waived.copyWith(aspect: ExportAspect.square1x1).watermark, isTrue);
    });
  });

  group('ExportQuality against the footage', () {
    test('offers nothing larger than the source', () {
      final offered = ExportQuality.values
          .where((quality) => quality.availableFor(1080))
          .toList();

      expect(offered, [
        ExportQuality.p720,
        ExportQuality.p1080,
        ExportQuality.source,
      ]);
    });

    test('a 4K source can have every size', () {
      expect(
        ExportQuality.values.every((quality) => quality.availableFor(2160)),
        isTrue,
      );
    });

    test('an unknown source is assumed 1080p, never offered 4K', () {
      expect(ExportQuality.p1080.availableFor(null), isTrue);
      expect(ExportQuality.p1440.availableFor(null), isFalse);
    });

    test('a stored 4K on a 1080p clip renders at 1080p', () {
      expect(ExportQuality.p2160.fitTo(1080), ExportQuality.p1080);
      expect(ExportQuality.p1440.fitTo(1200), ExportQuality.p1080);
    });

    test('a clip smaller than every preset keeps its own size', () {
      expect(ExportQuality.p720.fitTo(480), ExportQuality.source);
    });

    test('a size the clip can fill is left alone', () {
      expect(ExportQuality.p720.fitTo(2160), ExportQuality.p720);
    });
  });

  group('exportFrameFor', () {
    test('1080p keeps a landscape source landscape', () {
      expect(
        exportFrameFor(
          options: const ExportOptions(quality: ExportQuality.p1080),
          sourceWidth: 3840,
          sourceHeight: 2160,
        ),
        (width: 1920, height: 1080),
      );
    });

    test('never promises a frame larger than the source', () {
      // The render will not upscale, even when asked; see availableFor.
      expect(
        exportFrameFor(
          options: const ExportOptions(quality: ExportQuality.p1080),
          sourceWidth: 1280,
          sourceHeight: 720,
        ),
        (width: 1280, height: 720),
      );
    });

    test('quality names the short edge, so 720p portrait is 720 across', () {
      // The reason short edge rather than height: a person choosing 720p for a
      // reel wants 720x1280, not a 405-pixel-wide sliver.
      expect(
        exportFrameFor(
          options: const ExportOptions(
            quality: ExportQuality.p720,
            aspect: ExportAspect.portrait9x16,
          ),
          sourceWidth: 1920,
          sourceHeight: 1080,
        ),
        (width: 720, height: 1280),
      );
    });

    test('square is square whatever it came from', () {
      expect(
        exportFrameFor(
          options: const ExportOptions(
            quality: ExportQuality.p1080,
            aspect: ExportAspect.square1x1,
          ),
          sourceWidth: 1920,
          sourceHeight: 1080,
        ),
        (width: 1080, height: 1080),
      );
    });

    test('source quality keeps the source short edge', () {
      expect(
        exportFrameFor(
          options: const ExportOptions(quality: ExportQuality.source),
          sourceWidth: 1440,
          sourceHeight: 1080,
        ),
        (width: 1440, height: 1080),
      );
    });

    test('never returns an odd dimension, which H.264 rejects', () {
      final frame = exportFrameFor(
        options: const ExportOptions(
          quality: ExportQuality.p720,
          aspect: ExportAspect.portrait4x5,
        ),
        sourceWidth: 1920,
        sourceHeight: 1080,
      )!;

      expect(frame.width.isEven, isTrue);
      expect(frame.height.isEven, isTrue);
    });

    test('declines to promise a frame it cannot work out', () {
      expect(
        exportFrameFor(
          options: ExportOptions.defaults,
          sourceWidth: 0,
          sourceHeight: 0,
        ),
        isNull,
      );
    });
  });

  group('mediaRatioFromThumbnail', () {
    // The native side writes thumbnails 160 wide and truncates the height.
    test('recognises 9:16 despite the truncated height', () {
      // 1080x1920 scaled to 160 wide is 284.44 tall, stored as 284. Read
      // naively that is 0.5634, which promised a 720x1278 render that came
      // out 720x1280.
      final shape = mediaRatioFromThumbnail(160, 284);

      expect(shape.exact, isTrue);
      expect(shape.ratio, 9 / 16);
      // Through the same call the sheet's label makes, so a rounding step
      // added between the two is caught here rather than on a device.
      expect(
        exportFrameForShape(
          options: const ExportOptions(quality: ExportQuality.p720),
          sourceRatio: shape.ratio,
        ),
        (width: 720, height: 1280),
      );
    });

    test('recognises 16:9 and square, where nothing was truncated', () {
      expect(mediaRatioFromThumbnail(160, 90).ratio, 16 / 9);
      expect(mediaRatioFromThumbnail(160, 160).ratio, 1);
    });

    test('admits it does not know an unusual shape exactly', () {
      // 160 x 137 matches no standard ratio within the truncation window.
      final shape = mediaRatioFromThumbnail(160, 137);

      expect(shape.exact, isFalse);
      expect(shape.ratio, closeTo(160 / 137, 0.0001));
    });
  });
}
