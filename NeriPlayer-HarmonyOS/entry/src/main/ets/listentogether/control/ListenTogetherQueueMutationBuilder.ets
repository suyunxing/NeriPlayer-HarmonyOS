// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/control/ListenTogetherQueueMutationBuilder.kt
 * (upstream #359 / squashed 3cfd7037): diff a target queue against the base
 * room queue into a V2 mutation (remove/move/insert/reorder operations on
 * (stableKey, occurrence) references).
 *
 * The plan deliberately degrades: too many operations, or any blank stableKey,
 * means the caller must fall back to shipping the full snapshot instead.
 */
import {
  LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS,
  ListenTogetherQueueMutation,
  ListenTogetherQueueOperation,
  ListenTogetherQueueReference,
  listenTogetherQueueReferenceEquals
} from '../protocol/ListenTogetherQueueMutation';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherTrack } from '../protocol/ListenTogetherTrack';

export class ListenTogetherQueueMutationPlan {
  mutation: ListenTogetherQueueMutation = new ListenTogetherQueueMutation();
  requiresSnapshotFallback: boolean = false;
}

class QueueTargetEntry {
  readonly track: ListenTogetherTrack;
  readonly reference: ListenTogetherQueueReference | null;

  constructor(track: ListenTogetherTrack, reference: ListenTogetherQueueReference | null) {
    this.track = track;
    this.reference = reference;
  }
}

function referencesForQueue(queue: ListenTogetherTrack[]): ListenTogetherQueueReference[] {
  const nextOccurrence = new Map<string, number>();
  const references: ListenTogetherQueueReference[] = [];
  for (const track of queue) {
    const occurrence = nextOccurrence.get(track.stableKey) ?? 0;
    nextOccurrence.set(track.stableKey, occurrence + 1);
    references.push(new ListenTogetherQueueReference(track.stableKey, occurrence));
  }
  return references;
}

function referenceInList(reference: ListenTogetherQueueReference, list: ListenTogetherQueueReference[]): boolean {
  for (const candidate of list) {
    if (listenTogetherQueueReferenceEquals(candidate, reference)) {
      return true;
    }
  }
  return false;
}

function removeOperation(reference: ListenTogetherQueueReference): ListenTogetherQueueOperation {
  const operation = new ListenTogetherQueueOperation();
  operation.type = 'remove';
  operation.target = reference;
  return operation;
}

function buildMoveOperations(
  source: ListenTogetherQueueReference[],
  target: ListenTogetherQueueReference[]
): ListenTogetherQueueOperation[] {
  if (referencesEqualList(source, target)) {
    return [];
  }
  const working = source.slice();
  const operations: ListenTogetherQueueOperation[] = [];
  while (!referencesEqualList(working, target) &&
    operations.length <= LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS) {
    let mismatchIndex = -1;
    for (let index = 0; index < working.length; index++) {
      const targetRef = index < target.length ? target[index] : null;
      if (!listenTogetherQueueReferenceEquals(working[index], targetRef)) {
        mismatchIndex = index;
        break;
      }
    }
    if (mismatchIndex < 0) {
      break;
    }
    const sourceItem = working[mismatchIndex];
    let targetIndex = -1;
    for (let index = 0; index < target.length; index++) {
      if (listenTogetherQueueReferenceEquals(target[index], sourceItem)) {
        targetIndex = index;
        break;
      }
    }
    if (targetIndex > mismatchIndex && tryMoveMatches(working, mismatchIndex, targetIndex, target)) {
      operations.push(moveOperation(working, mismatchIndex, targetIndex));
      continue;
    }
    const targetItem = mismatchIndex < target.length ? target[mismatchIndex] : null;
    let sourceIndex = -1;
    if (targetItem !== null) {
      for (let index = 0; index < working.length; index++) {
        if (listenTogetherQueueReferenceEquals(working[index], targetItem)) {
          sourceIndex = index;
          break;
        }
      }
    }
    if (sourceIndex > mismatchIndex && tryMoveMatches(working, sourceIndex, mismatchIndex, target)) {
      operations.push(moveOperation(working, sourceIndex, mismatchIndex));
      continue;
    }
    if (sourceIndex < 0) {
      break;
    }
    operations.push(moveOperation(working, sourceIndex, mismatchIndex));
  }
  return operations;
}

function referencesEqualList(
  a: ListenTogetherQueueReference[],
  b: ListenTogetherQueueReference[]
): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let index = 0; index < a.length; index++) {
    if (!listenTogetherQueueReferenceEquals(a[index], b[index])) {
      return false;
    }
  }
  return true;
}

/** Upstream `tryMoveMatches`: does moving from→to produce the target exactly? */
function tryMoveMatches(
  source: ListenTogetherQueueReference[],
  fromIndex: number,
  toIndex: number,
  target: ListenTogetherQueueReference[]
): boolean {
  const moved = source.slice();
  const removed = moved.splice(fromIndex, 1)[0];
  moved.splice(toIndex, 0, removed);
  return referencesEqualList(moved, target);
}

function moveOperation(
  working: ListenTogetherQueueReference[],
  fromIndex: number,
  toIndex: number
): ListenTogetherQueueOperation {
  const target = working.splice(fromIndex, 1)[0];
  const anchor = toIndex < working.length ? working[toIndex] : null;
  working.splice(toIndex, 0, target);
  const operation = new ListenTogetherQueueOperation();
  operation.type = 'move';
  operation.target = target;
  operation.anchor = anchor;
  operation.placement = anchor === null ? 'append' : 'before';
  return operation;
}

