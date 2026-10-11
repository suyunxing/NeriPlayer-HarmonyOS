// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/session/ListenTogetherJoinPolicy.kt.
 *
 * `autoPauseOnJoin` alone must not pause a room that is playing: the flag only
 * explains why a listener arrived into an already-paused room.
 */
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { LISTEN_TOGETHER_ROLE_LISTENER } from '../protocol/ListenTogetherSessionModels';

export const LISTEN_TOGETHER_JOIN_AUTO_PAUSE_CAUSE: string = 'JOIN_AUTO_PAUSE';

/**
 * Upstream #359 `shouldAutoPauseListenTogetherForMemberChange`: the
 * `autoPauseOnMemberChange` setting gates both join and departure pauses, so
 * both routes share one decision.
 */
export function shouldAutoPauseListenTogetherForMemberChange(
  autoPauseOnMemberChange: boolean,
  memberChangeType: string | null
): boolean {
  if (!autoPauseOnMemberChange) {
    return false;
  }
  return memberChangeType === 'MEMBER_JOINED' || memberChangeType === 'MEMBER_LEFT';
}

export function resolveListenTogetherJoinAutoPauseCause(
  autoPauseOnJoin: boolean,
  role: string | null,
  state: ListenTogetherRoomState
): string | null {
  if (
    !shouldAutoPauseListenTogetherForMemberChange(autoPauseOnJoin, 'MEMBER_JOINED') ||
    role !== LISTEN_TOGETHER_ROLE_LISTENER
  ) {
    return null;
  }
  return state.playback.state === 'paused' ? LISTEN_TOGETHER_JOIN_AUTO_PAUSE_CAUSE : null;
}
