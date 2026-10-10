// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import {
  PlaybackControlSize,
  parsePlaybackControlSize,
  playbackControlScale,
  scaleButtonSize,
  scaleIconSize,
  resolveMainControlsLayout
} from '../../../main/ets/view/components/PlaybackControlSizing';

// 上游 PlaybackControlLayoutPreferencesTest + PlaybackControlSizingTest
// （2644267f）镜像：档位回落/缩放系数/尺寸下限/主控组适应宽度。
export default function playbackControlSizingTest(): void {
  describe('PlaybackControlSizing', () => {
    it('parseFallsBackToMediumOnInvalidValues', 0, () => {
      expect(parsePlaybackControlSize(PlaybackControlSize.SMALL))
        .assertEqual(PlaybackControlSize.SMALL);
      expect(parsePlaybackControlSize(PlaybackControlSize.MEDIUM))
        .assertEqual(PlaybackControlSize.MEDIUM);
      expect(parsePlaybackControlSize(PlaybackControlSize.LARGE))
        .assertEqual(PlaybackControlSize.LARGE);
      expect(parsePlaybackControlSize(-1)).assertEqual(PlaybackControlSize.MEDIUM);
      expect(parsePlaybackControlSize(3)).assertEqual(PlaybackControlSize.MEDIUM);
      expect(parsePlaybackControlSize(Number.NaN)).assertEqual(PlaybackControlSize.MEDIUM);
    });

    it('scalesMatchUpstreamTiers', 0, () => {
      expect(playbackControlScale(PlaybackControlSize.SMALL)).assertEqual(0.9);
      expect(playbackControlScale(PlaybackControlSize.MEDIUM)).assertEqual(1.0);
      expect(playbackControlScale(PlaybackControlSize.LARGE)).assertEqual(1.2);
    });

    it('sizeFloorsKeepTouchTargetsReadable', 0, () => {
      // 按钮 40vp 触控下限：小档缩到 36 时仍取 40；图标 18vp 下限。
      expect(scaleButtonSize(44, 0.9)).assertEqual(40);
      expect(scaleButtonSize(44, 1.0)).assertEqual(44);
      expect(scaleButtonSize(44, 1.2)).assertClose(52.8, 0.001);
      expect(scaleIconSize(20, 0.9)).assertEqual(18);
      expect(scaleIconSize(24, 0.9)).assertClose(21.6, 0.001);
      expect(scaleIconSize(24, 1.2)).assertClose(28.8, 0.001);
    });

    it('layoutKeepsRequestedSizesWhenWidthSufficient', 0, () => {
      // 鸿蒙传输行：2 次键 58 + 主键 64；360vp 宽足够，不压缩。
      const layout = resolveMainControlsLayout(360, 58, 64, 2, 0);
      expect(layout.secondaryButtonSize).assertEqual(58);
      expect(layout.primaryButtonSize).assertEqual(64);
      expect(layout.buttonScale).assertEqual(1);
      expect(layout.spacing).assertEqual(0);
    });

    it('layoutShrinksProportionallyWhenTooNarrow', 0, () => {
      // 请求 180vp 塞进 120vp：先留 2×4=8 间距，可容 112，压缩比 112/180。
      const layout = resolveMainControlsLayout(120, 58, 64, 2, 24);
      const expectedScale = 112 / 180;
      expect(layout.buttonScale).assertClose(expectedScale, 0.0001);
      expect(layout.secondaryButtonSize).assertClose(58 * expectedScale, 0.0001);
      expect(layout.primaryButtonSize).assertClose(64 * expectedScale, 0.0001);
      // 压缩后剩余空间不足时间距取最大可容纳值而非期望值。
      expect(layout.spacing <= 24).assertTrue();
      expect(layout.spacing >= 0).assertTrue();
    });

    it('layoutScalesUpstreamFiveButtonRow', 0, () => {
      // 上游原版形态：4 次键 + 1 主键（鸿蒙 1.2 大档：48×1.2=57.6×4+64×1.2
      // =76.8，请求 307.2vp）。可用 320 时留 4×4=16 间距剩 304 < 307.2，
      // 压缩比 304/307.2。
      const layout = resolveMainControlsLayout(320, 57.6, 76.8, 4, 12);
      expect(layout.buttonScale).assertClose(304 / 307.2, 0.0001);
      expect(layout.secondaryButtonSize).assertClose(57.6 * 304 / 307.2, 0.001);
    });

    it('layoutSurvivesDegenerateWidths', 0, () => {
      // 零宽/负宽：压缩到 0、间距 0，不产生 NaN 或负数。
      const zero = resolveMainControlsLayout(0, 58, 64, 2, 24);
      expect(zero.buttonScale).assertEqual(0);
      expect(zero.spacing).assertEqual(0);
      expect(Number.isFinite(zero.secondaryButtonSize)).assertTrue();
      expect(Number.isFinite(zero.primaryButtonSize)).assertTrue();
    });
  });
}
