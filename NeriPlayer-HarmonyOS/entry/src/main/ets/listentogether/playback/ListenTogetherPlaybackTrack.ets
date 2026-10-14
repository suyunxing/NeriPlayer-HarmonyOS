// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherPlaybackTrack.kt: which track a
 * room state or a control event is talking about, and how two local songs are
 * compared as "the same track".
 *
 * Kotlin `?:` chains only fall through on null, so an explicitly empty
 * `stableKey` is returned as-is instead of falling back to the queue.
 */
import { SongItem } from '../../model/SongItem';
import { ListenTogetherEvent } from '../protocol/ListenTogetherEventModels';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherTrack } from '../protocol/ListenTogetherTrack';
import { listenTogetherTrackToSongItem } from '../mapping/ListenTogetherTrackMapping';
import {
  resolvedListenTogetherAudioId,
  resolvedListenTogetherChannelId,
  resolvedListenTogetherPlaylistContextId,
  resolvedListenTogetherSubAudioId
} from '../mapping/ListenTogetherTrackIdentity';
import { trustedListenTogetherStreamUrls } from '../mapping/ListenTogetherStreamUrlPolicy';

function trackAt(queue: ListenTogetherTrack[], index: number): ListenTogetherTrack | null {
  return index >= 0 && index < queue.length ? queue[index] : null;
}

/**
 * Upstream #359: the queue slot wins over the legacy single `track` field — a
 * V2 server keeps `track` only for pre-mutation listeners, and index drift
 * between the two would make different peers pick different songs.
 */
export function listenTogetherCurrentTrack(state: ListenTogetherRoomState): ListenTogetherTrack | null {
  if (state.queue.length > 0) {
    const index = Math.min(Math.max(state.currentIndex, 0), state.queue.length - 1);
    return state.queue[index];
  }
  return state.track;
}

export function listenTogetherCurrentStableKey(state: ListenTogetherRoomState): string | null {
  const current = listenTogetherCurrentTrack(state);
  return current === null ? null : current.stableKey;
}

/**
 * The whitelisted direct links for the track the room is actually on: queue
 * slot first, then the legacy `track` field when it names the same track.
 */
export function listenTogetherAuthoritativeStreamUrlsForCurrentTrack(
  state: ListenTogetherRoomState
): string[] {
  const targetTrack = listenTogetherCurrentTrack(state);
  if (targetTrack === null) {
    return [];
  }
  const candidates: ListenTogetherTrack[] = [targetTrack];
  if (state.track !== null && state.track.stableKey === targetTrack.stableKey) {
    candidates.push(state.track);
  }
  const urls: string[] = [];
  for (const candidate of candidates) {
    for (const url of trustedListenTogetherStreamUrls(
      candidate.channelId,
      candidate.streamUrls,
      candidate.streamUrl
    )) {
      if (urls.indexOf(url) < 0) {
        urls.push(url);
      }
    }
  }
  return urls;
}

export function listenTogetherAuthoritativeStreamUrlForCurrentTrack(
  state: ListenTogetherRoomState
): string | null {
  const urls = listenTogetherAuthoritativeStreamUrlsForCurrentTrack(state);
  return urls.length > 0 ? urls[0] : null;
}

export function listenTogetherRequestedStableKey(event: ListenTogetherEvent): string | null {
  if (event.requestTrackStableKey !== null) {
    return event.requestTrackStableKey;
  }
  if (event.queue !== null) {
    const queued = trackAt(event.queue, event.currentIndex === null ? -1 : event.currentIndex);
    if (queued !== null) {
      return queued.stableKey;
    }
  }
  if (event.track !== null) {
    return event.track.stableKey;
  }
  return null;
}

/**
 * Upstream #359 `resolveListenTogetherQueueIndex`: where a queue update wants
 * the current index to land. The index is authoritative only while it still
 * names the preferred track; otherwise the preferred stableKey wins, and only
 * then does the raw index survive (clamped to a non-empty queue).
 */
export function resolveListenTogetherQueueIndex(
  queue: ListenTogetherTrack[],
  requestedIndex: number,
  preferredStableKey: string | null
): number {
  if (queue.length === 0) {
    return -1;
  }
  const indexedPosition = requestedIndex >= 0 && requestedIndex < queue.length ? requestedIndex : -1;
  if (preferredStableKey === null || preferredStableKey.trim().length === 0) {
    return indexedPosition >= 0 ? indexedPosition : 0;
  }
  if (indexedPosition >= 0 && queue[indexedPosition].stableKey === preferredStableKey) {
    return indexedPosition;
  }
  for (let index = 0; index < queue.length; index++) {
    if (queue[index].stableKey === preferredStableKey) {
      return index;
    }
  }
  return indexedPosition >= 0 ? indexedPosition : 0;
}

