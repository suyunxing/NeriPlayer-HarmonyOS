// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherRestoredPlaybackPolicy.kt
 * (upstream #359, squashed 3cfd7037): a restored "resume playback on launch"
 * request must not fire underneath an active room. The controller owns its own
 * transport, but a listener may only resume once the room state has arrived
 * and said playing — resuming on a stale local position would desync the room.
 */
export enum ListenTogetherRestoredPlaybackAction {
  SKIP,
  RESUME_LOCAL_PLAYBACK,
  WAIT_FOR_AUTHORITATIVE_ROOM_STATE
}

export function resolveListenTogetherRestoredPlaybackAction(
  restoredPlaybackRequested: boolean,
  listenTogetherSessionActive: boolean,
  currentUserIsController: boolean
): ListenTogetherRestoredPlaybackAction {
  if (!restoredPlaybackRequested) {
    return ListenTogetherRestoredPlaybackAction.SKIP;
  }
  if (!listenTogetherSessionActive || currentUserIsController) {
    return ListenTogetherRestoredPlaybackAction.RESUME_LOCAL_PLAYBACK;
  }
  return ListenTogetherRestoredPlaybackAction.WAIT_FOR_AUTHORITATIVE_ROOM_STATE;
}
