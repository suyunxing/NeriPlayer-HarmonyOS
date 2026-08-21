/**
 * Ports of listentogether/mapping/ListenTogetherSongItemMapper.kt and
 * listentogether/mapping/ListenTogetherTrackMapper.kt: the two directions
 * between this app's SongItem and the wire track model.
 *
 * Divergences from Android, all forced by this port's models:
 * - `SongItem.id` is a JS number, so the Long ids Android derives from
 *   SHA-256 (`stableYouTubeMusicId`) / `String.hashCode()` are replaced by the
 *   port's own FNV-1a `hashStableId`. Nothing compares ids across clients:
 *   room identity is `stableKey`, and local identity always goes through
 *   `songIdentity()`, which derives the same numbers from channel + audio id;
 * - a numeric `audioId` longer than 15 digits falls back to the hash instead of
 *   `toLongOrNull()` (outside the safe-integer range; real netease ids are ~10
 *   digits);
 * - `SongItem.platform` has no Android counterpart and is set per channel, so
 *   StreamResolver picks the right platform API;
 * - the YouTube Music `mediaUri` is rebuilt in this app's native
 *   `youtube_music|<videoId>` form (local identity/sync only understand that
 *   one) and is *omitted* when sharing, so the receiver rebuilds it in its own
 *   format from `audioId` + `playlistContextId`;
 * - an inbound `streamUrl` is deliberately NOT written into `SongItem`, exactly
 *   like Android: `StreamResolver` would otherwise fetch a peer-supplied URL
 *   before the whitelist in ListenTogetherStreamUrlPolicy ever ran.
 */
import { Constants } from '../../app/Constants';
import { SongItem } from '../../model/SongItem';
import { MusicPlatform } from '../../model/MusicPlatform';
import { hashStableId } from '../../model/SongIdentity';
import { ListenTogetherChannels, normalizedListenTogetherChannelId } from '../protocol/ListenTogetherChannels';
import {
  ListenTogetherTrack,
  cloneListenTogetherTrack,
  createListenTogetherTrack
} from '../protocol/ListenTogetherTrack';
import {
  buildListenTogetherYouTubeMusicMediaUri,
  buildStableTrackKey,
  resolvedListenTogetherAudioId,
  resolvedListenTogetherChannelId,
  resolvedListenTogetherPlaylistContextId,
  resolvedListenTogetherSubAudioId
} from './ListenTogetherTrackIdentity';
import {
  ListenTogetherBlockedStreamUrlListener,
  MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES,
  trustedListenTogetherStreamUrls
} from './ListenTogetherStreamUrlPolicy';

/** LocalSongSupport.LOCAL_ALBUM_IDENTITY: kept identical for cross-end keys. */
export const LISTEN_TOGETHER_LOCAL_ALBUM_IDENTITY: string = '__local_files__';

/** Digits only, short enough to stay an exact JS integer. */
const DECIMAL_ID_REGEX: RegExp = /^-?[0-9]{1,15}$/;

function emptyToNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

function nullToEmpty(value: string | null): string {
  return value === null ? '' : value;
}