function buildInsertOperations(targetEntries: QueueTargetEntry[]): ListenTogetherQueueOperation[] {
  const operations: ListenTogetherQueueOperation[] = [];
  let index = 0;
  while (index < targetEntries.length) {
    if (targetEntries[index].reference !== null) {
      index++;
      continue;
    }
    let endExclusive = targetEntries.length;
    for (let candidate = index + 1; candidate < targetEntries.length; candidate++) {
      if (targetEntries[candidate].reference !== null) {
        endExclusive = candidate;
        break;
      }
    }
    const nextReference = endExclusive < targetEntries.length ? targetEntries[endExclusive].reference : null;
    if (nextReference !== null) {
      for (let entryIndex = endExclusive - 1; entryIndex >= index; entryIndex--) {
        const operation = new ListenTogetherQueueOperation();
        operation.type = 'insert';
        operation.anchor = nextReference;
        operation.placement = 'before';
        operation.track = targetEntries[entryIndex].track;
        operations.push(operation);
      }
    } else {
      for (let entryIndex = index; entryIndex < endExclusive; entryIndex++) {
        const operation = new ListenTogetherQueueOperation();
        operation.type = 'insert';
        operation.placement = 'append';
        operation.track = targetEntries[entryIndex].track;
        operations.push(operation);
      }
    }
    index = endExclusive;
  }
  return operations;
}

export function buildListenTogetherQueueMutationPlan(
  baseState: ListenTogetherRoomState,
  targetQueue: ListenTogetherTrack[],
  targetCurrentIndex: number
): ListenTogetherQueueMutationPlan {
  const plan = new ListenTogetherQueueMutationPlan();
  const baseReferences = referencesForQueue(baseState.queue);
  let hasBlank = false;
  for (const reference of baseReferences) {
    if (reference.stableKey.length === 0) {
      hasBlank = true;
      break;
    }
  }
  if (!hasBlank) {
    for (const track of targetQueue) {
      if (track.stableKey.length === 0) {
        hasBlank = true;
        break;
      }
    }
  }
  if (hasBlank) {
    plan.mutation.baseRoomVersion = Math.max(baseState.version, 0);
    plan.mutation.operations = [];
    plan.requiresSnapshotFallback = true;
    return plan;
  }

  const baseCounts = new Map<string, number>();
  for (const reference of baseReferences) {
    baseCounts.set(reference.stableKey, (baseCounts.get(reference.stableKey) ?? 0) + 1);
  }
  const nextTargetOccurrence = new Map<string, number>();
  const targetEntries: QueueTargetEntry[] = [];
  for (const track of targetQueue) {
    const occurrence = nextTargetOccurrence.get(track.stableKey) ?? 0;
    nextTargetOccurrence.set(track.stableKey, occurrence + 1);
    const withinBase = occurrence < (baseCounts.get(track.stableKey) ?? 0);
    targetEntries.push(new QueueTargetEntry(
      track,
      withinBase ? new ListenTogetherQueueReference(track.stableKey, occurrence) : null
    ));
  }
  const targetReferences: ListenTogetherQueueReference[] = [];
  for (const entry of targetEntries) {
    if (entry.reference !== null) {
      targetReferences.push(entry.reference);
    }
  }
  const removedReferences: ListenTogetherQueueReference[] = [];
  const retainedReferences: ListenTogetherQueueReference[] = [];
  for (const reference of baseReferences) {
    if (referenceInList(reference, targetReferences)) {
      retainedReferences.push(reference);
    } else {
      removedReferences.push(reference);
    }
  }
  const desiredReferences = targetReferences;

  const removeOperations: ListenTogetherQueueOperation[] = [];
  if (removedReferences.length > LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS) {
    const compressed = new ListenTogetherQueueOperation();
    compressed.type = 'remove_many';
    compressed.order = removedReferences.slice();
    removeOperations.push(compressed);
  } else {
    for (const reference of removedReferences) {
      removeOperations.push(removeOperation(reference));
    }
  }
  const moveOperations = buildMoveOperations(retainedReferences, desiredReferences);
  const insertOperations = buildInsertOperations(targetEntries);
  const baseOperationCount = removeOperations.length + insertOperations.length;
  let orderOperation: ListenTogetherQueueOperation | null = null;
  if (moveOperations.length > LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS - baseOperationCount) {
    orderOperation = new ListenTogetherQueueOperation();
    orderOperation.type = 'reorder';
    orderOperation.order = desiredReferences.slice();
  }
  const orderingOperations = orderOperation !== null ? [orderOperation] : moveOperations;
  const operations: ListenTogetherQueueOperation[] = [];
  for (const operation of removeOperations) {
    operations.push(operation);
  }
  for (const operation of orderingOperations) {
    operations.push(operation);
  }
  for (const operation of insertOperations) {
    operations.push(operation);
  }
  const currentEntry = targetCurrentIndex >= 0 && targetCurrentIndex < targetEntries.length
    ? targetEntries[targetCurrentIndex]
    : null;
  plan.mutation.baseRoomVersion = Math.max(baseState.version, 0);
  plan.mutation.operations = operations;
  plan.mutation.targetCurrent = currentEntry === null ? null : currentEntry.reference;
  plan.requiresSnapshotFallback =
    baseOperationCount > LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS ||
    operations.length > LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS;
  return plan;
}
