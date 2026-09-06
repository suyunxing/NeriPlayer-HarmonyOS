/**
 * Port of ListenTogetherSessionManager.kt's `buildPendingMemberControlRequest()`
 * and `retryPendingMemberControlRequestIfNeeded()`.
 *
 * A listener cannot change the room itself: it sends `REQUEST_PLAY` and waits for
 * the controller to commit an authoritative `PLAY`. If the request is lost — a
 * dropped frame, a controller that was mid-reconnect — nothing tells the listener,
 * and the user is left looking at a button that did nothing. Hence the pending
 * slot and its bounded resends.
 *
 * The decision is separated from the act because every one of upstream's five
 * branches ends in mutating a field and returning, which makes the ordering
 * invisible and untestable. Ordering matters: *satisfied* is checked before
 * *expired*, so a request the room already honoured is retired quietly rather
 * than logged as a failure, and both are checked before the retry interval, so a
 * satisfied request is never resent just because its interval happened to elapse.
 *
 * All timestamps are monotonic uptime (upstream `SystemClock.elapsedRealtime()`),
 * never a wall clock — a clock adjustment must not expire a live request.
 */
import { ListenTogetherEvent } from '../protocol/ListenTogetherEventModels';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { isListenTogetherRequestControlEventType } from '../control/ListenTogetherControlEventTypes';
import { isListenTogetherPendingMemberControlSatisfied } from '../compat/ListenTogetherEventCompatibility';
import { ListenTogetherPendingMemberControlRequest } from './ListenTogetherPendingEvents';
import {
  LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_MAX_ATTEMPTS,
  LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_RETRY_INTERVAL_MS,
  LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_TTL_MS,
  LISTEN_TOGETHER_PENDING_MEMBER_SEEK_SATISFIED_DRIFT_MS
} from './ListenTogetherSessionRuntimeConstants';

/** Nothing is pending; upstream's leading `?: return`. */
export const LISTEN_TOGETHER_PENDING_CONTROL_IDLE: string = 'idle';
/** The room now reflects what was asked; retire the request without a resend. */
export const LISTEN_TOGETHER_PENDING_CONTROL_SATISFIED: string = 'satisfied';
/** Past its TTL: the controller is not going to answer this one. */
export const LISTEN_TOGETHER_PENDING_CONTROL_EXPIRED: string = 'expired';
/** Sent as many times as allowed; give up rather than keep shouting. */
export const LISTEN_TOGETHER_PENDING_CONTROL_MAX_ATTEMPTS: string = 'max_attempts';
/** Still within the retry interval; keep waiting, keep the request. */
export const LISTEN_TOGETHER_PENDING_CONTROL_TOO_SOON: string = 'too_soon';
/** Resend now. */
export const LISTEN_TOGETHER_PENDING_CONTROL_RETRY: string = 'retry';

/**
 * What the session should do with its pending slot this tick. `next` is the value
 * the slot must take: null for every terminal branch, the original request while
 * waiting, and a `retriedAt()` copy when resending — so the caller assigns rather
 * than deciding a second time.
 */
export class ListenTogetherPendingMemberControlRetryDecision {
  readonly outcome: string;
  readonly next: ListenTogetherPendingMemberControlRequest | null;

  constructor(outcome: string, next: ListenTogetherPendingMemberControlRequest | null) {
    this.outcome = outcome;
    this.next = next;
  }

  /** True only for [LISTEN_TOGETHER_PENDING_CONTROL_RETRY]. */
  shouldResend(): boolean {
    return this.outcome === LISTEN_TOGETHER_PENDING_CONTROL_RETRY;
  }
}

/**
 * Upstream `buildPendingMemberControlRequest()`. Returns null when there is
 * nothing to track: a controller's own events are authoritative and need no
 * answer, and a non-`REQUEST_*` event is not a request at all.
 *
 * `attempts` starts at 1, not 0 — the first send has already happened by the time
 * this record exists, which is what makes the max-attempts bound a bound on total
 * sends rather than on resends.
 */
export function buildListenTogetherPendingMemberControlRequest(
  event: ListenTogetherEvent,
  isCurrentUserController: boolean,
  nowElapsedMs: number
): ListenTogetherPendingMemberControlRequest | null {
  if (isCurrentUserController) {
    return null;
  }
  if (!isListenTogetherRequestControlEventType(event.type)) {
    return null;
  }
  return new ListenTogetherPendingMemberControlRequest(event, nowElapsedMs, nowElapsedMs, 1);
}

export function resolveListenTogetherPendingMemberControlRetry(
  pending: ListenTogetherPendingMemberControlRequest | null,
  roomState: ListenTogetherRoomState | null,
  nowElapsedMs: number,
  ttlMs: number = LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_TTL_MS,
  retryIntervalMs: number = LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_RETRY_INTERVAL_MS,
  maxAttempts: number = LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_MAX_ATTEMPTS,
  seekSatisfiedDriftMs: number = LISTEN_TOGETHER_PENDING_MEMBER_SEEK_SATISFIED_DRIFT_MS
): ListenTogetherPendingMemberControlRetryDecision {
  if (pending === null) {
    return new ListenTogetherPendingMemberControlRetryDecision(LISTEN_TOGETHER_PENDING_CONTROL_IDLE, null);
  }
  if (isListenTogetherPendingMemberControlSatisfied(pending.event, roomState, seekSatisfiedDriftMs)) {
    return new ListenTogetherPendingMemberControlRetryDecision(LISTEN_TOGETHER_PENDING_CONTROL_SATISFIED, null);
  }
  // Strictly greater than, matching upstream: a request that is exactly at its TTL
  // still gets its last chance.
  if (nowElapsedMs - pending.createdAtElapsedMs > ttlMs) {
    return new ListenTogetherPendingMemberControlRetryDecision(LISTEN_TOGETHER_PENDING_CONTROL_EXPIRED, null);
  }
  if (pending.attempts >= maxAttempts) {
    return new ListenTogetherPendingMemberControlRetryDecision(LISTEN_TOGETHER_PENDING_CONTROL_MAX_ATTEMPTS, null);
  }
  if (nowElapsedMs - pending.lastSentAtElapsedMs < retryIntervalMs) {
    // Keep the request as it stands: this is a wait, not a decision about it.
    return new ListenTogetherPendingMemberControlRetryDecision(LISTEN_TOGETHER_PENDING_CONTROL_TOO_SOON, pending);
  }
  return new ListenTogetherPendingMemberControlRetryDecision(
    LISTEN_TOGETHER_PENDING_CONTROL_RETRY,
    pending.retriedAt(nowElapsedMs)
  );
}
