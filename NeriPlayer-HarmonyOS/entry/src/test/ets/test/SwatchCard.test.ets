import { describe, it, expect } from '@ohos/hypium';
import { SwatchCard } from '../../../main/ets/view/theme/SwatchCard';
import { ColorScience } from '../../../main/ets/view/theme/ColorScience';

export default function swatchCardTest(): void {
  describe('SwatchCard', () => {
    it('tableIsLoaded', 0, () => {
      expect(SwatchCard.all().length > 500).assertTrue();
    });

    it('byCodeExactLookup', 0, () => {
      const swatch = SwatchCard.byCode('1788');
      expect(swatch !== null).assertTrue();
      expect(swatch!.hex).assertEqual('#EF2B2D');
      expect(SwatchCard.byCode('does-not-exist')).assertNull();
    });

    it('nearestRedStaysRedFamily', 0, () => {
      const result = SwatchCard.nearest('#E8112D');
      expect(result !== null).assertTrue();
      const dominantLch = ColorScience.hexToLch('#E8112D')!;
      const swatchLch = SwatchCard.lchByCode(result!.swatch.code)!;
      expect(ColorScience.hueWithin(dominantLch.h, swatchLch.h, 15)).assertTrue();
      expect(result!.deltaE < 10).assertTrue();
    });

    it('nearestGraySnapsToNeutralSwatch', 0, () => {
      const result = SwatchCard.nearest('#7A7A7A');
      expect(result !== null).assertTrue();
      const lch = SwatchCard.lchByCode(result!.swatch.code)!;
      expect(lch.c < 6).assertTrue();
    });

    it('nearestMalformedIsNull', 0, () => {
      expect(SwatchCard.nearest('zzz')).assertNull();
    });

    it('lchByCodeUnknownIsNull', 0, () => {
      expect(SwatchCard.lchByCode('999999')).assertNull();
    });
  });
}
