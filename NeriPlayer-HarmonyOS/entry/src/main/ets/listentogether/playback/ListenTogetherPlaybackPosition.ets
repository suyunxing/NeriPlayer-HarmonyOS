/**
 * Port of listentogether/playback/ListenTogetherPlaybackPosition.kt.
 *
 * `nowMs` is a required parameter here (Android defaults it to
 * `System.currentTimeMillis()`): the position math must stay deterministic for
 * the unit tests, and every caller already has a timestamp at hand.
 */
import { ListenTogetherPlaybackState } from '../protocol/ListenTogetherRoomModels';

export const LISTEN_TOGETHER_REPEAT_MODE_ONE: number = 1;

/** Single-track repeat wraps the extrapolated position back into the track. */
export function wrapListenTogetherSingleTrackRepeatPosition(
  positionMs: number,
  repeatMode: number | null,
  durationMs: number
): number {
  const flooredPositionMs = Math.max(positionMs, 0);
  if (repeatMode !== LISTEN_TOGETHER_REPEAT_MODE_ONE || durationMs <= 0) {
    return flooredPositionMs;
  }
  return flooredPositionMs % durationMs;
}

/** Extrapolates the authoritative position onto the local clock. */
export function listenTogetherExpectedPositionMs(
  playback: ListenTogetherPlaybackState,
  nowMs: number,
  serverClockOffsetMs: number = 0,
  durationMs: number = 0
): number {
  const correctedNowMs = nowMs + serverClockOffsetMs;
  if (playback.state !== 'playing') {
    return Math.max(playback.basePositionMs, 0);
  }
  // An illegal baseTimestampMs (<= 0) falls back to the current clock, so the
  // elapsed difference cannot push the position to an astronomical value.
  const effectiveBaseTimestampMs = playback.baseTimestampMs > 0
    ? playback.baseTimestampMs
    : correctedNowMs;
  const elapsedMs = correctedNowMs - effectiveBaseTimestampMs;
  // Kotlin `.toLong()` truncates toward zero before the floor at 0.
  const estimatedPositionMs = Math.max(
    Math.trunc(playback.basePositionMs + elapsedMs * playback.playbackRate),
    0
  );
  return wrapListenTogetherSingleTrackRepeatPosition(
    estimatedPositionMs,
    playback.repeatMode,
    durationMs
  );
}

export function clampListenTogetherPositionMs(positionMs: number, durationMs: number): number {
  const floored = Math.max(positionMs, 0);
  return durationMs > 0 ? Math.min(floored, durationMs) : floored;
}

/** A seek is satisfied once the authoritative base position is close enough. */
export function isListenTogetherSeekControlSatisfied(
  playback: ListenTogetherPlaybackState,
  requestedPositionMs: number,
  satisfiedDriftMs: number = 1500
): boolean {
  const base = Math.max(playback.basePositionMs, 0);
  const requested = Math.max(requestedPositionMs, 0);
  return Math.abs(base - requested) <= satisfiedDriftMs;
}
