// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Protobuf wire decoder for the sync binary channel, porting the read path
 * of Android SyncDataSerializer.decodeGzipProto (kotlinx.protobuf 1.11.0,
 * encodeDefaults=false, no packing, no zigzag — see ProtobufWire.ets notes).
 *
 * Field numbers and defaults mirror data/sync/model/SyncDataModels.kt and
 * SyncCausalToken.kt. Each message is parsed in two phases: RawFields.parse
 * enforces the expected wire type per known field (a mismatch fails the whole
 * decode — this is what makes the legacy schema fallback trigger, because
 * legacy SyncSong tag 8 is a varint addedAt while current tag 8 is a string
 * mediaUri), and unknown fields are skipped silently like kotlinx does.
 */
import {
  SyncData,
  SyncPlaylist,
  SyncSong,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncFavoritePlaylist,
  SyncLogEntry,
  SyncAction,
  SyncCausalToken,
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaybackCounterShard,
  normalizedSyncCausalTokens,
  SYNC_DATA_VERSION
} from './SyncModels';
import {
  ProtoReader,
  WIRE_VARINT,
  WIRE_LEN,
  int64NumberValue,
  idFieldText,
  int32FromVarint
} from './ProtobufWire';

// ---------------------------------------------------------------------------
// Phase 1: schema-checked wire parsing
// ---------------------------------------------------------------------------

/**
 * Per-message raw fields. Varint scalars keep the last occurrence (proto3
 * last-wins); length-delimited payloads keep every occurrence in order so
 * repeated messages stay positional.
 */
class RawFields {
  private readonly varints: Map<number, bigint> = new Map();
  private readonly lengths: Map<number, ProtoReader[]> = new Map();

  static parse(reader: ProtoReader, varintFields: Set<number>, lenFields: Set<number>): RawFields | null {
    const fields = new RawFields();
    while (!reader.atEnd()) {
      const tag = reader.readTag();
      if (tag === -1) {
        return null;
      }
      const field = tag >>> 3;
      const wireType = tag & 0x07;
      if (varintFields.has(field)) {
        if (wireType !== WIRE_VARINT) {
          return null;
        }
        const value = reader.readVarint();
        if (value === null) {
          return null;
        }
        fields.varints.set(field, value);
      } else if (lenFields.has(field)) {
        if (wireType !== WIRE_LEN) {
          return null;
        }
        const nested = reader.readLengthRange();
        if (nested === null) {
          return null;
        }
        const existing = fields.lengths.get(field);
        if (existing === undefined) {
          fields.lengths.set(field, [nested]);
        } else {
          existing.push(nested);
        }
      } else if (!reader.skip(wireType)) {
        return null;
      }
    }
    return fields;
  }

  varint(field: number): bigint | null {
    return this.varints.get(field) ?? null;
  }

  hasVarint(field: number): boolean {
    return this.varints.has(field);
  }

  readers(field: number): ProtoReader[] {
    return this.lengths.get(field) ?? [];
  }

  lastReader(field: number): ProtoReader | null {
    const list = this.lengths.get(field);
    if (list === undefined || list.length === 0) {
      return null;
    }
    return list[list.length - 1];
  }
}

// Field-number sets per message (current schema) ------------------------------

const DATA_VARINT: Set<number> = new Set([4, 11]);
const DATA_LEN: Set<number> = new Set([1, 2, 3, 5, 6, 7, 8, 9, 10, 12, 13]);

const PLAYLIST_VARINT: Set<number> = new Set([1, 4, 5, 6, 7]);
const PLAYLIST_LEN: Set<number> = new Set([2, 3]);

const SONG_VARINT: Set<number> = new Set([1, 5, 6, 9, 14, 28, 29]);
const SONG_LEN: Set<number> = new Set([2, 3, 4, 7, 8, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]);

const RECENT_PLAY_VARINT: Set<number> = new Set([1, 3, 5]);
const RECENT_PLAY_LEN: Set<number> = new Set([2, 4]);

const RECENT_DELETION_VARINT: Set<number> = new Set([1, 4]);
const RECENT_DELETION_LEN: Set<number> = new Set([2, 3, 5]);

const PLAYLIST_DELETION_VARINT: Set<number> = new Set([1, 2, 5]);
const PLAYLIST_DELETION_LEN: Set<number> = new Set([3, 4, 6, 7]);

