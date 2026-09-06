/**
 * Port of listentogether/network/reconnect/ListenTogetherReconnectPolicy.kt.
 *
 * One deliberate divergence: upstream calls `Math.random()` inline, which makes
 * the delay untestable. Here the jitter is split into a pure
 * `listenTogetherReconnectDelayMsWithRandom(attempt, randomUnit)` plus a thin
 * wrapper that supplies `Math.random()`, so the base table and the jitter range
 * can both be pinned by unit tests. The produced value distribution is
 * identical.
 *
 * Terminal-error matching is byte-for-byte the upstream substring set. It is
 * intentionally substring-based rather than structured: the message reaching
 * this policy is already a flattened string coming from either an HTTP error
 * (`... (410): {"error":"room closed"}`) or a socket failure
 * (`... (http=410 Gone)`), so both shapes must be recognised.
 */

/** Upstream: LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS. */
export const LISTEN_TOGETHER_MAX_RECONNECT_ATTEMPTS: number = 15;

/**
 * True when reconnecting can never succeed, so the caller must stop retrying
 * and surface the failure instead of burning the 15 attempts.
 */
export function isTerminalListenTogetherReconnectError(errorMessage: string | null | undefined): boolean {
  const normalized = (errorMessage ?? '').trim().toLowerCase();
  if (normalized.length === 0) {
    return false;
  }
  return isUnauthorizedReconnectError(normalized)
    || isClosedRoomReconnectError(normalized)
    || isMissingRoomReconnectError(normalized);
}

/**
 * Jitter-free backoff table (upstream `when (attempt)`), exposed separately so
 * tests can assert the schedule without fighting randomness. `attempt` is
 * 1-based; anything outside 1..4 (including 0 and negatives, matching Kotlin's
 * `else` branch) lands on the 12 s plateau.
 */
export function listenTogetherReconnectDelayBaseMs(attempt: number): number {
  if (attempt === 1) {
    return 1_500;
  }
  if (attempt === 2) {
    return 3_000;
  }
  if (attempt === 3) {
    return 5_000;
  }
  if (attempt === 4) {
    return 8_000;
  }
  return 12_000;
}

/**
 * Backoff with deterministic jitter: `randomUnit` is the [0, 1) draw upstream
 * takes from `Math.random()`, mapped to ±20% of the base delay. Truncation
 * toward zero matches Kotlin's `Double.toLong()`.
 */
export function listenTogetherReconnectDelayMsWithRandom(attempt: number, randomUnit: number): number {
  const baseMs = listenTogetherReconnectDelayBaseMs(attempt);
  const jitter = Math.trunc(baseMs * 0.2 * (randomUnit * 2.0 - 1.0));
  return baseMs + jitter;
}

/** Upstream: listenTogetherReconnectDelayMs(attempt). */
export function listenTogetherReconnectDelayMs(attempt: number): number {
  return listenTogetherReconnectDelayMsWithRandom(attempt, Math.random());
}

/** The room token was rejected: retrying with the same token cannot help. */
function isUnauthorizedReconnectError(normalized: string): boolean {
  return normalized.includes('unauthorized');
}

/**
 * The room is gone. `http=410` is the socket-failure shape and `(410)` the HTTP
 * shape; upstream matches both and so does this port.
 */
function isClosedRoomReconnectError(normalized: string): boolean {
  return normalized.includes('room closed')
    || normalized.includes('http=410')
    || normalized.includes('(410)');
}

/**
 * The Durable Object backing the room no longer exists. Upstream additionally
 * lists the JSON-quoted variants (`"error":"room not initialized"`), which are
 * strict supersets of the bare substrings already matched here; they are
 * omitted rather than duplicated because the result is identical.
 */
function isMissingRoomReconnectError(normalized: string): boolean {
  return normalized.includes('room not initialized')
    || normalized.includes('not found in do');
}
