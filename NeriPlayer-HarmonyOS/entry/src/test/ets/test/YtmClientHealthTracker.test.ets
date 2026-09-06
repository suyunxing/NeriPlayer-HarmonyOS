import { describe, it, expect } from '@ohos/hypium';
import { YtmClientHealthTracker } from '../../../main/ets/network/ytm/YtmClientHealthTracker';

const T0 = 1_800_000_000_000;
const WINDOW = 30 * 60 * 1000;

export default function ytmClientHealthTrackerTest(): void {
  describe('YtmClientHealthTracker', () => {
    it('suppressesAfterThreeConsecutiveRejections', 0, () => {
      const tracker = new YtmClientHealthTracker();
      tracker.recordRejection('ios', T0);
      expect(tracker.isSuppressed('ios', T0)).assertFalse();
      tracker.recordRejection('ios', T0);
      expect(tracker.isSuppressed('ios', T0)).assertFalse();
      tracker.recordRejection('ios', T0);
      expect(tracker.isSuppressed('ios', T0)).assertTrue();
      // Other clients unaffected.
      expect(tracker.isSuppressed('tvhtml5_downgraded', T0)).assertFalse();
    });

    it('suppressionExpiresAndSelfClears', 0, () => {
      const tracker = new YtmClientHealthTracker();
      for (let i = 0; i < 3; i++) {
        tracker.recordRejection('ios', T0);
      }
      expect(tracker.isSuppressed('ios', T0 + WINDOW - 1)).assertTrue();
      expect(tracker.isSuppressed('ios', T0 + WINDOW)).assertFalse();
      // Counter cleared with the suppression: three fresh failures needed again.
      expect(tracker.failureCount('ios')).assertEqual(0);
      tracker.recordRejection('ios', T0 + WINDOW);
      expect(tracker.isSuppressed('ios', T0 + WINDOW)).assertFalse();
    });

    it('successResetsCounterAndSuppression', 0, () => {
      const tracker = new YtmClientHealthTracker();
      tracker.recordRejection('ios', T0);
      tracker.recordRejection('ios', T0);
      tracker.recordSuccess('ios');
      tracker.recordRejection('ios', T0);
      expect(tracker.isSuppressed('ios', T0)).assertFalse();
      expect(tracker.failureCount('ios')).assertEqual(1);
    });

    it('chainFiltersSuppressedButNeverEmpty', 0, () => {
      const tracker = new YtmClientHealthTracker();
      const keys = ['ios', 'tvhtml5_downgraded'];
      // Nothing suppressed: full order kept.
      expect(
        tracker.selectUsableChain(keys, (k: string) => k, T0).join(',')
      ).assertEqual('ios,tvhtml5_downgraded');
      // Suppress ios only: downgraded leads.
      for (let i = 0; i < 3; i++) {
        tracker.recordRejection('ios', T0);
      }
      expect(
        tracker.selectUsableChain(keys, (k: string) => k, T0).join(',')
      ).assertEqual('tvhtml5_downgraded');
      // Suppress everything: fall back to the full chain (Android ifEmpty).
      for (let i = 0; i < 3; i++) {
        tracker.recordRejection('tvhtml5_downgraded', T0);
      }
      expect(
        tracker.selectUsableChain(keys, (k: string) => k, T0).join(',')
      ).assertEqual('ios,tvhtml5_downgraded');
    });
  });
}