const FAVORITE_VARINT: Set<number> = new Set([1, 4, 7, 8, 9, 10]);
const FAVORITE_LEN: Set<number> = new Set([2, 3, 5, 6, 11, 12, 13]);

const LOG_VARINT: Set<number> = new Set([1, 3, 4, 5]);
const LOG_LEN: Set<number> = new Set([2, 6]);

const SHARD_VARINT: Set<number> = new Set([2, 3, 4, 5, 6]);
const SHARD_LEN: Set<number> = new Set([1]);

const TRACK_STAT_VARINT: Set<number> = new Set([5, 6, 7, 8, 10, 12, 13, 14, 15]);
const TRACK_STAT_LEN: Set<number> = new Set([1, 2, 3, 4, 9, 11, 16]);

// SyncPlaybackStatBucket = dayStartAt(1, varint) + SyncTrackStat fields shifted by one:
// album lives at field 5 (LEN), totalListenMs at 6, and so on.
const BUCKET_VARINT: Set<number> = new Set([1, 6, 7, 8, 9, 11, 13, 14, 15, 16]);
const BUCKET_LEN: Set<number> = new Set([2, 3, 4, 5, 10, 12, 17]);

const TOKEN_VARINT: Set<number> = new Set([2]);
const TOKEN_LEN: Set<number> = new Set([1]);

// ---------------------------------------------------------------------------
// Phase 2: typed accessors (absent field → schema default)
// ---------------------------------------------------------------------------

function strOf(f: RawFields, field: number): string | null {
  const reader = f.lastReader(field);
  return reader === null ? null : reader.payloadAsString();
}

function int64Of(f: RawFields, field: number): number | null {
  const v = f.varint(field);
  return v === null ? null : int64NumberValue(v);
}

function int32Of(f: RawFields, field: number): number | null {
  const v = f.varint(field);
  return v === null ? null : int32FromVarint(v);
}

function boolOf(f: RawFields, field: number): boolean | null {
  const v = f.varint(field);
  return v === null ? null : v !== 0n;
}

/** Decodes an id varint into the JSON-codec-compatible number/text split. */
class IdValue {
  readonly value: number;
  readonly text: string;

  constructor(raw: bigint) {
    this.value = int64NumberValue(raw);
    this.text = idFieldText(raw);
  }
}

function idOf(f: RawFields, field: number): IdValue | null {
  const v = f.varint(field);
  return v === null ? null : new IdValue(v);
}

// ---------------------------------------------------------------------------
// Current schema: message decoders
// ---------------------------------------------------------------------------

function decodeCausalTokens(f: RawFields, field: number): SyncCausalToken[] {
  const tokens: SyncCausalToken[] = [];
  for (const nested of f.readers(field)) {
    const parsed = RawFields.parse(nested, TOKEN_VARINT, TOKEN_LEN);
    if (parsed === null) {
      continue;
    }
    const deviceId = strOf(parsed, 1);
    const counter = int64Of(parsed, 2);
    tokens.push(new SyncCausalToken(deviceId === null ? '' : deviceId, counter === null ? 0 : counter));
  }
  return normalizedSyncCausalTokens(tokens);
}

function decodeSyncSong(r: ProtoReader): SyncSong | null {
  const f = RawFields.parse(r, SONG_VARINT, SONG_LEN);
  if (f === null) {
    return null;
  }
  const id = idOf(f, 1);
  return new SyncSong(
    id === null ? 0 : id.value,
    strOf(f, 2) ?? '',
    strOf(f, 3) ?? '',
    strOf(f, 4) ?? '',
    int64Of(f, 5) ?? 0,
    int64Of(f, 6) ?? 0,
    strOf(f, 7),
    strOf(f, 8),
    int64Of(f, 9) ?? 0,
    strOf(f, 10),
    strOf(f, 11),
    strOf(f, 12),
    strOf(f, 13),
    int64Of(f, 14) ?? 0,
    strOf(f, 15),
    strOf(f, 16),
    strOf(f, 17),
    strOf(f, 18),
    strOf(f, 19),
    strOf(f, 20),
    strOf(f, 21),
    strOf(f, 22),
    strOf(f, 23),
    strOf(f, 24),
    strOf(f, 25),
    strOf(f, 26),
    decodeCausalTokens(f, 27),
    int32Of(f, 28) ?? 0,
    int64Of(f, 29),
    id === null ? '' : id.text
  );
}

