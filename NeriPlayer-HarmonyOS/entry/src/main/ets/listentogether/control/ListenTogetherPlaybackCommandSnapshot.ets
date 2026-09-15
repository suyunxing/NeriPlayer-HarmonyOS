// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/control/ListenTogetherPlaybackCommandSnapshot.kt.
 *
 * A local playback command may or may not carry its own queue/position; an
 * empty queue means "keep what is playing" rather than "clear the queue".
 */

export class ListenTogetherPlaybackCommandSnapshot<T> {
  readonly queue: T[];
  readonly positionMs: number;

  constructor(queue: T[], positionMs: number) {
    this.queue = queue;
    this.positionMs = positionMs;
  }
}

export function resolveListenTogetherPlaybackCommandSnapshot<T>(
  commandQueue: T[] | null,
  commandPositionMs: number | null,
  currentQueue: T[],
  currentPositionMs: number
): ListenTogetherPlaybackCommandSnapshot<T> {
  const queue = commandQueue !== null && commandQueue.length > 0 ? commandQueue : currentQueue;
  const rawPositionMs = commandPositionMs === null ? currentPositionMs : commandPositionMs;
  return new ListenTogetherPlaybackCommandSnapshot<T>(queue, Math.max(rawPositionMs, 0));
}
