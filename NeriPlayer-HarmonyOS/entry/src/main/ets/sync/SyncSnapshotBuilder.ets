/**
 * Port of GitHubSyncManager.buildLocalSyncData: assembles the local sync
 * snapshot from app-side sources. Kept as a pure function over injected
 * inputs so repositories can keep evolving independently (M5.5 wires the
 * real sources; the truncation/normalization semantics are fixed here).
 *
 * Snapshot rules (Android parity):
 *   - playlists keep repository order; deleted-playlist tombstones are
 *     appended only for ids absent from the live list;
 *   - recentPlays drop local songs first, then take(500);
 *   - deletion mediaUris are sanitized (local references become null) and
 *     membership tokens normalized;
 *   - counter bases are derived as max(0, total − Σshards) exactly like
 *     SyncPlaybackStatMapper.fromTrackStat;
 *   - syncLog is always empty on upload.
 */
import { SongItem } from '../model/SongItem';
import { Playlist } from '../model/Playlist';
import {
  SyncData,
  SyncPlaylist,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncFavoritePlaylist,
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaybackCounterShard,
  DISPLAY_ORDER_SONG_ORDER_VERSION,
  normalizedSyncCausalTokens,
  normalizeCounterShards
} from './SyncModels';
import {
  isLocalSongItem,
  sanitizeMediaUriForSync,
  syncSongFromSongItem,
  syncPlaylistFromPlaylist
} from './SyncSongConvert';

export const MAX_RECENT_PLAYS_UPLOAD: number = 500;

export class SnapshotPlaylistInput {
  playlist: Playlist;
  modifiedAt: number;

  constructor(playlist: Playlist, modifiedAt: number) {
    this.playlist = playlist;
    this.modifiedAt = modifiedAt;
  }
}

export class SnapshotDeletedPlaylistInput {
  id: number;
  deletedAt: number;

  constructor(id: number, deletedAt: number) {
    this.id = id;
    this.deletedAt = deletedAt;
  }
}

export class SnapshotRecentPlayInput {
  song: SongItem;
  playedAt: number;
  resumePositionMs: number;

  constructor(song: SongItem, playedAt: number, resumePositionMs: number) {
    this.song = song;
    this.playedAt = playedAt;
    this.resumePositionMs = resumePositionMs;
  }
}

export class SnapshotTrackStatInput {
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
  counterShards: SyncPlaybackCounterShard[];

  constructor(
    identityKey: string,
    name: string,
    artist: string,
    album: string,
    totalListenMs: number,
    playCount: number,
    lastPlayedAt: number,
    firstPlayedAt: number,
    coverUrl: string | null,
    durationMs: number,
    mediaUri: string | null,
    id: number,
    albumId: number,
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
    this.counterShards = counterShards;
  }
}

export class SnapshotBucketInput {
  dayStartAt: number;
  stat: SnapshotTrackStatInput;

  constructor(dayStartAt: number, stat: SnapshotTrackStatInput) {
    this.dayStartAt = dayStartAt;
    this.stat = stat;
  }
}

export class SyncSnapshotInput {
  playlists: SnapshotPlaylistInput[];
  deletedPlaylists: SnapshotDeletedPlaylistInput[];
  favoritePlaylists: SyncFavoritePlaylist[];
  recentPlays: SnapshotRecentPlayInput[];
  recentPlayDeletions: SyncRecentPlayDeletion[];
  playlistSongDeletions: SyncPlaylistSongDeletion[];
  playbackStats: SnapshotTrackStatInput[];
  playbackStatBuckets: SnapshotBucketInput[];
  playbackStatsClearedAt: number;
  deviceId: string;
  deviceName: string;

  constructor(deviceId: string, deviceName: string) {
    this.playlists = [];
    this.deletedPlaylists = [];
    this.favoritePlaylists = [];
    this.recentPlays = [];
    this.recentPlayDeletions = [];
    this.playlistSongDeletions = [];
    this.playbackStats = [];
    this.playbackStatBuckets = [];
    this.playbackStatsClearedAt = 0;
    this.deviceId = deviceId;
    this.deviceName = deviceName;
  }
}

/**
 * Local-timezone day start (00:00:00.000 of the calendar day containing
 * `millis`), matching Android playbackStatsDayStartAt's Calendar semantics —
 * deliberately NOT a UTC floor.
 */