function decodeSyncPlaylist(r: ProtoReader): SyncPlaylist | null {
  const f = RawFields.parse(r, PLAYLIST_VARINT, PLAYLIST_LEN);
  if (f === null) {
    return null;
  }
  const songs: SyncSong[] = [];
  for (const nested of f.readers(3)) {
    const song = decodeSyncSong(nested);
    if (song === null) {
      return null;
    }
    songs.push(song);
  }
  return new SyncPlaylist(
    int64Of(f, 1) ?? 0,
    strOf(f, 2) ?? '',
    songs,
    int64Of(f, 4) ?? 0,
    int64Of(f, 5) ?? 0,
    boolOf(f, 6) ?? false,
    int32Of(f, 7) ?? 0
  );
}

function decodeRecentPlay(r: ProtoReader): SyncRecentPlay | null {
  const f = RawFields.parse(r, RECENT_PLAY_VARINT, RECENT_PLAY_LEN);
  if (f === null) {
    return null;
  }
  let song = new SyncSong();
  const songReader = f.lastReader(2);
  if (songReader !== null) {
    const decoded = decodeSyncSong(songReader);
    if (decoded === null) {
      return null;
    }
    song = decoded;
  }
  return new SyncRecentPlay(
    int64Of(f, 1) ?? 0,
    song,
    int64Of(f, 3) ?? 0,
    strOf(f, 4) ?? '',
    int64Of(f, 5) ?? 0
  );
}

function decodeRecentPlayDeletion(r: ProtoReader): SyncRecentPlayDeletion | null {
  const f = RawFields.parse(r, RECENT_DELETION_VARINT, RECENT_DELETION_LEN);
  if (f === null) {
    return null;
  }
  const id = idOf(f, 1);
  return new SyncRecentPlayDeletion(
    id === null ? 0 : id.value,
    strOf(f, 2) ?? '',
    strOf(f, 3),
    int64Of(f, 4) ?? 0,
    strOf(f, 5) ?? '',
    id === null ? '' : id.text
  );
}

function decodePlaylistSongDeletion(r: ProtoReader): SyncPlaylistSongDeletion | null {
  const f = RawFields.parse(r, PLAYLIST_DELETION_VARINT, PLAYLIST_DELETION_LEN);
  if (f === null) {
    return null;
  }
  const id = idOf(f, 2);
  return new SyncPlaylistSongDeletion(
    int64Of(f, 1) ?? 0,
    id === null ? 0 : id.value,
    strOf(f, 3) ?? '',
    strOf(f, 4),
    int64Of(f, 5) ?? 0,
    strOf(f, 6) ?? '',
    decodeCausalTokens(f, 7),
    id === null ? '' : id.text
  );
}

function decodeFavoritePlaylist(r: ProtoReader): SyncFavoritePlaylist | null {
  const f = RawFields.parse(r, FAVORITE_VARINT, FAVORITE_LEN);
  if (f === null) {
    return null;
  }
  const songs: SyncSong[] = [];
  for (const nested of f.readers(6)) {
    const song = decodeSyncSong(nested);
    if (song === null) {
      return null;
    }
    songs.push(song);
  }
  const addedTime = int64Of(f, 7) ?? 0;
  return new SyncFavoritePlaylist(
    int64Of(f, 1) ?? 0,
    strOf(f, 2) ?? '',
    strOf(f, 3),
    int32Of(f, 4) ?? 0,
    strOf(f, 5) ?? '',
    songs,
    addedTime,
    int64Of(f, 8) ?? addedTime,
    boolOf(f, 9) ?? false,
    int64Of(f, 10) ?? addedTime,
    strOf(f, 11),
    strOf(f, 12),
    strOf(f, 13)
  );
}

function decodeSyncAction(f: RawFields, field: number): SyncAction | null {
  const v = f.varint(field);
  if (v === null) {
    return SyncAction.CREATE_PLAYLIST;
  }
  if (v > 6n) {
    return null; // kotlinx rejects unknown enum ordinals
  }
  const ordinal = Number(v);
  switch (ordinal) {
    case 0: return SyncAction.CREATE_PLAYLIST;
    case 1: return SyncAction.DELETE_PLAYLIST;
    case 2: return SyncAction.RENAME_PLAYLIST;
    case 3: return SyncAction.ADD_SONG;
    case 4: return SyncAction.REMOVE_SONG;
    case 5: return SyncAction.REORDER_SONGS;
    case 6: return SyncAction.PLAY_SONG;
    default: return null;
  }
}

