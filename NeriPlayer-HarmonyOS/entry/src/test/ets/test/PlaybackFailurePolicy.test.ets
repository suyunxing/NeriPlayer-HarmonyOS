import { describe, it, expect } from '@ohos/hypium';
import {
  decideLoadFailureAction,
  LoadFailureAction,
  MAX_CONSECUTIVE_FAILURES
} from '../../../main/ets/player/PlaybackFailurePolicy';

export default function playbackFailurePolicyTest(): void {
  describe('PlaybackFailurePolicy', () => {
    it('firstFailureRetriesSameTrack', 0, () => {
      expect(decideLoadFailureAction({
        errorAttempts: 1, autoSkipFailures: 0, queueLength: 1, nextTarget: 0, currentIndex: 0
      })).assertEqual(LoadFailureAction.RETRY_SAME);
    });

    it('secondFailureSkipsWhileBudgetRemains', 0, () => {
      // Queue of 3, first track failed twice: skip is allowed and budgeted.
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 0, queueLength: 3, nextTarget: 1, currentIndex: 0
      })).assertEqual(LoadFailureAction.SKIP_NEXT);
    });

    it('singleTrackWrapStopsInsteadOfReplaying', 0, () => {
      // Single-track queue under repeat-all: the engine's next target is the
      // same track; replaying it forever was the device retry storm.
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 0, queueLength: 1, nextTarget: 0, currentIndex: 0
      })).assertEqual(LoadFailureAction.STOP);
    });

    it('longQueueStopsAtConsecutiveLimit', 0, () => {
      // Upstream #499: a 500-entry queue must not skip through every entry
      // when all sources fail; the 10th consecutive failure stops.
      expect(MAX_CONSECUTIVE_FAILURES).assertEqual(10);
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 8, queueLength: 500, nextTarget: 9, currentIndex: 8
      })).assertEqual(LoadFailureAction.SKIP_NEXT);
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 9, queueLength: 500, nextTarget: 10, currentIndex: 9
      })).assertEqual(LoadFailureAction.STOP);
    });

    it('shortQueueStillBoundedByCircleWrap', 0, () => {
      // Queue shorter than the consecutive limit keeps the tighter wrap bound.
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 1, queueLength: 3, nextTarget: 2, currentIndex: 1
      })).assertEqual(LoadFailureAction.SKIP_NEXT);
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 2, queueLength: 3, nextTarget: 0, currentIndex: 2
      })).assertEqual(LoadFailureAction.STOP);
    });

    it('queueTailWithoutRepeatStops', 0, () => {
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 0, queueLength: 5, nextTarget: -1, currentIndex: 4
      })).assertEqual(LoadFailureAction.STOP);
    });

    it('everyTrackTriedStopsTheQueue', 0, () => {
      // After queueLength-1 skips, the final track's give-up must stop instead
      // of wrapping the queue for another lap of guaranteed failures.
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 4, queueLength: 5, nextTarget: 0, currentIndex: 4
      })).assertEqual(LoadFailureAction.STOP);
      // One skip before the cap still advances.
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 3, queueLength: 5, nextTarget: 0, currentIndex: 4
      })).assertEqual(LoadFailureAction.SKIP_NEXT);
    });

    it('degenerateQueueLengthStillStops', 0, () => {
      expect(decideLoadFailureAction({
        errorAttempts: 2, autoSkipFailures: 0, queueLength: 0, nextTarget: 1, currentIndex: 0
      })).assertEqual(LoadFailureAction.STOP);
    });
  });
}