/** The song the room wants playing, mapped onto this app's model. */
export function listenTogetherTargetSongItem(state: ListenTogetherRoomState): SongItem | null {
  const target = listenTogetherCurrentTrack(state);
  return target === null ? null : listenTogetherTrackToSongItem(target);
}

/** Identity comparison that ignores metadata (titles, covers, stream urls). */
export function sameListenTogetherTrack(song: SongItem, other: SongItem): boolean {
  return resolvedListenTogetherChannelId(song) === resolvedListenTogetherChannelId(other) &&
    resolvedListenTogetherAudioId(song) === resolvedListenTogetherAudioId(other) &&
    resolvedListenTogetherSubAudioId(song) === resolvedListenTogetherSubAudioId(other) &&
    resolvedListenTogetherPlaylistContextId(song) === resolvedListenTogetherPlaylistContextId(other);
}

export function hasSameListenTogetherTrackSequence(songs: SongItem[], other: SongItem[]): boolean {
  if (songs.length !== other.length) {
    return false;
  }
  for (let i = 0; i < songs.length; i++) {
    if (!sameListenTogetherTrack(songs[i], other[i])) {
      return false;
    }
  }
  return true;
}

/**
 * Upstream #359 `hasSameTrackMultisetAs`: same songs regardless of order. A
 * PLAYBACK_MODE (shuffle) update whose multiset matches only reorders — it can
 * be applied without a reload; a set change cannot.
 */
export function hasSameListenTogetherTrackMultiset(songs: SongItem[], other: SongItem[]): boolean {
  if (songs.length !== other.length) {
    return false;
  }
  const counts = new Map<string, number>();
  for (const song of songs) {
    counts.set(stableIdentityKey(song), (counts.get(stableIdentityKey(song)) ?? 0) + 1);
  }
  for (const song of other) {
    const key = stableIdentityKey(song);
    const remaining = counts.get(key) ?? 0;
    if (remaining <= 0) {
      return false;
    }
    counts.set(key, remaining - 1);
  }
  return true;
}

function stableIdentityKey(song: SongItem): string {
  return `${resolvedListenTogetherChannelId(song)}|${resolvedListenTogetherAudioId(song)}|` +
    `${resolvedListenTogetherSubAudioId(song)}|${resolvedListenTogetherPlaylistContextId(song)}`;
}

/**
 * Causes whose room state changes the queue content or order. Upstream #359
 * extends the set with PLAYBACK_MODE: a shuffle toggle reshapes the queue even
 * though the current song keeps playing.
 */
export function isListenTogetherQueueUpdateCause(causeType: string | null): boolean {
  if (causeType === null) {
    return false;
  }
  return LISTEN_TOGETHER_QUEUE_UPDATE_CAUSES.has(causeType) ||
    LISTEN_TOGETHER_PLAYBACK_MODE_QUEUE_UPDATE_CAUSES.has(causeType);
}

/**
 * A queue update can keep the player loaded (no reload) only when the incoming
 * current song is the local one and — for shuffle toggles — the queue holds
 * exactly the same songs, so nothing but the order changed.
 */
export function shouldApplyListenTogetherQueueUpdateWithoutReload(
  causeType: string | null,
  incomingQueue: SongItem[],
  incomingCurrentIndex: number,
  currentQueue: SongItem[],
  currentSong: SongItem | null
): boolean {
  if (!isListenTogetherQueueUpdateCause(causeType)) {
    return false;
  }
  const incomingCurrentSong = trackAtSong(incomingQueue, incomingCurrentIndex);
  if (incomingCurrentSong === null) {
    return false;
  }
  if (currentQueue.length === 0 || currentSong === null ||
    !sameListenTogetherTrack(currentSong, incomingCurrentSong)) {
    return false;
  }
  if (causeType !== null && LISTEN_TOGETHER_PLAYBACK_MODE_QUEUE_UPDATE_CAUSES.has(causeType)) {
    return hasSameListenTogetherTrackMultiset(currentQueue, incomingQueue);
  }
  return true;
}

function trackAtSong(queue: SongItem[], index: number): SongItem | null {
  return index >= 0 && index < queue.length ? queue[index] : null;
}

const LISTEN_TOGETHER_QUEUE_UPDATE_CAUSES: Set<string> = new Set<string>([
  'SET_TRACK',
  'SET_QUEUE',
  'REQUEST_SET_TRACK',
  'REQUEST_SET_QUEUE'
]);

const LISTEN_TOGETHER_PLAYBACK_MODE_QUEUE_UPDATE_CAUSES: Set<string> = new Set<string>([
  'PLAYBACK_MODE',
  'REQUEST_PLAYBACK_MODE'
]);

export function indexOfListenTogetherTrack(songs: SongItem[], track: SongItem | null): number {
  if (track === null) {
    return -1;
  }
  for (let i = 0; i < songs.length; i++) {
    if (sameListenTogetherTrack(songs[i], track)) {
      return i;
    }
  }
  return -1;
}