export function localDayStartAt(millis: number): number {
  const date = new Date(millis);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

/** SyncPlaybackStatMapper.fromTrackStat: base = max(0, total − Σshards). */
function counterBaseListenMsOf(totalListenMs: number, shards: SyncPlaybackCounterShard[]): number {
  let shardTotal = 0;
  for (const shard of shards) {
    shardTotal += Math.max(shard.totalListenMs, 0);
  }
  return Math.max(Math.max(totalListenMs, 0) - shardTotal, 0);
}

function counterBasePlayCountOf(playCount: number, shards: SyncPlaybackCounterShard[]): number {
  let shardTotal = 0;
  for (const shard of shards) {
    shardTotal += Math.max(shard.playCount, 0);
  }
  return Math.max(Math.max(playCount, 0) - shardTotal, 0);
}

export function syncTrackStatFromInput(entry: SnapshotTrackStatInput): SyncTrackStat {
  // Normalize first, then derive the bases — matching the Android call chain
  // where PlaybackStatsCounterStore.snapshot() hands pre-normalized shards to
  // SyncPlaybackStatMapper.fromTrackStat.
  const shards = normalizeCounterShards(entry.counterShards);
  return new SyncTrackStat(
    entry.identityKey,
    entry.name,
    entry.artist,
    entry.album,
    entry.totalListenMs,
    entry.playCount,
    entry.lastPlayedAt,
    entry.firstPlayedAt,
    entry.coverUrl,
    entry.durationMs,
    sanitizeMediaUriForSync(entry.mediaUri),
    entry.id,
    entry.albumId,
    counterBaseListenMsOf(entry.totalListenMs, shards),
    counterBasePlayCountOf(entry.playCount, shards),
    shards
  );
}

export function syncBucketFromInput(bucket: SnapshotBucketInput): SyncPlaybackStatBucket {
  const stat = syncTrackStatFromInput(bucket.stat);
  return new SyncPlaybackStatBucket(
    bucket.dayStartAt,
    stat.identityKey,
    stat.name,
    stat.artist,
    stat.album,
    stat.totalListenMs,
    stat.playCount,
    stat.lastPlayedAt,
    stat.firstPlayedAt,
    stat.coverUrl,
    stat.durationMs,
    stat.mediaUri,
    stat.id,
    stat.albumId,
    stat.counterBaseListenMs,
    stat.counterBasePlayCount,
    stat.counterShards
  );
}

function sanitizeRecentPlayDeletion(deletion: SyncRecentPlayDeletion): SyncRecentPlayDeletion {
  return new SyncRecentPlayDeletion(
    deletion.songId,
    deletion.album,
    sanitizeMediaUriForSync(deletion.mediaUri),
    deletion.deletedAt,
    deletion.deviceId,
    deletion.syncSongIdText
  );
}

function sanitizePlaylistSongDeletion(
  deletion: SyncPlaylistSongDeletion
): SyncPlaylistSongDeletion {
  return new SyncPlaylistSongDeletion(
    deletion.playlistId,
    deletion.songId,
    deletion.album,
    sanitizeMediaUriForSync(deletion.mediaUri),
    deletion.deletedAt,
    deletion.deviceId,
    normalizedSyncCausalTokens(deletion.removedMembershipTokens),
    deletion.syncSongIdText
  );
}

/** Builds the upload snapshot. Pure: same inputs → same SyncData. */
export function buildLocalSyncData(input: SyncSnapshotInput, nowMs: number): SyncData {
  const playlists: SyncPlaylist[] = [];
  const liveIds = new Set<number>();
  for (const entry of input.playlists) {
    const syncPlaylist = syncPlaylistFromPlaylist(entry.playlist, entry.modifiedAt);
    liveIds.add(syncPlaylist.id);
    playlists.push(syncPlaylist);
  }
  for (const deleted of input.deletedPlaylists) {
    if (!liveIds.has(deleted.id)) {
      playlists.push(new SyncPlaylist(
        deleted.id, '', [], 0, deleted.deletedAt, true, DISPLAY_ORDER_SONG_ORDER_VERSION
      ));
    }
  }

  const recentPlays: SyncRecentPlay[] = [];
  for (const entry of input.recentPlays) {
    if (recentPlays.length >= MAX_RECENT_PLAYS_UPLOAD) {
      break;
    }
    if (isLocalSongItem(entry.song)) {
      continue;
    }
    const song = syncSongFromSongItem(entry.song);
    if (song === null) {
      continue;
    }
    recentPlays.push(new SyncRecentPlay(
      entry.song.id,
      song,
      entry.playedAt,
      input.deviceId,
      entry.resumePositionMs
    ));
  }

  const playbackStats: SyncTrackStat[] = [];
  for (const entry of input.playbackStats) {
    playbackStats.push(syncTrackStatFromInput(entry));
  }
  const playbackStatBuckets: SyncPlaybackStatBucket[] = [];
  for (const entry of input.playbackStatBuckets) {
    playbackStatBuckets.push(syncBucketFromInput(entry));
  }

  const recentPlayDeletions: SyncRecentPlayDeletion[] = [];
  for (const deletion of input.recentPlayDeletions) {
    recentPlayDeletions.push(sanitizeRecentPlayDeletion(deletion));
  }
  const playlistSongDeletions: SyncPlaylistSongDeletion[] = [];
  for (const deletion of input.playlistSongDeletions) {
    playlistSongDeletions.push(sanitizePlaylistSongDeletion(deletion));
  }

  return new SyncData(
    '2.0',
    input.deviceId,
    input.deviceName,
    nowMs,
    playlists,
    input.favoritePlaylists,
    recentPlays,
    [],
    recentPlayDeletions,
    playbackStats,
    input.playbackStatsClearedAt,
    playbackStatBuckets,
    playlistSongDeletions
  );
}
