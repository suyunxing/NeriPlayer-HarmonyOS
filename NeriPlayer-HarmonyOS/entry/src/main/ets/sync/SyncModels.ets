/**
 * Ports of the Android sync data models (data/sync/model/SyncDataModels.kt,
 * SyncCausalToken.kt, data/model/SongIdentity.kt SyncSong.identity() and the
 * counter shard helpers from SyncPlaybackStatMapper.kt).
 *
 * These are pure ArkTS structures with no @ohos dependency so the merge
 * policies can be unit tested locally. Field order and defaults match the
 * Android definitions byte-for-byte because the sync wire format depends on
 * them (see docs/PORTING_EXECUTION_PLAN.md M5 / decision D1).
 */
import { Constants } from '../app/Constants';

export const LEGACY_SYNC_METADATA_VERSION: number = 0;
export const CURRENT_SYNC_METADATA_VERSION: number = 1;
export const LEGACY_SONG_ORDER_VERSION: number = 0;
export const DISPLAY_ORDER_SONG_ORDER_VERSION: number = 1;
export const SYNC_DATA_VERSION: string = '2.0';

/** Long.MIN_VALUE sentinel used by effectiveAddedAt comparisons. */
const LONG_MIN_VALUE: number = -9223372036854775808.0;

/**
 * mergePositiveTimestamp (SyncDataModels.kt): earliest known positive
 * timestamp wins; a missing value never overwrites a valid one.
 */
export function mergePositiveTimestamp(left: number, right: number): number {
  if (left <= 0) {
    return Math.max(right, 0);
  }
  if (right <= 0) {
    return left;
  }
  return Math.min(left, right);
}

// ---------------------------------------------------------------------------
// SHA-256 stable id (Android stableYouTubeMusicId in YouTubeMusicSupport.kt)
// ---------------------------------------------------------------------------

const SHA256_K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) | 0;
}

function utf8Encode(text: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const low = text.charCodeAt(i + 1);
      const cp = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
      bytes.push(
        0xF0 | (cp >> 18),
        0x80 | ((cp >> 12) & 0x3F),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F)
      );
      i++;
    } else {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    }
  }
  return bytes;
}

/** SHA-256 (FIPS 180-4) digest as 32 bytes. */
export function sha256Bytes(input: string): number[] {
  const bytes = utf8Encode(input);
  const bitLength = bytes.length * 8;
  const padded: number[] = bytes.slice();
  padded.push(0x80);
  while (padded.length % 64 !== 56) {
    padded.push(0);
  }
  // Message lengths used here stay far below 2^32 bits; high word is zero.
  padded.push(0, 0, 0, 0,
    (bitLength >>> 24) & 0xFF, (bitLength >>> 16) & 0xFF,
    (bitLength >>> 8) & 0xFF, bitLength & 0xFF);

  let h0 = 0x6a09e667;
  let h1 = 0xbb67ae85;
  let h2 = 0x3c6ef372;
  let h3 = 0xa54ff53a;
  let h4 = 0x510e527f;
  let h5 = 0x9b05688c;
  let h6 = 0x1f83d9ab;
  let h7 = 0x5be0cd19;
  const w: number[] = new Array(64);
  for (let block = 0; block < padded.length; block += 64) {
    for (let t = 0; t < 16; t++) {
      const o = block + t * 4;
      w[t] = ((padded[o] << 24) | (padded[o + 1] << 16) |
        (padded[o + 2] << 8) | padded[o + 3]) | 0;
    }
    for (let t = 16; t < 64; t++) {
      const x15 = w[t - 15];
      const x2 = w[t - 2];
      const s0 = rotr(x15, 7) ^ rotr(x15, 18) ^ (x15 >>> 3);
      const s1 = rotr(x2, 17) ^ rotr(x2, 19) ^ (x2 >>> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
    }
    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    let f = h5;
    let g = h6;
    let h = h7;
    for (let t = 0; t < 64; t++) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (h + s1 + ch + SHA256_K[t] + w[t]) | 0;
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (s0 + maj) | 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) | 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) | 0;
    }
    h0 = (h0 + a) | 0;
    h1 = (h1 + b) | 0;
    h2 = (h2 + c) | 0;
    h3 = (h3 + d) | 0;
    h4 = (h4 + e) | 0;
    h5 = (h5 + f) | 0;
    h6 = (h6 + g) | 0;
    h7 = (h7 + h) | 0;
  }
  const words: number[] = [h0, h1, h2, h3, h4, h5, h6, h7];
  const out: number[] = [];
  for (const word of words) {
    out.push((word >>> 24) & 0xFF, (word >>> 16) & 0xFF, (word >>> 8) & 0xFF, word & 0xFF);
  }
  return out;
}

/**
 * stableYouTubeMusicId: first 8 SHA-256 bytes as a big-endian signed 64-bit
 * integer (0 is remapped to 1). Returned as a canonical decimal string so the
 * full 64-bit range survives JS number precision limits and matches the
 * Kotlin Long.toString() output used inside sync stable keys.
 */
