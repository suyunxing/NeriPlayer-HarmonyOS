// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { MiniPlayerTextSizing } from '../../../main/ets/view/components/MiniPlayerTextSizing';

// 上游 NeriMiniPlayerDefaultsTest（#357）镜像 + 边界补充。
export default function miniPlayerTextSizingTest(): void {
  describe('MiniPlayerTextSizing', () => {
    it('normalFontScaleKeepsOriginalMetadataSizeRange', 0, () => {
      const range = MiniPlayerTextSizing.resolveTextAutoSizeRange(16, 24, 1, 10, 1.5);
      expect(Math.abs(range.maxFontSize - 16) < 0.001).assertTrue();
      expect(Math.abs(range.minFontSize - 10) < 0.001).assertTrue();
    });

    it('largeFontScaleReducesMaximumToTheAvailableLineHeight', 0, () => {
      const titleRange = MiniPlayerTextSizing.resolveTextAutoSizeRange(16, 24, 2, 10, 1.5);
      // 上游 artist 档的 lineHeightEm = 行高/字号（20/14）。
      const artistRange = MiniPlayerTextSizing.resolveTextAutoSizeRange(14, 20, 2, 9, 20 / 14);
      expect(Math.abs(titleRange.maxFontSize - 8) < 0.001).assertTrue();
      expect(Math.abs(titleRange.minFontSize - 5) < 0.001).assertTrue();
      expect(titleRange.maxFontSize > artistRange.maxFontSize).assertTrue();
      expect(titleRange.minFontSize <= titleRange.maxFontSize).assertTrue();
    });

    it('harmonyMiniPlayerBasesStayUntouchedAtDefaultScale', 0, () => {
      // 本移植的基础字号：标题 14、副行 11；默认缩放下封顶不生效。
      expect(Math.abs(MiniPlayerTextSizing.titleFontSize(14, 1) - 14) < 0.001).assertTrue();
      const sub = MiniPlayerTextSizing.subLineRange(11, 1);
      expect(Math.abs(sub.maxFontSize - 11) < 0.001).assertTrue();
      expect(Math.abs(sub.minFontSize - 9) < 0.001).assertTrue();
    });

    it('doubleScaleCapsMiniPlayerRows', 0, () => {
      // 2x 字体：标题 24/1.5/2 = 8，副行 20/1.5/2 ≈ 6.67，下限 9/2 = 4.5。
      expect(Math.abs(MiniPlayerTextSizing.titleFontSize(14, 2) - 8) < 0.001).assertTrue();
      const sub = MiniPlayerTextSizing.subLineRange(11, 2);
      expect(Math.abs(sub.maxFontSize - 20 / 1.5 / 2) < 0.001).assertTrue();
      expect(Math.abs(sub.minFontSize - 4.5) < 0.001).assertTrue();
      expect(sub.minFontSize <= sub.maxFontSize).assertTrue();
    });

    it('degenerateInputsClampToSafeFloor', 0, () => {
      // fontScale 0 / 负数与过小行高都不能产出 NaN 或越界值。
      const zeroScale = MiniPlayerTextSizing.resolveTextAutoSizeRange(14, 24, 0, 10, 1.5);
      expect(zeroScale.maxFontSize > 0).assertTrue();
      expect(Number.isFinite(zeroScale.maxFontSize)).assertTrue();
      expect(zeroScale.minFontSize <= zeroScale.maxFontSize).assertTrue();
      const tinyLineHeight = MiniPlayerTextSizing.resolveTextAutoSizeRange(14, 0, 1, 10, 0);
      expect(tinyLineHeight.maxFontSize >= 0.1).assertTrue();
      expect(tinyLineHeight.minFontSize >= 0.1).assertTrue();
    });

    it('minNeverExceedsMaxWhenBaseIsSmall', 0, () => {
      // 基础字号小于最小视觉字号时，下限跟随上限收缩而不是反超。
      const range = MiniPlayerTextSizing.resolveTextAutoSizeRange(6, 24, 1, 10, 1.5);
      expect(Math.abs(range.maxFontSize - 6) < 0.001).assertTrue();
      expect(Math.abs(range.minFontSize - 6) < 0.001).assertTrue();
    });
  });
}
