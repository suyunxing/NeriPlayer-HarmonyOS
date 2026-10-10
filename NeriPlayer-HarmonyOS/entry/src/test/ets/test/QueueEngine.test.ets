import { describe, it, expect } from '@ohos/hypium';
import { QueueEngine, ShuffleIndexState, TrackEndAction, resolvePlaylistPlaybackStartIndex } from '../../../main/ets/player/queue/QueueEngine';
import { RepeatMode } from '../../../main/ets/player/PlaybackConstants';

function expectList(actual: number[], expected: number[], label: string): void {
  expect(actual.length).assertEqual(expected.length);
  for (let i = 0; i < expected.length; i++) {
    expect(actual[i]).assertEqual(expected[i]);
  }
  expect(label.length > 0).assertTrue();
}

function engineWith(size: number, seed: number): QueueEngine {
  const engine = new QueueEngine(seed);
  engine.setQueueSize(size);
  return engine;
}

export default function queueEngineTest(): void {
  describe('QueueEngineRemap', () => {
    it('insertNextKeepsRemainingShuffleIndicesValidAndComplete', 0, () => {
      // [A,B,C,D] playing B; bag holds D,C; insert E at 2 (new song).
      const state = QueueEngine.remapForInsertNext([3, 2], [], [], -1, 2, 2);
      // D 3->4, C 2->3; new song E leaves the bag for future.
      expectList(state.bag, [4, 3], 'bag');
      expectList(state.history, [], 'history');
      expectList(state.future, [2], 'future');
    });

    it('insertNextRemapsBothRemovalAndInsertionForExistingSong', 0, () => {
      // [A,B,C,D,E] bag=[D,B,E,C]; D(existing 3) becomes next at insert 1.
      const state = QueueEngine.remapForInsertNext([3, 1, 4, 2], [], [], 3, 1, 1);
      // removal(3): [B=1,E=3,C=2]; insertion(1): [B=2,E=4,C=3]; D -> future.
      expectList(state.bag, [2, 4, 3], 'bag');
      expectList(state.future, [1], 'future');
    });

    it('insertNextShiftsHistoryAndDropsStaleNewSongHistory', 0, () => {
      // history=[A]; A(existing 0) is moved to play next.
      const state = QueueEngine.remapForInsertNext([], [0], [], 0, 0, 0);
      expectList(state.history, [], 'history');
      expectList(state.future, [0], 'future');
    });

    it('insertNextOnlyShiftsIndicesAtOrAfterInsertPoint', 0, () => {
      const state = QueueEngine.remapForInsertNext([0, 1, 2, 3], [], [], -1, 2, 2);
      expectList(state.bag, [0, 1, 3, 4], 'bag');
      expectList(state.future, [2], 'future');
    });

    it('insertNextPreservesExistingFutureWithoutDuplicates', 0, () => {
      // future=[C=2]; insert E at 3 (after C): C keeps its index, D shifts.
      const state = QueueEngine.remapForInsertNext([3], [], [2], -1, 3, 3);
      expectList(state.future, [2, 3], 'future');
      expectList(state.bag, [4], 'bag');
    });

    it('currentIndexFollowsDraggedItem', 0, () => {
      expect(QueueEngine.currentIndexAfterMove(5, 1, 1, 3)).assertEqual(3);
    });

    it('currentIndexShiftsWhenEarlierItemMovesAfterIt', 0, () => {
      expect(QueueEngine.currentIndexAfterMove(5, 2, 0, 3)).assertEqual(1);
    });

    it('currentIndexShiftsWhenLaterItemMovesBeforeIt', 0, () => {
      expect(QueueEngine.currentIndexAfterMove(5, 2, 4, 1)).assertEqual(3);
    });

    it('currentIndexSurvivesInvalidMove', 0, () => {
      expect(QueueEngine.currentIndexAfterMove(5, 2, -1, 3)).assertEqual(2);
      expect(QueueEngine.currentIndexAfterMove(5, 2, 1, 1)).assertEqual(2);
    });

    it('currentIndexReturnsMissingForEmptyQueue', 0, () => {
      expect(QueueEngine.currentIndexAfterMove(0, 0, 0, 0)).assertEqual(-1);
    });
  });

  describe('QueueEngineSequential', () => {
    it('advancesInOrderAndWrapsOnlyForRepeatAllOrForce', 0, () => {
      const engine = engineWith(3, 1);
      engine.start(0, false, RepeatMode.OFF);
      expect(engine.next(false)).assertEqual(1);
      expect(engine.next(false)).assertEqual(2);
      expect(engine.next(false)).assertEqual(-1);
      expect(engine.next(true)).assertEqual(0);
    });

    it('repeatAllWrapsAtEnd', 0, () => {
      const engine = engineWith(3, 1);
      engine.start(2, false, RepeatMode.ALL);
      expect(engine.next(false)).assertEqual(0);
    });

    it('previousWrapsOnlyForRepeatAll', 0, () => {
      const wrapping = engineWith(3, 1);
      wrapping.start(0, false, RepeatMode.ALL);
      expect(wrapping.previous()).assertEqual(2);
      const stopping = engineWith(3, 1);
      stopping.start(0, false, RepeatMode.OFF);
      expect(stopping.previous()).assertEqual(-1);
    });
  });

  describe('QueueEngineShuffle', () => {
    it('bagExcludesCurrentAndRebuildExcludesCurrent', 0, () => {
      const engine = engineWith(4, 7);
      engine.start(1, true, RepeatMode.ALL);
      const bag = engine.getBag();
      expect(bag.length).assertEqual(3);
      expect(bag.indexOf(1)).assertEqual(-1);
      engine.rebuildShuffleBag(2);
      const rebuilt = engine.getBag();
      expect(rebuilt.length).assertEqual(3);
      expect(rebuilt.indexOf(2)).assertEqual(-1);
    });

    it('nextDrainsBagDeterministicallyWithSeed', 0, () => {
      const first = engineWith(4, 42);
      first.start(0, true, RepeatMode.OFF);
      const second = engineWith(4, 42);
      second.start(0, true, RepeatMode.OFF);
      const firstOrder: number[] = [];
      const secondOrder: number[] = [];
      for (let i = 0; i < 3; i++) {
        firstOrder.push(first.next(false));
        secondOrder.push(second.next(false));
      }
      expectList(firstOrder, secondOrder, 'same seed same order');
      // Every queue index except the start appears exactly once.
      const seen = new Set<number>(firstOrder);
      expect(seen.size).assertEqual(3);
      expect(firstOrder.indexOf(0)).assertEqual(-1);
      // Bag exhausted under repeat off with no force.
      expect(first.next(false)).assertEqual(-1);
    });

    it('previousParksCurrentIntoFutureAndNextReplaysIt', 0, () => {
      const engine = engineWith(4, 9);
      engine.start(0, true, RepeatMode.ALL);
      const first = engine.next(false);
      const second = engine.next(false);
      expect(engine.previous()).assertEqual(first);
      // Walking forward again pops the parked track first (LIFO).
      expect(engine.next(false)).assertEqual(second);
    });

    it('playAtRecordsHistoryClearsFutureAndRemovesFromBag', 0, () => {
      const engine = engineWith(4, 5);
      engine.start(0, true, RepeatMode.ALL);
      const target = engine.next(false);
      engine.playAt(0);
      expect(engine.getCurrentQueueIndex()).assertEqual(0);
      expect(engine.getHistory()[engine.getHistory().length - 1]).assertEqual(target);
      expect(engine.getFuture().length).assertEqual(0);
      expect(engine.getBag().indexOf(0)).assertEqual(-1);
    });

    it('bagExhaustedUnderRepeatAllRebuildsAroundCurrent', 0, () => {
      const engine = engineWith(2, 3);
      engine.start(0, true, RepeatMode.ALL);
      const first = engine.next(false);
      expect(first).assertEqual(1);
      const second = engine.next(false);
      // Bag is now empty; repeat-all rebuilds and can pick 0.
      expect(second).assertEqual(0);
    });

    it('singleTrackQueueNextReplaysCurrent', 0, () => {
      const engine = engineWith(1, 3);
      engine.start(0, true, RepeatMode.ALL);
      expect(engine.next(true)).assertEqual(0);
    });
  });

  describe('QueueEnginePolicy', () => {
    it('cyclesRepeatModeInAndroidOrder', 0, () => {
      const engine = engineWith(2, 1);
      engine.setRepeatMode(RepeatMode.OFF);
      expect(engine.cycleRepeatMode()).assertEqual(RepeatMode.ALL);
      expect(engine.cycleRepeatMode()).assertEqual(RepeatMode.ONE);
      expect(engine.cycleRepeatMode()).assertEqual(RepeatMode.OFF);
    });

    it('trackEndReplaysUnderRepeatOne', 0, () => {
      const engine = engineWith(2, 1);
      engine.start(0, false, RepeatMode.ONE);
      expect(engine.onTrackEnded()).assertEqual(TrackEndAction.REPLAY);
    });

    it('trackEndAdvancesUnderRepeatAll', 0, () => {
      const engine = engineWith(2, 1);
      engine.start(1, false, RepeatMode.ALL);
      expect(engine.onTrackEnded()).assertEqual(TrackEndAction.ADVANCE);
    });

    it('trackEndStopsWhenExhaustedUnderRepeatOff', 0, () => {
      const engine = engineWith(2, 1);
      engine.start(0, false, RepeatMode.OFF);
      expect(engine.onTrackEnded()).assertEqual(TrackEndAction.ADVANCE);
      engine.next(false);
      expect(engine.onTrackEnded()).assertEqual(TrackEndAction.STOP);
    });
  });

  describe('QueueEngineSnapshot', () => {
    it('roundTripsFullStateIncludingRandomState', 0, () => {
      const engine = engineWith(5, 123);
      engine.start(2, true, RepeatMode.OFF);
      engine.next(false);
      engine.next(false);
      engine.previous();
      const restored = QueueEngine.fromJson(engine.toJson(), 5);
      expect(restored !== null).assertTrue();
      expectList(restored!.getBag(), engine.getBag(), 'bag');
      expectList(restored!.getHistory(), engine.getHistory(), 'history');
      expectList(restored!.getFuture(), engine.getFuture(), 'future');
      expect(restored!.getCurrentQueueIndex()).assertEqual(engine.getCurrentQueueIndex());
      expect(restored!.shuffle).assertTrue();
      expect(restored!.repeatMode).assertEqual(RepeatMode.OFF);
      // Continuation picks identical tracks because the random state traveled.
      expect(restored!.next(false)).assertEqual(engine.next(false));
    });

    it('returnsNullForCorruptedSnapshot', 0, () => {
      expect(QueueEngine.fromJson('not json {', 3)).assertNull();
    });
  });

  describe('QueueEngineReverseReset', () => {
    it('reverseMirrorsCurrentIndexAndSequentialMovement', 0, () => {
      const engine = engineWith(5, 1);
      engine.start(1, false, RepeatMode.OFF);
      engine.reverse();
      // The track at index 1 remaps to 3 in the flipped order, then next/prev
      // walk the reversed sequence from there.
      expect(engine.getCurrentQueueIndex()).assertEqual(3);
      expect(engine.next(false)).assertEqual(4);
      expect(engine.previous()).assertEqual(3);
    });

    it('reverseRemapsEveryShuffleStructureWithoutDuplicates', 0, () => {
      const engine = engineWith(6, 42);
      engine.start(0, true, RepeatMode.ALL);
      engine.next(false);
      engine.next(false);
      engine.previous();
      const bag = engine.getBag();
      const history = engine.getHistory();
      const future = engine.getFuture();
      engine.reverse();
      const flip = (value: number): number => 5 - value;
      expectList(engine.getBag(), bag.map(flip), 'bag');
      expectList(engine.getHistory(), history.map(flip), 'history');
      expectList(engine.getFuture(), future.map(flip), 'future');
      // The remap keeps the invariant that the current track is out of the bag.
      expect(engine.getBag().indexOf(engine.getCurrentQueueIndex())).assertEqual(-1);
    });

    it('reverseIsNoOpForSmallQueues', 0, () => {
      const single = engineWith(1, 1);
      single.start(0, false, RepeatMode.OFF);
      single.reverse();
      expect(single.getCurrentQueueIndex()).assertEqual(0);
      const empty = engineWith(0, 1);
      empty.reverse();
      expect(empty.getCurrentQueueIndex()).assertEqual(-1);
    });

    it('resetLeavesTheEngineInertUntilNextStart', 0, () => {
      const engine = engineWith(4, 7);
      engine.start(0, true, RepeatMode.ALL);
      engine.next(false);
      engine.reset();
      expect(engine.getCurrentQueueIndex()).assertEqual(-1);
      expectList(engine.getBag(), [], 'bag');
      expectList(engine.getHistory(), [], 'history');
      expectList(engine.getFuture(), [], 'future');
      expect(engine.hasNext(false)).assertFalse();
      expect(engine.next(true)).assertEqual(-1);
      expect(engine.previous()).assertEqual(-1);
    });
  });

  describe('QueueEngineEdits', () => {
    it('applyInsertNextParksNewSongAtopFutureAndShiftsBag', 0, () => {
      // [A,B,C,D] 播 B(1)，随机袋含其余三首；新曲 E 插到 2（下一首播放）。
      const engine = engineWith(4, 11);
      engine.start(1, true, RepeatMode.ALL);
      const shifted = engine.getBag().map((v: number): number => v >= 2 ? v + 1 : v);
      engine.applyQueueEdit(-1, 2, 2, 5, 1, false);
      expectList(engine.getBag(), shifted, 'bag');
      expectList(engine.getFuture(), [2], 'future');
      expect(engine.getCurrentQueueIndex()).assertEqual(1);
      expect(engine.getQueueSize()).assertEqual(5);
      // future 栈顶就是 E：下一首严格播它。
      expect(engine.next(false)).assertEqual(2);
    });

    it('applyInsertNextForExistingBagSongDrainsItIntoFuture', 0, () => {
      // [A,B,C] 播 A(0)；把 bag 里任一首「下一首播放」（existing>current，
      // insertIndex=1）：它必须离开 bag、压入 future 栈顶。
      const engine = engineWith(3, 42);
      engine.start(0, true, RepeatMode.ALL);
      const target = engine.getBag()[0];
      engine.applyQueueEdit(target, 1, 1, 3, 0, false);
      expect(engine.getBag().indexOf(1)).assertEqual(-1);
      expectList(engine.getFuture(), [1], 'future');
      expect(engine.next(false)).assertEqual(1);
    });

    it('applyMoveKeepsSequentialCurrentOnSameSong', 0, () => {
      // 顺序模式拖拽 B(1)->3：C 从 2 移到 1，next 继续播 D。
      const engine = engineWith(4, 5);
      engine.start(2, false, RepeatMode.ALL);
      engine.applyQueueEdit(1, 3, -1, 4, QueueEngine.currentIndexAfterMove(4, 2, 1, 3), false);
      expect(engine.getCurrentQueueIndex()).assertEqual(1);
      expect(engine.getQueueSize()).assertEqual(4);
      expect(engine.next(false)).assertEqual(2);
    });

    it('applyMoveUnderShuffleShiftsBagByRemovalThenInsertion', 0, () => {
      const engine = engineWith(5, 9);
      engine.start(0, true, RepeatMode.ALL);
      const expected = engine.getBag()
        .filter((v: number): boolean => v !== 4)
        .map((v: number): number => v + 1);
      engine.applyQueueEdit(4, 1, -1, 5, QueueEngine.currentIndexAfterMove(5, 0, 4, 1), false);
      expectList(engine.getBag(), expected, 'bag');
      expect(engine.getCurrentQueueIndex()).assertEqual(0);
    });

    it('applyRemovalUnderShuffleDropsAndShiftsBag', 0, () => {
      const engine = engineWith(4, 21);
      engine.start(0, true, RepeatMode.ALL);
      engine.next(false);
      const victim = engine.getBag()[0];
      const newCurrent = QueueEngine.currentIndexAfterRemoval(4, engine.getCurrentQueueIndex(), victim);
      const bagAfter = engine.getBag()
        .filter((v: number): boolean => v !== victim)
        .map((v: number): number => v > victim ? v - 1 : v);
      engine.applyQueueEdit(victim, -1, -1, 3, newCurrent, false);
      expectList(engine.getBag(), bagAfter, 'bag');
      expect(engine.getCurrentQueueIndex()).assertEqual(newCurrent);
      expect(engine.getQueueSize()).assertEqual(3);
    });

    it('applyEndAddRebuildsBagExcludingCurrentAndClearsStacks', 0, () => {
      // 加入队列末尾（上游 addToQueueEndImpl：随机模式整袋重建）。
      const engine = engineWith(3, 17);
      engine.start(0, true, RepeatMode.ALL);
      engine.next(false);
      const current = engine.getCurrentQueueIndex();
      engine.applyQueueEdit(-1, -1, -1, 4, current, true);
      expect(engine.getQueueSize()).assertEqual(4);
      expect(engine.getCurrentQueueIndex()).assertEqual(current);
      expectList(engine.getHistory(), [], 'history');
      expectList(engine.getFuture(), [], 'future');
      const bag = engine.getBag();
      expect(bag.length).assertEqual(3);
      expect(bag.indexOf(current)).assertEqual(-1);
      expect(bag.indexOf(3) >= 0).assertTrue();
    });

    it('applyEditWithoutShuffleOnlyResizesAndRepoints', 0, () => {
      const engine = engineWith(4, 3);
      engine.start(2, false, RepeatMode.ALL);
      engine.applyQueueEdit(1, 3, -1, 4, QueueEngine.currentIndexAfterMove(4, 2, 1, 3), false);
      expect(engine.getCurrentQueueIndex()).assertEqual(1);
      expectList(engine.getBag(), [], 'bag');
    });

    it('currentIndexAfterRemovalCoversUpstreamCases', 0, () => {
      expect(QueueEngine.currentIndexAfterRemoval(4, 2, 2)).assertEqual(2);
      expect(QueueEngine.currentIndexAfterRemoval(4, 3, 3)).assertEqual(2);
      expect(QueueEngine.currentIndexAfterRemoval(4, 2, 0)).assertEqual(1);
      expect(QueueEngine.currentIndexAfterRemoval(4, 0, 2)).assertEqual(0);
      expect(QueueEngine.currentIndexAfterRemoval(1, 0, 0)).assertEqual(-1);
      expect(QueueEngine.currentIndexAfterRemoval(4, 2, 9)).assertEqual(2);
      expect(QueueEngine.currentIndexAfterRemoval(4, -1, 1)).assertEqual(-1);
    });
  });

  describe('PlaylistStartIndex', () => {
    it('emptyPlaylistResolvesToMinusOne', 0, () => {
      expect(resolvePlaylistPlaybackStartIndex(0, false, 0)).assertEqual(-1);
      expect(resolvePlaylistPlaybackStartIndex(0, true, 5)).assertEqual(-1);
    });

    it('sequentialPlayAlwaysStartsAtZero', 0, () => {
      expect(resolvePlaylistPlaybackStartIndex(10, false, 0)).assertEqual(0);
      expect(resolvePlaylistPlaybackStartIndex(10, false, 7)).assertEqual(0);
    });

    it('shuffleUsesTheRandomPickWhenInRange', 0, () => {
      expect(resolvePlaylistPlaybackStartIndex(10, true, 0)).assertEqual(0);
      expect(resolvePlaylistPlaybackStartIndex(10, true, 3)).assertEqual(3);
      expect(resolvePlaylistPlaybackStartIndex(10, true, 9)).assertEqual(9);
    });

    it('shuffleClampsOutOfRangePicks', 0, () => {
      expect(resolvePlaylistPlaybackStartIndex(10, true, -1)).assertEqual(0);
      expect(resolvePlaylistPlaybackStartIndex(10, true, 10)).assertEqual(9);
      expect(resolvePlaylistPlaybackStartIndex(1, true, 42)).assertEqual(0);
    });
  });
}
