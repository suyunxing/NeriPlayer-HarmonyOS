/**
 * Port of listentogether/playback/ListenTogetherShareableQueueSnapshot.kt.
 *
 * Divergences forced by this port:
 * - Kotlin returns `Pair<List<ListenTogetherTrack>, Int>`; ArkTS has no Pair, so
 *   the result is a small class;
 * - the resolved stream urls are passed in instead of read from
 *   `PlayerManager.currentListenTogetherShareableStreamUrls()`, keeping this file
 *   free of a player dependency (the session layer injects them in M7.3).
 */
import { SongItem } from '../../model/SongItem';
import {
  ListenTogetherRoomSettings,
  normalizedListenTogetherRoomSettings
} from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherTrack, listenTogetherTrackEquals } from '../protocol/ListenTogetherTrack';
import {
  listenTogetherTrackWithStreamUrls,
  songItemToListenTogetherTrackOrNull
} from '../mapping/ListenTogetherTrackMapping';
import { ListenTogetherBlockedStreamUrlListener } from '../mapping/ListenTogetherStreamUrlPolicy';
import { boundedListenTogetherQueueAroundStableKey } from './ListenTogetherQueuePolicy';

export class ListenTogetherShareableQueueSnapshot {
  readonly tracks: ListenTogetherTrack[];
  readonly currentIndex: number;

  constructor(tracks: ListenTogetherTrack[], currentIndex: number) {
    this.tracks = tracks;
    this.currentIndex = currentIndex;
  }
}

export function listenTogetherShareableQueueSnapshot(
  queue: SongItem[],
  currentIndex: number,
  currentStreamUrls: string[] = [],
  roomSettings: ListenTogetherRoomSettings | null = null,
  includeResolvedStreamUrl: boolean = true,
  onBlocked: ListenTogetherBlockedStreamUrlListener | null = null
): ListenTogetherShareableQueueSnapshot {
  if (queue.length === 0) {
    return new ListenTogetherShareableQueueSnapshot([], 0);
  }
  const lastIndex = queue.length - 1;
  const targetIndex = Math.min(Math.max(currentIndex, 0), lastIndex);
  const targetTrack = songItemToListenTogetherTrackOrNull(queue[targetIndex]);
  const targetStableKey = targetTrack === null ? null : targetTrack.stableKey;
  const streamUrls = includeResolvedStreamUrl ? currentStreamUrls : [];
  const shareAudioLinks = normalizedListenTogetherRoomSettings(roomSettings).shareAudioLinks;
  const mapped: ListenTogetherTrack[] = [];
  for (const song of queue) {
    const track = songItemToListenTogetherTrackOrNull(song);
    if (track === null) {
      continue;
    }
    if (shareAudioLinks && targetStableKey !== null && track.stableKey === targetStableKey) {
      mapped.push(listenTogetherTrackWithStreamUrls(track, streamUrls, onBlocked));
    } else {
      mapped.push(track);
    }
  }
  const shareableQueue = boundedListenTogetherQueueAroundStableKey(mapped, targetStableKey);
  if (shareableQueue.length === 0) {
    return new ListenTogetherShareableQueueSnapshot(shareableQueue, 0);
  }
  let resolvedCurrentIndex = 0;
  if (targetStableKey !== null) {
    for (let i = 0; i < shareableQueue.length; i++) {
      if (shareableQueue[i].stableKey === targetStableKey) {
        resolvedCurrentIndex = i;
        break;
      }
    }
  }
  return new ListenTogetherShareableQueueSnapshot(shareableQueue, resolvedCurrentIndex);
}

/** Replaces the queue entry at `currentIndex` with the authoritative track. */
export function mergeListenTogetherCurrentTrack(
  queue: ListenTogetherTrack[],
  currentIndex: number,
  currentTrack: ListenTogetherTrack | null
): ListenTogetherTrack[] {
  if (currentTrack === null) {
    return queue;
  }
  if (currentIndex < 0 || currentIndex >= queue.length) {
    return queue;
  }
  if (listenTogetherTrackEquals(queue[currentIndex], currentTrack)) {
    return queue;
  }
  const merged = queue.slice();
  merged[currentIndex] = currentTrack;
  return merged;
}