export function stableSyncId(value: string): string {
  const digest = sha256Bytes(value).slice(0, 8);
  let result = 0n;
  for (const b of digest) {
    result = (result << 8n) | BigInt(b);
  }
  const two63 = 1n << 63n;
  if (result >= two63) {
    result -= (1n << 64n);
  }
  if (result === 0n) {
    return '1';
  }
  return result.toString();
}

// ---------------------------------------------------------------------------
// SyncCausalToken (data/sync/model/SyncCausalToken.kt)
// ---------------------------------------------------------------------------

export class SyncCausalToken {
  deviceId: string;
  counter: number;

  constructor(deviceId: string = '', counter: number = 0) {
    this.deviceId = deviceId;
    this.counter = counter;
  }

  /**
   * Validity is a property, not a constructor precondition: malformed tokens
   * decoded from third-party payloads must not brick the whole snapshot.
   */
  isValid(): boolean {
    return this.deviceId.trim().length > 0 && this.counter > 0;
  }
}

export function causalTokenEquals(a: SyncCausalToken, b: SyncCausalToken): boolean {
  return a.deviceId === b.deviceId && a.counter === b.counter;
}

/** Collision-free map key for token sets (deviceId cannot contain NUL). */
export function causalTokenKey(token: SyncCausalToken): string {
  return `${token.deviceId}\u0000${token.counter}`;
}

/** compareBy(deviceId).thenBy(counter) — UTF-16 code unit order like Kotlin. */
export function compareCausalTokens(a: SyncCausalToken, b: SyncCausalToken): number {
  if (a.deviceId < b.deviceId) {
    return -1;
  }
  if (a.deviceId > b.deviceId) {
    return 1;
  }
  if (a.counter < b.counter) {
    return -1;
  }
  if (a.counter > b.counter) {
    return 1;
  }
  return 0;
}

/**
 * normalizedSyncCausalTokens: drop invalid tokens, then deduplicate and sort
 * deterministically. The order (filter → distinct → sort) is the convergence
 * invariant every token merge in the codebase relies on.
 */
export function normalizedSyncCausalTokens(tokens: SyncCausalToken[] | null): SyncCausalToken[] {
  if (tokens === null || tokens.length === 0) {
    return [];
  }
  const seen = new Set<string>();
  const distinct: SyncCausalToken[] = [];
  for (const token of tokens) {
    if (!token.isValid()) {
      continue;
    }
    const key = causalTokenKey(token);
    if (!seen.has(key)) {
      seen.add(key);
      distinct.push(token);
    }
  }
  return distinct.sort(compareCausalTokens);
}

// ---------------------------------------------------------------------------
// SongIdentityKey (SyncSong.identity() in data/model/SongIdentity.kt)
// ---------------------------------------------------------------------------

/**
 * Identity triple used by every sync comparison. `id` is a canonical decimal
 * string (64-bit safe); mediaUri keeps null vs '' distinct like the Android
 * data class, while stableKey() collapses null to '' as on Android.
 */
export class SongIdentityKey {
  readonly id: string;
  readonly album: string;
  readonly mediaUri: string | null;

  constructor(id: string, album: string, mediaUri: string | null) {
    this.id = id;
    this.album = album;
    this.mediaUri = mediaUri;
  }

  stableKey(): string {
    return `${this.id}|${this.album}|${this.mediaUri === null ? '' : this.mediaUri}`;
  }

  /** Key for exact-equality maps: keeps null mediaUri distinct from ''. */
  mapKey(): string {
    const uriPart = this.mediaUri === null ? '\u0001' : `\u0002${this.mediaUri}`;
    return `${this.id}\u0000${this.album}\u0000${uriPart}`;
  }

  equals(other: SongIdentityKey): boolean {
    return this.id === other.id && this.album === other.album && this.mediaUri === other.mediaUri;
  }
}

function startsWithIgnoreCase(text: string, prefix: string): boolean {
  if (text.length < prefix.length) {
    return false;
  }
  return text.substring(0, prefix.length).toLowerCase() === prefix.toLowerCase();
}

function extractYouTubeMusicVideoId(mediaUri: string | null): string | null {
  if (mediaUri === null) {
    return null;
  }
  if (!mediaUri.startsWith(Constants.YOUTUBE_MUSIC_MEDIA_PREFIX)) {
    return null;
  }
  const videoId = mediaUri.substring(Constants.YOUTUBE_MUSIC_MEDIA_PREFIX.length);
  return videoId.length > 0 ? videoId : null;
}

function buildYouTubeMusicMediaUri(videoId: string): string {
  return `${Constants.YOUTUBE_MUSIC_MEDIA_PREFIX}${videoId}`;
}

function idToKeyString(id: number): string {
  return `${id}`;
}