function decodeLogEntry(r: ProtoReader): SyncLogEntry | null {
  const f = RawFields.parse(r, LOG_VARINT, LOG_LEN);
  if (f === null) {
    return null;
  }
  const action = decodeSyncAction(f, 3);
  if (action === null) {
    return null;
  }
  return new SyncLogEntry(
    int64Of(f, 1) ?? 0,
    strOf(f, 2) ?? '',
    action,
    int64Of(f, 4),
    int64Of(f, 5),
    strOf(f, 6)
  );
}

function decodeCounterShards(f: RawFields, field: number): SyncPlaybackCounterShard[] {
  const shards: SyncPlaybackCounterShard[] = [];
  for (const nested of f.readers(field)) {
    const parsed = RawFields.parse(nested, SHARD_VARINT, SHARD_LEN);
    if (parsed === null) {
      continue;
    }
    shards.push(new SyncPlaybackCounterShard(
      strOf(parsed, 1) ?? '',
      int64Of(parsed, 2) ?? 0,
      int64Of(parsed, 3) ?? 0,
      int32Of(parsed, 4) ?? 0,
      int64Of(parsed, 5) ?? 0,
      int64Of(parsed, 6) ?? 0
    ));
  }
  return shards;
}

function decodeTrackStat(r: ProtoReader): SyncTrackStat | null {
  const f = RawFields.parse(r, TRACK_STAT_VARINT, TRACK_STAT_LEN);
  if (f === null) {
    return null;
  }
  return new SyncTrackStat(
    strOf(f, 1) ?? '',
    strOf(f, 2) ?? '',
    strOf(f, 3) ?? '',
    strOf(f, 4) ?? '',
    int64Of(f, 5) ?? 0,
    int32Of(f, 6) ?? 0,
    int64Of(f, 7) ?? 0,
    int64Of(f, 8) ?? 0,
    strOf(f, 9),
    int64Of(f, 10) ?? 0,
    strOf(f, 11),
    int64Of(f, 12) ?? 0,
    int64Of(f, 13) ?? 0,
    int64Of(f, 14) ?? 0,
    int32Of(f, 15) ?? 0,
    decodeCounterShards(f, 16)
  );
}

function decodePlaybackStatBucket(r: ProtoReader): SyncPlaybackStatBucket | null {
  const f = RawFields.parse(r, BUCKET_VARINT, BUCKET_LEN);
  if (f === null) {
    return null;
  }
  return new SyncPlaybackStatBucket(
    int64Of(f, 1) ?? 0,
    strOf(f, 2) ?? '',
    strOf(f, 3) ?? '',
    strOf(f, 4) ?? '',
    strOf(f, 5) ?? '',
    int64Of(f, 6) ?? 0,
    int32Of(f, 7) ?? 0,
    int64Of(f, 8) ?? 0,
    int64Of(f, 9) ?? 0,
    strOf(f, 10),
    int64Of(f, 11) ?? 0,
    strOf(f, 12),
    int64Of(f, 13) ?? 0,
    int64Of(f, 14) ?? 0,
    int64Of(f, 15) ?? 0,
    int32Of(f, 16) ?? 0,
    decodeCounterShards(f, 17)
  );
}

/**
 * Current-schema SyncData decode. `nowMs` supplies the kotlinx default for a
 * missing lastModified field (Android: System.currentTimeMillis()).
 */
