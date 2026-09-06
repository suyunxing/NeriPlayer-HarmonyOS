/**
 * Port of ListenTogetherSessionManager.kt's `trySendTrackFinishedLegacyFallback()`
 * gate: when a worker rejects `TRACK_FINISHED` as an unknown event type, the
 * session rewrites the finish into the legacy pair the old protocol understood and
 * sends that instead — once.
 *
 * Only the gate is here; the rewrite itself already lives in
 * `buildTrackFinishedLegacyFallbackEvent`, and the sending is runtime wiring.
 *
 * The branch worth isolating is the one upstream hides in a mutation: an
 * over-TTL pending is *cleared*, while an already-attempted one is *kept*. Both
 * refuse to send, so a boolean return cannot tell them apart, yet the difference
 * decides whether a later error can retry. Keeping the attempted record is what
 * makes "once" mean once.
 */
import { isUnsupportedTrackFinishedEventError } from '../compat/ListenTogetherEventCompatibility';
import { ListenTogetherPendingTrackFinishedLegacyFallback } from './ListenTogetherPendingEvents';
import { LISTEN_TOGETHER_TRACK_FINISHED_LEGACY_FALLBACK_TTL_MS } from './ListenTogetherSessionRuntimeConstants';

/** The error was something else entirely; the pending fallback stays untouched. */
export const LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_NOT_REJECTED: string = 'not_rejected';
/** No fallback was recorded, so there is nothing to rewrite. */
export const LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_IDLE: string = 'idle';
/** Already rewritten once; refuse without discarding the record. */
export const LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_ALREADY_ATTEMPTED: string = 'already_attempted';
/** Too old to be worth sending; discard the record. */
export const LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_EXPIRED: string = 'expired';
/** Send the rewritten event now. */
export const LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_SEND: string = 'send';

/**
 * `next` is the value the pending slot must take afterwards, so the caller never
 * has to re-derive it: null when the record is discarded or absent, the record
 * itself when nothing changed, and a `markAttempted()` copy when sending.
 */
export class ListenTogetherTrackFinishedFallbackDecision {
  readonly outcome: string;
  readonly next: ListenTogetherPendingTrackFinishedLegacyFallback | null;

  constructor(outcome: string, next: ListenTogetherPendingTrackFinishedLegacyFallback | null) {
    this.outcome = outcome;
    this.next = next;
  }

  /** True only for [LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_SEND]. */
  shouldSend(): boolean {
    return this.outcome === LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_SEND;
  }
}

export function resolveListenTogetherTrackFinishedFallback(
  errorMessage: string,
  pending: ListenTogetherPendingTrackFinishedLegacyFallback | null,
  nowElapsedMs: number,
  ttlMs: number = LISTEN_TOGETHER_TRACK_FINISHED_LEGACY_FALLBACK_TTL_MS
): ListenTogetherTrackFinishedFallbackDecision {
  if (!isUnsupportedTrackFinishedEventError(errorMessage)) {
    return new ListenTogetherTrackFinishedFallbackDecision(
      LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_NOT_REJECTED,
      pending
    );
  }
  if (pending === null) {
    return new ListenTogetherTrackFinishedFallbackDecision(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_IDLE, null);
  }
  if (pending.attempted) {
    return new ListenTogetherTrackFinishedFallbackDecision(
      LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_ALREADY_ATTEMPTED,
      pending
    );
  }
  if (nowElapsedMs - pending.createdAtElapsedMs > ttlMs) {
    return new ListenTogetherTrackFinishedFallbackDecision(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_EXPIRED, null);
  }
  return new ListenTogetherTrackFinishedFallbackDecision(
    LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_SEND,
    pending.markAttempted()
  );
}