/** Kotlin String.toLongOrNull(): optional '-', digits only, Long range. */
function parseLongOrNullDecimal(text: string): number | null {
  if (!/^-?[0-9]+$/.test(text)) {
    return null;
  }
  const value = Number(text);
  if (!Number.isFinite(value) || Math.abs(value) > 9223372036854775807) {
    return null;
  }
  return value;
}

function normalizeSyncChannelAlias(channel: string): string {
  if (channel === 'youtube' || channel === 'ytmusic' || channel === 'youtubemusic') {
    return Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
  }
  return channel;
}

function normalizedSyncChannelId(
  rawChannelId: string | null,
  album: string,
  mediaUri: string | null,
  inferNeteaseForBlankRemote: boolean
): string | null {
  const trimmed = rawChannelId === null ? '' : rawChannelId.trim();
  if (trimmed.length > 0) {
    return normalizeSyncChannelAlias(trimmed.toLowerCase());
  }
  if (extractYouTubeMusicVideoId(mediaUri) !== null) {
    return Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM;
  }
  if (startsWithIgnoreCase(album, Constants.BILIBILI_IDENTITY_HINT)) {
    return 'bilibili';
  }
  if (startsWithIgnoreCase(album, Constants.NETEASE_IDENTITY_HINT)) {
    return 'netease';
  }
  if (inferNeteaseForBlankRemote &&
    (mediaUri === null || mediaUri.trim().length === 0)) {
    return 'netease';
  }
  return null;
}

function normalizedSyncSubAudioId(channel: string, rawSubAudioId: string | null, album: string): string {
  if (channel !== 'bilibili') {
    return '';
  }
  const explicit = rawSubAudioId === null ? '' : rawSubAudioId.trim();
  if (explicit.length > 0) {
    return explicit;
  }
  const separator = album.indexOf('|');
  return separator >= 0 ? album.substring(separator + 1) : '';
}

/** SyncSong.identity(): normalize YouTube Music / channel identities first. */
export function syncSongIdentity(song: SyncSong): SongIdentityKey {
  const videoId = extractYouTubeMusicVideoId(song.mediaUri);
  if (videoId !== null) {
    return new SongIdentityKey(
      stableSyncId(videoId),
      Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM,
      buildYouTubeMusicMediaUri(videoId)
    );
  }

  const channel = normalizedSyncChannelId(song.channelId, song.album, song.mediaUri, true);
  const trimmedAudio = song.audioId === null ? '' : song.audioId.trim();
  const audio = trimmedAudio.length > 0
    ? trimmedAudio
    : (song.id !== 0 ? songIdKeyText(song) : null);
  if (channel === null || audio === null) {
    return new SongIdentityKey(songIdKeyText(song), song.album, song.mediaUri);
  }
  if (channel === Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM) {
    return new SongIdentityKey(
      stableSyncId(audio),
      Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM,
      buildYouTubeMusicMediaUri(audio)
    );
  }

  const subAudio = normalizedSyncSubAudioId(channel, song.subAudioId, song.album);
  if (channel === 'netease') {
    const numeric = parseLongOrNullDecimal(audio);
    return new SongIdentityKey(
      numeric !== null ? idToKeyString(numeric) : stableSyncId(`${channel}|${audio}`),
      channel,
      null
    );
  }  return new SongIdentityKey(stableSyncId(`${channel}|${audio}|${subAudio}`), channel, null);
}

// ---------------------------------------------------------------------------
// SyncSong (data/sync/model/SyncDataModels.kt)
// ---------------------------------------------------------------------------

export class SyncSong {
  id: number;
  name: string;
  artist: string;
  album: string;
  albumId: number;
  durationMs: number;
  coverUrl: string | null;
  mediaUri: string | null;
  addedAt: number;
  matchedLyric: string | null;
  matchedTranslatedLyric: string | null;
  matchedLyricSource: string | null;
  matchedSongId: string | null;
  userLyricOffsetMs: number;
  customCoverUrl: string | null;
  customName: string | null;
  customArtist: string | null;
  originalName: string | null;
  originalArtist: string | null;
  originalCoverUrl: string | null;
  originalLyric: string | null;
  originalTranslatedLyric: string | null;
  channelId: string | null;
  audioId: string | null;
  subAudioId: string | null;
  playlistContextId: string | null;
  syncMembershipTokens: SyncCausalToken[];
  syncMetadataVersion: number;
  legacyAddedAt: number | null;
  /**
   * Wire-fidelity field (not part of the Android schema): keeps the exact
   * decimal text of `id` when a decoded snapshot carries a 64-bit id beyond
   * JS number precision (YTM/Bilibili hashed ids). Empty when id is exact.
   * Every id-sensitive computation (stable keys, canonical payload key,
   * serialization) prefers this over `${id}`.
   */
  syncIdText: string;

