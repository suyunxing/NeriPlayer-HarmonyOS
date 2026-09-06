/** Bridges the app repositories to the transport-independent sync domain. */

import { util } from '@kit.ArkTS';
import { AppPreferences } from '../data/AppPreferences';
import {
  LocalPlaylistRepository,
  LocalPlaylistTombstone
} from '../data/LocalPlaylistRepository';
import { HistoryRepository } from '../data/HistoryRepository';
import {
  PlaybackStatsRepository,
  DailyTrackStats,
  StatsRoot,
  TrackStats
} from '../data/PlaybackStatsRepository';
import { FavoritePlaylistRepository } from '../data/FavoritePlaylistRepository';
import { Playlist } from '../model/Playlist';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { stableKeyOf } from '../model/SongIdentity';
import { SyncLocalStore } from './SyncCoordinator';
import { SyncData, SyncPlaylist, sha256ByteArray } from './SyncModels';
import {
  SnapshotBucketInput,
  SnapshotDeletedPlaylistInput,
  SnapshotPlaylistInput,
  SnapshotRecentPlayInput,
  SnapshotTrackStatInput,
  SyncSnapshotInput,
  buildLocalSyncData
} from './SyncSnapshotBuilder';
import {
  isLocalSongItem,
  playlistIdToSync,
  songItemFromSyncSong,
  syncPlaylistIdToLocal
} from './SyncSongConvert';
import { SyncDeletionState, SyncDeletionStore } from './SyncDeletionStore';
import {
  deserializeSyncContent,
  serializeSyncDataJson,
  utf8Decode,
  utf8EncodeText
} from './SyncDataJsonCodec';

const DEVICE_NAME: string = 'HarmonyOS Device';
const FAVORITES_SYNC_ID: number = playlistIdToSync(LocalPlaylistRepository.FAVORITES_ID);
const APPLY_JOURNAL_KEY: string = 'sync_apply_journal';

export class SyncAppLocalStore implements SyncLocalStore {
  async loadSnapshot(): Promise<SyncData> {
    await this.replayApplyJournal();
    return this.buildSnapshot(Date.now());
  }

  async stateFingerprint(): Promise<string> {
    const snapshot = await this.buildSnapshot(0);
    const pending = await LocalPlaylistRepository.getSyncPendingIds();
    const snapshotBytes = serializeSyncDataJson(snapshot);
    const pendingBytes = utf8EncodeText(JSON.stringify(pending));
    const combined = new Uint8Array(snapshotBytes.length + pendingBytes.length);
    combined.set(snapshotBytes, 0);
    combined.set(pendingBytes, snapshotBytes.length);
    const digest = sha256ByteArray(combined);
    let result = '';
    for (const value of digest) {
      result += value.toString(16).padStart(2, '0');
    }
    return result;
  }

  async applySnapshot(data: SyncData): Promise<void> {
    await AppPreferences.putString(APPLY_JOURNAL_KEY,
      utf8Decode(serializeSyncDataJson(data)));
    await this.applySnapshotParts(data);
    await AppPreferences.putString(APPLY_JOURNAL_KEY, '');
  }

  private async applySnapshotParts(data: SyncData): Promise<void> {
    const current = await LocalPlaylistRepository.loadAll();
    const currentById = new Map<number, Playlist>();
    for (const playlist of current) {
      currentById.set(playlistIdToSync(playlist.id), playlist);
    }
    const applied: Playlist[] = [];
    const tombstones: LocalPlaylistTombstone[] = [];
    for (const syncPlaylist of data.playlists) {
      if (syncPlaylist.isDeleted) {
        tombstones.push(new LocalPlaylistTombstone(syncPlaylistIdToLocal(syncPlaylist.id),
          syncPlaylist.modifiedAt));
        continue;
      }
      applied.push(this.playlistFromSync(syncPlaylist, currentById.get(syncPlaylist.id)));
    }
    await LocalPlaylistRepository.replaceAllFromSync(applied);
    await LocalPlaylistRepository.replaceDeletedTombstones(tombstones);
    await FavoritePlaylistRepository.replaceFromSync(data.favoritePlaylists);

    const localOnlyHistory = (await HistoryRepository.getRecent())
      .filter((song: SongItem): boolean => isLocalSongItem(song));
    const history: SongItem[] = [];
    for (const recent of data.recentPlays) {
      const song = songItemFromSyncSong(recent.song);
      song.addedAt = recent.playedAt;
      history.push(song);
    }
    const historyKeys = new Set<string>();
    for (const song of history) {
      historyKeys.add(stableKeyOf(song));
    }
    for (const song of localOnlyHistory) {
      if (!historyKeys.has(stableKeyOf(song))) {
        history.push(song);
      }
    }
    await HistoryRepository.replaceFromSync(history);

    const deletionState = new SyncDeletionState(
      data.recentPlayDeletions, data.playlistSongDeletions, data.deviceId);
    await SyncDeletionStore.save(deletionState);
    await PlaybackStatsRepository.replaceFromSync(this.statsRootFromSync(data));
  }