export function decodeSyncDataProto(bytes: Uint8Array, nowMs: number = Date.now()): SyncData | null {
  const f = RawFields.parse(ProtoReader.over(bytes), DATA_VARINT, DATA_LEN);
  if (f === null) {
    return null;
  }
  const playlists: SyncPlaylist[] = [];
  for (const nested of f.readers(5)) {
    const playlist = decodeSyncPlaylist(nested);
    if (playlist === null) {
      return null;
    }
    playlists.push(playlist);
  }
  const favorites: SyncFavoritePlaylist[] = [];
  for (const nested of f.readers(6)) {
    const favorite = decodeFavoritePlaylist(nested);
    if (favorite === null) {
      return null;
    }
    favorites.push(favorite);
  }
  const recentPlays: SyncRecentPlay[] = [];
  for (const nested of f.readers(7)) {
    const entry = decodeRecentPlay(nested);
    if (entry === null) {
      return null;
    }
    recentPlays.push(entry);
  }
  const syncLog: SyncLogEntry[] = [];
  for (const nested of f.readers(8)) {
    const entry = decodeLogEntry(nested);
    if (entry === null) {
      return null;
    }
    syncLog.push(entry);
  }
  const recentPlayDeletions: SyncRecentPlayDeletion[] = [];
  for (const nested of f.readers(9)) {
    const deletion = decodeRecentPlayDeletion(nested);
    if (deletion === null) {
      return null;
    }
    recentPlayDeletions.push(deletion);
  }
  const playbackStats: SyncTrackStat[] = [];
  for (const nested of f.readers(10)) {
    const stat = decodeTrackStat(nested);
    if (stat === null) {
      return null;
    }
    playbackStats.push(stat);
  }
  const buckets: SyncPlaybackStatBucket[] = [];
  for (const nested of f.readers(12)) {
    const bucket = decodePlaybackStatBucket(nested);
    if (bucket === null) {
      return null;
    }
    buckets.push(bucket);
  }
  const playlistSongDeletions: SyncPlaylistSongDeletion[] = [];
  for (const nested of f.readers(13)) {
    const deletion = decodePlaylistSongDeletion(nested);
    if (deletion === null) {
      return null;
    }
    playlistSongDeletions.push(deletion);
  }
  return new SyncData(
    strOf(f, 1) ?? SYNC_DATA_VERSION,
    strOf(f, 2) ?? '',
    strOf(f, 3) ?? '',
    f.hasVarint(4) ? (int64Of(f, 4) as number) : nowMs,
    playlists,
    favorites,
    recentPlays,
    syncLog,
    recentPlayDeletions,
    playbackStats,
    int64Of(f, 11) ?? 0,
    buckets,
    playlistSongDeletions
  );
}

// ---------------------------------------------------------------------------
// Legacy schema (pre-mediaUri backups): decode then map to current models,
// mirroring LegacySyncData.toCurrent() in SyncDataSerializer.kt
// ---------------------------------------------------------------------------

const LEGACY_DATA_VARINT: Set<number> = new Set([4]);
const LEGACY_DATA_LEN: Set<number> = new Set([1, 2, 3, 5, 6, 7, 8]);

const LEGACY_PLAYLIST_VARINT: Set<number> = new Set([1, 4, 5, 6]);
const LEGACY_PLAYLIST_LEN: Set<number> = new Set([2, 3]);

const LEGACY_SONG_VARINT: Set<number> = new Set([1, 5, 6, 8, 13]);
const LEGACY_SONG_LEN: Set<number> = new Set([2, 3, 4, 7, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21]);

const LEGACY_RECENT_VARINT: Set<number> = new Set([1, 3]);
const LEGACY_RECENT_LEN: Set<number> = new Set([2, 4]);

const LEGACY_FAVORITE_VARINT: Set<number> = new Set([1, 4, 7]);
const LEGACY_FAVORITE_LEN: Set<number> = new Set([2, 3, 5, 6]);

function decodeLegacySyncSong(r: ProtoReader): SyncSong | null {
  const f = RawFields.parse(r, LEGACY_SONG_VARINT, LEGACY_SONG_LEN);
  if (f === null) {
    return null;
  }
  const id = idOf(f, 1);
  return new SyncSong(
    id === null ? 0 : id.value,
    strOf(f, 2) ?? '',
    strOf(f, 3) ?? '',
    strOf(f, 4) ?? '',
    int64Of(f, 5) ?? 0,
    int64Of(f, 6) ?? 0,
    strOf(f, 7),
    null,
    int64Of(f, 8) ?? 0,
    strOf(f, 9),
    strOf(f, 10),
    strOf(f, 11),
    strOf(f, 12),
    int64Of(f, 13) ?? 0,
    strOf(f, 14),
    strOf(f, 15),
    strOf(f, 16),
    strOf(f, 17),
    strOf(f, 18),
    strOf(f, 19),
    strOf(f, 20),
    strOf(f, 21),
    null,
    null,
    null,
    null,
    [],
    0,
    null,
    id === null ? '' : id.text
  );
}

