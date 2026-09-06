import { Constants } from '../app/Constants';
import { SongItem } from './SongItem';
import { MusicPlatform } from './MusicPlatform';

/**
 * Port of SongIdentity + stableKey() from the Android codebase.
 * Identities are kept compatible with the existing Android/Desktop sync data format:
 *   "<id>|<album>|<mediaUri>"
 */
export class SongIdentity {
  id: number;
  album: string;
  mediaUri: string;

  constructor(id: number, album: string, mediaUri: string) {
    this.id = id;
    this.album = album;
    this.mediaUri = mediaUri;
  }

  stableKey(): string {
    return `${this.id}|${this.album}|${this.mediaUri}`;
  }
}

/**
 * FNV-1a 32-bit hash used to derive stable numeric ids for platform tracks that do
 * not have a numeric id of their own (Bilibili, YouTube Music).
 */
export function hashStableId(seed: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < seed.length; i++) {
    hash ^= seed.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

export function extractYouTubeMusicVideoId(mediaUri: string): string {
  if (mediaUri.startsWith(Constants.YOUTUBE_MUSIC_MEDIA_PREFIX)) {
    const videoId = mediaUri.substring(Constants.YOUTUBE_MUSIC_MEDIA_PREFIX.length);
    return videoId.length > 0 ? videoId : '';
  }
  return '';
}

function buildYouTubeMusicMediaUri(videoId: string): string {
  return `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${videoId}`;
}

function normalizedChannelId(song: SongItem): string {
  const rawChannelId = song.channelId.trim();
  if (rawChannelId.length > 0) {
    const lowered = rawChannelId.toLowerCase();
    if (lowered === 'youtube' || lowered === 'ytmusic' || lowered === 'youtubemusic') {
      return Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
    }
    return lowered;
  }
  if (extractYouTubeMusicVideoId(song.mediaUri).length > 0) {
    return Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
  }
  if (song.album.startsWith(Constants.BILIBILI_IDENTITY_HINT)) {
    return 'bilibili';
  }
  if (song.album.startsWith(Constants.NETEASE_IDENTITY_HINT)) {
    return 'netease';
  }
  if (song.mediaUri.length === 0) {
    return 'netease';
  }
  return '';
}

function normalizedSubAudioId(channel: string, rawSubAudioId: string, album: string): string {
  const explicit = rawSubAudioId.trim();
  if (channel !== 'bilibili') {
    return '';
  }
  if (explicit.length > 0) {
    return explicit;
  }
  const afterSeparator = album.indexOf('|');
  return afterSeparator >= 0 ? album.substring(afterSeparator + 1) : '';
}

export function songIdentity(song: SongItem): SongIdentity {
  // Local songs keep the plain id|album|mediaUri identity; channel
  // normalization below is only for remote tracks (Android parity).
  if (song.platform === MusicPlatform.LOCAL) {
    return new SongIdentity(song.id, song.album, song.mediaUri);
  }
  const videoId = extractYouTubeMusicVideoId(song.mediaUri);
  if (videoId.length > 0) {
    return new SongIdentity(
      hashStableId(videoId),
      Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM,
      buildYouTubeMusicMediaUri(videoId)
    );
  }

  const channel = normalizedChannelId(song);
  const audioId = song.audioId.trim();
  const audio = audioId.length > 0 ? audioId : (song.id !== 0 ? `${song.id}` : '');
  if (channel.length === 0 || audio.length === 0) {
    // Last-resort identity: numeric id + album + media uri (local songs).
    return new SongIdentity(song.id, song.album, song.mediaUri);
  }
  if (channel === Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM) {
    return new SongIdentity(
      hashStableId(audio),
      Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM,
      buildYouTubeMusicMediaUri(audio)
    );
  }

  const subAudio = normalizedSubAudioId(channel, song.subAudioId, song.album);
  if (channel === 'netease') {
    const numericId = Number(audio);
    return new SongIdentity(
      Number.isNaN(numericId) ? hashStableId(`${channel}|${audio}`) : numericId,
      channel,
      ''
    );
  }
  return new SongIdentity(hashStableId(`${channel}|${audio}|${subAudio}`), channel, '');
}

export function stableKeyOf(song: SongItem): string {
  return songIdentity(song).stableKey();
}
