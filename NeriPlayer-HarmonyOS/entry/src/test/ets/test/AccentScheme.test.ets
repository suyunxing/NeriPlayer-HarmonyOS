import { describe, it, expect } from '@ohos/hypium';
import { AccentScheme, CoverCandidate } from '../../../main/ets/view/theme/AccentScheme';
import { ColorScience } from '../../../main/ets/view/theme/ColorScience';

function schemeAssertions(scheme: AccentScheme, dark: boolean): void {
  const mode = dark ? scheme.dark : scheme.light;
  const surface = dark ? mode.background : mode.surface;
  // UI accent ≥3:1 against its surface.
  const uiContrast = ColorScience.contrastRatio(mode.primary, surface);
  expect(uiContrast >= 3.0).assertTrue();
  // on-accent text ≥4.5:1.
  const textContrast = ColorScience.contrastRatio(mode.onPrimary, mode.primary);
  expect(textContrast >= 4.5).assertTrue();
  // Body text readable on background.
  expect(ColorScience.contrastRatio(mode.textPrimary, mode.background) >= 7.0).assertTrue();
  expect(ColorScience.contrastRatio(mode.textSecondary, mode.background) >= 4.0).assertTrue();
  // Tag pill keeps its own label readable.
  expect(ColorScience.contrastRatio(mode.tagText, mode.tagBg) >= 4.5).assertTrue();
}

export default function accentSchemeTest(): void {
  describe('AccentScheme', () => {
    it('chromaticCoverProducesSnappedSchemes', 0, () => {
      const candidates: CoverCandidate[] = [
        { hex: '#E8452B', proportion: 0.8 },
        { hex: '#202020', proportion: 0.2 }
      ];
      const scheme = AccentScheme.from(candidates);
      expect(scheme.isFallback).assertFalse();
      expect(scheme.swatchCode.length > 0).assertTrue();
      expect(scheme.dominantHex).assertEqual('#E8452B');
      schemeAssertions(scheme, false);
      schemeAssertions(scheme, true);
    });

    it('accentKeepsCoverHue', 0, () => {
      const scheme = AccentScheme.from([{ hex: '#1E88E5', proportion: 1.0 }]);
      const dominantHue = ColorScience.hexToLch('#1E88E5')!.h;
      // Accent hue comes from the snapped swatch, so allow the snap's own
      // hue shift (CIEDE2000 can trade hue for lightness/chroma); 20° keeps
      // the family identity while permitting designer-grade matches.
      const lightAccentHue = ColorScience.hexToLch(scheme.light.primary)!.h;
      const darkAccentHue = ColorScience.hexToLch(scheme.dark.primary)!.h;
      expect(ColorScience.hueWithin(dominantHue, lightAccentHue, 20)).assertTrue();
      expect(ColorScience.hueWithin(dominantHue, darkAccentHue, 20)).assertTrue();
    });

    it('skipsNearWhiteCandidateInFavorOfChromatic', 0, () => {
      const candidates: CoverCandidate[] = [
        { hex: '#F5F5F0', proportion: 0.85 },
        { hex: '#43A047', proportion: 0.15 }
      ];
      const scheme = AccentScheme.from(candidates);
      expect(scheme.dominantHex).assertEqual('#43A047');
    });

    it('grayCoverFallsBackToNeutral', 0, () => {
      const scheme = AccentScheme.from([{ hex: '#808080', proportion: 1.0 }]);
      expect(scheme.isFallback).assertTrue();
      expect(scheme.swatchCode).assertEqual('');
      // Guardrails still hold on the neutral scheme.
      schemeAssertions(scheme, false);
      schemeAssertions(scheme, true);
    });

    it('emptyInputYieldsNeutralFallback', 0, () => {
      const scheme = AccentScheme.from([]);
      expect(scheme.isFallback).assertTrue();
      schemeAssertions(scheme, false);
      schemeAssertions(scheme, true);
    });

    it('hardRedCoverStillPassesAllContrastGates', 0, () => {
      // Pure saturated red is the hardest case: max chroma, mid lightness.
      const scheme = AccentScheme.from([{ hex: '#FF0000', proportion: 1.0 }]);
      schemeAssertions(scheme, false);
      schemeAssertions(scheme, true);
    });

    it('yellowCoverDarkModeStaysReadable', 0, () => {
      // Yellow hue in dark mode would wash out; guardrails must clamp it.
      const scheme = AccentScheme.from([{ hex: '#F9E814', proportion: 1.0 }]);
      schemeAssertions(scheme, false);
      schemeAssertions(scheme, true);
    });

    it('modesTintNeutralsWithAccentHue', 0, () => {
      const scheme = AccentScheme.from([{ hex: '#1E88E5', proportion: 1.0 }]);
      const bgLch = ColorScience.hexToLch(scheme.light.background)!;
      const accentHue = ColorScience.hexToLch(scheme.light.primary)!.h;
      expect(ColorScience.hueWithin(bgLch.h, accentHue, 25)).assertTrue();
      // Background stays a quiet neutral.
      expect(bgLch.c < 6).assertTrue();
    });
  });
}