  constructor(
    id: number = 0,
    name: string = '',
    artist: string = '',
    album: string = '',
    albumId: number = 0,
    durationMs: number = 0,
    coverUrl: string | null = null,
    mediaUri: string | null = null,
    addedAt: number = 0,
    matchedLyric: string | null = null,
    matchedTranslatedLyric: string | null = null,
    matchedLyricSource: string | null = null,
    matchedSongId: string | null = null,
    userLyricOffsetMs: number = 0,
    customCoverUrl: string | null = null,
    customName: string | null = null,
    customArtist: string | null = null,
    originalName: string | null = null,
    originalArtist: string | null = null,
    originalCoverUrl: string | null = null,
    originalLyric: string | null = null,
    originalTranslatedLyric: string | null = null,
    channelId: string | null = null,
    audioId: string | null = null,
    subAudioId: string | null = null,
    playlistContextId: string | null = null,
    syncMembershipTokens: SyncCausalToken[] = [],
    syncMetadataVersion: number = LEGACY_SYNC_METADATA_VERSION,
    legacyAddedAt: number | null = null,
    syncIdText: string = ''
  ) {
    this.id = id;
    this.name = name;
    this.artist = artist;
    this.album = album;
    this.albumId = albumId;
    this.durationMs = durationMs;
    this.coverUrl = coverUrl;
    this.mediaUri = mediaUri;
    this.addedAt = addedAt;
    this.matchedLyric = matchedLyric;
    this.matchedTranslatedLyric = matchedTranslatedLyric;
    this.matchedLyricSource = matchedLyricSource;
    this.matchedSongId = matchedSongId;
    this.userLyricOffsetMs = userLyricOffsetMs;
    this.customCoverUrl = customCoverUrl;
    this.customName = customName;
    this.customArtist = customArtist;
    this.originalName = originalName;
    this.originalArtist = originalArtist;
    this.originalCoverUrl = originalCoverUrl;
    this.originalLyric = originalLyric;
    this.originalTranslatedLyric = originalTranslatedLyric;
    this.channelId = channelId;
    this.audioId = audioId;
    this.subAudioId = subAudioId;
    this.playlistContextId = playlistContextId;
    this.syncMembershipTokens = syncMembershipTokens;
    this.syncMetadataVersion = syncMetadataVersion;
    this.legacyAddedAt = legacyAddedAt;
    this.syncIdText = syncIdText;
  }
}

/** Exact decimal id text: the wire-fidelity value when present, else `${id}`. */
export function songIdKeyText(song: SyncSong): string {
  return song.syncIdText.length > 0 ? song.syncIdText : `${song.id}`;
}

/** Structural equality (Kotlin data class): token list is order-sensitive. */
export function syncSongEquals(a: SyncSong, b: SyncSong): boolean {
  if (a === b) {
    return true;
  }
  if (a.id !== b.id || a.name !== b.name || a.artist !== b.artist || a.album !== b.album ||
    a.albumId !== b.albumId || a.durationMs !== b.durationMs ||
    a.coverUrl !== b.coverUrl || a.mediaUri !== b.mediaUri || a.addedAt !== b.addedAt ||
    a.matchedLyric !== b.matchedLyric ||
    a.matchedTranslatedLyric !== b.matchedTranslatedLyric ||
    a.matchedLyricSource !== b.matchedLyricSource ||
    a.matchedSongId !== b.matchedSongId ||
    a.userLyricOffsetMs !== b.userLyricOffsetMs ||
    a.customCoverUrl !== b.customCoverUrl || a.customName !== b.customName ||
    a.customArtist !== b.customArtist || a.originalName !== b.originalName ||
    a.originalArtist !== b.originalArtist || a.originalCoverUrl !== b.originalCoverUrl ||
    a.originalLyric !== b.originalLyric ||
    a.originalTranslatedLyric !== b.originalTranslatedLyric ||
    a.channelId !== b.channelId || a.audioId !== b.audioId ||
    a.subAudioId !== b.subAudioId ||
    a.playlistContextId !== b.playlistContextId ||
    a.syncMembershipTokens.length !== b.syncMembershipTokens.length ||
    a.syncMetadataVersion !== b.syncMetadataVersion || a.legacyAddedAt !== b.legacyAddedAt ||
    a.syncIdText !== b.syncIdText) {
    return false;
  }
  for (let i = 0; i < a.syncMembershipTokens.length; i++) {
    if (!causalTokenEquals(a.syncMembershipTokens[i], b.syncMembershipTokens[i])) {
      return false;
    }
  }
  return true;
}

export function cloneSyncSong(song: SyncSong): SyncSong {
  return new SyncSong(
    song.id, song.name, song.artist, song.album, song.albumId, song.durationMs,
    song.coverUrl, song.mediaUri, song.addedAt, song.matchedLyric,
    song.matchedTranslatedLyric, song.matchedLyricSource, song.matchedSongId,
    song.userLyricOffsetMs, song.customCoverUrl, song.customName, song.customArtist,
    song.originalName, song.originalArtist, song.originalCoverUrl, song.originalLyric,
    song.originalTranslatedLyric, song.channelId, song.audioId, song.subAudioId,
    song.playlistContextId, song.syncMembershipTokens, song.syncMetadataVersion,
    song.legacyAddedAt, song.syncIdText
  );
}

