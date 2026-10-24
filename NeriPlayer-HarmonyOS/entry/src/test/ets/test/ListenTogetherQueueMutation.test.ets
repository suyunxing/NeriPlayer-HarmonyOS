import { describe, it, expect } from '@ohos/hypium';
import {
  LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS,
  ListenTogetherQueueMutation,
  ListenTogetherQueueOperation,
  ListenTogetherQueueReference,
  listenTogetherQueueReferenceEquals,
  listenTogetherQueueMutationFromRecord,
  listenTogetherQueueMutationToRecord
} from '../../../main/ets/listentogether/protocol/ListenTogetherQueueMutation';
import {
  buildListenTogetherQueueMutationPlan
} from '../../../main/ets/listentogether/control/ListenTogetherQueueMutationBuilder';
import {
  applyListenTogetherQueueMutation
} from '../../../main/ets/listentogether/control/ListenTogetherQueueMutationApplier';
import {
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';

function track(key: string): ListenTogetherTrack {
  return createListenTogetherTrack(key, 'netease', key, `Song ${key}`, 'Artist');
}

function tracksOf(keys: string[]): ListenTogetherTrack[] {
  return keys.map((key: string): ListenTogetherTrack => track(key));
}

function stableKeys(queue: ListenTogetherTrack[]): string[] {
  return queue.map((item: ListenTogetherTrack): string => item.stableKey);
}

function roomStateOf(queue: ListenTogetherTrack[], version: number): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ROOM1', version);
  state.queue = queue;
  state.currentIndex = 0;
  return state;
}