function decodeLegacySyncPlaylist(r: ProtoReader): SyncPlaylist | null {
  const f = RawFields.parse(r, LEGACY_PLAYLIST_VARINT, LEGACY_PLAYLIST_LEN);
  if (f === null) {
    return null;
  }
  const songs: SyncSong[] = [];
  for (const nested of f.readers(3)) {
    const song = decodeLegacySyncSong(nested);
    if (song === null) {
      return null;
    }
    songs.push(song);
  }
  return new SyncPlaylist(
    int64Of(f, 1) ?? 0,
    strOf(f, 2) ?? '',
    songs,
    int64Of(f, 4) ?? 0,
    int64Of(f, 5) ?? 0,
    boolOf(f, 6) ?? false,
    0
  );
}

function decodeLegacyRecentPlay(r: ProtoReader): SyncRecentPlay | null {
  const f = RawFields.parse(r, LEGACY_RECENT_VARINT, LEGACY_RECENT_LEN);
  if (f === null) {
    return null;
  }
  let song = new SyncSong();
  const songReader = f.lastReader(2);
  if (songReader !== null) {
    const decoded = decodeLegacySyncSong(songReader);
    if (decoded === null) {
      return null;
    }
    song = decoded;
  }
  return new SyncRecentPlay(
    int64Of(f, 1) ?? 0,
    song,
    int64Of(f, 3) ?? 0,
    strOf(f, 4) ?? '',
    0
  );
}

function decodeLegacyFavoritePlaylist(r: ProtoReader): SyncFavoritePlaylist | null {
  const f = RawFields.parse(r, LEGACY_FAVORITE_VARINT, LEGACY_FAVORITE_LEN);
  if (f === null) {
    return null;
  }
  const songs: SyncSong[] = [];
  for (const nested of f.readers(6)) {
    const song = decodeLegacySyncSong(nested);
    if (song === null) {
      return null;
    }
    songs.push(song);
  }
  const addedTime = int64Of(f, 7) ?? 0;
  return new SyncFavoritePlaylist(
    int64Of(f, 1) ?? 0,
    strOf(f, 2) ?? '',
    strOf(f, 3),
    int32Of(f, 4) ?? 0,
    strOf(f, 5) ?? '',
    songs,
    addedTime,
    addedTime,
    false,
    addedTime,
    null,
    null,
    null
  );
}

/** Legacy-schema fallback; returns null when bytes match neither schema. */
export function decodeLegacySyncData(bytes: Uint8Array, nowMs: number = Date.now()): SyncData | null {
  const f = RawFields.parse(ProtoReader.over(bytes), LEGACY_DATA_VARINT, LEGACY_DATA_LEN);
  if (f === null) {
    return null;
  }
  const playlists: SyncPlaylist[] = [];
  for (const nested of f.readers(5)) {
    const playlist = decodeLegacySyncPlaylist(nested);
    if (playlist === null) {
      return null;
    }
    playlists.push(playlist);
  }
  const favorites: SyncFavoritePlaylist[] = [];
  for (const nested of f.readers(6)) {
    const favorite = decodeLegacyFavoritePlaylist(nested);
    if (favorite === null) {
      return null;
    }
    favorites.push(favorite);
  }
  const recentPlays: SyncRecentPlay[] = [];
  for (const nested of f.readers(7)) {
    const entry = decodeLegacyRecentPlay(nested);
    if (entry === null) {
      return null;
    }
    recentPlays.push(entry);
  }
  const syncLog: SyncLogEntry[] = [];
  for (const nested of f.readers(8)) {
    const entry = decodeLogEntry(nested);
    if (entry === null) {
      return null;
    }
    syncLog.push(entry);
  }
  return new SyncData(
    strOf(f, 1) ?? SYNC_DATA_VERSION,
    strOf(f, 2) ?? '',
    strOf(f, 3) ?? '',
    f.hasVarint(4) ? (int64Of(f, 4) as number) : nowMs,
    playlists,
    favorites,
    recentPlays,
    syncLog,
    [],
    [],
    0,
    [],
    []
  );
}

/**
 * protobuf bytes → SyncData with the Android fallback order: current schema
 * first, legacy schema second, null when both fail.
 */
export function decodeProtoSyncDataWithLegacyFallback(protoBytes: Uint8Array, nowMs: number = Date.now()): SyncData | null {
  return decodeSyncDataProto(protoBytes, nowMs) ??
    decodeLegacySyncData(protoBytes, nowMs);
}
