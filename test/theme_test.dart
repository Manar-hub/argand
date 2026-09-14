import 'package:argand/core/captions/speaker_palette.dart';
import 'package:argand/core/theme/app_surface.dart';
import 'package:argand/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parts of the theme that are checkable rather than a matter of taste.
///
/// Nothing here says the design is good — that needs eyes. It says the design
/// cannot violate the two rules it is built on: the chrome never competes with
/// `SpeakerPalette`, and the shadow stays hard.
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
        expect(hue, isNot(AppTheme.accent),
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
      // **Chroma, not HSL saturation.** This test first used saturation and
      // failed the moment the ground became a warm off-white: HSL reports
      // `#FFF1E8` as fully saturated, because a near-white tint sits at the top
      // of the lightness axis where saturation stops meaning "colourful".
      // Chroma -- the plain spread between the channels -- is what actually
      // measures how much colour is present.
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
      // ground, and the answer was **not** to lighten the requirement until it
      // passed. It was to give the speaker chip an outline, which is what
      // separates it -- and which is the job an outline does in this design.
      //
      // So the fills are free to be whatever reads best as caption text over
      // video, and this only catches a fill that has become literally the page
      // colour, at which point the outline would be enclosing nothing.
      for (final scheme in [light.colorScheme, dark.colorScheme]) {
        for (var speaker = 0; speaker < SpeakerPalette.length; speaker++) {
          final fill = SpeakerPalette.colorFor(speaker, fallback: Colors.black);
          expect(contrast(fill, scheme.surface), greaterThan(1.05),
              reason: 'speaker $speaker is the same colour as the page');
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
            .decoration(fill: const Color(0xFFFFFFFF))
            .boxShadow!
            .single;

        expect(shadow.blurRadius, 0);
        expect(shadow.spreadRadius, 0);
        expect(shadow.offset.dy, greaterThan(0));
      }
    });

    test('an unraised surface keeps its border but drops the shadow', () {
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

    test('the outline separates a surface from its ground in both themes', () {
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(contrast(surface.outline, theme.colorScheme.surface),
            greaterThan(4.5),
            reason: 'the outline does not separate a card from the page');
      }
    });

    test('the shadow drops straight down, with no sideways lean', () {
      // A diagonal offset skews a full-width card -- the shadow runs off one
      // edge and not the other. Reference image 3 drops it vertically, which is
      // what keeps wide surfaces square at phone width.
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(surface.offset.dx, 0);
        expect(surface.offset.dy, greaterThan(0));
      }
    });

    test('both themes actually show their shadow', () {
      // This assertion has been round the houses. It once required a visible
      // shadow, was then relaxed to let dark keep an invisible black one on
      // the theory that a pale shadow reads as a glow, and is now back --
      // because what dark really had was light cards raised off the page and
      // dark cards sitting flat, which is two designs rather than one.
      //
      // A glow needs a blur. The zero-blur assertion above is what makes a
      // pale offset a printed layer instead, so the two rules hold together.
      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        expect(
          surface.showsShadowOn(theme.colorScheme.surface),
          isTrue,
          reason: 'the shadow is invisible against this ground',
        );
      }
    });

    test('the outline is never quieter than the shadow', () {
      // The outline defines the card; the shadow only lifts it. If the shadow
      // ever out-contrasts the outline, the brightest thing on screen is
      // behind the content instead of around it -- which is exactly what full
      // strength looked like on dark before it was pulled back to a grey.
      double contrast(Color a, Color b) {
        final la = a.computeLuminance() + 0.05;
        final lb = b.computeLuminance() + 0.05;
        return la > lb ? la / lb : lb / la;
      }

      for (final theme in [light, dark]) {
        final surface = theme.extension<AppSurface>()!;
        final ground = theme.colorScheme.surface;
        expect(
          contrast(surface.shadow, ground),
          lessThanOrEqualTo(contrast(surface.outline, ground)),
        );
      }
    });
  });

  test('selection is never the same colour as the call to action', () {
    // This replaced an assertion that selection had to be *identical* across
    // themes. The two colours now trade roles -- yellow leads on paper and
    // selects on black, the violet the other way round -- so the rule that
    // actually protects the user is that within one theme a selected control
    // can never be mistaken for the primary action.
    for (final scheme in [light.colorScheme, dark.colorScheme]) {
      expect(scheme.secondary, isNot(scheme.primary));
    }
    // And they really do swap, rather than both themes drifting to one colour.
    expect(light.colorScheme.primary, dark.colorScheme.secondary);
    expect(dark.colorScheme.primary, light.colorScheme.secondary);
  });

  test('the call-to-action fill differs by theme, on purpose', () {
    // Yellow is right on paper and a floodlight on near-black, so the two
    // swap rather than one being forced to work everywhere.
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
  });

  test('the ink on every filled accent is legible', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    // Measured rather than asserted by taste, and this is the test that caught
    // a fixed black failing at 3.4:1 on the violet. 4.5:1 is the WCAG AA
    // threshold for body text.
    for (final fill in [
      light.colorScheme.primary,
      dark.colorScheme.primary,
      light.colorScheme.secondary,
      dark.colorScheme.secondary,
    ]) {
      expect(contrast(fill, AppTheme.inkOn(fill)), greaterThan(4.5),
          reason: 'text on $fill is not legible');
    }
  });

  test('both themes are built and disagree about brightness', () {
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.scaffoldBackgroundColor,
        isNot(dark.scaffoldBackgroundColor));
  });
}
