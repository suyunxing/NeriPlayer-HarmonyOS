// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherRoomClosurePolicy.kt (upstream
 * #359, squashed 3cfd7037): whether the final room state carried by a
 * room_closed broadcast calls for a local pause. The controller's departure
 * already paused its own transport; listeners mirror that paused state instead
 * of playing on into an empty room.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';

export function shouldApplyListenTogetherClosedRoomPause(state: ListenTogetherRoomState): boolean {
  return state.playback.state === 'paused';
}
