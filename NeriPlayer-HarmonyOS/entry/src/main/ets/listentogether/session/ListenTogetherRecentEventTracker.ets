/**
 * Port of listentogether/session/ListenTogetherRecentEventTracker.kt: the
 * bounded memory of event ids this client has recently sent and received, used
 * to recognise the server echoing one of our own events back.
 *
 * Two divergences from upstream, both deliberate:
 *
 * 1. **No lock.** Upstream wraps every access in `synchronized(lock)` because an
 *    okhttp callback thread and the session coroutine both touch it. ArkTS runs
 *    all of this on one event loop, so a lock would be dead weight. If any part
 *    of the session ever moves to a worker, the tracker must not be shared
 *    across the boundary — pass event ids, not the tracker.
 * 2. **Insertion order is tracked explicitly.** Upstream relies on
 *    `LinkedHashSet` for both membership and eviction order. An ArkTS `Set` does
 *    preserve insertion order, but evicting the oldest entry would mean stepping
 *    an iterator; a parallel array of keys keeps the eviction typed and obvious.
 *    Re-marking an id that is already present is a no-op, exactly like
 *    `LinkedHashSet.add`, so it does not refresh the entry's position.
 */

/** Upstream `DEFAULT_RECENT_EVENT_LIMIT`. */
export const LISTEN_TOGETHER_DEFAULT_RECENT_EVENT_LIMIT: number = 128;

/** A bounded, insertion-ordered set of event ids. */
class RecentEventIdRing {
  private readonly ids: Set<string> = new Set<string>();
  private readonly order: string[] = [];
  private readonly maxSize: number;

  constructor(maxSize: number) {
    this.maxSize = Math.max(maxSize, 1);
  }

  has(eventId: string): boolean {
    return this.ids.has(eventId);
  }

  /** Blank and missing ids are ignored: they cannot identify an echo. */
  mark(eventId: string | null): void {
    const id = eventId === null ? '' : eventId.trim();
    if (id.length === 0 || this.ids.has(id)) {
      return;
    }
    this.ids.add(id);
    this.order.push(id);
    while (this.order.length > this.maxSize) {
      const oldest = this.order.shift();
      if (oldest !== undefined) {
        this.ids.delete(oldest);
      }
    }
  }

  clear(): void {
    this.ids.clear();
    this.order.length = 0;
  }
}

export class ListenTogetherRecentEventTracker {
  private readonly outbound: RecentEventIdRing;
  private readonly inbound: RecentEventIdRing;

  constructor(maxSize: number = LISTEN_TOGETHER_DEFAULT_RECENT_EVENT_LIMIT) {
    this.outbound = new RecentEventIdRing(maxSize);
    this.inbound = new RecentEventIdRing(maxSize);
  }

  /** Wipes both directions; used when leaving a room. */
  clear(): void {
    this.outbound.clear();
    this.inbound.clear();
  }

  hasOutbound(eventId: string): boolean {
    return this.outbound.has(eventId);
  }

  hasInbound(eventId: string): boolean {
    return this.inbound.has(eventId);
  }

  markOutbound(eventId: string | null): void {
    this.outbound.mark(eventId);
  }

  markInbound(eventId: string | null): void {
    this.inbound.mark(eventId);
  }
}
