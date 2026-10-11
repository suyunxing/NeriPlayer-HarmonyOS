// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherSoftSyncRecoveryPolicy.kt
 * (upstream #359, squashed 3cfd7037): what to do with an in-flight soft-sync
 * playback rate once rechecked. A rate below 1.0 is only valid while every
 * precondition still holds; otherwise it must be dropped before it keeps
 * skewing an already-diverged listener.
 */
export enum ListenTogetherSoftSyncRecheckAction {
  NONE,
  KEEP_RATE,
  RESET_RATE,
  FORCE_POSITION_SYNC
}

export function resolveListenTogetherSoftSyncRecheckAction(
  currentRate: number,
  sessionConnected: boolean,
  isController: boolean,
  desiredPlaying: boolean,
  localPlaying: boolean,
  currentTrackMatchesRoom: boolean,
  signedDriftMs: number,
  softSyncMinDriftMs: number,
  forcePositionSyncDriftMs: number
): ListenTogetherSoftSyncRecheckAction {
  if (Math.abs(currentRate - 1.0) < 0.001) {
    return ListenTogetherSoftSyncRecheckAction.NONE;
  }
  if (!sessionConnected || isController || !desiredPlaying || !localPlaying ||
    !currentTrackMatchesRoom) {
    return ListenTogetherSoftSyncRecheckAction.RESET_RATE;
  }
  const driftMs = Math.abs(signedDriftMs);
  if (driftMs >= forcePositionSyncDriftMs) {
    return ListenTogetherSoftSyncRecheckAction.FORCE_POSITION_SYNC;
  }
  return driftMs < softSyncMinDriftMs
    ? ListenTogetherSoftSyncRecheckAction.RESET_RATE
    : ListenTogetherSoftSyncRecheckAction.KEEP_RATE;
}
