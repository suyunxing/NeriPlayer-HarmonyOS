// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherQueuePolicy.kt.
 *
 * A huge local queue is not shared whole: the window keeps the playing track
 * (and its neighbours) so the room stays under the server's queue limit.
 */
import { ListenTogetherTrack } from '../protocol/ListenTogetherTrack';

export const LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE: number = 2000;

function coerceIn(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

export function boundedListenTogetherQueueAroundStableKey(
  queue: ListenTogetherTrack[],
  targetStableKey: string | null
): ListenTogetherTrack[] {
  if (queue.length <= LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE) {
    return queue;
  }
  let targetIndex = 0;
  if (targetStableKey !== null) {
    for (let i = 0; i < queue.length; i++) {
      if (queue[i].stableKey === targetStableKey) {
        targetIndex = i;
        break;
      }
    }
  }
  const maxSize = LISTEN_TOGETHER_MAX_SHAREABLE_QUEUE_SIZE;
  const halfWindow = Math.trunc(maxSize / 2);
  const start = coerceIn(targetIndex - halfWindow, 0, queue.length - maxSize);
  return queue.slice(start, start + maxSize);
}
