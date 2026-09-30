// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherControlBlockPolicy.kt: why a
 * local playback command must be refused while a room session is active.
 *
 * **Divergence: reason codes instead of strings.** Upstream takes an Android
 * `Context` and returns an `@StringRes Int`, so the policy itself is a pure
 * lookup and the caller resolves the text. HarmonyOS resources are read through
 * a `resourceManager` bound to a UI context, which would drag a UI dependency
 * into a pure-logic file and make it untestable on the host. So this returns a
 * stable code and M7.4's room UI owns the code → text table. The codes are
 * internal to this client (never sent on the wire), so they are free to change
 * as long as both sides move together.
 */
import {
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  normalizedListenTogetherRoomSettings
} from '../protocol/ListenTogetherRoomModels';
import { LISTEN_TOGETHER_ROLE_CONTROLLER, LISTEN_TOGETHER_ROLE_LISTENER } from '../protocol/ListenTogetherSessionModels';
import { isListenTogetherControlledPlaybackCommandType } from '../control/ListenTogetherControlEventTypes';

/** Upstream `R.string.listen_together_error_controller_offline_link`. */
export const LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE_LINK: string = 'controller_offline_link';
/** Upstream `R.string.listen_together_error_controller_offline`. */
export const LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE: string = 'controller_offline';
/** Upstream `R.string.listen_together_error_member_control_disabled`. */
export const LISTEN_TOGETHER_BLOCK_REASON_MEMBER_CONTROL_DISABLED: string = 'member_control_disabled';

/**
 * Returns the reason a command must be blocked, or null when it may proceed.
 *
 * The offline branch deliberately fires for every non-controller role, including
 * an unknown one: with no controller answering, nobody may drive the room.
 */
export function resolveListenTogetherControlBlockReason(
  sessionRole: string | null,
  roomState: ListenTogetherRoomState | null,
  commandType: string
): string | null {
  if (
    roomState !== null &&
    roomState.roomStatus === ListenTogetherRoomStatuses.CONTROLLER_OFFLINE &&
    sessionRole !== LISTEN_TOGETHER_ROLE_CONTROLLER
  ) {
    return normalizedListenTogetherRoomSettings(roomState.settings).shareAudioLinks
      ? LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE_LINK
      : LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE;
  }
  const allowMemberControl = roomState === null
    ? null
    : normalizedListenTogetherRoomSettings(roomState.settings).allowMemberControl;
  if (
    sessionRole === LISTEN_TOGETHER_ROLE_LISTENER &&
    allowMemberControl === false &&
    isListenTogetherControlledPlaybackCommandType(commandType)
  ) {
    return LISTEN_TOGETHER_BLOCK_REASON_MEMBER_CONTROL_DISABLED;
  }
  return null;
}

/**
 * Controller side: whether a forwarded `REQUEST_*` from a listener must be
 * dropped instead of committed.
 *
 * A blank or missing requester id cannot be proven to be the controller, so it
 * is rejected — the server may forward a request whose author it could not
 * attribute, and honouring it would let member control back in through the door
 * the room settings just closed.
 */
export function shouldRejectForwardedListenTogetherMemberControl(
  requesterUuid: string | null,
  controllerUserUuid: string | null,
  allowMemberControl: boolean
): boolean {
  if (allowMemberControl) {
    return false;
  }
  const requester = requesterUuid === null ? '' : requesterUuid.trim();
  const isRequesterController = requester.length > 0 && requesterUuid === controllerUserUuid;
  return !isRequesterController;
}
