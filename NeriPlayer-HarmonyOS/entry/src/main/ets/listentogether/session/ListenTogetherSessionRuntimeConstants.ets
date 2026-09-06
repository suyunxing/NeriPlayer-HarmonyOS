/**
 * The session runtime's timing constants, lifted out of
 * ListenTogetherSessionManager.kt's `companion object` so the policies that
 * consume them stay unit-testable and so the session manager (M7.3b-3) has no
 * private magic numbers of its own.
 *
 * Only constants with no other home live here. The drift thresholds belong to
 * [ListenTogetherPlayerSyncPlanner], the heartbeat cadences and the worker
 * controller timeout to [ListenTogetherIncomingStatePolicy], the controller
 * grace period to [ListenTogetherRoomNotice], and the clock-sync RTT ceiling to
 * [ListenTogetherServerClockOffset] — none of them are duplicated here, because
 * two copies of a threshold is one copy too many.
 */

/**
 * How long after a track switch a listener stops treating a passive update as
 * authoritative. Upstream `TRACK_SWITCH_GRACE_PERIOD_MS`.
 */
export const LISTEN_TOGETHER_TRACK_SWITCH_GRACE_PERIOD_MS: number = 800;

/**
 * The heartbeat loop's own tick. It re-reads the session on every tick rather
 * than sleeping the full heartbeat interval, so a role change or a disconnect is
 * noticed within this window instead of one heartbeat later.
 */
export const LISTEN_TOGETHER_HEARTBEAT_STATE_RECHECK_INTERVAL_MS: number = 10_000;

/**
 * The socket keep-alive ping cadence. Upstream
 * `LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS`; it is deliberately well under
 * `LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS`, which the session-policy suite
 * asserts, because the worker drops a controller it has not heard from.
 */
export const LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS: number = 20_000;

/**
 * The minimum gap between two `REQUEST_LINK` events for the same track. A
 * listener that cannot resolve a stream will otherwise ask on every watchdog
 * tick, and the controller pays for each ask with a stream resolve.
 */
export const LISTEN_TOGETHER_LINK_REQUEST_THROTTLE_MS: number = 4_000;

/**
 * How long the controller treats an incoming state as an echo of its own local
 * action. Consumed by `shouldDropListenTogetherControllerLocalEcho`.
 */
export const LISTEN_TOGETHER_CONTROLLER_LOCAL_CONTROL_COOLDOWN_MS: number = 1_200;

/** The sync watchdog's tick, which drives listener drift correction. */
export const LISTEN_TOGETHER_SYNC_WATCHDOG_INTERVAL_MS: number = 8_000;

/**
 * How long a listener tolerates websocket silence before repairing its state
 * over HTTP. Matches the worker's controller timeout on purpose: past this point
 * the room may have moved on without us.
 */
export const LISTEN_TOGETHER_LISTENER_WEB_SOCKET_SILENCE_TIMEOUT_MS: number = 45_000;

/**
 * The floor between two HTTP state repairs. This gate is checked *before* the
 * version-gap reason, so a persistent gap cannot turn into a request storm.
 */
export const LISTEN_TOGETHER_LISTENER_STATE_REPAIR_MIN_INTERVAL_MS: number = 30_000;

/** How long a listener may sit not-producing-audio before it counts as stalled. */
export const LISTEN_TOGETHER_LISTENER_PLAYBACK_STALL_TIMEOUT_MS: number = 8_000;

/** The floor between two stall recoveries, so a bad stream cannot loop. */
export const LISTEN_TOGETHER_LISTENER_PLAYBACK_STALL_RECOVERY_COOLDOWN_MS: number = 12_000;

/** How long a member waits before resending an unanswered `REQUEST_*`. */
export const LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_RETRY_INTERVAL_MS: number = 3_000;

/** How long a `REQUEST_*` stays worth resending at all. */
export const LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_TTL_MS: number = 18_000;

/** Total sends, not resends: the first send counts as attempt 1. */
export const LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_MAX_ATTEMPTS: number = 4;

/**
 * How close the room has to land to a requested seek for the request to count as
 * answered. A seek is never exact, so an equality check would resend forever.
 */
export const LISTEN_TOGETHER_PENDING_MEMBER_SEEK_SATISFIED_DRIFT_MS: number = 1_500;

/**
 * How long a rejected `TRACK_FINISHED` may still be retried as its legacy
 * equivalent. Past this the room has almost certainly advanced on its own.
 */
export const LISTEN_TOGETHER_TRACK_FINISHED_LEGACY_FALLBACK_TTL_MS: number = 15_000;

/** Below this drift a listener does not correct at all — correcting would jitter. */
export const LISTEN_TOGETHER_SOFT_SYNC_MIN_DRIFT_MS: number = 600;

/** Above this drift a soft correction is not enough and a seek is issued. */
export const LISTEN_TOGETHER_SOFT_SYNC_FAST_DRIFT_MS: number = 1_500;

/**
 * A window after a load in which a reported position of 0 is treated as "the
 * player has not started yet" rather than as an authoritative rollback to the
 * beginning of the track.
 */
export const LISTEN_TOGETHER_UNEXPECTED_ZERO_POSITION_ROLLBACK_GUARD_MS: number = 2_000;
