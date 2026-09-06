/**
 * Port of listentogether/playback/ListenTogetherPlaybackSyncPolicies.kt: the two
 * rules that keep a listener aligned without visible jumps.
 */
import { isListenTogetherPassivePositionUpdateType } from '../control/ListenTogetherControlEventTypes';

/**
 * The playback rate a listener should adopt to close a small drift smoothly, or
 * null to leave the rate alone.
 *
 * Only drifts inside `[softSyncMinDriftMs, playingDriftForceSyncMs)` qualify:
 * below the floor there is nothing worth correcting, and at or above the force
 * threshold the caller seeks instead — nudging the rate there would take minutes
 * to converge. The controller never soft-syncs: it *is* the reference clock.
 *
 * A positive signed drift means the room is ahead of us, so we speed up; the
 * ±5 %/±3 % pairs are chosen to stay under the threshold where a pitch change
 * becomes audible.
 */
export function resolveListenTogetherSoftSyncPlaybackRate(
  driftMs: number,
  signedDriftMs: number,
  allowSoftSync: boolean,
  isController: boolean,
  softSyncMinDriftMs: number,
  softSyncFastDriftMs: number,
  playingDriftForceSyncMs: number
): number | null {
  if (!allowSoftSync || isController) {
    return null;
  }
  if (driftMs < softSyncMinDriftMs || driftMs >= playingDriftForceSyncMs) {
    return null;
  }
  if (signedDriftMs >= softSyncFastDriftMs) {
    return 1.05;
  }
  if (signedDriftMs > 0) {
    return 1.03;
  }
  if (signedDriftMs <= -softSyncFastDriftMs) {
    return 0.95;
  }
  return 0.97;
}

/**
 * True when a passive update reporting position 0 must be treated as a stale
 * snapshot rather than a real rewind.
 *
 * The room worker briefly reports 0 for a track it has accepted but not yet
 * timestamped. Obeying that would throw a listener who is a minute in back to the
 * start of the track. It is only safe to ignore when nothing about the track
 * changed — a genuine track switch legitimately arrives at position 0, and the
 * caller must seek there.
 */
export function shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
  causeType: string | null,
  desiredPlaying: boolean,
  expectedPositionMs: number,
  localPositionMs: number,
  playbackContextChanged: boolean,
  targetIndexChanged: boolean,
  zeroPositionRollbackGuardMs: number
): boolean {
  if (causeType === null || !isListenTogetherPassivePositionUpdateType(causeType)) {
    return false;
  }
  if (!desiredPlaying) {
    return false;
  }
  if (expectedPositionMs > 0) {
    return false;
  }
  // Close to the start of the track a rollback to 0 is indistinguishable from
  // the truth, so let it through rather than guessing.
  if (localPositionMs < zeroPositionRollbackGuardMs) {
    return false;
  }
  return !playbackContextChanged && !targetIndexChanged;
}