/** copyWithNormalizedMembershipTokens: normalized tokens, rest unchanged. */
export function songWithNormalizedTokens(song: SyncSong): SyncSong {
  const normalized = normalizedSyncCausalTokens(song.syncMembershipTokens);
  if (normalized.length === song.syncMembershipTokens.length) {
    let same = true;
    for (let i = 0; i < normalized.length; i++) {
      if (!causalTokenEquals(normalized[i], song.syncMembershipTokens[i])) {
        same = false;
        break;
      }
    }
    if (same) {
      return song;
    }
  }
  const copy = cloneSyncSong(song);
  copy.syncMembershipTokens = normalized;
  return copy;
}

/** Payload resolution result: new addedAt + union tokens + current version. */
export function songWithResolvedPayload(
  payload: SyncSong,
  addedAt: number,
  tokens: SyncCausalToken[]
): SyncSong {
  const copy = cloneSyncSong(payload);
  copy.addedAt = addedAt;
  copy.syncMembershipTokens = tokens;
  copy.syncMetadataVersion = CURRENT_SYNC_METADATA_VERSION;
  return copy;
}

export function effectiveAddedAt(song: SyncSong): number {
  const raw = song.legacyAddedAt !== null ? song.legacyAddedAt : song.addedAt;
  return raw > 0 ? raw : LONG_MIN_VALUE;
}

/**
 * Both identity stable keys a song maps to: the normalized channel identity
 * plus the raw id|album|mediaUri triple (deletion tombstones may use either).
 */
export function syncSongIdentityStableKeys(song: SyncSong): string[] {
  const keys: string[] = [];
  const normalizedKey = syncSongIdentity(song).stableKey();
  if (keys.indexOf(normalizedKey) < 0) {
    keys.push(normalizedKey);
  }
  const rawKey = new SongIdentityKey(
    songIdKeyText(song),
    song.album,
    song.mediaUri
  ).stableKey();
  if (keys.indexOf(rawKey) < 0) {
    keys.push(rawKey);
  }
  return keys;
}

// ---------------------------------------------------------------------------
// Playlist / history / tombstone / favorites models
// ---------------------------------------------------------------------------

export class SyncPlaylist {
  id: number;
  name: string;
  songs: SyncSong[];
  createdAt: number;
  modifiedAt: number;
  isDeleted: boolean;
  songOrderVersion: number;

  constructor(
    id: number = 0,
    name: string = '',
    songs: SyncSong[] = [],
    createdAt: number = 0,
    modifiedAt: number = 0,
    isDeleted: boolean = false,
    songOrderVersion: number = LEGACY_SONG_ORDER_VERSION
  ) {
    this.id = id;
    this.name = name;
    this.songs = songs;
    this.createdAt = createdAt;
    this.modifiedAt = modifiedAt;
    this.isDeleted = isDeleted;
    this.songOrderVersion = songOrderVersion;
  }
}

export class SyncRecentPlay {
  songId: number;
  song: SyncSong;
  playedAt: number;
  deviceId: string;
  resumePositionMs: number;

  constructor(
    songId: number = 0,
    song: SyncSong = new SyncSong(),
    playedAt: number = 0,
    deviceId: string = '',
    resumePositionMs: number = 0
  ) {
    this.songId = songId;
    this.song = song;
    this.playedAt = playedAt;
    this.deviceId = deviceId;
    this.resumePositionMs = resumePositionMs;
  }
}

export class SyncRecentPlayDeletion {
  songId: number;
  album: string;
  mediaUri: string | null;
  deletedAt: number;
  deviceId: string;
  /** Wire-fidelity decimal text for 64-bit songIds beyond JS precision. */
  syncSongIdText: string;

  constructor(
    songId: number = 0,
    album: string = '',
    mediaUri: string | null = null,
    deletedAt: number = 0,
    deviceId: string = '',
    syncSongIdText: string = ''
  ) {
    this.songId = songId;
    this.album = album;
    this.mediaUri = mediaUri;
    this.deletedAt = deletedAt;
    this.deviceId = deviceId;
    this.syncSongIdText = syncSongIdText;
  }

  identity(): SongIdentityKey {
    return new SongIdentityKey(
      this.syncSongIdText.length > 0 ? this.syncSongIdText : `${this.songId}`,
      this.album,
      this.mediaUri
    );
  }

  stableKey(): string {
    return this.identity().stableKey();
  }
}

export class SyncPlaylistSongDeletion {
  playlistId: number;
  songId: number;
  album: string;
  mediaUri: string | null;
  deletedAt: number;
  deviceId: string;
  removedMembershipTokens: SyncCausalToken[];
  /** Wire-fidelity decimal text for 64-bit songIds beyond JS precision. */
  syncSongIdText: string;

