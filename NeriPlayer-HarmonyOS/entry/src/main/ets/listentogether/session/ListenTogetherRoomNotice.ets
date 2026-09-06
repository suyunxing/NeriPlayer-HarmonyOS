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

export function resolveListenTogetherRoomNotice(
  state: ListenTogetherRoomState | null,
  fallbackMessage: string | null = null,
  nowMs: number = Date.now(),
  controllerGracePeriodMs: number = LISTEN_TOGETHER_DEFAULT_CONTROLLER_GRACE_PERIOD_MS
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
    return fallbackMessage ?? state.closedReason ?? LISTEN_TOGETHER_NOTICE_ROOM_CLOSED;
  }
  return fallbackMessage;
}
