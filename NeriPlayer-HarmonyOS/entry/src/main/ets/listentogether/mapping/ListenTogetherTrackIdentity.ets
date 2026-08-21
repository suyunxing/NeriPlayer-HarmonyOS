/**
 * Port of listentogether/mapping/ListenTogetherTrackIdentity.kt.
 *
 * `stableKey` is the room-wide track identity: both clients must derive the
 * same string for the same song or the queue diff and the "same track" check
 * fall apart, so the separator and the field order stay exactly as upstream.
 *
 * Divergences forced by this port:
 * - an explicit `channelId` is normalized onto the wire vocabulary, because
 *   this app stores the YouTube Music channel as "youtube_music" while the wire
 *   value is "youtubeMusic" (Android holds the wire value everywhere);
 * - `SongItem.platform` is consulted as a last hint before defaulting to
 *   netease; the Android model has no such field, and every channel it can
 *   report already sets `channelId`, so no Android-shaped input changes;
 * - the YouTube Music media URI is recognized in both this app's native
 *   `youtube_music|<videoId>` form and Android's
 *   `ytmusic://video/<videoId>[?playlistId=...]` form, so a track received from
 *   an Android peer still resolves its video and playlist ids.
 */
import { Constants } from '../../app/Constants';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { isLocalSongItem } from '../../sync/SyncSongConvert';
import { ListenTogetherChannels, normalizedListenTogetherChannelId } from '../protocol/ListenTogetherChannels';

/** Android `buildYouTubeMusicMediaUri` prefix, accepted on input. */
const ANDROID_YOUTUBE_MUSIC_URI_PREFIX: string = 'ytmusic://video/';

function decodeUriComponentOrNull(value: string): string | null {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return null;
  }
}

function blankToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** Splits `<path>[?query][#fragment]` after the Android URI prefix. */
function androidYouTubeMusicUriRest(mediaUri: string): string | null {
  if (!mediaUri.startsWith(ANDROID_YOUTUBE_MUSIC_URI_PREFIX)) {
    return null;
  }
  return mediaUri.substring(ANDROID_YOUTUBE_MUSIC_URI_PREFIX.length);
}

export function extractListenTogetherYouTubeMusicVideoId(mediaUri: string | null): string | null {
  if (mediaUri === null || mediaUri.length === 0) {
    return null;
  }
  if (mediaUri.startsWith(Constants.YOUTUBE_MUSIC_MEDIA_PREFIX)) {
    return blankToNull(mediaUri.substring(Constants.YOUTUBE_MUSIC_MEDIA_PREFIX.length));
  }
  const rest = androidYouTubeMusicUriRest(mediaUri);
  if (rest === null) {
    return null;
  }
  const queryStart = rest.indexOf('?');
  const withoutQuery = queryStart < 0 ? rest : rest.substring(0, queryStart);
  const fragmentStart = withoutQuery.indexOf('#');
  const raw = fragmentStart < 0 ? withoutQuery : withoutQuery.substring(0, fragmentStart);
  const decoded = decodeUriComponentOrNull(raw);
  return decoded === null ? null : blankToNull(decoded);
}

/** Android reads this back with `Uri.getQueryParameter("playlistId")`. */
export function extractListenTogetherYouTubeMusicPlaylistId(mediaUri: string | null): string | null {
  if (mediaUri === null || mediaUri.length === 0) {
    return null;
  }
  const rest = androidYouTubeMusicUriRest(mediaUri);
  if (rest === null) {
    return null;
  }
  const queryStart = rest.indexOf('?');
  if (queryStart < 0) {
    return null;
  }
  const fragmentStart = rest.indexOf('#', queryStart);
  const query = fragmentStart < 0 ? rest.substring(queryStart + 1) : rest.substring(queryStart + 1, fragmentStart);
  for (const pair of query.split('&')) {
    const separatorIndex = pair.indexOf('=');
    const rawKey = separatorIndex >= 0 ? pair.substring(0, separatorIndex) : pair;
    if (decodeUriComponentOrNull(rawKey) !== 'playlistId') {
      continue;
    }
    const rawValue = separatorIndex >= 0 ? pair.substring(separatorIndex + 1) : '';
    const decoded = decodeUriComponentOrNull(rawValue);
    return decoded === null ? null : blankToNull(decoded);
  }
  return null;
}

/** This app's native YouTube Music media URI (`youtube_music|<videoId>`). */
export function buildListenTogetherYouTubeMusicMediaUri(videoId: string): string {
  return `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${videoId}`;
}

/** Kotlin `filterNot { it.isNullOrBlank() }.joinToString(":")`. */
function joinNonBlank(parts: (string | null)[]): string {
  const kept: string[] = [];
  for (const part of parts) {
    if (part !== null && part.trim().length > 0) {
      kept.push(part);
    }
  }
  return kept.join(':');
}

export function buildStableTrackKey(
  channelId: string,
  audioId: string,
  subAudioId: string | null = null,
  playlistContextId: string | null = null
): string {
  if (channelId === ListenTogetherChannels.BILIBILI) {
    return joinNonBlank([channelId, audioId, subAudioId]);
  }
  if (channelId === ListenTogetherChannels.YOUTUBE_MUSIC) {
    return joinNonBlank([channelId, audioId, playlistContextId]);
  }
  return `${channelId}:${audioId}`;
}

export function resolvedListenTogetherChannelId(song: SongItem): string | null {
  const explicit = normalizedListenTogetherChannelId(song.channelId);
  if (explicit !== null) {
    return explicit;
  }
  if (isLocalSongItem(song)) {
    return ListenTogetherChannels.LOCAL;
  }
  if (extractListenTogetherYouTubeMusicVideoId(song.mediaUri) !== null) {
    return ListenTogetherChannels.YOUTUBE_MUSIC;
  }
  if (song.album.startsWith(Constants.BILIBILI_IDENTITY_HINT)) {
    return ListenTogetherChannels.BILIBILI;
  }
  if (song.platform === MusicPlatform.YOUTUBE_MUSIC) {
    return ListenTogetherChannels.YOUTUBE_MUSIC;
  }
  if (song.platform === MusicPlatform.BILIBILI) {
    return ListenTogetherChannels.BILIBILI;
  }
  return ListenTogetherChannels.NETEASE;
}

export function resolvedListenTogetherAudioId(song: SongItem): string | null {
  const explicit = blankToNull(song.audioId);
  if (explicit !== null) {
    return explicit;
  }
  if (resolvedListenTogetherChannelId(song) === ListenTogetherChannels.YOUTUBE_MUSIC) {
    return extractListenTogetherYouTubeMusicVideoId(song.mediaUri);
  }
  return `${song.id}`;
}

export function resolvedListenTogetherSubAudioId(song: SongItem): string | null {
  const explicit = blankToNull(song.subAudioId);
  if (explicit !== null) {
    return explicit;
  }
  if (resolvedListenTogetherChannelId(song) !== ListenTogetherChannels.BILIBILI) {
    return null;
  }
  // Kotlin `album.substringAfter('|', "")`: no separator means no sub id.
  const separator = song.album.indexOf('|');
  if (separator < 0) {
    return null;
  }
  return blankToNull(song.album.substring(separator + 1));
}

export function resolvedListenTogetherPlaylistContextId(song: SongItem): string | null {
  const explicit = blankToNull(song.playlistContextId);
  if (explicit !== null) {
    return explicit;
  }
  if (resolvedListenTogetherChannelId(song) !== ListenTogetherChannels.YOUTUBE_MUSIC) {
    return null;
  }
  return extractListenTogetherYouTubeMusicPlaylistId(song.mediaUri);
}
