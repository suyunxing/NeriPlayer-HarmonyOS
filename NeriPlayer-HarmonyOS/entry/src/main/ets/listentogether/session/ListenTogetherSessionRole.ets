// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherSessionRole.kt: the room state is
 * authoritative about who holds control, so the locally cached role is only a
 * fallback for when either side of the comparison is unknown.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import {
  LISTEN_TOGETHER_ROLE_CONTROLLER,
  LISTEN_TOGETHER_ROLE_LISTENER
} from '../protocol/ListenTogetherSessionModels';

function blankToNull(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function resolveListenTogetherSessionRole(
  sessionUserId: string | null,
  fallbackRole: string | null,
  state: ListenTogetherRoomState | null
): string | null {
  const normalizedUserId = blankToNull(sessionUserId);
  let controllerUserId: string | null = null;
  if (state !== null) {
    controllerUserId = blankToNull(state.controllerUserUuid);
    if (controllerUserId === null) {
      controllerUserId = blankToNull(state.controllerUserId);
    }
  }
  if (normalizedUserId !== null && controllerUserId !== null) {
    return normalizedUserId === controllerUserId
      ? LISTEN_TOGETHER_ROLE_CONTROLLER
      : LISTEN_TOGETHER_ROLE_LISTENER;
  }
  return fallbackRole;
}