  private async replayApplyJournal(): Promise<void> {
    const journal = await AppPreferences.getString(APPLY_JOURNAL_KEY, '');
    if (journal.length === 0) {
      return;
    }
    const decoded = deserializeSyncContent(utf8EncodeText(journal));
    if (decoded.data === null) {
      await AppPreferences.putString(APPLY_JOURNAL_KEY, '');
      return;
    }
    await this.applySnapshotParts(decoded.data);
    await AppPreferences.putString(APPLY_JOURNAL_KEY, '');
  }

  async consumePending(): Promise<void> {
    await LocalPlaylistRepository.clearAllSyncPending();
  }

  favoritesPlaylistId(): number {
    return FAVORITES_SYNC_ID;
  }

  private async buildSnapshot(nowMs: number): Promise<SyncData> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const tombstones = await LocalPlaylistRepository.getDeletedTombstones();
    const history = await HistoryRepository.getRecent();
    const deletionState = await SyncDeletionStore.load();
    const stats = await PlaybackStatsRepository.snapshot();
    const deviceId = await SyncDeletionStore.getOrCreateDeviceId(
      (): string => util.generateRandomUUID(false));
    const input = new SyncSnapshotInput(deviceId, DEVICE_NAME);
    for (const playlist of playlists) {
      input.playlists.push(new SnapshotPlaylistInput(playlist, playlist.updatedAt));
    }
    for (const tombstone of tombstones) {
      input.deletedPlaylists.push(new SnapshotDeletedPlaylistInput(
        playlistIdToSync(tombstone.id), tombstone.deletedAt));
    }
    input.favoritePlaylists = await FavoritePlaylistRepository.snapshot();
    for (const song of history) {
      input.recentPlays.push(new SnapshotRecentPlayInput(song, song.addedAt, 0));
    }
    input.recentPlayDeletions = deletionState.recentPlayDeletions;
    input.playlistSongDeletions = deletionState.playlistSongDeletions;
    input.playbackStatsClearedAt = stats.clearedAt;
    const songsByKey = songIndex(playlists, history);
    this.appendStatsInput(input, stats, songsByKey);
    return buildLocalSyncData(input, nowMs);
  }

  private appendStatsInput(input: SyncSnapshotInput, stats: StatsRoot,
    songsByKey: Map<string, SongItem>): void {
    for (const identityKey of Object.keys(stats.tracks)) {
      const track = stats.tracks[identityKey];
      input.playbackStats.push(trackInput(identityKey, track, songsByKey.get(identityKey)));
    }
    for (const day of Object.keys(stats.daily)) {
      const dayStartAt = parseDayStart(day);
      const entries = stats.daily[day];
      for (const identityKey of Object.keys(entries)) {
        const song = songsByKey.get(identityKey);
        const aggregate = stats.tracks[identityKey];
        const daily = entries[identityKey];
        const track = new TrackStats();
        track.listenMs = daily.listenMs;
        track.playCount = daily.playCount;
        track.firstPlayedAt = daily.firstPlayedAt > 0 ? daily.firstPlayedAt : dayStartAt;
        track.lastPlayedAt = daily.lastPlayedAt > 0 ? daily.lastPlayedAt :
          (aggregate === undefined ? dayStartAt : aggregate.lastPlayedAt);
        track.counterShards = daily.counterShards;
        input.playbackStatBuckets.push(new SnapshotBucketInput(dayStartAt,
          trackInput(identityKey, track, song)));
      }
    }
  }

  private playlistFromSync(syncPlaylist: SyncPlaylist, existing: Playlist | undefined): Playlist {
    // Keep the id string shape the local store already uses for this playlist
    // (both "local_<ts>" and plain numeric Android-imported ids round-trip to
    // the same sync id); rewriting the shape would orphan existing references.
    const id = syncPlaylist.id === FAVORITES_SYNC_ID
      ? LocalPlaylistRepository.FAVORITES_ID
      : (existing !== undefined ? existing.id : syncPlaylistIdToLocal(syncPlaylist.id));
    const playlist = new Playlist(id, syncPlaylist.name, MusicPlatform.LOCAL);
    playlist.createdAt = syncPlaylist.createdAt;
    playlist.updatedAt = syncPlaylist.modifiedAt;
    if (existing !== undefined) {
      playlist.coverUrl = existing.coverUrl;
      playlist.description = existing.description;
      playlist.source = existing.source;
    }
    for (const syncSong of syncPlaylist.songs) {
      const song = songItemFromSyncSong(syncSong);
      playlist.songs.push(song);
      playlist.songKeys.push(stableKeyOf(song));
    }
    if (existing !== undefined) {
      for (const song of existing.songs) {
        if (isLocalSongItem(song) && playlist.songKeys.indexOf(stableKeyOf(song)) < 0) {
          playlist.songs.push(song);
          playlist.songKeys.push(stableKeyOf(song));
        }
      }
    }
    return playlist;
  }

  private statsRootFromSync(data: SyncData): StatsRoot {
    const root = new StatsRoot();
    root.clearedAt = data.playbackStatsClearedAt;
    for (const stat of data.playbackStats) {
      const track = new TrackStats();
      track.listenMs = stat.totalListenMs;
      track.playCount = stat.playCount;
      track.firstPlayedAt = stat.firstPlayedAt;
      track.lastPlayedAt = stat.lastPlayedAt;
      track.counterShards = stat.counterShards;
      root.tracks[stat.identityKey] = track;
    }
    for (const bucket of data.playbackStatBuckets) {
      const day = dayKey(bucket.dayStartAt);
      if (root.daily[day] === undefined) {
        root.daily[day] = {};
      }
      const daily = new DailyTrackStats();
      daily.listenMs = bucket.totalListenMs;
      daily.playCount = bucket.playCount;
      daily.firstPlayedAt = bucket.firstPlayedAt;
      daily.lastPlayedAt = bucket.lastPlayedAt;
      daily.counterShards = bucket.counterShards;
      root.daily[day][bucket.identityKey] = daily;
    }
    return root;
  }
}

