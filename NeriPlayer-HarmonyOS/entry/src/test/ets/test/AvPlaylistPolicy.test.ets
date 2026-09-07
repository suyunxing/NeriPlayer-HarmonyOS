import { describe, it, expect } from '@ohos/hypium';
import { QueueEngine } from '../../../main/ets/player/queue/QueueEngine';
import { RepeatMode } from '../../../main/ets/player/PlaybackConstants';
import {
  advanceForceFor,
  peekNextIndex,
  shouldPrimeNext,
  PrimeNextInput
} from '../../../main/ets/player/AvPlaylistPolicy';

function engineStarted(size: number, start: number, shuffle: boolean, seed: number, repeat: RepeatMode): QueueEngine {
  const engine = new QueueEngine(seed);
  engine.setQueueSize(size);
  engine.start(start, shuffle, repeat);
  return engine;
}

function primeInput(
  queueLength: number,
  repeat: RepeatMode,
  nextIndex: number,
  listenTogether: boolean,
  offline: boolean
): PrimeNextInput {
  return {
    queueLength: queueLength,
    repeatMode: repeat,
    nextIndex: nextIndex,
    listenTogetherActive: listenTogether,
    nextOfflineAvailable: offline
  };
}

export default function avPlaylistPolicyTest(): void {
  describe('AvPlaylistPolicy', () => {
    it('advanceForceMirrorsAutoNextForce', 0, () => {
      expect(advanceForceFor(RepeatMode.ALL)).assertTrue();
      expect(advanceForceFor(RepeatMode.ONE)).assertFalse();
      expect(advanceForceFor(RepeatMode.OFF)).assertFalse();
    });

    it('peekPredictsSequentialAdvance', 0, () => {
      const engine = engineStarted(3, 1, false, 7, RepeatMode.OFF);
      expect(peekNextIndex(engine, false)).assertEqual(2);
      // Repeat-off at the tail stops; force (repeat-all path) wraps to 0.
      engine.next(false);
      expect(peekNextIndex(engine, false)).assertEqual(-1);
      expect(peekNextIndex(engine, true)).assertEqual(0);
    });

    it('peekDoesNotMutateTheEngine', 0, () => {
      const engine = engineStarted(4, 1, false, 11, RepeatMode.ALL);
      const first = peekNextIndex(engine, true);
      const second = peekNextIndex(engine, true);
      expect(first).assertEqual(second);
      expect(engine.getCurrentQueueIndex()).assertEqual(1);
      // The real transition lands exactly where the peek predicted.
      expect(engine.next(true)).assertEqual(first);
    });

    it('peekPredictsShufflePickExactly', 0, () => {
      const engine = engineStarted(6, 0, true, 42, RepeatMode.ALL);
      const predicted = peekNextIndex(engine, true);
      expect(predicted).assertEqual(engine.next(true));
      // And a second prediction from the moved engine still matches.
      const predicted2 = peekNextIndex(engine, true);
      expect(predicted2).assertEqual(engine.next(true));
    });

    it('shouldPrimeNextGatesEveryCondition', 0, () => {
      expect(shouldPrimeNext(primeInput(3, RepeatMode.ALL, 2, false, true))).assertTrue();
      expect(shouldPrimeNext(primeInput(3, RepeatMode.ONE, 2, false, true))).assertFalse();
      expect(shouldPrimeNext(primeInput(1, RepeatMode.ALL, 0, false, true))).assertFalse();
      expect(shouldPrimeNext(primeInput(3, RepeatMode.ALL, 2, true, true))).assertFalse();
      expect(shouldPrimeNext(primeInput(3, RepeatMode.OFF, -1, false, true))).assertFalse();
      expect(shouldPrimeNext(primeInput(3, RepeatMode.ALL, 2, false, false))).assertFalse();
    });
  });
}