  constructor(
    playlistId: number = 0,
    songId: number = 0,
    album: string = '',
    mediaUri: string | null = null,
    deletedAt: number = 0,
    deviceId: string = '',
    removedMembershipTokens: SyncCausalToken[] = [],
    syncSongIdText: string = ''
  ) {
    this.playlistId = playlistId;
    this.songId = songId;
    this.album = album;
    this.mediaUri = mediaUri;
    this.deletedAt = deletedAt;
    this.deviceId = deviceId;
    this.removedMembershipTokens = removedMembershipTokens;
    this.syncSongIdText = syncSongIdText;
  }

  identity(): SongIdentityKey {
    return new SongIdentityKey(
      this.syncSongIdText.length > 0 ? this.syncSongIdText : `${this.songId}`,
      this.album,
      this.mediaUri
    );
  }

  stableKey(): string {
    return `${this.playlistId}|${this.identity().stableKey()}`;
  }
}

export class SyncFavoritePlaylist {
  id: number;
  name: string;
  coverUrl: string | null;
  trackCount: number;
  source: string;
  songs: SyncSong[];
  addedTime: number;
  modifiedAt: number;
  isDeleted: boolean;
  sortOrder: number;
  browseId: string | null;
  playlistId: string | null;
  subtitle: string | null;

  constructor(
    id: number = 0,
    name: string = '',
    coverUrl: string | null = null,
    trackCount: number = 0,
    source: string = '',
    songs: SyncSong[] = [],
    addedTime: number = 0,
    modifiedAt: number = addedTime,
    isDeleted: boolean = false,
    sortOrder: number = addedTime,
    browseId: string | null = null,
    playlistId: string | null = null,
    subtitle: string | null = null
  ) {
    this.id = id;
    this.name = name;
    this.coverUrl = coverUrl;
    this.trackCount = trackCount;
    this.source = source;
    this.songs = songs;
    this.addedTime = addedTime;
    this.modifiedAt = modifiedAt;
    this.isDeleted = isDeleted;
    this.sortOrder = sortOrder;
    this.browseId = browseId;
    this.playlistId = playlistId;
    this.subtitle = subtitle;
  }
}

export enum SyncAction {
  CREATE_PLAYLIST = 0,
  DELETE_PLAYLIST = 1,
  RENAME_PLAYLIST = 2,
  ADD_SONG = 3,
  REMOVE_SONG = 4,
  REORDER_SONGS = 5,
  PLAY_SONG = 6
}

export class SyncLogEntry {
  timestamp: number;
  deviceId: string;
  action: SyncAction;
  playlistId: number | null;
  songId: number | null;
  details: string | null;

  constructor(
    timestamp: number = 0,
    deviceId: string = '',
    action: SyncAction = SyncAction.CREATE_PLAYLIST,
    playlistId: number | null = null,
    songId: number | null = null,
    details: string | null = null
  ) {
    this.timestamp = timestamp;
    this.deviceId = deviceId;
    this.action = action;
    this.playlistId = playlistId;
    this.songId = songId;
    this.details = details;
  }
}

// ---------------------------------------------------------------------------
// Playback stats models + counter shard helpers (SyncPlaybackStatMapper.kt)
// ---------------------------------------------------------------------------

export class SyncPlaybackCounterShard {
  deviceId: string;
  epochStartedAt: number;
  totalListenMs: number;
  playCount: number;
  firstPlayedAt: number;
  lastPlayedAt: number;

  constructor(
    deviceId: string = '',
    epochStartedAt: number = 0,
    totalListenMs: number = 0,
    playCount: number = 0,
    firstPlayedAt: number = 0,
    lastPlayedAt: number = 0
  ) {
    this.deviceId = deviceId;
    this.epochStartedAt = epochStartedAt;
    this.totalListenMs = totalListenMs;
    this.playCount = playCount;
    this.firstPlayedAt = firstPlayedAt;
    this.lastPlayedAt = lastPlayedAt;
  }
}

export function counterShardEquals(a: SyncPlaybackCounterShard, b: SyncPlaybackCounterShard): boolean {
  return a.deviceId === b.deviceId && a.epochStartedAt === b.epochStartedAt &&
    a.totalListenMs === b.totalListenMs && a.playCount === b.playCount &&
    a.firstPlayedAt === b.firstPlayedAt && a.lastPlayedAt === b.lastPlayedAt;
}

function minPositivePlayedAt(left: number, right: number): number {
  if (left <= 0) {
    return right;
  }
  if (right <= 0) {
    return left;
  }
  return Math.min(left, right);
}

function compareCounterShards(
  a: SyncPlaybackCounterShard,
  b: SyncPlaybackCounterShard
): number {
  if (a.deviceId < b.deviceId) {
    return -1;
  }
  if (a.deviceId > b.deviceId) {
    return 1;
  }
  if (a.epochStartedAt < b.epochStartedAt) {
    return -1;
  }
  if (a.epochStartedAt > b.epochStartedAt) {
    return 1;
  }
  return 0;
}

