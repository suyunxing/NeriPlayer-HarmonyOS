/**
 * Port of listentogether/session/ListenTogetherForwardedRequestDeduper.kt: the
 * controller's guard against acting twice on the same forwarded listener
 * request, which the server may deliver more than once.
 *
 * Upstream's header records why this is per-requester rather than one global
 * counter, and the semantics are load-bearing enough to restate:
 *
 * 1. A `requestSequence` of 0 or null bypassed the old counter entirely, so any
 *    client that omitted the field got no dedupe at all. Those requests now fall
 *    back to event-id dedupe.
 * 2. A single global counter compared sequences across listeners, so if A's
 *    sequence had run ahead, B's first request looked stale and was silently
 *    dropped. Each requester now gets its own high-water mark.
 *
 * Both maps are insertion-ordered LRU caches: an entry that is touched moves to
 * the back, and the oldest is evicted first. Same divergence as
 * [ListenTogetherRecentEventTracker] — no lock (single event loop), and the
 * order is kept in a parallel array so eviction needs no iterator.
 */

/** Upstream `DEFAULT_MAX_REQUESTERS`. */
export const LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_REQUESTERS: number = 64;
/** Upstream `DEFAULT_MAX_EVENT_IDS`. */
export const LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_EVENT_IDS: number = 256;
/** Upstream `GLOBAL_REQUESTER`: the bucket for sequences with no attributable author. */
export const LISTEN_TOGETHER_DEDUPER_GLOBAL_REQUESTER: string = '__global__';

export class ListenTogetherForwardedRequestDeduper {
  private readonly lastSequenceByRequester: Map<string, number> = new Map<string, number>();
  private readonly requesterOrder: string[] = [];
  private readonly seenEventIds: Set<string> = new Set<string>();
  private readonly eventIdOrder: string[] = [];
  private readonly maxRequesters: number;
  private readonly maxEventIds: number;

  constructor(
    maxRequesters: number = LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_REQUESTERS,
    maxEventIds: number = LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_EVENT_IDS
  ) {
    this.maxRequesters = Math.max(maxRequesters, 1);
    this.maxEventIds = Math.max(maxEventIds, 1);
  }

  /**
   * True when this forwarded request has not been seen before and should be
   * committed. A positive sequence is authoritative; otherwise the event id is
   * the only identity available, and a request carrying neither is always
   * processed (dropping it would lose a real command).
   */
  shouldProcess(requesterUuid: string | null, sequence: number | null, eventId: string | null): boolean {
    const seq = sequence === null ? 0 : sequence;
    if (seq > 0) {
      return this.shouldProcessBySequence(requesterUuid, seq);
    }
    const id = eventId === null ? '' : eventId.trim();
    if (id.length === 0) {
      return true;
    }
    if (this.seenEventIds.has(id)) {
      return false;
    }
    this.seenEventIds.add(id);
    this.eventIdOrder.push(id);
    while (this.eventIdOrder.length > this.maxEventIds) {
      const oldest = this.eventIdOrder.shift();
      if (oldest !== undefined) {
        this.seenEventIds.delete(oldest);
      }
    }
    return true;
  }

  clear(): void {
    this.lastSequenceByRequester.clear();
    this.requesterOrder.length = 0;
    this.seenEventIds.clear();
    this.eventIdOrder.length = 0;
  }

  private shouldProcessBySequence(requesterUuid: string | null, sequence: number): boolean {
    const trimmed = requesterUuid === null ? '' : requesterUuid.trim();
    const requester = trimmed.length > 0 ? trimmed : LISTEN_TOGETHER_DEDUPER_GLOBAL_REQUESTER;
    const last = this.lastSequenceByRequester.get(requester) ?? 0;
    if (sequence <= last) {
      return false;
    }
    // Remove before insert so the requester moves to the back of the LRU order,
    // matching upstream's `remove()` + `put()` on a LinkedHashMap.
    if (this.lastSequenceByRequester.delete(requester)) {
      const at = this.requesterOrder.indexOf(requester);
      if (at >= 0) {
        this.requesterOrder.splice(at, 1);
      }
    }
    this.lastSequenceByRequester.set(requester, sequence);
    this.requesterOrder.push(requester);
    while (this.requesterOrder.length > this.maxRequesters) {
      const oldest = this.requesterOrder.shift();
      if (oldest !== undefined) {
        this.lastSequenceByRequester.delete(oldest);
      }
    }
    return true;
  }
}
