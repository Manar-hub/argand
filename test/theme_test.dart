import 'package:argand/core/captions/speaker_palette.dart';
import 'package:argand/core/theme/app_surface.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parts of the theme that are checkable rather than a matter of taste.
void main() {
  final light = AppTheme.light();
  final dark = AppTheme.dark();

  group('the accent stays out of the speaker palette', () {
    test('it is none of the six speaker hues', () {
      // If the accent were also a speaker colour, a primary button and a
      // speaker chip would be the same thing on screen, and speaker-coloured
      // captions are the app's signature output (CLAUDE.md §2).
      for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
        final hue = SpeakerPalette.colorFor(speaker, fallback: Colors.black);
        expect(hue, isNot(AppTheme.defaultAccent),
            reason: 'speaker $speaker shares the accent colour');
        expect(hue, isNot(AppTheme.danger),
            reason: 'speaker $speaker shares the danger colour');
        for (final scheme in [light.colorScheme, dark.colorScheme]) {
          expect(hue, isNot(scheme.secondary),
              reason: 'speaker $speaker shares a selection colour');
        }
        expect(hue, isNot(AppTheme.highlight),
            reason: 'speaker $speaker shares the highlight colour');
      }
    });

    test('the chrome is quieter than the speakers', () {
      // Chroma, not HSL saturation.
      double chromaOf(Color c) {
        final r = c.r;
        final g = c.g;
        final b = c.b;
        final high = [r, g, b].reduce((a, v) => a > v ? a : v);
        final low = [r, g, b].reduce((a, v) => a < v ? a : v);
        return high - low;
      }

      final speakerFloor = [
        for (var i = 0; i < SpeakerPalette.length; i++)
          chromaOf(SpeakerPalette.colorFor(i, fallback: Colors.black)),
      ].reduce((a, b) => a < b ? a : b);

      for (final scheme in [light.colorScheme, dark.colorScheme]) {
        for (final chrome in [scheme.surface, scheme.onSurface]) {
          expect(chromaOf(chrome), lessThan(speakerFloor),
              reason: 'chrome $chrome carries more colour than a speaker hue');
        }
      }
    });
  });

  group('speaker colours stay legible on both grounds', () {
    /// WCAG relative-contrast ratio.
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('a speaker chip is readable against its own text colour', () {
      for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
        final fill = SpeakerPalette.colorFor(speaker, fallback: Colors.black);
        final ink = SpeakerPalette.onColorFor(speaker, fallback: Colors.black);
        // 4.5:1 is the WCAG AA threshold for body text. The label is small and
        // bold, so this is the bar that matters.
        expect(contrast(fill, ink), greaterThan(4.5),
            reason: 'speaker $speaker label is not legible on its chip');
      }
    });

    test('no speaker fill is indistinguishable from a ground', () {
      // A deliberately low bar, and the reason is worth stating rather than
      // tuning silently: this measured 1.22:1 for amber on the warm off-white
      // ground.
      for (final scheme in [light.colorScheme, dark.colorScheme]) {
        for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
          final fill = SpeakerPalette.colorFor(speaker, fallback: Colors.black);
          expect(contrast(fill, scheme.surface), greaterThan(1.05),
              reason: 'speaker $speaker is the same colour as the page');
        }
      }
    });
  });

  group('speaker colours used as text', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance() + 0.05;
      final lb = b.computeLuminance() + 0.05;
      return la > lb ? la / lb : lb / la;
    }

    test('every speaker is legible as text on its own theme', () {
      // The transcript colours its timestamps by speaker, which uses a speaker
      // colour as *text* rather than as a fill.
      for (final theme in [light, dark]) {
        for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
          final ink = SpeakerPalette.textColorFor(
            speaker,
            brightness: theme.brightness,
            fallback: Colors.black,
          );
          expect(contrast(ink, theme.colorScheme.surface),
              greaterThanOrEqualTo(4.5),
              reason: 'speaker $speaker cannot be read on this ground');
        }
      }
    });

    test('dark uses the caption fills unchanged', () {
      // Nothing to fix there: the fills already clear 7.5:1 on the near-black
      // ground, and reusing them keeps a stamp identical to the caption chip
      // beside it.
      for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
        expect(
          SpeakerPalette.textColorFor(
            speaker,
            brightness: Brightness.dark,
            fallback: Colors.black,
          ),
          SpeakerPalette.colorFor(speaker, fallback: Colors.black),
        );
      }
    });

    test('the light inks stay saturated rather than going grey', () {
      // The failure mode being guarded against is the previous attempt:
      // blending each hue toward black until it passed, which desaturates and
      // produced olive and teal. Chroma is the plain spread between channels.
      double chromaOf(Color c) {
        final hi = [c.r, c.g, c.b].reduce((a, v) => a > v ? a : v);
        final lo = [c.r, c.g, c.b].reduce((a, v) => a < v ? a : v);
        return hi - lo;
      }

      for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
        final ink = SpeakerPalette.textColorFor(
          speaker,
          brightness: Brightness.light,
          fallback: Colors.black,
        );
        expect(chromaOf(ink), greaterThan(0.45),
            reason: 'speaker $speaker has gone muddy');
      }
    });

    test('the light inks are all clearly different from each other', () {
      // Amber and orange are ten degrees apart as fills and converge on the
      // same brown when darkened, which is why the orange ink is pushed to
      // vermilion. This is what stops that regressing.
      for (var i = 0; i < SpeakerPalette.length; i++) {
        for (var j = i + 1; j < SpeakerPalette.length; j++) {
          expect(_apart(i, j, Brightness.light), greaterThan(0.4),
              reason: 'light speakers $i and $j look alike');
        }
      }
    });

    test('the dark fills are weaker, and that is recorded not fixed', () {
      // A finding, not a passing grade. The caption fills put amber at
      // `#FFD54F` and orange at `#FFB74D` -- 32 apart out of a possible 765,
      // which is nearly the same colour.
      for (var i = 0; i < SpeakerPalette.length; i++) {
        for (var j = i + 1; j < SpeakerPalette.length; j++) {
          expect(_apart(i, j, Brightness.dark), greaterThan(0.12),
              reason: 'dark speakers $i and $j are closer than amber/orange');
        }
      }
    });
  });

  group('the surface pattern', () {
    test('is registered on both themes', () {
      expect(light.extension<AppSurface>(), isNotNull);
      expect(dark.extension<AppSurface>(), isNotNull);
    });

    test('has no blur, in either theme', () {
      // Zero blur is what makes the shadow read as a printed offset layer
      // rather than as Material elevation. It is the signature of the whole
      // design, so it is pinned rather than trusted.
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        final shadow = surface
            .decoration(fill: const Color(0xFFFFFFFF), raised: true)
            .boxShadow!
            .single;

        expect(shadow.blurRadius, 0);
        expect(shadow.spreadRadius, 0);
        expect(shadow.offset.dy, greaterThan(0));
      }
    });

    test('corners are square, in both themes', () {
      // The reference style has no rounded parts; one rounded card would
      // read as a mistake.
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(surface.borderRadius, BorderRadius.zero);
        final card = theme.cardTheme.shape! as RoundedRectangleBorder;
        expect(card.borderRadius, BorderRadius.zero);
        final dialog = theme.dialogTheme.shape! as RoundedRectangleBorder;
        expect(dialog.borderRadius, BorderRadius.zero);
      }
    });

    test('flat unless asked: the shadow is for emphasis only', () {
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(
          surface.decoration(fill: const Color(0xFFFFFFFF)).boxShadow,
          isNull,
        );
      }
    });

    test('an unraised surface drops the shadow and keeps its outline', () {
      final surface = light.extension<AppSurface>()!;
      final flat = surface.decoration(
        fill: const Color(0xFFFFFFFF),
        raised: false,
      );

      // Nesting one offset shadow inside another is what makes this style read
      // as noise, so the flat variant has to actually be flat.
      expect(flat.boxShadow, isNull);
      expect(flat.border, isNotNull);
    });

    test('dark draws no outline, but keeps its room', () {
      // An off-white frame round every card, chip and button read as cheap
      // on dark. The line's width stays, see-through, so nothing moves when
      // the theme switches.
      final surface = dark.extension<AppSurface>()!;
      final paper = light.extension<AppSurface>()!;
      expect(surface.outlined, isFalse);
      expect(surface.borderWidth, paper.borderWidth);
      for (final side in [
        surface.side,
        (surface.decoration(fill: const Color(0xFFFFFFFF)).border! as Border)
            .top,
        dark.chipTheme.side!,
        (dark.cardTheme.shape! as RoundedRectangleBorder).side,
        (dark.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
            .borderSide,
      ]) {
        expect(side.color.a, 0);
        expect(side.width, paper.borderWidth);
      }
    });

    test('the outline separates a surface from its ground on paper', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      final surface = light.extension<AppSurface>()!;
      expect(surface.outlined, isTrue);
      expect(contrast(surface.outline, light.colorScheme.surface),
          greaterThan(4.5),
          reason: 'the outline does not separate a card from the page');
    });

    test('a chosen item sinks less than the shadow drops', () {
      // Sinking the full drop read as too deep.
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(surface.pressDepth, greaterThan(0));
        expect(surface.pressDepth, lessThan(surface.offset.dy));
      }
    });

    test('the shadow drops down and to the right, as the reference', () {
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(surface.offset.dx, greaterThan(0));
        expect(surface.offset.dy, greaterThan(0));
      }
    });

    test('both themes actually show their shadow', () {
      // On dark the shadow is now the only thing lifting a card off the page,
      // so it matters more there than anywhere.
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(
          surface.showsShadowOn(theme.colorScheme.surface),
          isTrue,
          reason: 'the shadow is invisible against this ground',
        );
      }
    });

    test('the outline is never quieter than the shadow, on paper', () {
      // The outline defines the card; the shadow only lifts it. If the shadow
      // ever out-contrasts the outline, the brightest thing on screen is
      // behind the content instead of around it.
      double contrast(Color a, Color b) {
        final la = a.computeLuminance() + 0.05;
        final lb = b.computeLuminance() + 0.05;
        return la > lb ? la / lb : lb / la;
      }

      final surface = light.extension<AppSurface>()!;
      final ground = light.colorScheme.surface;
      expect(
        contrast(surface.shadow, ground),
        lessThanOrEqualTo(contrast(surface.outline, ground)),
      );
    });
  });

  group("the action colour is the user's", () {
    // The same presets the settings sheet offers, and colours at the edges.
    const accents = [
      AppTheme.defaultAccent,
      Color(0xFF116DD6),
      Color(0xFF00A3A3),
      Color(0xFFFFD93D),
      Color(0xFFFF8A3D),
      Color(0xFFE8485A),
    ];

    double contrast(Color a, Color b) {
      final la = a.computeLuminance() + 0.05;
      final lb = b.computeLuminance() + 0.05;
      return la > lb ? la / lb : lb / la;
    }

    test('every call to action takes it, in both themes', () {
      for (final accent in accents) {
        for (final theme in [
          AppTheme.light(accent: accent),
          AppTheme.dark(accent: accent),
        ]) {
          expect(theme.colorScheme.primary, accent);
          expect(theme.floatingActionButtonTheme.backgroundColor, accent);
        }
      }
    });

    test('selection takes the action colour, with legible ink on it', () {
      // One colour for everything the user has chosen or can press (the
      // user's call, 2026-09-27): a selected tool, font or segment is filled
      // with the action colour, its label picked for that fill.
      for (final accent in accents) {
        for (final theme in [
          AppTheme.light(accent: accent),
          AppTheme.dark(accent: accent),
        ]) {
          expect(theme.colorScheme.secondary, accent);
          expect(theme.colorScheme.onSecondary, AppTheme.inkOn(accent));
        }
      }
    });

    test('the label on every offered action colour is legible', () {
      // Measured rather than assumed: the ink is picked per fill. 4.5:1 is
      // the WCAG AA threshold for body text.
      for (final accent in accents) {
        expect(contrast(accent, AppTheme.inkOn(accent)), greaterThan(4.5),
            reason: 'text on $accent is not legible');
      }
      for (final theme in [light, dark]) {
        final scheme = theme.colorScheme;
        expect(contrast(scheme.secondary, scheme.onSecondary), greaterThan(4.5));
      }
    });
  });

  test('both themes are built and disagree about brightness', () {
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor,
        isNot(dark.scaffoldBackgroundColor));
  });
}

/// Total channel separation between two speakers' text colours, 0 to 3.
double _apart(int a, int b, Brightness brightness) {
  Color ink(int i) => SpeakerPalette.textColorFor(
        i,
        brightness: brightness,
        fallback: Colors.black,
      );
  final x = ink(a);
  final y = ink(b);
  return (x.r - y.r).abs() + (x.g - y.g).abs() + (x.b - y.b).abs();
}
