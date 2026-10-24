// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherControlOutbox.kt (upstream #359,
 * squashed 3cfd7037): local control events that have been handed to the socket
 * but not yet acknowledged. Keyed by (roomId, intent) so a newer action of the
 * same intent replaces the queued one, replayed after a reconnect, and swapped
 * for a legacy full-snapshot event when the server rejects the V2 payload.
 *
 * Divergence: ArkTS has no coroutines, so the single-threaded event loop
 * replaces the Kotlin `synchronized` blocks.
 */
import { ListenTogetherEvent } from '../protocol/ListenTogetherEventModels';

export class PendingListenTogetherControlEvent {
  readonly event: ListenTogetherEvent;
  readonly roomId: string;
  readonly legacyFallbackEvent: ListenTogetherEvent | null;

  constructor(
    event: ListenTogetherEvent,
    roomId: string,
    legacyFallbackEvent: ListenTogetherEvent | null = null
  ) {
    this.event = event;
    this.roomId = roomId;
    this.legacyFallbackEvent = legacyFallbackEvent;
  }
}

const DEFAULT_MAX_EVENTS: number = 8;

/**
 * One pending entry per intent: a rapid SET_QUEUE → SET_QUEUE only ever ships
 * the last one. `null` (no key) means the event type carries no queue/transport
 * intent worth replaying.
 */
export function listenTogetherControlOutboxKey(
  roomId: string,
  event: ListenTogetherEvent
): string | null {
  let intentKey: string | null = null;
  switch (event.type) {
    case 'SET_TRACK':
    case 'REQUEST_SET_TRACK':
      intentKey = 'track';
      break;
    case 'SET_QUEUE':
    case 'REQUEST_SET_QUEUE':
      intentKey = 'queue';
      break;
    case 'PLAY':
    case 'REQUEST_PLAY':
    case 'PAUSE':
    case 'REQUEST_PAUSE':
      intentKey = 'transport';
      break;
    case 'SEEK':
    case 'REQUEST_SEEK':
      intentKey = 'seek';
      break;
    case 'PLAYBACK_MODE':
    case 'REQUEST_PLAYBACK_MODE':
      intentKey = 'playback_mode';
      break;
    case 'TRACK_FINISHED':
      intentKey = 'track_finished';
      break;
    default:
      intentKey = null;
      break;
  }
  return intentKey === null ? null : `${roomId}:${intentKey}`;
}

export class ListenTogetherControlOutbox {
  private readonly maxEvents: number;
  private readonly events: Map<string, PendingListenTogetherControlEvent> = new Map();

  constructor(maxEvents: number = DEFAULT_MAX_EVENTS) {
    if (maxEvents <= 0) {
      throw new Error('ListenTogetherControlOutbox maxEvents must be positive');
    }
    this.maxEvents = maxEvents;
  }

  offer(
    event: ListenTogetherEvent,
    roomId: string | null,
    legacyFallbackEvent: ListenTogetherEvent | null = null
  ): void {
    const resolvedRoomId = roomId !== null && roomId.trim().length > 0 ? roomId : null;
    if (resolvedRoomId === null) {
      return;
    }
    const key = listenTogetherControlOutboxKey(resolvedRoomId, event);
    if (key === null) {
      return;
    }
    this.events.delete(key);
    this.events.set(key, new PendingListenTogetherControlEvent(event, resolvedRoomId, legacyFallbackEvent));
    while (this.events.size > this.maxEvents) {
      const oldest = this.events.keys().next();
      if (oldest.done) {
        break;
      }
      this.events.delete(oldest.value);
    }
  }

  pendingForRoom(roomId: string | null): PendingListenTogetherControlEvent[] {
    if (roomId === null || roomId.trim().length === 0) {
      return [];
    }
    const pending: PendingListenTogetherControlEvent[] = [];
    this.events.forEach((entry: PendingListenTogetherControlEvent) => {
      if (entry.roomId === roomId) {
        pending.push(entry);
      }
    });
    return pending;
  }

  acknowledge(eventId: string | null): void {
    const resolvedEventId = eventId !== null && eventId.trim().length > 0 ? eventId : null;
    if (resolvedEventId === null) {
      return;
    }
    const stale: string[] = [];
    this.events.forEach((entry: PendingListenTogetherControlEvent, key: string) => {
      if (entry.event.eventId === resolvedEventId) {
        stale.push(key);
      }
    });
    for (const key of stale) {
      this.events.delete(key);
    }
  }

  pendingByEventId(eventId: string | null): PendingListenTogetherControlEvent | null {
    const resolvedEventId = eventId !== null && eventId.trim().length > 0 ? eventId : null;
    if (resolvedEventId === null) {
      return null;
    }
    let found: PendingListenTogetherControlEvent | null = null;
    this.events.forEach((entry: PendingListenTogetherControlEvent) => {
      if (found === null && entry.event.eventId === resolvedEventId) {
        found = entry;
      }
    });
    return found;
  }

  /** Exactly one fallback-capable entry, or null when the count is ambiguous. */
  singlePendingWithLegacyFallback(): PendingListenTogetherControlEvent | null {
    let found: PendingListenTogetherControlEvent | null = null;
    let matchCount = 0;
    this.events.forEach((entry: PendingListenTogetherControlEvent) => {
      if (entry.legacyFallbackEvent !== null) {
        matchCount++;
        if (matchCount === 1) {
          found = entry;
        }
      }
    });
    return matchCount === 1 ? found : null;
  }

  replace(eventId: string | null, replacement: ListenTogetherEvent): PendingListenTogetherControlEvent | null {
    const resolvedEventId = eventId !== null && eventId.trim().length > 0 ? eventId : null;
    if (resolvedEventId === null) {
      return null;
    }
    let existingKey: string | null = null;
    this.events.forEach((entry: PendingListenTogetherControlEvent, key: string) => {
      if (existingKey === null && entry.event.eventId === resolvedEventId) {
        existingKey = key;
      }
    });
    if (existingKey === null) {
      return null;
    }
    const existing = this.events.get(existingKey);
    if (existing === undefined) {
      return null;
    }
    const replacementKey = listenTogetherControlOutboxKey(existing.roomId, replacement);
    if (replacementKey === null) {
      return null;
    }
    this.events.delete(existingKey);
    this.events.set(replacementKey, new PendingListenTogetherControlEvent(replacement, existing.roomId));
    return existing;
  }

  clear(): void {
    this.events.clear();
  }
}
