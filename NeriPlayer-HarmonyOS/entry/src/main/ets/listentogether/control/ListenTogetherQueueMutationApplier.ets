// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/control/ListenTogetherQueueMutationApplier.kt
 * (upstream #359 / squashed 3cfd7037): apply a V2 queue mutation to a room
 * queue locally. Used by the controller to mirror a forwarded member request
 * optimistically, before the authoritative room state arrives.
 *
 * Tracks are matched by object identity (`===`), mirroring upstream
 * `indexOfIdentity`: the reference map resolves each (stableKey, occurrence)
 * to the very object in the working queue, so a "move" can never accidentally
 * relocate a duplicate copy.
 */
import { LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE } from '../playback/ListenTogetherQueuePolicy';
import { LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS } from '../protocol/ListenTogetherQueueMutation';
import {
  ListenTogetherQueueMutation,
  ListenTogetherQueueOperation,
  ListenTogetherQueueReference,
  listenTogetherQueueReferenceEquals
} from '../protocol/ListenTogetherQueueMutation';
import { ListenTogetherTrack } from '../protocol/ListenTogetherTrack';

export class ListenTogetherQueueMutationResult {
  queue: ListenTogetherTrack[] = [];
  currentIndex: number = 0;
  targetCurrentIndex: number | null = null;
  currentRemoved: boolean = false;
}

function indexOfIdentity(queue: ListenTogetherTrack[], target: ListenTogetherTrack): number {
  for (let index = 0; index < queue.length; index++) {
    if (queue[index] === target) {
      return index;
    }
  }
  return -1;
}

function containsIdentity(queue: ListenTogetherTrack[], target: ListenTogetherTrack): boolean {
  return indexOfIdentity(queue, target) >= 0;
}

class ReferenceMap {
  private readonly map: Map<string, ListenTogetherTrack> = new Map();

  build(queue: ListenTogetherTrack[]): void {
    const occurrences = new Map<string, number>();
    for (const track of queue) {
      if (track.stableKey.length === 0) {
        continue;
      }
      const occurrence = occurrences.get(track.stableKey) ?? 0;
      occurrences.set(track.stableKey, occurrence + 1);
      this.map.set(`${track.stableKey}\u0000${occurrence}`, track);
    }
  }

  resolve(reference: ListenTogetherQueueReference | null): ListenTogetherTrack | null {
    if (reference === null || reference.stableKey.length === 0 || reference.occurrence < 0) {
      return null;
    }
    return this.map.get(`${reference.stableKey}\u0000${reference.occurrence}`) ?? null;
  }
}

function insertionIndex(
  operation: ListenTogetherQueueOperation,
  nextQueue: ListenTogetherTrack[],
  anchor: ListenTogetherTrack | null
): number {
  const anchorIndex = anchor === null ? -1 : indexOfIdentity(nextQueue, anchor);
  if (operation.placement === 'prepend') {
    return 0;
  }
  if (operation.placement === 'before' && anchorIndex >= 0) {
    return anchorIndex;
  }
  return nextQueue.length;
}

function applyRemoveOrMove(
  operation: ListenTogetherQueueOperation,
  nextQueue: ListenTogetherTrack[],
  references: ReferenceMap,
  move: boolean
): void {
  const target = references.resolve(operation.target);
  if (target === null) {
    return;
  }
  const targetIndex = indexOfIdentity(nextQueue, target);
  if (targetIndex < 0) {
    return;
  }
  nextQueue.splice(targetIndex, 1);
  if (!move) {
    return;
  }
  const anchor = references.resolve(operation.anchor);
  nextQueue.splice(insertionIndex(operation, nextQueue, anchor), 0, target);
}

function applyInsert(
  operation: ListenTogetherQueueOperation,
  nextQueue: ListenTogetherTrack[],
  references: ReferenceMap
): void {
  const track = operation.track;
  if (track === null || track.stableKey.length === 0) {
    return;
  }
  if (nextQueue.length >= LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE) {
    return;
  }
  const anchor = references.resolve(operation.anchor);
  nextQueue.splice(insertionIndex(operation, nextQueue, anchor), 0, track);
}

function applyReorder(
  operation: ListenTogetherQueueOperation,
  nextQueue: ListenTogetherTrack[],
  references: ReferenceMap
): void {
  if (operation.order === null) {
    return;
  }
  const requestedTracks: ListenTogetherTrack[] = [];
  for (const reference of operation.order) {
    const resolved = references.resolve(reference);
    if (resolved !== null) {
      requestedTracks.push(resolved);
    }
  }
  if (requestedTracks.length === 0) {
    return;
  }
  const selectedSlots: number[] = [];
  for (let index = 0; index < nextQueue.length; index++) {
    for (const track of requestedTracks) {
      if (nextQueue[index] === track) {
        selectedSlots.push(index);
        break;
      }
    }
  }
  for (let position = 0; position < requestedTracks.length && position < selectedSlots.length; position++) {
    nextQueue[selectedSlots[position]] = requestedTracks[position];
  }
}

function unchangedMutationResult(
  queue: ListenTogetherTrack[],
  currentIndex: number
): ListenTogetherQueueMutationResult {
  const result = new ListenTogetherQueueMutationResult();
  result.queue = queue;
  result.currentIndex = queue.length === 0 ? -1 : Math.min(Math.max(currentIndex, 0), queue.length - 1);
  result.targetCurrentIndex = null;
  result.currentRemoved = false;
  return result;
}

export function applyListenTogetherQueueMutation(
  roomQueue: ListenTogetherTrack[],
  roomCurrentIndex: number,
  mutation: ListenTogetherQueueMutation,
  targetCurrentStableKey: string | null = null
): ListenTogetherQueueMutationResult {
  if (mutation.operations.length > LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS) {
    return unchangedMutationResult(roomQueue, roomCurrentIndex);
  }
  const references = new ReferenceMap();
  references.build(roomQueue);
  const nextQueue = roomQueue.slice();
  const previousCurrent = roomCurrentIndex >= 0 && roomCurrentIndex < nextQueue.length
    ? nextQueue[roomCurrentIndex]
    : null;
  const targetCurrent = references.resolve(mutation.targetCurrent);

  for (const operation of mutation.operations) {
    if (operation.type === 'remove' || operation.type === 'move') {
      applyRemoveOrMove(operation, nextQueue, references, operation.type === 'move');
    } else if (operation.type === 'remove_many') {
      if (operation.order !== null) {
        for (const reference of operation.order) {
          const resolved = references.resolve(reference);
          if (resolved === null) {
            continue;
          }
          const index = indexOfIdentity(nextQueue, resolved);
          if (index >= 0) {
            nextQueue.splice(index, 1);
          }
        }
      }
    } else if (operation.type === 'insert') {
      applyInsert(operation, nextQueue, references);
    } else if (operation.type === 'reorder') {
      applyReorder(operation, nextQueue, references);
    }
  }

  if (nextQueue.length === 0) {
    const result = new ListenTogetherQueueMutationResult();
    result.queue = [];
    result.currentIndex = -1;
    result.targetCurrentIndex = null;
    result.currentRemoved = previousCurrent !== null;
    return result;
  }

  let targetCurrentIndex: number | null = null;
  if (targetCurrent !== null) {
    const index = indexOfIdentity(nextQueue, targetCurrent);
    targetCurrentIndex = index >= 0 ? index : null;
  }
  let currentCandidate: ListenTogetherTrack | null = null;
  if (previousCurrent !== null && containsIdentity(nextQueue, previousCurrent)) {
    currentCandidate = previousCurrent;
  } else if (targetCurrent !== null && containsIdentity(nextQueue, targetCurrent)) {
    currentCandidate = targetCurrent;
  } else if (targetCurrentStableKey !== null && targetCurrentStableKey.length > 0) {
    for (const track of nextQueue) {
      if (track.stableKey === targetCurrentStableKey) {
        currentCandidate = track;
        break;
      }
    }
  }
  let currentIndex: number;
  if (currentCandidate !== null) {
    const index = indexOfIdentity(nextQueue, currentCandidate);
    currentIndex = index >= 0 ? index : Math.min(Math.max(roomCurrentIndex, 0), nextQueue.length - 1);
  } else {
    currentIndex = Math.min(Math.max(roomCurrentIndex, 0), nextQueue.length - 1);
  }
  const result = new ListenTogetherQueueMutationResult();
  result.queue = nextQueue;
  result.currentIndex = currentIndex;
  result.targetCurrentIndex = targetCurrentIndex;
  result.currentRemoved = previousCurrent !== null && !containsIdentity(nextQueue, previousCurrent);
  return result;
}
