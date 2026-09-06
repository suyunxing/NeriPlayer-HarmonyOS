/**
 * Port of listentogether/session/ListenTogetherIncomingStatePolicy.kt: which
 * incoming room states must be ignored, deferred, or applied, plus the heartbeat
 * and self-repair cadences.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherCause } from '../protocol/ListenTogetherEventModels';
import { isListenTogetherPassivePositionUpdateType } from '../control/ListenTogetherControlEventTypes';
import { listenTogetherCurrentStableKey } from '../playback/ListenTogetherPlaybackTrack';

/** Answers whether an event id is in one of the recent-event rings. */
export type ListenTogetherRecentEventPredicate = (eventId: string) => boolean;

/**
 * True when an incoming room state is this client's own event coming back and
 * must not be re-applied.
 *
 * `TRACK_FINISHED` is never ignored: the server, not the client, decides what
 * plays next, so that state carries information we do not have. A forwarded
 * `REQUEST_*` is never ignored either — it is the listener's request arriving at
 * the controller, which is exactly the case that must be acted on.
 *
 * One small divergence: the event id is trimmed before the ring lookups.
 * [ListenTogetherRecentEventTracker] trims on `mark`, and upstream queries with
 * the untrimmed value, so a padded id would never match what was stored. Trimming
 * on both sides closes that gap; no test depends on the padded behaviour.
 */
export function shouldIgnoreListenTogetherIncomingState(
  cause: ListenTogetherCause | null,
  currentUserId: string | null,
  hasRecentOutboundEvent: ListenTogetherRecentEventPredicate,
  hasRecentInboundEvent: ListenTogetherRecentEventPredicate
): boolean {
  const causeType = cause === null ? null : cause.type;
  if (causeType === 'TRACK_FINISHED') {
    return false;
  }
  if (causeType !== null && causeType.startsWith('REQUEST_')) {
    return false;
  }
  const rawEventId = cause === null ? null : cause.eventId;
  const eventId = rawEventId === null ? '' : rawEventId.trim();
  if (eventId.length === 0) {
    return false;
  }
  if (hasRecentOutboundEvent(eventId) || hasRecentInboundEvent(eventId)) {
    return true;
  }
  // Same author, different id: still our own action, seen through the server.
  return (cause === null ? null : cause.userUuid) === currentUserId;
}

/**
 * True while a local `TRACK_FINISHED` is still in flight and the room has not
 * yet moved off the finished track: applying a passive position update now would
 * seek back into a track we are about to leave.
 */
export function shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
  state: ListenTogetherRoomState,
  cause: ListenTogetherCause | null,
  awaitingTrackFinishStableKey: string | null
): boolean {
  if (awaitingTrackFinishStableKey === null) {
    return false;
  }
  const causeType = cause === null ? null : cause.type;
  if (causeType === null || !isListenTogetherPassivePositionUpdateType(causeType)) {
    return false;
  }
  if (state.playback.state !== 'playing') {
    return false;
  }
  return listenTogetherCurrentStableKey(state) === awaitingTrackFinishStableKey;
}

/**
 * True when a candidate room state may drive the local player.
 *
 * Equal versions are accepted, not just greater ones: the server re-sends the
 * same version over different transports (HTTP refresh and websocket push), and
 * the later arrival may be the one that finally reaches a player that was not
 * ready before.
 */
export function shouldApplyListenTogetherRoomStateToPlayer(
  candidateState: ListenTogetherRoomState,
  currentState: ListenTogetherRoomState | null
): boolean {
  if (currentState === null) {
    return false;
  }
  if (candidateState.roomId !== currentState.roomId) {
    return false;
  }
  return candidateState.version >= currentState.version;
}

/**
 * Listener-side self repair: whether to re-fetch the room over HTTP because the
 * websocket has gone quiet or a version gap was observed.
 *
 * The minimum-interval gate comes first, so a repair storm cannot be triggered
 * by a persistent gap.
 */
export function shouldRepairListenTogetherListenerState(
  nowElapsedMs: number,
  lastWebSocketMessageAtElapsedMs: number,
  lastRefreshAtElapsedMs: number,
  pendingVersionGap: number,
  webSocketSilenceTimeoutMs: number,
  repairMinIntervalMs: number
): boolean {
  if (lastRefreshAtElapsedMs > 0 && nowElapsedMs - lastRefreshAtElapsedMs < repairMinIntervalMs) {
    return false;
  }
  if (pendingVersionGap >= 0) {
    return true;
  }
  if (lastWebSocketMessageAtElapsedMs <= 0) {
    return true;
  }
  return nowElapsedMs - lastWebSocketMessageAtElapsedMs >= webSocketSilenceTimeoutMs;
}

/**
 * Upstream `LISTEN_TOGETHER_PLAYING_HEARTBEAT_INTERVAL_MS`. Both cadences must
 * stay comfortably under the room worker's controller timeout, or the controller
 * would be declared offline while it is happily playing.
 */
export const LISTEN_TOGETHER_PLAYING_HEARTBEAT_INTERVAL_MS: number = 22_000;
/** Upstream `LISTEN_TOGETHER_PAUSED_HEARTBEAT_INTERVAL_MS`. */
export const LISTEN_TOGETHER_PAUSED_HEARTBEAT_INTERVAL_MS: number = 25_000;
/**
 * The room worker's controller-offline timeout. Not sent or received — it is the
 * server-side budget both heartbeat cadences must fit inside, asserted by the
 * unit suite so a future tweak cannot silently cross it.
 */
export const LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS: number = 45_000;

export function resolveListenTogetherHeartbeatIntervalMs(
  isPlaying: boolean,
  playingIntervalMs: number = LISTEN_TOGETHER_PLAYING_HEARTBEAT_INTERVAL_MS,
  pausedIntervalMs: number = LISTEN_TOGETHER_PAUSED_HEARTBEAT_INTERVAL_MS
): number {
  return isPlaying ? playingIntervalMs : pausedIntervalMs;
}
