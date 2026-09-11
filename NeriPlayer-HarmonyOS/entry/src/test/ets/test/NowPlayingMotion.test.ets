import { describe, it, expect } from '@ohos/hypium';
import { NowPlayingMotion, NowPlayingRect } from '../../../main/ets/view/NowPlayingMotion';

const MINI: NowPlayingRect = { x: 16, y: 700, width: 328, height: 40 };

export default function nowPlayingMotionTest(): void {
  describe('NowPlayingMotion', () => {
    it('panelLerpIsLinearInAmount', 0, () => {
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

      // Lerp midpoint: the slow-then-fast character lives in advance(), not here.
      const mid = NowPlayingMotion.panel(0.5, MINI, 360, 800);
      expect(mid.y).assertEqual(350);
      expect(mid.height).assertEqual(420);
    });

    it('advanceIsSlowThenFastInBothDirections', 0, () => {
      // Expand: first half of the window covers less ground than the second.
      const firstHalf = NowPlayingMotion.advance(0, 150, true, 300);
      const secondHalf = NowPlayingMotion.advance(firstHalf, 150, true, 300);
      expect(firstHalf < 0.4).assertTrue();
      expect(secondHalf).assertEqual(1);
      // The second half of the window covers more ground than the first.
      expect(secondHalf - firstHalf > firstHalf).assertTrue();

      // Collapse mirrors it: leaves the full-screen state slowly, then drops fast.
      const dropFirst = 1 - NowPlayingMotion.advance(1, 200, false, 400);
      const after = NowPlayingMotion.advance(1 - dropFirst, 200, false, 400);
      expect(dropFirst < 0.4).assertTrue();
      expect(after).assertEqual(0);
    });

    it('advanceCompletesWithinDurationAndNeverOvershoots', 0, () => {
      expect(NowPlayingMotion.advance(0, 300, true, 300)).assertEqual(1);
      expect(NowPlayingMotion.advance(1, 400, false, 400)).assertEqual(0);
      // Long frame (jank) cannot push past the endpoints.
      expect(NowPlayingMotion.advance(0.5, 2000, true, 300)).assertEqual(1);
      expect(NowPlayingMotion.advance(0.5, 2000, false, 400)).assertEqual(0);
    });

    it('advanceReversalStaysContinuous', 0, () => {
      let a = NowPlayingMotion.advance(0, 120, true, 300);
      const expanded = a;
      // Flip direction mid-flight: the step is a normal frame step, no jump.
      a = NowPlayingMotion.advance(a, 16, false, 400);
      expect(Math.abs(a - expanded) < 0.1).assertTrue();
      expect(a > 0).assertTrue();
    });

    it('rowsStaggerAfterPanelNearlyExpanded', 0, () => {
      // Rows must stay hidden while the panel is still expanding.
      expect(NowPlayingMotion.rowProgress(0.5, 0)).assertEqual(0);
      // Successive rows start later, each by 0.038.
      expect(NowPlayingMotion.rowProgress(0.7, 0) > 0).assertTrue();
      expect(NowPlayingMotion.rowProgress(0.7, 1)).assertEqual(0);
      // The last of six rows still settles before the panel amount tops out.
      expect(NowPlayingMotion.rowProgress(1, 5)).assertEqual(1);
    });

    it('rowOpacityFadesInOverFirstHalfOnly', 0, () => {
      expect(NowPlayingMotion.rowOpacity(0, 0)).assertEqual(0);
      // Halfway through a row's own motion the row is already opaque.
      const half = 0.68 + (0.81 - 0.68) * 0.5;
      expect(NowPlayingMotion.rowOpacity(half, 0)).assertEqual(1);
      // Reverse keeps opacity at 1 across the first half of the downward move.
      const late = 0.68 + (0.81 - 0.68) * 0.75;
      expect(NowPlayingMotion.rowOpacity(late, 0)).assertEqual(1);
    });

    it('rowOffsetHasElasticTerminalOvershoot', 0, () => {
      expect(NowPlayingMotion.rowOffset(0, 3)).assertEqual(48);
      expect(NowPlayingMotion.rowOffset(1, 3)).assertEqual(0);
      // Late in row 3's own window the row overshoots above its resting place
      // (negative offset), then settles back — the elastic feel.
      const rowStart = 0.68 + 3 * 0.038;
      const amount = rowStart + 0.13 * 0.7;
      expect(NowPlayingMotion.rowOffset(amount, 3) < 0).assertTrue();
    });

    it('backOutGluesEndpointsButOvershootsMidFlight', 0, () => {
      expect(NowPlayingMotion.backOut(0)).assertEqual(0);
      expect(NowPlayingMotion.backOut(1)).assertEqual(1);
      expect(NowPlayingMotion.backOut(0.7) > 1).assertTrue();
    });

    it('miniReturnsOnlyWhenPanelTopDropsToFifth', 0, () => {
      // windowHeight 800 -> threshold 640 (80% height).
      expect(NowPlayingMotion.miniReturnOpacity(640, 800, 700)).assertEqual(0);
      expect(NowPlayingMotion.miniReturnOpacity(650, 800, 700) > 0).assertTrue();
      expect(NowPlayingMotion.miniReturnOpacity(650, 800, 700) < 1).assertTrue();
      // Panel fully collapsed: mini is visible again.
      expect(NowPlayingMotion.miniReturnOpacity(700, 800, 700)).assertEqual(1);
    });

    it('panelRadiusMatchesBarAtEndpointsAndSwellMidFlight', 0, () => {
      // Both endpoints must equal the bar pill radius for a seamless handoff.
      expect(NowPlayingMotion.panelRadius(0)).assertEqual(20);
      expect(NowPlayingMotion.panelRadius(1)).assertEqual(0);
      // Corners swell beyond the bar radius through the first quarter...
      expect(NowPlayingMotion.panelRadius(0.28) > 20).assertTrue();
      // ...and are already below it by mid-flight.
      expect(NowPlayingMotion.panelRadius(0.5) < 20).assertTrue();
    });
  });
}