export default function listenTogetherQueueMutationTest(): void {
  describe('ListenTogetherQueueMutation', () => {
    it('roundTripsEveryOperationKindThroughTheWireCodec', 0, () => {
      const mutation = new ListenTogetherQueueMutation();
      mutation.baseRoomVersion = 12;

      const remove = new ListenTogetherQueueOperation();
      remove.type = 'remove';
      remove.target = new ListenTogetherQueueReference('kA', 0);

      const move = new ListenTogetherQueueOperation();
      move.type = 'move';
      move.target = new ListenTogetherQueueReference('kB', 1);
      move.anchor = new ListenTogetherQueueReference('kA', 0);
      move.placement = 'before';

      const insert = new ListenTogetherQueueOperation();
      insert.type = 'insert';
      insert.anchor = new ListenTogetherQueueReference('kB', 0);
      insert.placement = 'before';
      insert.track = track('kNew');

      const removeMany = new ListenTogetherQueueOperation();
      removeMany.type = 'remove_many';
      removeMany.order = [new ListenTogetherQueueReference('kC', 0),
        new ListenTogetherQueueReference('kD', 2)];

      const reorder = new ListenTogetherQueueOperation();
      reorder.type = 'reorder';
      reorder.order = [new ListenTogetherQueueReference('kB', 0),
        new ListenTogetherQueueReference('kA', 0)];

      mutation.operations = [remove, move, insert, removeMany, reorder];
      mutation.targetCurrent = new ListenTogetherQueueReference('kNew', 0);

      const decoded = listenTogetherQueueMutationFromRecord(
        listenTogetherQueueMutationToRecord(mutation));
      expect(decoded.baseRoomVersion).assertEqual(12);
      expect(decoded.operations.length).assertEqual(5);
      expect(decoded.operations[0].type).assertEqual('remove');
      expect(listenTogetherQueueReferenceEquals(
        decoded.operations[0].target, new ListenTogetherQueueReference('kA', 0))).assertTrue();
      expect(decoded.operations[1].type).assertEqual('move');
      expect(decoded.operations[1].placement).assertEqual('before');
      expect(listenTogetherQueueReferenceEquals(
        decoded.operations[1].anchor, new ListenTogetherQueueReference('kA', 0))).assertTrue();
      expect(decoded.operations[2].type).assertEqual('insert');
      expect(decoded.operations[2].track?.stableKey).assertEqual('kNew');
      expect(decoded.operations[3].type).assertEqual('remove_many');
      const removeManyOrder = decoded.operations[3].order;
      expect(removeManyOrder === null ? 0 : removeManyOrder.length).assertEqual(2);
      expect(removeManyOrder === null ? -1 : removeManyOrder[1].occurrence).assertEqual(2);
      expect(decoded.operations[4].type).assertEqual('reorder');
      expect(decoded.operations[4].order?.length).assertEqual(2);
      expect(listenTogetherQueueReferenceEquals(
        decoded.targetCurrent, new ListenTogetherQueueReference('kNew', 0))).assertTrue();
    });

    it('decodesAnEmptyPayloadToDefaults', 0, () => {
      const decoded = listenTogetherQueueMutationFromRecord({});
      expect(decoded.baseRoomVersion).assertEqual(0);
      expect(decoded.operations.length).assertEqual(0);
      expect(decoded.targetCurrent).assertNull();
    });

    it('comparesReferencesByStableKeyAndOccurrence', 0, () => {
      expect(listenTogetherQueueReferenceEquals(
        new ListenTogetherQueueReference('a', 0), new ListenTogetherQueueReference('a', 0))).assertTrue();
      expect(listenTogetherQueueReferenceEquals(
        new ListenTogetherQueueReference('a', 0), new ListenTogetherQueueReference('a', 1))).assertFalse();
      expect(listenTogetherQueueReferenceEquals(null, null)).assertTrue();
      expect(listenTogetherQueueReferenceEquals(
        new ListenTogetherQueueReference('a', 0), null)).assertFalse();
    });
  });

  describe('ListenTogetherQueueMutationBuilder', () => {
    it('emitsNoOperationsForAnIdenticalQueue', 0, () => {
      const base = tracksOf(['a', 'b', 'c']);
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 4), tracksOf(['a', 'b', 'c']), 1);
      expect(plan.requiresSnapshotFallback).assertFalse();
      expect(plan.mutation.operations.length).assertEqual(0);
      expect(plan.mutation.baseRoomVersion).assertEqual(4);
      expect(listenTogetherQueueReferenceEquals(
        plan.mutation.targetCurrent, new ListenTogetherQueueReference('b', 0))).assertTrue();
    });

    it('emitsASingleRemoveForOneRemovedTrack', 0, () => {
      const base = tracksOf(['a', 'b', 'c']);
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 3), tracksOf(['a', 'c']), 0);
      expect(plan.requiresSnapshotFallback).assertFalse();
      expect(plan.mutation.operations.length).assertEqual(1);
      expect(plan.mutation.operations[0].type).assertEqual('remove');
      expect(listenTogetherQueueReferenceEquals(
        plan.mutation.operations[0].target, new ListenTogetherQueueReference('b', 0))).assertTrue();
    });

    it('compressesMassRemovalsIntoRemoveMany', 0, () => {
      const keys: string[] = [];
      for (let index = 0; index < 70; index++) {
        keys.push(`k${index}`);
      }
      const base = tracksOf(keys);
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 2), tracksOf(['fresh']), 0);
      expect(plan.requiresSnapshotFallback).assertFalse();
      expect(plan.mutation.operations.length).assertEqual(2);
      expect(plan.mutation.operations[0].type).assertEqual('remove_many');
      expect(plan.mutation.operations[0].order?.length).assertEqual(70);
      expect(plan.mutation.operations[1].type).assertEqual('insert');
      expect(plan.mutation.operations[1].placement).assertEqual('append');
    });

    it('movesATrackWithASingleBeforeOperation', 0, () => {
      // [a, b, c] -> [b, a, c] is exactly one move of `a` before `b`.
      const base = tracksOf(['a', 'b', 'c']);
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 1), tracksOf(['b', 'a', 'c']), 0);
      expect(plan.requiresSnapshotFallback).assertFalse();
      expect(plan.mutation.operations.length).assertEqual(1);
      const move = plan.mutation.operations[0];
      expect(move.type).assertEqual('move');
      expect(move.placement).assertEqual('before');
      expect(listenTogetherQueueReferenceEquals(
        move.target, new ListenTogetherQueueReference('a', 0))).assertTrue();
      expect(listenTogetherQueueReferenceEquals(
        move.anchor, new ListenTogetherQueueReference('b', 0))).assertTrue();
    });

    it('insertsBeforeTheNextAnchorOrAppendsAtTheEnd', 0, () => {
      const base = tracksOf(['a', 'c']);
      const middle = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 1), tracksOf(['a', 'b', 'c']), 0);
      expect(middle.mutation.operations.length).assertEqual(1);
      expect(middle.mutation.operations[0].type).assertEqual('insert');
      expect(middle.mutation.operations[0].placement).assertEqual('before');
      expect(listenTogetherQueueReferenceEquals(
        middle.mutation.operations[0].anchor, new ListenTogetherQueueReference('c', 0))).assertTrue();

      const tail = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 1), tracksOf(['a', 'c', 'z']), 0);
      expect(tail.mutation.operations.length).assertEqual(1);
      expect(tail.mutation.operations[0].type).assertEqual('insert');
      expect(tail.mutation.operations[0].placement).assertEqual('append');
    });

    it('fallsBackToASnapshotOnBlankStableKeys', 0, () => {
      const blank = track('');
      const base = tracksOf(['a', 'b']);
      base.push(blank);
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 1), tracksOf(['a', 'b']), 0);
      expect(plan.requiresSnapshotFallback).assertTrue();
      expect(plan.mutation.operations.length).assertEqual(0);
      expect(plan.mutation.baseRoomVersion).assertEqual(1);
    });

    it('compressesUnboundedReorderingIntoOneReorderOperation', 0, () => {
      const keys: string[] = [];
      for (let index = 0; index < 70; index++) {
        keys.push(`k${index}`);
      }
      const reversed = keys.slice().reverse();
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(tracksOf(keys), 1), tracksOf(reversed), 0);
      expect(plan.requiresSnapshotFallback).assertFalse();
      expect(plan.mutation.operations.length).assertEqual(1);
      expect(plan.mutation.operations[0].type).assertEqual('reorder');
      expect(plan.mutation.operations[0].order?.length).assertEqual(70);
    });

    it('disambiguatesDuplicateTracksByOccurrence', 0, () => {
      // Two copies of `a`: removing the second one targets occurrence 1.
      const base = [track('a'), track('b'), track('a')];
      const plan = buildListenTogetherQueueMutationPlan(
        roomStateOf(base, 1), [track('a'), track('b')], 1);
      expect(plan.mutation.operations.length).assertEqual(1);
      expect(plan.mutation.operations[0].type).assertEqual('remove');
      expect(listenTogetherQueueReferenceEquals(
        plan.mutation.operations[0].target, new ListenTogetherQueueReference('a', 1))).assertTrue();
    });
  });

  describe('ListenTogetherQueueMutationApplier', () => {
    it('removesTheCurrentTrackAndReportsItRemoved', 0, () => {
      const queue = tracksOf(['a', 'b', 'c']);
      const mutation = new ListenTogetherQueueMutation();
      const remove = new ListenTogetherQueueOperation();
      remove.type = 'remove';
      remove.target = new ListenTogetherQueueReference('b', 0);
      mutation.operations = [remove];

      const result = applyListenTogetherQueueMutation(queue, 1, mutation);
      expect(stableKeys(result.queue)).assertEqual(['a', 'c']);
      expect(result.currentRemoved).assertTrue();
      expect(result.currentIndex).assertEqual(1);
    });

    it('keepsTheCurrentTrackWhenOnlyOthersMove', 0, () => {
      const queue = tracksOf(['a', 'b', 'c']);
      const mutation = new ListenTogetherQueueMutation();
      const move = new ListenTogetherQueueOperation();
      move.type = 'move';
      move.target = new ListenTogetherQueueReference('c', 0);
      move.anchor = new ListenTogetherQueueReference('a', 0);
      move.placement = 'before';
      mutation.operations = [move];

      const result = applyListenTogetherQueueMutation(queue, 1, mutation);
      expect(stableKeys(result.queue)).assertEqual(['c', 'a', 'b']);
      expect(result.currentRemoved).assertFalse();
      expect(result.currentIndex).assertEqual(1);
    });

    it('landsTheCurrentIndexOnTargetCurrent', 0, () => {
      const queue = tracksOf(['a', 'b', 'c']);
      const mutation = new ListenTogetherQueueMutation();
      mutation.targetCurrent = new ListenTogetherQueueReference('c', 0);
      // Remove the previous current so only targetCurrent remains as candidate.
      const remove = new ListenTogetherQueueOperation();
      remove.type = 'remove';
      remove.target = new ListenTogetherQueueReference('a', 0);
      mutation.operations = [remove];

      const result = applyListenTogetherQueueMutation(queue, 0, mutation);
      expect(stableKeys(result.queue)).assertEqual(['b', 'c']);
      expect(result.targetCurrentIndex).assertEqual(1);
      expect(result.currentIndex).assertEqual(1);
      expect(result.currentRemoved).assertTrue();
    });

    it('insertsBeforeTheAnchorOrAppends', 0, () => {
      const queue = tracksOf(['a', 'c']);
      const mutation = new ListenTogetherQueueMutation();
      const insert = new ListenTogetherQueueOperation();
      insert.type = 'insert';
      insert.anchor = new ListenTogetherQueueReference('c', 0);
      insert.placement = 'before';
      insert.track = track('b');
      const append = new ListenTogetherQueueOperation();
      append.type = 'insert';
      append.placement = 'append';
      append.track = track('z');
      mutation.operations = [insert, append];

      const result = applyListenTogetherQueueMutation(queue, 0, mutation);
      expect(stableKeys(result.queue)).assertEqual(['a', 'b', 'c', 'z']);
    });

    it('reordersOnlyTheReferencedSlots', 0, () => {
      const queue = tracksOf(['a', 'b', 'c', 'd']);
      const mutation = new ListenTogetherQueueMutation();
      const reorder = new ListenTogetherQueueOperation();
      reorder.type = 'reorder';
      reorder.order = [new ListenTogetherQueueReference('d', 0),
        new ListenTogetherQueueReference('a', 0)];
      mutation.operations = [reorder];

      const result = applyListenTogetherQueueMutation(queue, 0, mutation);
      // Slots 0 and 3 swap; b/c stay in place.
      expect(stableKeys(result.queue)).assertEqual(['d', 'b', 'c', 'a']);
    });

    it('returnsAnEmptyQueueWhenEverythingIsRemoved', 0, () => {
      const queue = tracksOf(['a', 'b']);
      const mutation = new ListenTogetherQueueMutation();
      const removeMany = new ListenTogetherQueueOperation();
      removeMany.type = 'remove_many';
      removeMany.order = [new ListenTogetherQueueReference('a', 0),
        new ListenTogetherQueueReference('b', 0)];
      mutation.operations = [removeMany];

      const result = applyListenTogetherQueueMutation(queue, 0, mutation);
      expect(result.queue.length).assertEqual(0);
      expect(result.currentIndex).assertEqual(-1);
      expect(result.currentRemoved).assertTrue();
    });

    it('leavesTheQueueUntouchedBeyondTheOperationBudget', 0, () => {
      const queue = tracksOf(['a', 'b']);
      const mutation = new ListenTogetherQueueMutation();
      const operations: ListenTogetherQueueOperation[] = [];
      for (let index = 0; index <= LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS; index++) {
        const remove = new ListenTogetherQueueOperation();
        remove.type = 'remove';
        remove.target = new ListenTogetherQueueReference('a', 0);
        operations.push(remove);
      }
      mutation.operations = operations;

      const result = applyListenTogetherQueueMutation(queue, 0, mutation);
      expect(stableKeys(result.queue)).assertEqual(['a', 'b']);
      expect(result.currentRemoved).assertFalse();
    });

    it('roundTripsABuiltPlanIntoTheTargetQueue', 0, () => {
      const base = tracksOf(['a', 'b', 'c', 'd']);
      const target = tracksOf(['c', 'b', 'e', 'a']);
      const baseState = roomStateOf(base, 6);
      const plan = buildListenTogetherQueueMutationPlan(baseState, target, 2);
      expect(plan.requiresSnapshotFallback).assertFalse();

      const result = applyListenTogetherQueueMutation(base, 0, plan.mutation, 'e');
      expect(stableKeys(result.queue)).assertEqual(['c', 'b', 'e', 'a']);
      // The previous current (`a`) survives, so it stays current at its new
      // slot even though the requested current sits at index 2.
      expect(result.currentIndex).assertEqual(3);
    });
  });
}
