/**
 * Port of listentogether/session/ListenTogetherPendingEvents.kt: the two events
 * the session may have to hold and retry.
 *
 * Kotlin `data class` + `copy()` becomes a class with a method returning a new
 * instance, so the retry bookkeeping stays immutable at the call site.
 */
import { ListenTogetherEvent } from '../protocol/ListenTogetherEventModels';

/**
 * A `TRACK_FINISHED` the server rejected as unsupported; the session rewrites it
 * into a legacy `SET_TRACK`/`PAUSE` once, and `attempted` makes sure that
 * rewrite happens exactly once.
 */
export class ListenTogetherPendingTrackFinishedLegacyFallback {
  readonly event: ListenTogetherEvent;
  readonly createdAtElapsedMs: number;
  readonly attempted: boolean;

  constructor(event: ListenTogetherEvent, createdAtElapsedMs: number, attempted: boolean = false) {
    this.event = event;
    this.createdAtElapsedMs = createdAtElapsedMs;
    this.attempted = attempted;
  }

  /** Kotlin `copy(attempted = true)`. */
  markAttempted(): ListenTogetherPendingTrackFinishedLegacyFallback {
    return new ListenTogetherPendingTrackFinishedLegacyFallback(this.event, this.createdAtElapsedMs, true);
  }
}

/**
 * A listener's `REQUEST_*` awaiting the controller's commit. `createdAtElapsedMs`
 * bounds how long it may wait; `lastSentAtElapsedMs` and `attempts` pace the
 * resends.
 */
export class ListenTogetherPendingMemberControlRequest {
  readonly event: ListenTogetherEvent;
  readonly createdAtElapsedMs: number;
  readonly lastSentAtElapsedMs: number;
  readonly attempts: number;

  constructor(
    event: ListenTogetherEvent,
    createdAtElapsedMs: number,
    lastSentAtElapsedMs: number,
    attempts: number
  ) {
    this.event = event;
    this.createdAtElapsedMs = createdAtElapsedMs;
    this.lastSentAtElapsedMs = lastSentAtElapsedMs;
    this.attempts = attempts;
  }

  /**
   * Upstream `retriedAt(nowElapsedMs)`: the same event resent, so `event` and
   * `createdAtElapsedMs` are carried over untouched — the deadline is measured
   * from the original request, not from the latest attempt.
   */
  retriedAt(nowElapsedMs: number): ListenTogetherPendingMemberControlRequest {
    return new ListenTogetherPendingMemberControlRequest(
      this.event,
      this.createdAtElapsedMs,
      nowElapsedMs,
      this.attempts + 1
    );
  }
}
