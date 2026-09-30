import { describe, it, expect } from '@ohos/hypium';
import { NowPlayingMotion, NowPlayingRect } from '../../../main/ets/view/NowPlayingMotion';

const MINI: NowPlayingRect = { x: 27, y: 611, width: 323, height: 40 };

// 几何由原生属性动画驱动（NowPlayingCurves），本模型只算端点：amount 恒为 0/1，
// 行错峰由 NowPlayingPage.rowDelay 的 delay 承担。
export default function nowPlayingMotionTest(): void {
  describe('NowPlayingMotion', () => {
    it('panelLerpEndpointsAndMidpoint', 0, () => {
      const start = NowPlayingMotion.panel(0, MINI, 360, 800);
      expect(start.x).assertEqual(27);
      expect(start.y).assertEqual(611);
      expect(start.width).assertEqual(323);
      expect(start.height).assertEqual(40);

      const end = NowPlayingMotion.panel(1, MINI, 360, 800);
      expect(end.x).assertEqual(0);
      expect(end.y).assertEqual(0);
      expect(end.width).assertEqual(360);
      expect(end.height).assertEqual(800);

      const mid = NowPlayingMotion.panel(0.5, MINI, 360, 800);
      expect(mid.y).assertEqual(305.5);
      expect(mid.height).assertEqual(420);
    });

    it('rowsEvaluateTogetherAtEndpoints', 0, () => {
      // 收起端：所有行隐藏在 48vp 下方、完全透明。
      for (let row = 0; row <= 5; row++) {
        expect(NowPlayingMotion.rowOffset(0, row)).assertEqual(48);
        expect(NowPlayingMotion.rowOpacity(0, row)).assertEqual(0);
      }
      // 展开端：所有行回到原位、不透明（错峰只由 delay 决定）。
      for (let row = 0; row <= 5; row++) {
        expect(NowPlayingMotion.rowOffset(1, row)).assertEqual(0);
        expect(NowPlayingMotion.rowOpacity(1, row)).assertEqual(1);
      }
    });

    it('rowDomainKeepsInteriorAmountsHidden', 0, () => {
      // 端点语义之外的防御：半程量不产生「半行」中间态（0 或 1）。
      for (let row = 0; row <= 5; row++) {
        const progress = NowPlayingMotion.rowProgress(0.5, row);
        expect(progress === 0 || progress === 1).assertTrue();
      }
    });

    it('panelRadiusMatchesBarWhenCollapsedAndZeroWhenFull', 0, () => {
      expect(NowPlayingMotion.panelRadius(0)).assertEqual(20);
      expect(NowPlayingMotion.panelRadius(1)).assertEqual(0);
    });

    it('settleBudgetCoversRowStagger', 0, () => {
      // 结算预算必须 ≥ 收起方向最大行时延（5×10ms）+ 行时长（100ms），
      // 否则收起会截断最后一行。
      expect(NowPlayingMotion.ROW_SETTLE_MS >= 5 * 10 + 100).assertTrue();
      expect(NowPlayingMotion.COLLAPSE_MS).assertEqual(400);
      expect(NowPlayingMotion.EXPAND_MS).assertEqual(300);
    });
  });
}
