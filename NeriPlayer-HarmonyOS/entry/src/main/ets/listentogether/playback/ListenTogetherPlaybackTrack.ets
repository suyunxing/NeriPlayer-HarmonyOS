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

function trackAt(queue: ListenTogetherTrack[], index: number): ListenTogetherTrack | null {
  return index >= 0 && index < queue.length ? queue[index] : null;
}

export function listenTogetherCurrentStableKey(state: ListenTogetherRoomState): string | null {
  if (state.track !== null) {
    return state.track.stableKey;
  }
  const queued = trackAt(state.queue, state.currentIndex);
  return queued === null ? null : queued.stableKey;
}

export function listenTogetherRequestedStableKey(event: ListenTogetherEvent): string | null {
  if (event.requestTrackStableKey !== null) {
    return event.requestTrackStableKey;
  }
  if (event.track !== null) {
    return event.track.stableKey;
  }
  if (event.queue === null) {
    return null;
  }
  const queued = trackAt(event.queue, event.currentIndex === null ? -1 : event.currentIndex);
  return queued === null ? null : queued.stableKey;
}

/** The song the room wants playing, mapped onto this app's model. */
export function listenTogetherTargetSongItem(state: ListenTogetherRoomState): SongItem | null {
  const target = state.track !== null ? state.track : trackAt(state.queue, state.currentIndex);
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
