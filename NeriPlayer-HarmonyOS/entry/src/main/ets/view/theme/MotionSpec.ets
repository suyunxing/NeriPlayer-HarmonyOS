/**
 * Centralized motion constants and distance curves for the M11.6 animation
 * work (docs/UI_ANIMATION_PLAN.md). Every value traces back to the Android
 * reference so both builds move the same way:
 *
 *   - theme color transition: NeriTheme.kt:47,151-154 (420ms FastOutSlowIn)
 *   - route/page transitions: NeriApp.kt:304-310, 3641-3689
 *   - mini player swipe release: NeriMiniPlayer.kt:106-128,151-159
 *   - lyric distance curves: SyncedLyricsView.kt:98-114,1040-1062
 *
 * This file must stay free of @ohos imports: the local hypium suite has no
 * ArkUI runtime, so only this pure half is unit-testable. The curves.*
 * factories live in MotionCurves.ets.
 */
export class MotionSpec {
  // ---- Global transitions (NeriTheme.kt / NeriApp.kt) ----
  /** Whole-app recolor on theme/seed switch (NeriTheme animateColorScheme). */
  static readonly THEME_COLOR_TRANSITION_MS: number = 420;
  /** Cover page <-> lyric page content fade (NowPlayingScreen.kt:290). */
  static readonly PAGE_FADE_MS: number = 300;
  /** Full-screen detail route push/pop vertical slide (NeriApp.kt:304-305). */
  static readonly DETAIL_OPEN_MS: number = 220;
  static readonly DETAIL_CLOSE_MS: number = 240;
  /** Drawer-style sheet open/close (NeriApp.kt:306-307). */
  static readonly DRAWER_OPEN_MS: number = 300;
  static readonly DRAWER_CLOSE_MS: number = 280;
  /** NowPlaying fullscreen layer enter/exit (NeriApp.kt:3679-3689). */
  static readonly NOWPLAYING_ENTER_SLIDE_MS: number = 300;
  static readonly NOWPLAYING_EXIT_SLIDE_MS: number = 250;
  static readonly NOWPLAYING_FADE_MS: number = 150;
  /** Mini player appear/disappear (NeriApp.kt:3641-3656). */
  static readonly MINIPLAYER_ENTER_SLIDE_MS: number = 220;
  static readonly MINIPLAYER_ENTER_FADE_MS: number = 180;
  static readonly MINIPLAYER_EXIT_SLIDE_MS: number = 180;
  static readonly MINIPLAYER_EXIT_FADE_MS: number = 120;

  // ---- Mini player swipe release (NeriMiniPlayer.kt:115-128,151-159) ----
  static readonly SWIPE_RELEASE_STAGE_MS: number = 120;
  static readonly SWIPE_RELEASE_RETURN_MS: number = 180;
  static readonly SWIPE_CANCEL_MS: number = 160;

  // ---- Lyric row dynamics (SyncedLyricsView.kt) ----
  /**
   * Spring for lyric row scale/alpha. dampingFraction mirrors Android's
   * spring(StiffnessLow, dampingRatio = 0.85f); response (seconds) has no
   * closed-form mapping from Compose stiffness and is a device-tunable
   * initial value (UI_ANIMATION_PLAN.md §7 R4).
   */
  static readonly LYRIC_ROW_SPRING_RESPONSE_S: number = 0.55;
  static readonly LYRIC_ROW_SPRING_DAMPING_FRACTION: number = 0.85;
  static readonly LYRIC_ACTIVE_SCALE: number = 1.1;
  static readonly LYRIC_NEAR_SCALE: number = 0.9;
  static readonly LYRIC_FAR_SCALE: number = 0.88;
  static readonly LYRIC_FAR_SCALE_MIN: number = 0.8;
  static readonly LYRIC_FAR_SCALE_FALLOFF_PER_STEP: number = 0.02;
  /** Inactive-row opacity with distance blur on/off (SyncedLyricsView.kt:326-331). */
  static readonly LYRIC_ALPHA_NEAR_BLUR: number = 0.72;
  static readonly LYRIC_ALPHA_FAR_BLUR: number = 0.40;
  static readonly LYRIC_ALPHA_NEAR_PLAIN: number = 0.40;
  static readonly LYRIC_ALPHA_FAR_PLAIN: number = 0.35;
  static readonly LYRIC_ALPHA_FALLOFF_PER_STEP: number = 0.08;
  static readonly LYRIC_ALPHA_MIN: number = 0.16;
  /**
   * Base blur amount the distance multipliers scale (Android lyricBlurAmount
   * settings default, AutoSettingsSchema.kt:813-822; the composable's own
   * 10f default is never reached because SettingsMotionSection always feeds
   * the persisted value).
   */
  static readonly LYRIC_BLUR_BASE_VP: number = 1.5;

  /**
   * Row scale by distance from the active row, a 1:1 port of
   * SyncedLyricsView.kt scaleForDistance: active 1.1, distance 1 -> 0.9,
   * distance >= 2 falls off from 0.88 by 0.02 per step, floored at 0.8.
   */
  static lyricScaleForDistance(distance: number): number {
    if (distance <= 0) {
      return MotionSpec.LYRIC_ACTIVE_SCALE;
    }
    if (distance === 1) {
      return MotionSpec.LYRIC_NEAR_SCALE;
    }
    const value = MotionSpec.LYRIC_FAR_SCALE
      - (distance - 2) * MotionSpec.LYRIC_FAR_SCALE_FALLOFF_PER_STEP;
    return Math.min(MotionSpec.LYRIC_FAR_SCALE,
      Math.max(MotionSpec.LYRIC_FAR_SCALE_MIN, value));
  }

  /**
   * Inactive-row opacity by distance, porting alphaForDistance with the two
   * parameter pairs the Android call sites use (blur on: 0.72/0.40, blur
   * off: 0.40/0.35). Deviation, documented: distance <= 0 returns 1.0 —
   * Android never routes the active row through this function, and an ArkUI
   * consumer applying it uniformly would otherwise dim the line being read.
   */
  static lyricAlphaForDistance(distance: number, blurEnabled: boolean): number {
    if (distance <= 0) {
      return 1.0;
    }
    const near = blurEnabled ? MotionSpec.LYRIC_ALPHA_NEAR_BLUR : MotionSpec.LYRIC_ALPHA_NEAR_PLAIN;
    const far = blurEnabled ? MotionSpec.LYRIC_ALPHA_FAR_BLUR : MotionSpec.LYRIC_ALPHA_FAR_PLAIN;
    if (distance === 1) {
      return near;
    }
    if (distance === 2) {
      return far;
    }
    const value = far - MotionSpec.LYRIC_ALPHA_FALLOFF_PER_STEP * (distance - 2);
    return Math.min(far, Math.max(MotionSpec.LYRIC_ALPHA_MIN, value));
  }

  /**
   * Distance-blur multiplier of the configured base blur amount, porting
   * blurForDistance. The active row (distance <= 0) is never blurred, so it
   * returns 0 rather than Android's implicit 1x for an unreachable input.
   */
  static lyricBlurMultiplierForDistance(distance: number): number {
    if (distance <= 0) {
      return 0;
    }
    if (distance === 1) {
      return 1.0;
    }
    if (distance === 2) {
      return 1.5;
    }
    if (distance === 3) {
      return 2.0;
    }
    if (distance === 4) {
      return 2.5;
    }
    return 4.0;
  }
}
