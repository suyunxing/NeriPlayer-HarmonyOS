// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/protocol/ListenTogetherTrack.kt.
 *
 * Kotlin data class -> ArkTS class + hand-written record codec. `streamUrl`
 * stays the first candidate for older clients and servers; `streamUrls` carries
 * the full candidate list.
 */
import {
  JsonRecord,
  optString,
  optStringArray,
  putNumber,
  putString,
  putStringArray,
  reqNumber,
  reqString
} from './ListenTogetherJson';

export class ListenTogetherTrack {
  stableKey: string = '';
  channelId: string = '';
  audioId: string = '';
  subAudioId: string | null = null;
  playlistContextId: string | null = null;
  mediaUri: string | null = null;
  // streamUrl remains the first candidate for older clients and servers
  streamUrl: string | null = null;
  streamUrls: string[] = [];
  name: string = '';
  artist: string = '';
  album: string | null = null;
  durationMs: number = 0;
  coverUrl: string | null = null;
}

/** Mirrors the Kotlin constructor for the fields every call site provides. */
export function createListenTogetherTrack(
  stableKey: string,
  channelId: string,
  audioId: string,
  name: string,
  artist: string
): ListenTogetherTrack {
  const track = new ListenTogetherTrack();
  track.stableKey = stableKey;
  track.channelId = channelId;
  track.audioId = audioId;
  track.name = name;
  track.artist = artist;
  return track;
}

/** Kotlin `copy()` equivalent: callers mutate the clone. */
export function cloneListenTogetherTrack(track: ListenTogetherTrack): ListenTogetherTrack {
  const copy = new ListenTogetherTrack();
  copy.stableKey = track.stableKey;
  copy.channelId = track.channelId;
  copy.audioId = track.audioId;
  copy.subAudioId = track.subAudioId;
  copy.playlistContextId = track.playlistContextId;
  copy.mediaUri = track.mediaUri;
  copy.streamUrl = track.streamUrl;
  copy.streamUrls = track.streamUrls.slice();
  copy.name = track.name;
  copy.artist = track.artist;
  copy.album = track.album;
  copy.durationMs = track.durationMs;
  copy.coverUrl = track.coverUrl;
  return copy;
}

function stringListEquals(a: string[], b: string[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

/** Kotlin data-class equality, used by mergeCurrentTrack/withStreamUrls. */
export function listenTogetherTrackEquals(
  a: ListenTogetherTrack | null,
  b: ListenTogetherTrack | null
): boolean {
  if (a === null || b === null) {
    return a === b;
  }
  return a.stableKey === b.stableKey &&
    a.channelId === b.channelId &&
    a.audioId === b.audioId &&
    a.subAudioId === b.subAudioId &&
    a.playlistContextId === b.playlistContextId &&
    a.mediaUri === b.mediaUri &&
    a.streamUrl === b.streamUrl &&
    stringListEquals(a.streamUrls, b.streamUrls) &&
    a.name === b.name &&
    a.artist === b.artist &&
    a.album === b.album &&
    a.durationMs === b.durationMs &&
    a.coverUrl === b.coverUrl;
}

export function listenTogetherTrackListEquals(
  a: ListenTogetherTrack[],
  b: ListenTogetherTrack[]
): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (!listenTogetherTrackEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

export function listenTogetherTrackFromRecord(raw: JsonRecord): ListenTogetherTrack {
  const track = new ListenTogetherTrack();
  track.stableKey = reqString(raw, 'stableKey');
  track.channelId = reqString(raw, 'channelId');
  track.audioId = reqString(raw, 'audioId');
  track.subAudioId = optString(raw, 'subAudioId');
  track.playlistContextId = optString(raw, 'playlistContextId');
  track.mediaUri = optString(raw, 'mediaUri');
  track.streamUrl = optString(raw, 'streamUrl');
  const streamUrls = optStringArray(raw, 'streamUrls');
  track.streamUrls = streamUrls === null ? [] : streamUrls;
  track.name = reqString(raw, 'name');
  track.artist = reqString(raw, 'artist');
  track.album = optString(raw, 'album');
  track.durationMs = reqNumber(raw, 'durationMs', 0);
  track.coverUrl = optString(raw, 'coverUrl');
  return track;
}

export function listenTogetherTrackToRecord(track: ListenTogetherTrack): JsonRecord {
  const raw: JsonRecord = {};
  raw['stableKey'] = track.stableKey;
  raw['channelId'] = track.channelId;
  raw['audioId'] = track.audioId;
  putString(raw, 'subAudioId', track.subAudioId);
  putString(raw, 'playlistContextId', track.playlistContextId);
  putString(raw, 'mediaUri', track.mediaUri);
  putString(raw, 'streamUrl', track.streamUrl);
  putStringArray(raw, 'streamUrls', track.streamUrls);
  raw['name'] = track.name;
  raw['artist'] = track.artist;
  putString(raw, 'album', track.album);
  putNumber(raw, 'durationMs', track.durationMs);
  putString(raw, 'coverUrl', track.coverUrl);
  return raw;
}

export function listenTogetherTracksFromRecords(records: JsonRecord[]): ListenTogetherTrack[] {
  const tracks: ListenTogetherTrack[] = [];
  for (const record of records) {
    tracks.push(listenTogetherTrackFromRecord(record));
  }
  return tracks;
}

export function listenTogetherTracksToRecords(tracks: ListenTogetherTrack[]): JsonRecord[] {
  const records: JsonRecord[] = [];
  for (const track of tracks) {
    records.push(listenTogetherTrackToRecord(track));
  }
  return records;
}