function mergeCounterShard(
  left: SyncPlaybackCounterShard,
  right: SyncPlaybackCounterShard
): SyncPlaybackCounterShard {
  return new SyncPlaybackCounterShard(
    left.deviceId,
    left.epochStartedAt,
    Math.max(left.totalListenMs, right.totalListenMs),
    Math.max(left.playCount, right.playCount),
    minPositivePlayedAt(left.firstPlayedAt, right.firstPlayedAt),
    Math.max(left.lastPlayedAt, right.lastPlayedAt)
  );
}

/**
 * normalizeCounterShards: clamp values, reset irrational firstPlayedAt, reduce
 * per (deviceId, epoch), sort by (deviceId, epochStartedAt). Grouping,
 * aggregation and ordering are all load-bearing for merge convergence.
 */
export function normalizeCounterShards(shards: SyncPlaybackCounterShard[]): SyncPlaybackCounterShard[] {
  const cleaned: SyncPlaybackCounterShard[] = [];
  for (const shard of shards) {
    if (shard.deviceId.trim().length === 0) {
      continue;
    }
    const lastPlayedAt = Math.max(shard.lastPlayedAt, 0);
    let firstPlayedAt = Math.max(shard.firstPlayedAt, 0);
    if (lastPlayedAt > 0 && (firstPlayedAt === 0 || firstPlayedAt > lastPlayedAt)) {
      firstPlayedAt = lastPlayedAt;
    }
    cleaned.push(new SyncPlaybackCounterShard(
      shard.deviceId,
      Math.max(shard.epochStartedAt, 0),
      Math.max(shard.totalListenMs, 0),
      Math.max(shard.playCount, 0),
      firstPlayedAt,
      lastPlayedAt
    ));
  }
  const groups = new Map<string, SyncPlaybackCounterShard[]>();
  for (const shard of cleaned) {
    const key = `${shard.deviceId}\u0000${shard.epochStartedAt}`;
    const bucket = groups.get(key);
    if (bucket === undefined) {
      groups.set(key, [shard]);
    } else {
      bucket.push(shard);
    }
  }
  const reduced: SyncPlaybackCounterShard[] = [];
  groups.forEach((snapshots: SyncPlaybackCounterShard[]) => {
    let acc = snapshots[0];
    for (let i = 1; i < snapshots.length; i++) {
      acc = mergeCounterShard(acc, snapshots[i]);
    }
    reduced.push(acc);
  });
  return reduced.sort(compareCounterShards);
}

export class SyncTrackStat {
  identityKey: string;
  name: string;
  artist: string;
  album: string;
  totalListenMs: number;
  playCount: number;
  lastPlayedAt: number;
  firstPlayedAt: number;
  coverUrl: string | null;
  durationMs: number;
  mediaUri: string | null;
  id: number;
  albumId: number;
  counterBaseListenMs: number;
  counterBasePlayCount: number;
  counterShards: SyncPlaybackCounterShard[];

  constructor(
    identityKey: string = '',
    name: string = '',
    artist: string = '',
    album: string = '',
    totalListenMs: number = 0,
    playCount: number = 0,
    lastPlayedAt: number = 0,
    firstPlayedAt: number = 0,
    coverUrl: string | null = null,
    durationMs: number = 0,
    mediaUri: string | null = null,
    id: number = 0,
    albumId: number = 0,
    counterBaseListenMs: number = 0,
    counterBasePlayCount: number = 0,
    counterShards: SyncPlaybackCounterShard[] = []
  ) {
    this.identityKey = identityKey;
    this.name = name;
    this.artist = artist;
    this.album = album;
    this.totalListenMs = totalListenMs;
    this.playCount = playCount;
    this.lastPlayedAt = lastPlayedAt;
    this.firstPlayedAt = firstPlayedAt;
    this.coverUrl = coverUrl;
    this.durationMs = durationMs;
    this.mediaUri = mediaUri;
    this.id = id;
    this.albumId = albumId;
    this.counterBaseListenMs = counterBaseListenMs;
    this.counterBasePlayCount = counterBasePlayCount;
    this.counterShards = counterShards;
  }
}

export class SyncPlaybackStatBucket {
  dayStartAt: number;
  identityKey: string;
  name: string;
  artist: string;
  album: string;
  totalListenMs: number;
  playCount: number;
  lastPlayedAt: number;
  firstPlayedAt: number;
  coverUrl: string | null;
  durationMs: number;
  mediaUri: string | null;
  id: number;
  albumId: number;
  counterBaseListenMs: number;
  counterBasePlayCount: number;
  counterShards: SyncPlaybackCounterShard[];

