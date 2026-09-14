// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { Constants } from '../app/Constants';
import { SongItem } from './SongItem';
import { MusicPlatform } from './MusicPlatform';
import { stableSyncId } from '../sync/SyncModels';

/**
 * Port of SongIdentity + stableKey() from the Android codebase.
 * Identities are kept compatible with the existing Android/Desktop sync data format:
 *   "<id>|<album>|<mediaUri>"
 *
 * `id` is a canonical decimal string (not a JS number): platform hashed ids are
 * full signed 64-bit longs on Android (SHA-256 first 8 bytes, big-endian) and
 * exceed Number.MAX_SAFE_INTEGER, so keeping them as text is the only way the
 * stable key matches the Android Long.toString() output byte-for-byte.
 */
export class SongIdentity {
  id: string;
  album: string;
  mediaUri: string;

  constructor(id: string, album: string, mediaUri: string) {
    this.id = id;
    this.album = album;
    this.mediaUri = mediaUri;
  }

  stableKey(): string {
    return `${this.id}|${this.album}|${this.mediaUri}`;
  }
}

/**
 * FNV-1a 32-bit hash. Historical note: before the SHA-256 alignment this was
 * the cross-device id algorithm, which made B 站/YTM stable keys diverge from
 * Android. It now only serves in-session SongItem.id fallbacks (listen-together
 * track mapping, non-numeric playlist ids) and the one-time legacy-key
 * migration (legacyFnvStableKey) — never as a persisted identity.
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

/** Kotlin String.toLongOrNull(): optional '-', digits only. */
function isDecimalLongText(text: string): boolean {
  return /^-?[0-9]+$/.test(text);
}

/**
 * Android SongIdentity.parseStableSongIdentity: "id|album|mediaUri" back into
 * an identity, or null when the text does not carry a remote identity.
 */
export function parseStableSongIdentity(stableKey: string): SongIdentity | null {
  const firstSeparator = stableKey.indexOf('|');
  if (firstSeparator <= 0) {
    return null;
  }
  const secondSeparator = stableKey.indexOf('|', firstSeparator + 1);
  if (secondSeparator <= firstSeparator) {
    return null;
  }
  const id = stableKey.substring(0, firstSeparator);
  if (!isDecimalLongText(id)) {
    return null;
  }
  const album = stableKey.substring(firstSeparator + 1, secondSeparator);
  if (album.trim().length === 0) {
    return null;
  }
  const mediaUri = stableKey.substring(secondSeparator + 1);
  return new SongIdentity(id, album, mediaUri);
}

/** Exact decimal id text: wire-fidelity syncIdText wins over the number id. */
function localSongIdText(song: SongItem): string {
  return song.syncIdText.length > 0 ? song.syncIdText : `${song.id}`;
}

/**
 * Android SongItem.normalizedDownloadedSourceIdentity: a local file whose
 * sourceStableKey still points at the original remote song restores that
 * identity, so downloaded tracks keep counting as the same song across
 * devices after a sync round-trip.
 */
function normalizedDownloadedSourceIdentity(song: SongItem): SongIdentity | null {
  const sourceKey = song.sourceStableKey.trim();
  if (sourceKey.length === 0) {
    return null;
  }
  const sourceIdentity = parseStableSongIdentity(sourceKey);
  if (sourceIdentity === null) {
    return null;
  }
  if (sourceIdentity.stableKey() === new SongIdentity(localSongIdText(song), song.album, song.mediaUri).stableKey()) {
    return null;
  }
  return sourceIdentity;
}

export function songIdentity(song: SongItem): SongIdentity {
  // Local songs first try to restore the remote identity of a downloaded
  // source (Android parity); the plain id|album|mediaUri identity is the
  // fallback. Channel normalization below is only for remote tracks.
  if (song.platform === MusicPlatform.LOCAL) {
    const restored = normalizedDownloadedSourceIdentity(song);
    if (restored !== null) {
      return restored;
    }
    return new SongIdentity(localSongIdText(song), song.album, song.mediaUri);
  }
  const videoId = extractYouTubeMusicVideoId(song.mediaUri);
  if (videoId.length > 0) {
    return new SongIdentity(
      stableSyncId(videoId),
      Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM,
      buildYouTubeMusicMediaUri(videoId)
    );
  }

  const channel = normalizedChannelId(song);
  const audioId = song.audioId.trim();
  const audio = audioId.length > 0 ? audioId : (song.id !== 0 ? `${song.id}` : '');
  if (channel.length === 0 || audio.length === 0) {
    // Last-resort identity: numeric id + album + media uri (local songs).
    return new SongIdentity(localSongIdText(song), song.album, song.mediaUri);
  }
  if (channel === Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM) {
    return new SongIdentity(
      stableSyncId(audio),
      Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM,
      buildYouTubeMusicMediaUri(audio)
    );
  }

  const subAudio = normalizedSubAudioId(channel, song.subAudioId, song.album);
  if (channel === 'netease') {
    // NetEase ids are platform-native numeric ids kept verbatim.
    return new SongIdentity(
      isDecimalLongText(audio) ? audio : stableSyncId(`${channel}|${audio}`),
      channel,
      ''
    );
  }
  return new SongIdentity(stableSyncId(`${channel}|${audio}|${subAudio}`), channel, '');
}

export function stableKeyOf(song: SongItem): string {
  return songIdentity(song).stableKey();
}

/**
 * The pre-SHA-256 identity algorithm (FNV-1a hashed ids, numeric-only ids),
 * frozen verbatim for the one-time StableKeyMigration remap of persisted
 * keys. Must never be used for new identities.
 */
export function legacyFnvStableKey(song: SongItem): string {
  if (song.platform === MusicPlatform.LOCAL) {
    return `${song.id}|${song.album}|${song.mediaUri}`;
  }
  const videoId = extractYouTubeMusicVideoId(song.mediaUri);
  if (videoId.length > 0) {
    return `${hashStableId(videoId)}|${Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM}|${buildYouTubeMusicMediaUri(videoId)}`;
  }
  const channel = normalizedChannelId(song);
  const audioId = song.audioId.trim();
  const audio = audioId.length > 0 ? audioId : (song.id !== 0 ? `${song.id}` : '');
  if (channel.length === 0 || audio.length === 0) {
    return `${song.id}|${song.album}|${song.mediaUri}`;
  }
  if (channel === Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM) {
    return `${hashStableId(audio)}|${Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM}|${buildYouTubeMusicMediaUri(audio)}`;
  }
  const subAudio = normalizedSubAudioId(channel, song.subAudioId, song.album);
  if (channel === 'netease') {
    const numericId = Number(audio);
    const id = Number.isNaN(numericId) ? hashStableId(`${channel}|${audio}`) : numericId;
    return `${id}|${channel}|`;
  }
  return `${hashStableId(`${channel}|${audio}|${subAudio}`)}|${channel}|`;
}
