import { curves } from '@kit.ArkUI';
import { MotionSpec } from './MotionSpec';

/**
 * ArkUI curve factories for the M11.6 motion work. Kept apart from
 * MotionSpec.ets because importing @kit.ArkUI would take the constants out
 * of reach of the local hypium suite (no ArkUI runtime there).
 */
export class MotionCurves {
  /**
   * Material FastOutSlowInEasing, which is exactly cubic-bezier(0.4, 0, 0.2,
   * 1). The theme color transition, detail/drawer slides and the mini player
   * gestures all run on it upstream.
   */
  static fastOutSlowIn(): curves.ICurve {
    return curves.cubicBezierCurve(0.4, 0, 0.2, 1);
  }

  /**
   * Physics spring for lyric row scale/alpha. dampingFraction mirrors
   * Android's 0.85; the response value is a tuning initial (§7 R4).
   */
  static lyricRowSpring(): curves.ICurve {
    return curves.springMotion(MotionSpec.LYRIC_ROW_SPRING_RESPONSE_S,
      MotionSpec.LYRIC_ROW_SPRING_DAMPING_FRACTION);
  }
}
