import { describe, it, expect } from '@ohos/hypium';
import { MotionSpec } from '../../../main/ets/view/theme/MotionSpec';

/**
 * Locks the M11.6 motion constants and distance curves to the Android
 * reference values (docs/UI_ANIMATION_PLAN.md §2.3), so a future tweak has to
 * consciously diverge rather than drift. Float expectations use an epsilon
 * helper: the falloff arithmetic (e.g. 0.4 - 0.08 * 3) is not exact in binary.
 */
function assertNear(actual: number, expected: number): void {
  expect(Math.abs(actual - expected) < 1e-6).assertTrue();
}

export default function motionSpecTest(): void {
  describe('MotionSpec', (): void => {
    it('transition durations match the Android reference', 0, (): void => {
      // NeriTheme.kt:47
      expect(MotionSpec.THEME_COLOR_TRANSITION_MS).assertEqual(420);
      // NowPlayingScreen.kt:290
      expect(MotionSpec.PAGE_FADE_MS).assertEqual(300);
      // NeriApp.kt:304-310
      expect(MotionSpec.DETAIL_OPEN_MS).assertEqual(220);
      expect(MotionSpec.DETAIL_CLOSE_MS).assertEqual(240);
      expect(MotionSpec.DRAWER_OPEN_MS).assertEqual(300);
      expect(MotionSpec.DRAWER_CLOSE_MS).assertEqual(280);
      // NeriApp.kt:3679-3689
      expect(MotionSpec.NOWPLAYING_ENTER_SLIDE_MS).assertEqual(300);
      expect(MotionSpec.NOWPLAYING_EXIT_SLIDE_MS).assertEqual(250);
      expect(MotionSpec.NOWPLAYING_FADE_MS).assertEqual(150);
      // NeriApp.kt:3641-3656
      expect(MotionSpec.MINIPLAYER_ENTER_SLIDE_MS).assertEqual(220);
      expect(MotionSpec.MINIPLAYER_ENTER_FADE_MS).assertEqual(180);
      expect(MotionSpec.MINIPLAYER_EXIT_SLIDE_MS).assertEqual(180);
      expect(MotionSpec.MINIPLAYER_EXIT_FADE_MS).assertEqual(120);
      // NeriMiniPlayer.kt:115-128,151-159
      expect(MotionSpec.SWIPE_RELEASE_STAGE_MS).assertEqual(120);
      expect(MotionSpec.SWIPE_RELEASE_RETURN_MS).assertEqual(180);
      expect(MotionSpec.SWIPE_CANCEL_MS).assertEqual(160);
    });

    it('lyric row spring mirrors the Compose spring(StiffnessLow, 0.85f)', 0, (): void => {
      assertNear(MotionSpec.LYRIC_ROW_SPRING_DAMPING_FRACTION, 0.85);
      // Response has no closed-form upstream mapping; pin the tuning initial
      // so a change is a deliberate re-tune (UI_ANIMATION_PLAN.md §7 R4).
      assertNear(MotionSpec.LYRIC_ROW_SPRING_RESPONSE_S, 0.55);
    });

    it('lyricScaleForDistance ports scaleForDistance exactly', 0, (): void => {
      // SyncedLyricsView.kt:102-114, 1040-1046: active 1.1, near 0.9,
      // far base 0.88 falling 0.02/step, floored at 0.8.
      assertNear(MotionSpec.lyricScaleForDistance(0), 1.1);
      assertNear(MotionSpec.lyricScaleForDistance(1), 0.9);
      assertNear(MotionSpec.lyricScaleForDistance(2), 0.88);
      assertNear(MotionSpec.lyricScaleForDistance(3), 0.86);
      assertNear(MotionSpec.lyricScaleForDistance(4), 0.84);
      assertNear(MotionSpec.lyricScaleForDistance(6), 0.80);
      assertNear(MotionSpec.lyricScaleForDistance(9), 0.80);
      assertNear(MotionSpec.lyricScaleForDistance(-1), 1.1);
    });

    it('lyricAlphaForDistance ports alphaForDistance with both parameter pairs', 0, (): void => {
      // Blur enabled: near 0.72, far 0.40, -0.08/step, floored at 0.16.
      assertNear(MotionSpec.lyricAlphaForDistance(1, true), 0.72);
      assertNear(MotionSpec.lyricAlphaForDistance(2, true), 0.40);
      assertNear(MotionSpec.lyricAlphaForDistance(3, true), 0.32);
      assertNear(MotionSpec.lyricAlphaForDistance(5, true), 0.16);
      assertNear(MotionSpec.lyricAlphaForDistance(8, true), 0.16);
      // Blur disabled: near 0.4, far 0.35.
      assertNear(MotionSpec.lyricAlphaForDistance(1, false), 0.40);
      assertNear(MotionSpec.lyricAlphaForDistance(2, false), 0.35);
      assertNear(MotionSpec.lyricAlphaForDistance(3, false), 0.27);
      assertNear(MotionSpec.lyricAlphaForDistance(4, false), 0.19);
      assertNear(MotionSpec.lyricAlphaForDistance(5, false), 0.16);
      // Documented deviation: the active row keeps full opacity (Android
      // never routes it through alphaForDistance).
      assertNear(MotionSpec.lyricAlphaForDistance(0, true), 1.0);
      assertNear(MotionSpec.lyricAlphaForDistance(0, false), 1.0);
    });

    it('lyricBlurMultiplierForDistance ports blurForDistance exactly', 0, (): void => {
      // SyncedLyricsView.kt:1055-1062: 1x/1.5x/2x/2.5x/4x of the base blur.
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(0), 0);
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(1), 1.0);
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(2), 1.5);
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(3), 2.0);
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(4), 2.5);
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(5), 4.0);
      assertNear(MotionSpec.lyricBlurMultiplierForDistance(12), 4.0);
      // Base amount: Android lyricBlurAmount settings default.
      assertNear(MotionSpec.LYRIC_BLUR_BASE_VP, 1.5);
    });
  });
}
