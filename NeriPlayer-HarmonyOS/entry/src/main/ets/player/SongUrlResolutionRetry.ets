// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of core/player/url/SongUrlResolutionRetry.kt (upstream 89a8694c):
 * transient stream-resolution failures get a short bounded retry before the
 * load is declared failed.
 *
 * Divergences: upstream types the retry against `SongUrlResult` (only a
 * `Failure` is retried — `RequiresLogin` must surface immediately). This
 * player's resolvers return a plain URL string ('' = failure), so the retry
 * takes an `isFailure` predicate instead; the policy (which attempt counts,
 * the escalating delay) is the ported part. The coroutine `delay` becomes an
 * injectable async function so unit tests run without timers.
 */
import { Logger } from '../app/Logger';

/** Upstream `SONG_URL_RESOLUTION_RETRY_COUNT`: retries after the first attempt. */
export const SONG_URL_RESOLUTION_RETRY_COUNT: number = 5;

/** Upstream `SONG_URL_RESOLUTION_RETRY_DELAY_MS`, multiplied by the retry number. */
export const SONG_URL_RESOLUTION_RETRY_DELAY_UNIT_MS: number = 250;

export type SongUrlResolutionDelayFn = (retryNumber: number) => Promise<void>;

export function defaultSongUrlResolutionDelay(retryNumber: number): Promise<void> {
  const delayMs = SONG_URL_RESOLUTION_RETRY_DELAY_UNIT_MS * Math.max(retryNumber, 1);
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, delayMs);
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

/** Test seam: a delay fn that awaits the event loop without real waiting. */
export function immediateSongUrlResolutionDelay(retryNumber: number): Promise<void> {
  return sleep(0);
}

/**
 * Upstream `retrySongUrlResolution`: attempt 0 runs first, then up to
 * `retryCount` retries — but only while the result keeps matching the failure
 * predicate; the first non-failure (or the last attempt's) result is returned.
 */
export async function retrySongUrlResolution<T>(
  resolveAttempt: (attempt: number) => Promise<T>,
  isFailure: (result: T) => boolean,
  retryCount: number = SONG_URL_RESOLUTION_RETRY_COUNT,
  delayBeforeRetry: SongUrlResolutionDelayFn = defaultSongUrlResolutionDelay,
  onRetry: ((attempt: number) => void) | null = null
): Promise<T> {
  if (retryCount < 0) {
    throw new Error('retryCount must not be negative');
  }
  let result = await resolveAttempt(0);
  for (let retryIndex = 0; retryIndex < retryCount; retryIndex++) {
    if (!isFailure(result)) {
      return result;
    }
    const retryNumber = retryIndex + 1;
    if (onRetry !== null) {
      onRetry(retryNumber);
    }
    // The explicit annotation keeps the awaited type visible to the linter.
    const retryDelay: Promise<void> = delayBeforeRetry(retryNumber);
    await retryDelay;
    result = await resolveAttempt(retryNumber);
  }
  return result;
}

/**
 * Upstream `resolveSongUrlOrWaitForAuthoritativeStream`: a listener that is
 * waiting for the room's authoritative link must not resolve (nor fail) on
 * its own — the sentinel result keeps the load pending until the link lands.
 */
export function resolveSongUrlOrWaitForAuthoritativeStream<T>(
  shouldWaitForAuthoritativeStream: boolean,
  waitingResult: () => T,
  resolve: () => Promise<T>
): Promise<T> {
  if (shouldWaitForAuthoritativeStream) {
    return Promise.resolve(waitingResult());
  }
  return resolve();
}

/** Retry logger matching upstream's `resolveSongUrl: retry=n/N` warning line. */
export function songUrlResolutionRetryLogger(tag: string): (attempt: number) => void {
  return (attempt: number): void => {
    Logger.warn(`${tag}: retry=${attempt}/${SONG_URL_RESOLUTION_RETRY_COUNT}`);
  };
}
