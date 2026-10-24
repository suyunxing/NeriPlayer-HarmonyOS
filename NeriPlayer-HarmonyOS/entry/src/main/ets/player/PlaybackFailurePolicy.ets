// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * What load-failure recovery should do after a load chain failed.
 */
export enum LoadFailureAction {
  /** Reload the same track once (transient failures do recover). */
  RETRY_SAME = 0,
  /** Advance to the next queue entry via the auto-skip path. */
  SKIP_NEXT = 1,
  /** Stop playback: no entry left that has not already failed. */
  STOP = 2
}

export interface LoadFailureInput {
  /** Failed attempts for the current song including this one (1-based). */
  errorAttempts: number;
  /** Consecutive auto-skips since the last successful playback start. */
  autoSkipFailures: number;
  /** Queue length; always >= 1 when a song is loaded. */
  queueLength: number;
  /** Index the engine would advance to (-1 when it would stop). */
  nextTarget: number;
  /** Current queue index. */
  currentIndex: number;
}

/**
 * Consecutive auto-skip bound (upstream #499 `stop failure auto-advance at
 * the consecutive limit`, MAX_CONSECUTIVE_FAILURES = 10): without it a long
 * queue with every entry failing (e.g. network down) skips through the whole
 * list instead of stopping early.
 */
export const MAX_CONSECUTIVE_FAILURES: number = 10;

/**
 * Bounded failure recovery. Android semantics retry once and then skip; the
 * skip path is bounded twice — by the queue circle (stop after one full wrap
 * of failures) and by the consecutive limit above (stop after 10 failures in
 * a row regardless of queue length) — so a broken track or a fully broken
 * queue can never wrap forever. On a single-track queue with repeat-all the
 * engine's next target is the same track, and without the stop below that
 * replayed the failed load at full speed: LOADING/ERROR status churn,
 * MiniPlayer symbol reload flashing and main-thread jank on device.
 */
export function decideLoadFailureAction(input: LoadFailureInput): LoadFailureAction {
  if (input.errorAttempts < 2) {
    return LoadFailureAction.RETRY_SAME;
  }
  if (input.nextTarget < 0 || input.nextTarget === input.currentIndex) {
    return LoadFailureAction.STOP;
  }
  const consecutiveLimit = Math.min(Math.max(1, input.queueLength), MAX_CONSECUTIVE_FAILURES);
  if (input.autoSkipFailures + 1 >= consecutiveLimit) {
    return LoadFailureAction.STOP;
  }
  return LoadFailureAction.SKIP_NEXT;
}
