// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherForegroundRecoveryPolicy.kt
 * plus the coalesced-control job identity check from the same upstream wave
 * (#359, squashed 3cfd7037).
 *
 * Divergence: upstream identifies the in-flight coalescing coroutine by its
 * `Job` reference; this port runs on the single-threaded event loop with plain
 * numeric generations, so the identity check compares those instead.
 */
import { ListenTogetherConnectionState } from '../protocol/ListenTogetherSessionModels';

export enum ListenTogetherForegroundRecoveryAction {
  NONE,
  CONNECT,
  REFRESH_ROOM_STATE
}

/** Upstream `DEFAULT_CONNECTING_TIMEOUT_MS`. */
export const LISTEN_TOGETHER_DEFAULT_CONNECTING_TIMEOUT_MS: number = 15000;

/**
 * What returning to the foreground should do about the room socket: reconnect
 * when it dropped, refresh when it claims to be live, and force a reconnect
 * when CONNECTING has been stuck past the timeout (the socket layer may have
 * died without reporting).
 */
export function resolveListenTogetherForegroundRecoveryAction(
  connectionState: ListenTogetherConnectionState,
  roomId: string | null,
  wsUrl: string | null,
  reconnectEnabled: boolean,
  connectingSinceMs: number = 0,
  nowMs: number = 0,
  connectingTimeoutMs: number = LISTEN_TOGETHER_DEFAULT_CONNECTING_TIMEOUT_MS
): ListenTogetherForegroundRecoveryAction {
  if (!reconnectEnabled || roomId === null || roomId.trim().length === 0 ||
    wsUrl === null || wsUrl.trim().length === 0) {
    return ListenTogetherForegroundRecoveryAction.NONE;
  }
  if (connectionState === ListenTogetherConnectionState.DISCONNECTED) {
    return ListenTogetherForegroundRecoveryAction.CONNECT;
  }
  if (connectionState === ListenTogetherConnectionState.CONNECTED) {
    return ListenTogetherForegroundRecoveryAction.REFRESH_ROOM_STATE;
  }
  const connectingDurationMs = nowMs - connectingSinceMs;
  if (connectingSinceMs > 0 && nowMs >= connectingSinceMs &&
    connectingDurationMs >= Math.max(connectingTimeoutMs, 0)) {
    return ListenTogetherForegroundRecoveryAction.CONNECT;
  }
  return ListenTogetherForegroundRecoveryAction.NONE;
}

/**
 * After a foreground ping probe: reconnect only when the socket still says
 * CONNECTED, the room is the one probed, and nothing at all arrived since the
 * probe started — anything received proves the pipe is alive.
 */
export function shouldReconnectListenTogetherForegroundSocket(
  reconnectEnabled: boolean,
  connectionState: ListenTogetherConnectionState,
  expectedRoomId: string | null,
  currentRoomId: string | null,
  lastWebSocketMessageAtMs: number,
  probeStartedAtMs: number
): boolean {
  return reconnectEnabled &&
    connectionState === ListenTogetherConnectionState.CONNECTED &&
    expectedRoomId !== null && expectedRoomId.trim().length > 0 &&
    expectedRoomId === currentRoomId &&
    lastWebSocketMessageAtMs < probeStartedAtMs;
}

/**
 * Upstream `isCurrentListenTogetherCoalescedControlJob(currentJob, completingJob)`
 * with job references replaced by generation numbers: a newer enqueue for the
 * same event type bumps the generation, and the older timer fires stale.
 */
export function isCurrentListenTogetherCoalescedControlJob(
  currentJobId: number,
  completingJobId: number
): boolean {
  return currentJobId === completingJobId;
}
