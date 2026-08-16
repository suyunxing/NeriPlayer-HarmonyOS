import { describe, it, expect } from '@ohos/hypium';
import { AudioInterruptPolicy, InterruptAction, InterruptValues as V } from '../../../main/ets/player/AudioInterruptPolicy';

export default function audioInterruptPolicyTest(): void {
  describe('AudioInterruptPolicy', () => {
    it('transientLossWhilePlayingPausesWithResumeIntent', 0, () => {
      expect(AudioInterruptPolicy.decide(V.HINT_PAUSE, V.FORCE, true, false))
        .assertEqual(InterruptAction.PAUSE_TRANSIENT);
    });

    it('transientLossWhilePausedIsNoOp', 0, () => {
      expect(AudioInterruptPolicy.decide(V.HINT_PAUSE, V.FORCE, false, false))
        .assertEqual(InterruptAction.NONE);
    });

    it('permanentLossNeverAutoResumes', 0, () => {
      expect(AudioInterruptPolicy.decide(V.HINT_STOP, V.FORCE, true, true))
        .assertEqual(InterruptAction.PAUSE_PERMANENT);
    });

    it('duckingIsSystemHandled', 0, () => {
      expect(AudioInterruptPolicy.decide(V.HINT_DUCK, V.FORCE, true, false))
        .assertEqual(InterruptAction.NONE);
      expect(AudioInterruptPolicy.decide(V.HINT_UNDUCK, V.FORCE, true, false))
        .assertEqual(InterruptAction.NONE);
    });

    it('resumeHintOnlyResumesWithIntent', 0, () => {
      expect(AudioInterruptPolicy.decide(V.HINT_RESUME, V.SHARE, false, true))
        .assertEqual(InterruptAction.RESUME);
      expect(AudioInterruptPolicy.decide(V.HINT_RESUME, V.SHARE, false, false))
        .assertEqual(InterruptAction.NONE);
    });

    it('deviceUnavailableHardPauses', 0, () => {
      expect(AudioInterruptPolicy.decideForDeviceChange(V.REASON_OLD_DEVICE_UNAVAILABLE))
        .assertEqual(InterruptAction.PAUSE_PERMANENT);
      expect(AudioInterruptPolicy.decideForDeviceChange(1))
        .assertEqual(InterruptAction.NONE);
    });
  });
}
