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

    it('mixWithOthersIgnoresCooperativePauseHint', 0, () => {
      // 允许与其他应用同时播放：SHARE 型暂停请求不再自我暂停。
      expect(AudioInterruptPolicy.decide(V.HINT_PAUSE, V.SHARE, true, false, true))
        .assertEqual(InterruptAction.NONE);
      // 关闭混音（独占）：正在播放时配合暂停请求并保留续播意图。
      expect(AudioInterruptPolicy.decide(V.HINT_PAUSE, V.SHARE, true, false, false))
        .assertEqual(InterruptAction.PAUSE_TRANSIENT);
      // 关闭混音但本就没在播放：无事可做。
      expect(AudioInterruptPolicy.decide(V.HINT_PAUSE, V.SHARE, false, false, false))
        .assertEqual(InterruptAction.NONE);
    });

    it('mixWithOthersStillHonorsForcedInterruption', 0, () => {
      // 系统 FORCED 抢占无法拒绝：仍按瞬时/永久丢失处理。
      expect(AudioInterruptPolicy.decide(V.HINT_PAUSE, V.FORCE, true, false, true))
        .assertEqual(InterruptAction.PAUSE_TRANSIENT);
      expect(AudioInterruptPolicy.decide(V.HINT_STOP, V.FORCE, true, true, true))
        .assertEqual(InterruptAction.PAUSE_PERMANENT);
      // 混音不影响 resume 提示。
      expect(AudioInterruptPolicy.decide(V.HINT_RESUME, V.SHARE, false, true, true))
        .assertEqual(InterruptAction.RESUME);
    });
  });
}
