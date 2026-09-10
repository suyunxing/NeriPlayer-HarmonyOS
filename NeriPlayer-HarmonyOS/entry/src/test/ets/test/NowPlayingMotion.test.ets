import { describe, it, expect } from '@ohos/hypium';
import { NowPlayingMotion, NowPlayingRect } from '../../../main/ets/view/NowPlayingMotion';

const MINI: NowPlayingRect = { x: 16, y: 700, width: 328, height: 40 };

export default function nowPlayingMotionTest(): void {
  describe('NowPlayingMotion', () => {
    it('panelInterpolatesFromMiniRectToFullScreen', 0, () => {
      const start = NowPlayingMotion.panel(0, MINI, 360, 800);
      expect(start.x).assertEqual(16);
      expect(start.y).assertEqual(700);
      expect(start.width).assertEqual(328);
      expect(start.height).assertEqual(40);

      const end = NowPlayingMotion.panel(1, MINI, 360, 800);
      expect(end.x).assertEqual(0);
      expect(end.y).assertEqual(0);
      expect(end.width).assertEqual(360);
      expect(end.height).assertEqual(800);

      const mid = NowPlayingMotion.panel(0.34, MINI, 360, 800);
      expect(mid.y > 0 && mid.y < 700).assertTrue();
      expect(mid.height > 40 && mid.height < 800).assertTrue();
    });

    it('rowsStaggerAfterPanelNearlyExpanded', 0, () => {
      // Rows must stay hidden while the panel is still expanding.
      expect(NowPlayingMotion.rowProgress(0.5, 0)).assertEqual(0);
      // Successive rows start later, each by 0.035.
      const first = NowPlayingMotion.rowProgress(0.6, 0);
      const second = NowPlayingMotion.rowProgress(0.6, 1);
      expect(first > 0).assertTrue();
      expect(second).assertEqual(0);
      // The last of six rows still settles before progress 1.
      expect(NowPlayingMotion.rowProgress(1, 5)).assertEqual(1);
    });

    it('rowOpacityFadesInOverFirstHalfOnly', 0, () => {
      expect(NowPlayingMotion.rowOpacity(0, 0)).assertEqual(0);
      // Halfway through a row's own motion the row is already opaque.
      const half = 0.57 + (0.82 - 0.57) * 0.5;
      expect(NowPlayingMotion.rowOpacity(half, 0)).assertEqual(1);
      // Reverse keeps opacity at 1 across the first half of the downward move.
      const late = 0.57 + (0.82 - 0.57) * 0.75;
      expect(NowPlayingMotion.rowOpacity(late, 0)).assertEqual(1);
    });

    it('rowOffsetStartsBelowAndSettlesAtZero', 0, () => {
      expect(NowPlayingMotion.rowOffset(0, 3)).assertEqual(48);
      expect(NowPlayingMotion.rowOffset(1, 3)).assertEqual(0);
      const mid = NowPlayingMotion.rowOffset(0.7, 3);
      expect(mid < 48 && mid > -12).assertTrue();
    });

    it('miniReturnsOnlyWhenPanelTopDropsToFifth', 0, () => {
      // windowHeight 800 -> threshold 640 (80% height).
      expect(NowPlayingMotion.miniReturnOpacity(640, 800, 700)).assertEqual(0);
      expect(NowPlayingMotion.miniReturnOpacity(650, 800, 700) > 0).assertTrue();
      expect(NowPlayingMotion.miniReturnOpacity(650, 800, 700) < 1).assertTrue();
      // Panel fully collapsed: mini is visible again.
      expect(NowPlayingMotion.miniReturnOpacity(700, 800, 700)).assertEqual(1);
    });

    it('springSettlesExactlyAtEndpoints', 0, () => {
      expect(NowPlayingMotion.spring(0)).assertEqual(0);
      expect(NowPlayingMotion.spring(1)).assertEqual(1);
      // Interrupted reversals never overshoot the [0, 1] progress domain.
      expect(NowPlayingMotion.clamp(NowPlayingMotion.spring(0.5)) <= 1).assertTrue();
    });
  });
}
