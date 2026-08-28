import { describe, it, expect } from '@ohos/hypium';
import { LyricScrollMath } from '../../../main/ets/lyrics/LyricScrollMath';

export default function lyricScrollMathTest(): void {
  describe('LyricScrollMath', () => {
    it('buildsCumulativeTopsWithPaddingAndSpacing', 0, () => {
      const layout = LyricScrollMath.buildLayout([20, 30, 20], 10, 100, 100);
      // tops: 100, 100 + 20 + 10, 100 + 30 + 30
      expect(layout.tops.length).assertEqual(3);
      expect(layout.tops[0]).assertEqual(100);
      expect(layout.tops[1]).assertEqual(130);
      expect(layout.tops[2]).assertEqual(170);
      // content = 100 + (20+10) + (30+10) + 20 + 100
      expect(layout.contentHeight).assertEqual(290);
    });

    it('emptyListYieldsPurePadding', 0, () => {
      const layout = LyricScrollMath.buildLayout([], 10, 40, 40);
      expect(layout.tops.length).assertEqual(0);
      expect(layout.contentHeight).assertEqual(80);
    });

    it('targetScrollCentersMiddleLine', 0, () => {
      const layout = LyricScrollMath.buildLayout([40, 40, 40], 10, 200, 200);
      const viewport = 300;
      // tops 200/250/300; line 1 center = 250 + 20 = 270; scroll = 270 - 150 = 120.
      expect(LyricScrollMath.targetScroll(1, layout, viewport)).assertEqual(120);
    });

    it('targetScrollClampsAtTopAndBottom', 0, () => {
      // Content 190 < viewport 300: nothing to scroll.
      const short = LyricScrollMath.buildLayout([40, 40], 10, 100, 100);
      expect(LyricScrollMath.targetScroll(0, short, 300)).assertEqual(0);
      expect(LyricScrollMath.targetScroll(1, short, 300)).assertEqual(0);

      // Top clamp: thin padTop puts line 0's center above the viewport half,
      // so the wanted scroll is negative.
      const topHeavy = LyricScrollMath.buildLayout([40, 40, 40], 10, 50, 200);
      expect(LyricScrollMath.targetScroll(0, topHeavy, 300)).assertEqual(0);

      // Bottom clamp: thin padBottom pushes the last line past max scroll.
      // content = 150 + 120 + 20 + 10 = 300; maxScroll = 100; line 2 center
      // 270 wants 170, clamped to 100.
      const bottomHeavy = LyricScrollMath.buildLayout([40, 40, 40], 10, 150, 10);
      expect(LyricScrollMath.targetScroll(2, bottomHeavy, 200)).assertEqual(100);
    });

    it('targetScrollOfInvalidIndexIsZero', 0, () => {
      const layout = LyricScrollMath.buildLayout([40], 10, 50, 50);
      expect(LyricScrollMath.targetScroll(-1, layout, 100)).assertEqual(0);
      expect(LyricScrollMath.targetScroll(9, layout, 100)).assertEqual(0);
    });

    it('centeredIndexFindsNearestLineToViewportCenter', 0, () => {
      const layout = LyricScrollMath.buildLayout([20, 20, 20, 20], 10, 100, 100);
      const viewport = 200;
      // Line i center: 110, 140, 170, 200. Viewport center = scroll + 100.
      expect(LyricScrollMath.centeredIndex(0, layout, viewport)).assertEqual(0);
      expect(LyricScrollMath.centeredIndex(35, layout, viewport)).assertEqual(1);
      expect(LyricScrollMath.centeredIndex(70, layout, viewport)).assertEqual(2);
      expect(LyricScrollMath.centeredIndex(100, layout, viewport)).assertEqual(3);
    });

    it('centeredIndexOnEmptyLayout', 0, () => {
      const layout = LyricScrollMath.buildLayout([], 10, 0, 0);
      expect(LyricScrollMath.centeredIndex(0, layout, 100)).assertEqual(-1);
    });

    it('centeredIndexAndTargetScrollAreInverse', 0, () => {
      const layout = LyricScrollMath.buildLayout([24, 60, 24, 44, 30], 10, 150, 150);
      const viewport = 240;
      for (let index = 0; index < 5; index++) {
        const scroll = LyricScrollMath.targetScroll(index, layout, viewport);
        expect(LyricScrollMath.centeredIndex(scroll, layout, viewport)).assertEqual(index);
      }
    });
  });
}