function songIndex(playlists: Playlist[], history: SongItem[]): Map<string, SongItem> {
  const result = new Map<string, SongItem>();
  for (const playlist of playlists) {
    for (const song of playlist.songs) {
      result.set(stableKeyOf(song), song);
    }
  }
  for (const song of history) {
    result.set(stableKeyOf(song), song);
  }
  return result;
}

function trackInput(identityKey: string, track: TrackStats,
  song: SongItem | undefined): SnapshotTrackStatInput {
  const fallback = parseIdentityKey(identityKey);
  return new SnapshotTrackStatInput(
    identityKey,
    song === undefined ? '' : song.name,
    song === undefined ? '' : song.artist,
    song === undefined ? fallback.album : song.album,
    track.listenMs,
    track.playCount,
    track.lastPlayedAt,
    track.firstPlayedAt,
    song === undefined || song.coverUrl.length === 0 ? null : song.coverUrl,
    song === undefined ? 0 : song.durationMs,
    song === undefined ? fallback.mediaUri : emptyToNull(song.mediaUri),
    song === undefined ? fallback.id : song.id,
    song === undefined ? 0 : song.albumId,
    track.counterShards
  );
}

class ParsedIdentityKey {
  id: number = 0;
  album: string = '';
  mediaUri: string | null = null;
}

function parseIdentityKey(identityKey: string): ParsedIdentityKey {
  const parsed = new ParsedIdentityKey();
  const first = identityKey.indexOf('|');
  const second = first < 0 ? -1 : identityKey.indexOf('|', first + 1);
  if (first < 0 || second < 0) {
    return parsed;
  }
  parsed.id = Number(identityKey.substring(0, first));
  if (!Number.isFinite(parsed.id)) {
    parsed.id = 0;
  }
  parsed.album = identityKey.substring(first + 1, second);
  parsed.mediaUri = emptyToNull(identityKey.substring(second + 1));
  return parsed;
}

function emptyToNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

function parseDayStart(day: string): number {
  const parts = day.split('-');
  if (parts.length !== 3) {
    return 0;
  }
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])).getTime();
}

function dayKey(timeMs: number): string {
  const date = new Date(timeMs);
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}