function parseDecimalIdOrNull(value: string): number | null {
  if (!DECIMAL_ID_REGEX.test(value)) {
    return null;
  }
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function sameStringList(a: string[], b: string[]): boolean {
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

/** `SongItem.toListenTogetherTrackOrNull`: null when the song cannot be shared. */
export function songItemToListenTogetherTrackOrNull(
  song: SongItem,
  includeLocal: boolean = false
): ListenTogetherTrack | null {
  const channel = resolvedListenTogetherChannelId(song);
  if (channel === null) {
    return null;
  }
  if (channel.toLowerCase() === ListenTogetherChannels.LOCAL && !includeLocal) {
    return null;
  }
  const audio = resolvedListenTogetherAudioId(song);
  if (audio === null) {
    return null;
  }
  const subAudio = resolvedListenTogetherSubAudioId(song);
  const playlistContext = resolvedListenTogetherPlaylistContextId(song);
  const track = createListenTogetherTrack(
    buildStableTrackKey(channel, audio, subAudio, playlistContext),
    channel,
    audio,
    song.displayName,
    song.displayArtist
  );
  track.subAudioId = subAudio;
  track.playlistContextId = playlistContext;
  track.mediaUri = channel === ListenTogetherChannels.YOUTUBE_MUSIC
    ? null
    : emptyToNull(song.mediaUri);
  track.streamUrl = emptyToNull(song.streamUrl);
  track.streamUrls = track.streamUrl === null ? [] : [track.streamUrl];
  track.album = song.album;
  track.durationMs = song.durationMs;
  track.coverUrl = emptyToNull(song.effectiveCoverUrl);
  return track;
}

function fallbackSongId(track: ListenTogetherTrack): number {
  const numeric = parseDecimalIdOrNull(track.audioId);
  return numeric === null ? hashStableId(track.stableKey) : numeric;
}

/** `ListenTogetherTrack.toSongItem`. */
export function listenTogetherTrackToSongItem(track: ListenTogetherTrack): SongItem {
  const channel = normalizedListenTogetherChannelId(track.channelId);
  const coverUrl = nullToEmpty(track.coverUrl);
  if (channel === ListenTogetherChannels.YOUTUBE_MUSIC) {
    const song = new SongItem(
      hashStableId(track.audioId),
      track.name,
      track.artist,
      nullToEmpty(track.album),
      0,
      track.durationMs,
      coverUrl,
      buildListenTogetherYouTubeMusicMediaUri(track.audioId),
      MusicPlatform.YOUTUBE_MUSIC
    );
    song.originalName = track.name;
    song.originalArtist = track.artist;
    song.originalCoverUrl = coverUrl;
    song.channelId = Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
    song.audioId = track.audioId;
    song.subAudioId = nullToEmpty(track.subAudioId);
    song.playlistContextId = nullToEmpty(track.playlistContextId);
    return song;
  }
  if (channel === ListenTogetherChannels.BILIBILI) {
    const subAudioId = track.subAudioId;
    const albumTag = subAudioId !== null && subAudioId.trim().length > 0
      ? `${Constants.BILIBILI_IDENTITY_HINT}|${subAudioId}`
      : Constants.BILIBILI_IDENTITY_HINT;
    const song = new SongItem(
      fallbackSongId(track),
      track.name,
      track.artist,
      albumTag,
      0,
      track.durationMs,
      coverUrl,
      '',
      MusicPlatform.BILIBILI
    );
    song.channelId = ListenTogetherChannels.BILIBILI;
    song.audioId = track.audioId;
    song.subAudioId = nullToEmpty(track.subAudioId);
    song.playlistContextId = nullToEmpty(track.playlistContextId);
    return song;
  }
  if (channel === ListenTogetherChannels.LOCAL) {
    const mediaUri = nullToEmpty(track.mediaUri);
    const song = new SongItem(
      fallbackSongId(track),
      track.name,
      track.artist,
      track.album === null ? LISTEN_TOGETHER_LOCAL_ALBUM_IDENTITY : track.album,
      0,
      track.durationMs,
      coverUrl,
      mediaUri,
      MusicPlatform.LOCAL
    );
    song.originalName = track.name;
    song.originalArtist = track.artist;
    song.originalCoverUrl = coverUrl;
    song.localFilePath = mediaUri;
    song.channelId = ListenTogetherChannels.LOCAL;
    song.audioId = track.audioId;
    song.subAudioId = nullToEmpty(track.subAudioId);
    song.playlistContextId = nullToEmpty(track.playlistContextId);
    return song;
  }
  const song = new SongItem(
    fallbackSongId(track),
    track.name,
    track.artist,
    nullToEmpty(track.album),
    0,
    track.durationMs,
    coverUrl,
    '',
    MusicPlatform.NETEASE
  );
  song.channelId = ListenTogetherChannels.NETEASE;
  song.audioId = track.audioId;
  song.subAudioId = nullToEmpty(track.subAudioId);
  song.playlistContextId = nullToEmpty(track.playlistContextId);
  return song;
}

/** `ListenTogetherTrack.withStreamUrls`; returns the input when nothing moved. */
export function listenTogetherTrackWithStreamUrls(
  track: ListenTogetherTrack,
  streamUrls: string[] | null,
  onBlocked: ListenTogetherBlockedStreamUrlListener | null = null
): ListenTogetherTrack {
  const trusted = trustedListenTogetherStreamUrls(
    track.channelId,
    streamUrls,
    null,
    MAX_LISTEN_TOGETHER_STREAM_URL_CANDIDATES,
    onBlocked
  );
  const primary = trusted.length > 0 ? trusted[0] : null;
  if (primary === track.streamUrl && sameStringList(trusted, track.streamUrls)) {
    return track;
  }
  const copy = cloneListenTogetherTrack(track);
  copy.streamUrl = primary;
  copy.streamUrls = trusted;
  return copy;
}

/** `ListenTogetherTrack.withStreamUrl`. */
export function listenTogetherTrackWithStreamUrl(
  track: ListenTogetherTrack,
  streamUrl: string | null,
  onBlocked: ListenTogetherBlockedStreamUrlListener | null = null
): ListenTogetherTrack {
  return listenTogetherTrackWithStreamUrls(
    track,
    streamUrl === null ? [] : [streamUrl],
    onBlocked
  );
}
