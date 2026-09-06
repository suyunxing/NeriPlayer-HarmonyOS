import { describe, it, expect } from '@ohos/hypium';
import { ColorScience, Lab } from '../../../main/ets/view/theme/ColorScience';

export default function colorScienceTest(): void {
  describe('ColorScience', () => {
    it('parsesSixDigitHex', 0, () => {
      const rgb = ColorScience.parseHex('#E8452B');
      expect(rgb !== null).assertTrue();
      expect(rgb![0]).assertEqual(232);
      expect(rgb![1]).assertEqual(69);
      expect(rgb![2]).assertEqual(43);
    });

    it('parsesEightDigitHexDroppingAlpha', 0, () => {
      const rgb = ColorScience.parseHex('#80E8452B');
      expect(rgb !== null).assertTrue();
      expect(rgb![0]).assertEqual(232);
    });

    it('rejectsMalformedHex', 0, () => {
      expect(ColorScience.parseHex('nope')).assertNull();
      expect(ColorScience.parseHex('#12345')).assertNull();
    });

    it('redLabMatchesReference', 0, () => {
      // #FF0000 → L*53.24 a*80.09 b*67.20 (published sRGB→Lab reference).
      const lab = ColorScience.hexToLab('#FF0000')!;
      expect(Math.abs(lab.l - 53.24) < 0.05).assertTrue();
      expect(Math.abs(lab.a - 80.09) < 0.05).assertTrue();
      expect(Math.abs(lab.b - 67.20) < 0.05).assertTrue();
    });

    it('labHexRoundTrip', 0, () => {
      // Round trip goes through 8-bit sRGB quantization, so compare channel
      // integers with ±1 tolerance instead of raw Lab floats.
      const samples: string[] = ['#000000', '#FFFFFF', '#E8452B', '#1E88E5', '#7C4DFF', '#12B76A'];
      for (const hex of samples) {
        const back = ColorScience.labToHex(ColorScience.hexToLab(hex)!);
        const orig = ColorScience.parseHex(hex)!;
        const got = ColorScience.parseHex(back)!;
        expect(Math.abs(orig[0] - got[0]) <= 1).assertTrue();
        expect(Math.abs(orig[1] - got[1]) <= 1).assertTrue();
        expect(Math.abs(orig[2] - got[2]) <= 1).assertTrue();
      }
    });

    it('deltaE2000MatchesSharmaReferencePair1', 0, () => {
      // Sharma et al. 2005 dataset pair 1: expected ΔE00 = 2.0425.
      const d = ColorScience.deltaE2000(new Lab(50.0000, 2.6772, -79.7751), new Lab(50.0000, 0.0000, -82.7485));
      expect(Math.abs(d - 2.0425) < 0.0005).assertTrue();
    });

    it('deltaE2000MatchesSharmaReferencePair4', 0, () => {
      // Pair 4: expected ΔE00 = 1.0000.
      const d = ColorScience.deltaE2000(new Lab(50.0000, -1.3802, -84.2814), new Lab(50.0000, 0.0000, -82.7485));
      expect(Math.abs(d - 1.0000) < 0.0005).assertTrue();
    });

    it('deltaE2000MatchesSharmaReferencePair17', 0, () => {
      // Pair 17: expected ΔE00 = 27.1492.
      const d = ColorScience.deltaE2000(new Lab(50.0000, 2.5000, 0.0000), new Lab(73.0000, 25.0000, -18.0000));
      expect(Math.abs(d - 27.1492) < 0.0005).assertTrue();
    });

    it('deltaE2000IsSymmetricAndZeroForIdentical', 0, () => {
      const a = new Lab(42.5, 20.1, -30.2);
      const b = new Lab(61.0, -8.4, 44.9);
      const ab = ColorScience.deltaE2000(a, b);
      const ba = ColorScience.deltaE2000(b, a);
      expect(Math.abs(ab - ba) < 1e-9).assertTrue();
      expect(ColorScience.deltaE2000(a, a)).assertEqual(0);
    });

    it('contrastRatioExtremesAndGrayThreshold', 0, () => {
      expect(Math.abs(ColorScience.contrastRatio('#FFFFFF', '#000000') - 21.0) < 0.01).assertTrue();
      // #767676 is the canonical 4.5:1 gray against white.
      expect(Math.abs(ColorScience.contrastRatio('#767676', '#FFFFFF') - 4.54) < 0.02).assertTrue();
    });

    it('hueWithinHandlesWraparound', 0, () => {
      expect(ColorScience.hueWithin(359, 1, 5)).assertTrue();
      expect(ColorScience.hueWithin(350, 10, 5)).assertFalse();
    });

    it('lchRoundTripPreservesHueAtWraparound', 0, () => {
      const hex = '#E8452B';
      const lch = ColorScience.hexToLch(hex)!;
      const back = ColorScience.lchToHex(lch);
      const lchBack = ColorScience.hexToLch(back)!;
      expect(Math.abs(lch.h - lchBack.h) < 1.0).assertTrue();
      expect(Math.abs(lch.c - lchBack.c) < 1.0).assertTrue();
    });
  });
}
