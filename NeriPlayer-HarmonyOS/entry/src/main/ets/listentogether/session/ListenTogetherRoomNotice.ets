// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherRoomNotice.kt: the single line of
 * room status shown above the player.
 *
 * Upstream returns the notice as a raw string (already localised by the caller
 * for the offline countdown, and server-supplied for a close reason), so the
 * codes below are passed through verbatim. `controller_offline:<n>` keeps the
 * minute count in the payload rather than formatting it here — M7.4's UI maps
 * both the bare codes and the countdown form to display text.
 */
import { ListenTogetherRoomState, ListenTogetherRoomStatuses } from '../protocol/ListenTogetherRoomModels';

/** Upstream `DEFAULT_CONTROLLER_GRACE_PERIOD_MS`. */
export const LISTEN_TOGETHER_DEFAULT_CONTROLLER_GRACE_PERIOD_MS: number = 10 * 60 * 1000;

export const LISTEN_TOGETHER_NOTICE_CONTROLLER_OFFLINE: string = 'controller_offline';
export const LISTEN_TOGETHER_NOTICE_ROOM_CLOSED: string = 'room_closed';
export const LISTEN_TOGETHER_NOTICE_CONTROLLER_LEFT: string = 'controller_left';
export const LISTEN_TOGETHER_NOTICE_CONTROLLER_RECONNECTED: string = 'controller_reconnected';

/**
 * Upstream #359: trims free-text close reasons to the canonical codes the UI
 * knows how to localize; unknown text passes through verbatim.
 */
export function normalizeListenTogetherRoomClosureReason(reason: string | null): string | null {
  if (reason === null) {
    return null;
  }
  const normalizedReason = reason.trim();
  if (normalizedReason.length === 0) {
    return null;
  }
  const lowered = normalizedReason.toLowerCase();
  if (lowered === 'controller_left') {
    return LISTEN_TOGETHER_NOTICE_CONTROLLER_LEFT;
  }
  if (lowered === 'controller_timeout') {
    return 'controller_timeout';
  }
  if (lowered === 'room_closed') {
    return LISTEN_TOGETHER_NOTICE_ROOM_CLOSED;
  }
  return normalizedReason;
}

/** `controller_left` is the one closure that is not an error anywhere. */
export function isNormalListenTogetherRoomClosureReason(reason: string | null): boolean {
  return normalizeListenTogetherRoomClosureReason(reason) === LISTEN_TOGETHER_NOTICE_CONTROLLER_LEFT;
}

/**
 * Upstream #359: a listener that saw the controller go offline deserves a
 * "controller reconnected" line when the room resumes.
 */
export function shouldShowListenTogetherControllerReconnectedNotice(
  isCurrentUserController: boolean,
  observedControllerOffline: boolean
): boolean {
  return !isCurrentUserController && observedControllerOffline;
}

export function resolveListenTogetherRoomNotice(
  state: ListenTogetherRoomState | null,
  fallbackMessage: string | null = null,
  nowMs: number = Date.now(),
  controllerGracePeriodMs: number = LISTEN_TOGETHER_DEFAULT_CONTROLLER_GRACE_PERIOD_MS,
  showControllerReconnected: boolean = false
): string | null {
  if (state === null) {
    return fallbackMessage;
  }
  if (state.roomStatus === ListenTogetherRoomStatuses.CONTROLLER_OFFLINE) {
    const offlineSince = state.controllerOfflineSince;
    if (offlineSince === null) {
      return fallbackMessage ?? LISTEN_TOGETHER_NOTICE_CONTROLLER_OFFLINE;
    }
    const remainingMs = Math.max(offlineSince + controllerGracePeriodMs - nowMs, 0);
    // Floor to whole minutes then add one, matching upstream: the countdown
    // reads "1 minute left" through the final minute rather than "0".
    const remainingMinutes = Math.max(Math.floor(remainingMs / 60000), 0);
    return `${LISTEN_TOGETHER_NOTICE_CONTROLLER_OFFLINE}:${remainingMinutes + 1}`;
  }
  if (state.roomStatus === ListenTogetherRoomStatuses.CLOSED) {
    // The server's close reason is authoritative over any relayed text.
    const closedReason = state.closedReason === null ? null : state.closedReason.trim();
    if (closedReason !== null && closedReason.length > 0) {
      return closedReason;
    }
    return fallbackMessage ?? LISTEN_TOGETHER_NOTICE_ROOM_CLOSED;
  }
  if (fallbackMessage !== null &&
    fallbackMessage.toLowerCase() === LISTEN_TOGETHER_NOTICE_CONTROLLER_RECONNECTED &&
    !showControllerReconnected) {
    return null;
  }
  return fallbackMessage;
}
