// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/protocol/ListenTogetherQueueMutation.kt (upstream #359,
 * squashed commit 3cfd7037; server-side V2 protocol landed in LTW submodule
 * 920f599/245e27c).
 *
 * A V2 queue update no longer ships the whole queue: the client describes the
 * diff against a base room version as a list of operations on
 * (stableKey, occurrence) references, plus the reference the current index
 * should land on. Occurrence disambiguates duplicate tracks in the queue.
 *
 * `legacyQueueSnapshot` on the *event* (not here) carries the full snapshot for
 * one-shot fallback when an older server rejects the mutation payload.
 */

import { ListenTogetherTrack } from './ListenTogetherTrack';
import {
  JsonRecord,
  optNumber,
  optRecord,
  optRecordArray,
  optString,
  putNumber,
  putRecord,
  putRecordArray,
  putString,
  reqString
} from './ListenTogetherJson';
import {
  listenTogetherTrackFromRecord,
  listenTogetherTrackToRecord
} from './ListenTogetherTrack';

/** Upstream `LISTEN_TOGETHER_QUEUE_MUTATION_SCHEMA_VERSION`. */
export const LISTEN_TOGETHER_QUEUE_MUTATION_SCHEMA_VERSION: number = 2;

/** Upstream `LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS`. */
export const LISTEN_TOGETHER_MAX_QUEUE_MUTATION_OPERATIONS: number = 64;

export class ListenTogetherQueueReference {
  stableKey: string = '';
  occurrence: number = 0;

  constructor(stableKey: string = '', occurrence: number = 0) {
    this.stableKey = stableKey;
    this.occurrence = occurrence;
  }
}

export class ListenTogetherQueueOperation {
  /** remove | remove_many | move | insert | reorder */
  type: string = '';
  target: ListenTogetherQueueReference | null = null;
  anchor: ListenTogetherQueueReference | null = null;
  /** before | prepend | append (move/insert). */
  placement: string | null = null;
  track: ListenTogetherTrack | null = null;
  order: ListenTogetherQueueReference[] | null = null;
}

export class ListenTogetherQueueMutation {
  /** The room version the diff was computed against. */
  baseRoomVersion: number = 0;
  operations: ListenTogetherQueueOperation[] = [];
  targetCurrent: ListenTogetherQueueReference | null = null;
}

/** Structural equality for reference keys (value objects upstream). */
export function listenTogetherQueueReferenceEquals(
  a: ListenTogetherQueueReference | null,
  b: ListenTogetherQueueReference | null
): boolean {
  if (a === null || b === null) {
    return a === b;
  }
  return a.stableKey === b.stableKey && a.occurrence === b.occurrence;
}

// ---------- wire codec (matches kotlinx serialization shape) ----------

function queueReferenceFromRecord(raw: JsonRecord): ListenTogetherQueueReference {
  const reference = new ListenTogetherQueueReference();
  reference.stableKey = reqString(raw, 'stableKey');
  reference.occurrence = optNumber(raw, 'occurrence') ?? 0;
  return reference;
}

function queueReferenceToRecord(reference: ListenTogetherQueueReference): JsonRecord {
  const raw: JsonRecord = {};
  raw['stableKey'] = reference.stableKey;
  putNumber(raw, 'occurrence', reference.occurrence);
  return raw;
}

function optQueueReference(raw: JsonRecord, key: string): ListenTogetherQueueReference | null {
  const record = optRecord(raw, key);
  return record === null ? null : queueReferenceFromRecord(record);
}

function putQueueReference(raw: JsonRecord, key: string, reference: ListenTogetherQueueReference | null): void {
  putRecord(raw, key, reference === null ? null : queueReferenceToRecord(reference));
}

function queueOperationFromRecord(raw: JsonRecord): ListenTogetherQueueOperation {
  const operation = new ListenTogetherQueueOperation();
  operation.type = reqString(raw, 'type');
  operation.target = optQueueReference(raw, 'target');
  operation.anchor = optQueueReference(raw, 'anchor');
  operation.placement = optString(raw, 'placement');
  const trackRecord = optRecord(raw, 'track');
  operation.track = trackRecord === null ? null : listenTogetherTrackFromRecord(trackRecord);
  const orderRecords = optRecordArray(raw, 'order');
  if (orderRecords === null) {
    operation.order = null;
  } else {
    const order: ListenTogetherQueueReference[] = [];
    for (const orderRecord of orderRecords) {
      order.push(queueReferenceFromRecord(orderRecord));
    }
    operation.order = order;
  }
  return operation;
}

function queueOperationToRecord(operation: ListenTogetherQueueOperation): JsonRecord {
  const raw: JsonRecord = {};
  raw['type'] = operation.type;
  putQueueReference(raw, 'target', operation.target);
  putQueueReference(raw, 'anchor', operation.anchor);
  putString(raw, 'placement', operation.placement);
  putRecord(raw, 'track', operation.track === null ? null : listenTogetherTrackToRecord(operation.track));
  if (operation.order === null) {
    putRecordArray(raw, 'order', null);
  } else {
    const orderRecords: JsonRecord[] = [];
    for (const reference of operation.order) {
      orderRecords.push(queueReferenceToRecord(reference));
    }
    putRecordArray(raw, 'order', orderRecords);
  }
  return raw;
}

export function listenTogetherQueueMutationFromRecord(raw: JsonRecord): ListenTogetherQueueMutation {
  const mutation = new ListenTogetherQueueMutation();
  mutation.baseRoomVersion = optNumber(raw, 'baseRoomVersion') ?? 0;
  const operationRecords = optRecordArray(raw, 'operations');
  if (operationRecords !== null) {
    for (const operationRecord of operationRecords) {
      mutation.operations.push(queueOperationFromRecord(operationRecord));
    }
  }
  mutation.targetCurrent = optQueueReference(raw, 'targetCurrent');
  return mutation;
}

export function listenTogetherQueueMutationToRecord(mutation: ListenTogetherQueueMutation): JsonRecord {
  const raw: JsonRecord = {};
  putNumber(raw, 'baseRoomVersion', mutation.baseRoomVersion);
  const operationRecords: JsonRecord[] = [];
  for (const operation of mutation.operations) {
    operationRecords.push(queueOperationToRecord(operation));
  }
  putRecordArray(raw, 'operations', operationRecords);
  putQueueReference(raw, 'targetCurrent', mutation.targetCurrent);
  return raw;
}
