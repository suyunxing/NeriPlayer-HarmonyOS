/**
 * Numeric mirror of media.PlaybackSpeed (API 24), kept here so the mapping
 * stays a pure, unit-testable module without @kit imports — same arrangement
 * as AudioInterruptPolicy.
 *
 * The enum's ordinals are not in rate order, which is exactly why they are
 * spelled out rather than computed.
 */
export class PlaybackSpeedStep {
  static readonly SPEED_0_75_X: number = 0;
  static readonly SPEED_1_00_X: number = 1;
  static readonly SPEED_1_25_X: number = 2;
  static readonly SPEED_1_75_X: number = 3;
  static readonly SPEED_2_00_X: number = 4;
  static readonly SPEED_0_50_X: number = 5;
  static readonly SPEED_1_50_X: number = 6;
  static readonly SPEED_3_00_X: number = 7;
  static readonly SPEED_0_25_X: number = 8;
  static readonly SPEED_0_125_X: number = 9;
}

/**
 * Maps a requested numeric rate onto the enum step AVPlayer will actually run
 * at. API 24 only accepts these fixed steps, so anything in between is
 * quantized — to the *nearest* one, i.e. the boundaries are the midpoints
 * between adjacent steps.
 *
 * The midpoints matter because PlayerManager multiplies the user's speed by
 * the listen-together sync rate (clamped to [0.95, 1.05]) before quantizing.
 * The original boundaries were the step values themselves rather than the
 * midpoints, so `0.75 * 1.05 = 0.7875` fell through to 1.00x: a 5% drift
 * correction silently became a 33% speed-up. With midpoints, all six UI steps
 * survive the full clamp range unchanged (asserted in PlaybackSpeedMap.test).
 *
 * Known gap, preserved deliberately: SPEED_1_75_X and SPEED_3_00_X are never
 * produced — 1.375..1.75 lands on 1.50 and anything above on 2.00. The UI
 * offers [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], none of which can reach them.
 * Enabling those steps would be a behaviour change, not a mapping fix.
 */
export function toPlaybackSpeedStep(rate: number): number {
  if (rate < 0.625) {
    return PlaybackSpeedStep.SPEED_0_50_X;
  }
  if (rate < 0.875) {
    return PlaybackSpeedStep.SPEED_0_75_X;
  }
  if (rate < 1.125) {
    return PlaybackSpeedStep.SPEED_1_00_X;
  }
  if (rate < 1.375) {
    return PlaybackSpeedStep.SPEED_1_25_X;
  }
  if (rate < 1.75) {
    return PlaybackSpeedStep.SPEED_1_50_X;
  }
  return PlaybackSpeedStep.SPEED_2_00_X;
}

/**
 * Inverse of toPlaybackSpeedStep: the rate a step actually plays at.
 *
 * AVSession's progress bar is extrapolated by the system from
 * elapsedTime + updateTime + speed, so `speed` has to be the rate the player
 * runs at — the quantized one — not the rate that was requested. Reporting the
 * request instead makes the control center drift whenever quantization rounds
 * it to a different step.
 */
export function playbackSpeedStepRate(step: number): number {
  switch (step) {
    case PlaybackSpeedStep.SPEED_0_125_X:
      return 0.125;
    case PlaybackSpeedStep.SPEED_0_25_X:
      return 0.25;
    case PlaybackSpeedStep.SPEED_0_50_X:
      return 0.5;
    case PlaybackSpeedStep.SPEED_0_75_X:
      return 0.75;
    case PlaybackSpeedStep.SPEED_1_25_X:
      return 1.25;
    case PlaybackSpeedStep.SPEED_1_50_X:
      return 1.5;
    case PlaybackSpeedStep.SPEED_1_75_X:
      return 1.75;
    case PlaybackSpeedStep.SPEED_2_00_X:
      return 2.0;
    case PlaybackSpeedStep.SPEED_3_00_X:
      return 3.0;
    default:
      return 1.0;
  }
}

/** The rate the player really runs at for a requested rate. */
export function effectivePlaybackRate(rate: number): number {
  return playbackSpeedStepRate(toPlaybackSpeedStep(rate));
}
