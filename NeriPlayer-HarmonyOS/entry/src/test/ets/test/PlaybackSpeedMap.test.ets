import { describe, it, expect } from '@ohos/hypium';
import {
  PlaybackSpeedStep,
  effectivePlaybackRate,
  playbackSpeedStepRate,
  toPlaybackSpeedStep
} from '../../../main/ets/player/PlaybackSpeedMap';

/**
 * The six rates NowPlayingPage / SettingsDetailPage actually offer. Every one
 * must survive the round trip unchanged, otherwise the control center's
 * extrapolated progress drifts against the audio the user hears.
 */
const UI_SPEED_STEPS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/** PlayerManager clamps the listen-together sync rate to this range. */
const SYNC_RATE_MIN: number = 0.95;
const SYNC_RATE_MAX: number = 1.05;

export default function playbackSpeedMapTest(): void {
  describe('PlaybackSpeedMapTest', () => {
    it('maps every UI speed step losslessly', 0, () => {
      for (const rate of UI_SPEED_STEPS) {
        expect(effectivePlaybackRate(rate)).assertEqual(rate);
      }
    });

    it('keeps UI steps lossless across the whole sync-rate clamp', 0, () => {
      // A listen-together drift correction must never silently change the
      // reported rate: the two are multiplied before quantization. This is the
      // assertion that caught 0.75 * 1.05 escaping to 1.00x.
      for (const rate of UI_SPEED_STEPS) {
        expect(effectivePlaybackRate(rate * SYNC_RATE_MIN)).assertEqual(rate);
        expect(effectivePlaybackRate(rate * SYNC_RATE_MAX)).assertEqual(rate);
      }
    });

    it('quantizes to the nearest step, not the one below', 0, () => {
      // Midpoint boundaries. The pre-M10.3 mapping used the step values
      // themselves, which is what let 0.7875 escape to 1.00x.
      expect(toPlaybackSpeedStep(0.62)).assertEqual(PlaybackSpeedStep.SPEED_0_50_X);
      expect(toPlaybackSpeedStep(0.625)).assertEqual(PlaybackSpeedStep.SPEED_0_75_X);
      expect(toPlaybackSpeedStep(0.7875)).assertEqual(PlaybackSpeedStep.SPEED_0_75_X);
      expect(toPlaybackSpeedStep(0.874)).assertEqual(PlaybackSpeedStep.SPEED_0_75_X);
      expect(toPlaybackSpeedStep(0.875)).assertEqual(PlaybackSpeedStep.SPEED_1_00_X);
      expect(toPlaybackSpeedStep(1.124)).assertEqual(PlaybackSpeedStep.SPEED_1_00_X);
      expect(toPlaybackSpeedStep(1.125)).assertEqual(PlaybackSpeedStep.SPEED_1_25_X);
      expect(toPlaybackSpeedStep(1.374)).assertEqual(PlaybackSpeedStep.SPEED_1_25_X);
      expect(toPlaybackSpeedStep(1.375)).assertEqual(PlaybackSpeedStep.SPEED_1_50_X);
      expect(toPlaybackSpeedStep(1.749)).assertEqual(PlaybackSpeedStep.SPEED_1_50_X);
      expect(toPlaybackSpeedStep(1.75)).assertEqual(PlaybackSpeedStep.SPEED_2_00_X);
    });

    it('documents the 1.75x and 3.0x gap instead of pretending it is covered', 0, () => {
      // Preserved behaviour, not an oversight: no caller can produce these, so
      // enabling the steps would be a behaviour change. If a UI step is ever
      // added between 1.5 and 2.0, this assertion is the one that should fail.
      expect(toPlaybackSpeedStep(1.75)).assertEqual(PlaybackSpeedStep.SPEED_2_00_X);
      expect(toPlaybackSpeedStep(3.0)).assertEqual(PlaybackSpeedStep.SPEED_2_00_X);
    });

    it('reports the rate of every enum step, including unreachable ones', 0, () => {
      // The inverse covers the full enum so a future mapping change cannot
      // produce a step whose rate is silently reported as 1.0.
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_0_125_X)).assertEqual(0.125);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_0_25_X)).assertEqual(0.25);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_0_50_X)).assertEqual(0.5);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_0_75_X)).assertEqual(0.75);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_1_00_X)).assertEqual(1.0);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_1_25_X)).assertEqual(1.25);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_1_50_X)).assertEqual(1.5);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_1_75_X)).assertEqual(1.75);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_2_00_X)).assertEqual(2.0);
      expect(playbackSpeedStepRate(PlaybackSpeedStep.SPEED_3_00_X)).assertEqual(3.0);
    });

    it('falls back to 1.0 for an unknown step', 0, () => {
      expect(playbackSpeedStepRate(-1)).assertEqual(1.0);
      expect(playbackSpeedStepRate(99)).assertEqual(1.0);
    });

    it('is monotonic: a faster request never reports a slower rate', 0, () => {
      // Guards the mapping's ordering, which the enum ordinals do not: they run
      // 0.75, 1.00, 1.25, 1.75, 2.00, 0.50, 1.50, 3.00, so a table written in
      // ordinal order would look plausible and be wrong. Note the quantization
      // rounds both ways (0.61 -> 0.75, 1.89 -> 1.50), so "never overshoots"
      // would be a false property to assert here.
      let previous: number = 0;
      for (let rate = 0.4; rate <= 2.4; rate += 0.05) {
        const reported = effectivePlaybackRate(rate);
        expect(reported >= previous).assertTrue();
        previous = reported;
      }
    });
  });
}
