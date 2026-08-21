/**
 * Port of listentogether/control/ListenTogetherControlEventTypes.kt.
 *
 * The wire event names are shared with the Android client and the room server;
 * they must stay byte-identical. Kotlin exposes immutable `setOf(...)`, so each
 * set is paired with a predicate that call sites should prefer over touching
 * the Set instance.
 */

export const LISTEN_TOGETHER_CONTROLLER_HEARTBEAT_RECOVERY_TYPES: Set<string> = new Set<string>([
  'MEMBER_JOINED',
  'PLAY',
  'PAUSE',
  'SEEK',
  'PLAYBACK_MODE',
  'SET_TRACK',
  'SET_QUEUE',
  'REQUEST_PLAY',
  'REQUEST_PAUSE',
  'REQUEST_SEEK',
  'REQUEST_PLAYBACK_MODE',
  'REQUEST_SET_TRACK'
]);

export const LISTEN_TOGETHER_PASSIVE_POSITION_UPDATE_TYPES: Set<string> = new Set<string>([
  'HEARTBEAT',
  'WATCHDOG',
  'WATCHDOG_STALL',
  'LINK_READY',
  'MEMBER_JOINED',
  'MEMBER_LEFT'
]);

export const LISTEN_TOGETHER_CONTROLLED_PLAYBACK_COMMAND_TYPES: Set<string> = new Set<string>([
  'PLAY_PLAYLIST',
  'PLAY_FROM_QUEUE',
  'NEXT',
  'PREVIOUS',
  'PLAY',
  'PAUSE',
  'PLAYBACK_MODE',
  'SEEK'
]);

export const LISTEN_TOGETHER_REQUEST_CONTROL_EVENT_TYPES: Set<string> = new Set<string>([
  'REQUEST_PLAY',
  'REQUEST_PAUSE',
  'REQUEST_SEEK',
  'REQUEST_PLAYBACK_MODE',
  'REQUEST_SET_TRACK'
]);

export const LISTEN_TOGETHER_TRACK_BOUND_REQUEST_CONTROL_EVENT_TYPES: Set<string> = new Set<string>([
  'REQUEST_PLAY',
  'REQUEST_PAUSE',
  'REQUEST_SEEK'
]);

/** Events that prove the controller is alive again. */
export function isListenTogetherControllerHeartbeatRecoveryType(type: string): boolean {
  return LISTEN_TOGETHER_CONTROLLER_HEARTBEAT_RECOVERY_TYPES.has(type);
}

/** Events that only carry a position refresh, never a user intent. */
export function isListenTogetherPassivePositionUpdateType(type: string): boolean {
  return LISTEN_TOGETHER_PASSIVE_POSITION_UPDATE_TYPES.has(type);
}

/** Local player commands the room takes over while a session is active. */
export function isListenTogetherControlledPlaybackCommandType(type: string): boolean {
  return LISTEN_TOGETHER_CONTROLLED_PLAYBACK_COMMAND_TYPES.has(type);
}

/** Listener-side requests forwarded to the controller. */
export function isListenTogetherRequestControlEventType(type: string): boolean {
  return LISTEN_TOGETHER_REQUEST_CONTROL_EVENT_TYPES.has(type);
}

/** Requests that only apply while the room still plays the requested track. */
export function isListenTogetherTrackBoundRequestControlEventType(type: string): boolean {
  return LISTEN_TOGETHER_TRACK_BOUND_REQUEST_CONTROL_EVENT_TYPES.has(type);
}