  constructor(
    dayStartAt: number = 0,
    identityKey: string = '',
    name: string = '',
    artist: string = '',
    album: string = '',
    totalListenMs: number = 0,
    playCount: number = 0,
    lastPlayedAt: number = 0,
    firstPlayedAt: number = 0,
    coverUrl: string | null = null,
    durationMs: number = 0,
    mediaUri: string | null = null,
    id: number = 0,
    albumId: number = 0,
    counterBaseListenMs: number = 0,
    counterBasePlayCount: number = 0,
    counterShards: SyncPlaybackCounterShard[] = []
  ) {
    this.dayStartAt = dayStartAt;
    this.identityKey = identityKey;
    this.name = name;
    this.artist = artist;
    this.album = album;
    this.totalListenMs = totalListenMs;
    this.playCount = playCount;
    this.lastPlayedAt = lastPlayedAt;
    this.firstPlayedAt = firstPlayedAt;
    this.coverUrl = coverUrl;
    this.durationMs = durationMs;
    this.mediaUri = mediaUri;
    this.id = id;
    this.albumId = albumId;
    this.counterBaseListenMs = counterBaseListenMs;
    this.counterBasePlayCount = counterBasePlayCount;
    this.counterShards = counterShards;
  }
}

function shardListEquals(a: SyncPlaybackCounterShard[], b: SyncPlaybackCounterShard[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (!counterShardEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

/** SyncPlaybackStatMapper.sameMetadata for track stats. */
export function trackStatMetadataEquals(a: SyncTrackStat, b: SyncTrackStat): boolean {
  return a.identityKey === b.identityKey && a.name === b.name && a.artist === b.artist &&
    a.album === b.album && a.totalListenMs === b.totalListenMs &&
    a.playCount === b.playCount && a.lastPlayedAt === b.lastPlayedAt &&
    a.firstPlayedAt === b.firstPlayedAt && a.coverUrl === b.coverUrl &&
    a.durationMs === b.durationMs && a.mediaUri === b.mediaUri && a.id === b.id &&
    a.albumId === b.albumId && a.counterBaseListenMs === b.counterBaseListenMs &&
    a.counterBasePlayCount === b.counterBasePlayCount &&
    shardListEquals(normalizeCounterShards(a.counterShards), normalizeCounterShards(b.counterShards));
}

/** SyncPlaybackStatMapper.sameMetadata for daily buckets. */
export function bucketMetadataEquals(a: SyncPlaybackStatBucket, b: SyncPlaybackStatBucket): boolean {
  return a.dayStartAt === b.dayStartAt && a.identityKey === b.identityKey &&
    a.name === b.name && a.artist === b.artist && a.album === b.album &&
    a.totalListenMs === b.totalListenMs && a.playCount === b.playCount &&
    a.lastPlayedAt === b.lastPlayedAt && a.firstPlayedAt === b.firstPlayedAt &&
    a.coverUrl === b.coverUrl && a.durationMs === b.durationMs &&
    a.mediaUri === b.mediaUri && a.id === b.id && a.albumId === b.albumId &&
    a.counterBaseListenMs === b.counterBaseListenMs &&
    a.counterBasePlayCount === b.counterBasePlayCount &&
    shardListEquals(normalizeCounterShards(a.counterShards), normalizeCounterShards(b.counterShards));
}

// ---------------------------------------------------------------------------
// SyncData top-level snapshot
// ---------------------------------------------------------------------------

export class SyncData {
  version: string;
  deviceId: string;
  deviceName: string;
  lastModified: number;
  playlists: SyncPlaylist[];
  favoritePlaylists: SyncFavoritePlaylist[];
  recentPlays: SyncRecentPlay[];
  syncLog: SyncLogEntry[];
  recentPlayDeletions: SyncRecentPlayDeletion[];
  playbackStats: SyncTrackStat[];
  playbackStatsClearedAt: number;
  playbackStatBuckets: SyncPlaybackStatBucket[];
  playlistSongDeletions: SyncPlaylistSongDeletion[];

  constructor(
    version: string = SYNC_DATA_VERSION,
    deviceId: string = '',
    deviceName: string = '',
    lastModified: number = 0,
    playlists: SyncPlaylist[] = [],
    favoritePlaylists: SyncFavoritePlaylist[] = [],
    recentPlays: SyncRecentPlay[] = [],
    syncLog: SyncLogEntry[] = [],
    recentPlayDeletions: SyncRecentPlayDeletion[] = [],
    playbackStats: SyncTrackStat[] = [],
    playbackStatsClearedAt: number = 0,
    playbackStatBuckets: SyncPlaybackStatBucket[] = [],
    playlistSongDeletions: SyncPlaylistSongDeletion[] = []
  ) {
    this.version = version;
    this.deviceId = deviceId;
    this.deviceName = deviceName;
    this.lastModified = lastModified;
    this.playlists = playlists;
    this.favoritePlaylists = favoritePlaylists;
    this.recentPlays = recentPlays;
    this.syncLog = syncLog;
    this.recentPlayDeletions = recentPlayDeletions;
    this.playbackStats = playbackStats;
    this.playbackStatsClearedAt = playbackStatsClearedAt;
    this.playbackStatBuckets = playbackStatBuckets;
    this.playlistSongDeletions = playlistSongDeletions;
  }
}
