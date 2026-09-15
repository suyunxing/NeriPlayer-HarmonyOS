// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherControllerEchoPolicy.kt.
 *
 * The controller applies its own commands locally first and only then publishes
 * them. The room state that comes back is therefore a stale echo of something
 * already applied, and re-applying it would make the controller's own playback
 * stutter. `TRACK_FINISHED` is exempt because the server, not the client, picks
 * the next track, so that echo carries information the controller does not have.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherCause } from '../protocol/ListenTogetherEventModels';

export function shouldDropListenTogetherControllerLocalEcho(
  state: ListenTogetherRoomState,
  cause: ListenTogetherCause | null,
  latestVersion: number,
  currentUserId: string | null,
  lastControllerLocalControlAtElapsedMs: number,
  nowElapsedMs: number,
  controllerLocalControlCooldownMs: number
): boolean {
  if (cause !== null && cause.type === 'TRACK_FINISHED') {
    return false;
  }
  const controllerId = state.controllerUserUuid ?? state.controllerUserId;
  const causeUserUuid = cause === null ? null : cause.userUuid;
  return currentUserId === controllerId &&
    causeUserUuid === currentUserId &&
    nowElapsedMs - lastControllerLocalControlAtElapsedMs < controllerLocalControlCooldownMs &&
    // One version ahead is still an echo: the server bumps the version when it
    // accepts the command the controller already applied.
    state.version <= latestVersion + 1;
}
