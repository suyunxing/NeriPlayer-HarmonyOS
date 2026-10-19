// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { DEFAULT_STALL_THRESHOLD_MS, PlaybackStallDetector } from '../../../main/ets/player/PlaybackStallPolicy';

export default function playbackStallPolicyTest(): void {
  describe('PlaybackStallDetector', () => {
    it('noSamplesMeansNotStalled', 0, () => {
      const detector = new PlaybackStallDetector(1000);
      expect(detector.isStalled(10_000)).assertFalse();
    });

    it('frozenPositionPastThresholdIsStalled', 0, () => {
      const detector = new PlaybackStallDetector(1000);
      detector.observe(0, 100);
      detector.observe(500, 100);
      // The last advance was at 0, so the threshold is reached at 1000.
      expect(detector.isStalled(999)).assertFalse();
      expect(detector.isStalled(1000)).assertTrue();
    });

    it('anyPositionChangeCountsAsProgress', 0, () => {
      const detector = new PlaybackStallDetector(1000);
      detector.observe(0, 100);
      // A backwards seek landing still proves the transport is alive.
      detector.observe(900, 40);
      expect(detector.isStalled(1800)).assertFalse();
      expect(detector.isStalled(1900)).assertTrue();
    });

    it('continuousAdvanceNeverStalls', 0, () => {
      const detector = new PlaybackStallDetector(1000);
      for (let t = 0; t <= 5000; t += 250) {
        detector.observe(t, t);
        expect(detector.isStalled(t)).assertFalse();
      }
    });

    it('resetClearsHistory', 0, () => {
      const detector = new PlaybackStallDetector(1000);
      detector.observe(0, 100);
      detector.reset();
      expect(detector.isStalled(100_000)).assertFalse();
    });

    it('defaultThresholdMatchesUpstreamRecoveryWindow', 0, () => {
      expect(DEFAULT_STALL_THRESHOLD_MS).assertEqual(15000);
    });
  });
}
