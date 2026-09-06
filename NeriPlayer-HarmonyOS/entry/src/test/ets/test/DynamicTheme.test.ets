import { describe, it, expect } from '@ohos/hypium';
import { DynamicTheme } from '../../../main/ets/view/theme/DynamicTheme';
import { PaletteSwatch } from '../../../main/ets/view/theme/Palette';

function hexToRgb(hex: string): number[] {
  return [
    parseInt(hex.slice(1, 3), 16),
    parseInt(hex.slice(3, 5), 16),
    parseInt(hex.slice(5, 7), 16)
  ];
}

function hexLuminance(hex: string): number {
  const rgb = hexToRgb(hex);
  return (rgb[0] + rgb[1] + rgb[2]) / 765;
}

export default function dynamicThemeTest(): void {
  describe('DynamicTheme', () => {
    it('normalizesSeedHex', 0, () => {
      expect(DynamicTheme.normalizeSeedHex('#ff5722')).assertEqual('#FF5722');
      expect(DynamicTheme.normalizeSeedHex('FF5722')).assertEqual('#FF5722');
      expect(DynamicTheme.normalizeSeedHex('  #FF5722 ')).assertEqual('#FF5722');
      expect(DynamicTheme.normalizeSeedHex('#FFF')).assertNull();
      expect(DynamicTheme.normalizeSeedHex('#GGGGGG')).assertNull();
      expect(DynamicTheme.normalizeSeedHex('#1234567')).assertNull();
      expect(DynamicTheme.normalizeSeedHex('')).assertNull();
    });

    it('adjustedAccentDarkCompressesSaturationAndBlendsNeutral', 0, () => {
      // Pure red seed -> HSL(0, 1, 0.5). Dark accent: S = min(1*0.38, 0.30)
      // = 0.30, L = 0.22 -> rgb(73, 39, 39), then 22% blend toward #121212.
      expect(DynamicTheme.adjustedAccentColor('#FF0000', true)).assertEqual('#3D2222');
    });

    it('adjustedAccentLightLocksHighLuminance', 0, () => {
      // Light accent: S = min(1*0.32, 0.24) = 0.24, L = 0.90 ->
      // rgb(236, 223, 223), then 28% blend toward white.
      expect(DynamicTheme.adjustedAccentColor('#FF0000', false)).assertEqual('#F1E8E8');
    });

    it('tonePaletteKeepsSeedHue', 0, () => {
      const seed = '#FF5722';
      const seedHue = PaletteSwatch.rgbToHsl(255, 87, 34)[0];
      for (const dark of [true, false]) {
        const palette = DynamicTheme.tonePalette(seed, dark);
        const primaryRgb = hexToRgb(palette.primary);
        const hue = PaletteSwatch.rgbToHsl(primaryRgb[0], primaryRgb[1], primaryRgb[2])[0];
        const delta = Math.min(Math.abs(hue - seedHue), 360 - Math.abs(hue - seedHue));
        expect(delta < 12).assertTrue();
      }
    });

    it('tonePaletteDarkSurfacesAreDarkerThanLight', 0, () => {
      const dark = DynamicTheme.tonePalette('#3F51B5', true);
      const light = DynamicTheme.tonePalette('#3F51B5', false);
      expect(hexLuminance(dark.background) < hexLuminance(light.background)).assertTrue();
      expect(hexLuminance(dark.surface) < hexLuminance(light.surface)).assertTrue();
      expect(hexLuminance(dark.primary) > hexLuminance(dark.background)).assertTrue();
      expect(hexLuminance(light.primary) < hexLuminance(light.background)).assertTrue();
    });

    it('tonePaletteIsDeterministicAndSaturatesCapped', 0, () => {
      const first = DynamicTheme.tonePalette('#00FF00', true);
      const second = DynamicTheme.tonePalette('#00FF00', true);
      expect(first.primary).assertEqual(second.primary);
      expect(first.background).assertEqual(second.background);
      // Pure green (S=1.0) must be compressed: primary saturation < 0.7.
      const rgb = hexToRgb(first.primary);
      const hsl = PaletteSwatch.rgbToHsl(rgb[0], rgb[1], rgb[2]);
      expect(hsl[1] < 0.7).assertTrue();
    });
  });
}
