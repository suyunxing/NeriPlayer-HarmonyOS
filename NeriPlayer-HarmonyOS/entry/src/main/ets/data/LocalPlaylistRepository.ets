// SPDX-License-Identifier: GPL-3.0

import { AppPreferences } from './AppPreferences';
import { SchemaStore } from './schema/SchemaStore';
import { SyncPendingState } from './AndroidDataParser';
import { Playlist, mergePlaylistSongs } from '../model/Playlist';
import { MusicPlatform } from '../model/MusicPlatform';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { util } from '@kit.ArkTS';
import { SyncDeletionStore } from '../sync/SyncDeletionStore';
import { AutoSyncScheduler } from '../sync/AutoSyncScheduler';
import { SyncPlaylistSongDeletion, songIdKeyText, syncSongIdentity } from '../sync/SyncModels';
import { playlistIdToSync, syncSongFromSongItem } from '../sync/SyncSongConvert';
import {
  PlaylistSyncSource,
  SOURCE_SYNC_MODE_APPEND,
  mirrorPlaylistId
} from '../sourcesync/SourceSyncModels';
import { appendDiff, mirrorDiff } from '../sourcesync/SourceSyncDiff';

export class LocalPlaylistTombstone {
  id: string;
  deletedAt: number;

  constructor(id: string = '', deletedAt: number = 0) {
    this.id = id;
    this.deletedAt = deletedAt;
  }
}

/**
 * Local playlist + favorites repository, mirroring LocalPlaylistRepository and
 * FavoritePlaylistRepository. Membership is stable song keys.
 */
export class LocalPlaylistRepository {
  static readonly FAVORITES_ID: string = 'favorites';
  private static readonly KEY: string = 'playlists';
  private static readonly DELETED_KEY: string = 'playlists.deleted';

  static parseJson(json: string): Playlist[] | null {
    const rawList = JSON.parse(json) as Object[];
    if (!Array.isArray(rawList)) {
      return null;
    }
    const playlists: Playlist[] = [];
    for (const raw of rawList) {
      playlists.push(Playlist.fromJson(JSON.stringify(raw)));
    }
    return playlists;
  }

  static async loadAll(): Promise<Playlist[]> {
    return SchemaStore.load<Playlist[]>(LocalPlaylistRepository.KEY, [], LocalPlaylistRepository.parseJson);
  }

  /** Playlist ids changed locally but not yet consumed by a sync upload. */
  static async getSyncPendingIds(): Promise<string[]> {
    const json = await AppPreferences.getString(SyncPendingState.KEY, '[]');
    return SyncPendingState.fromJson(json);
  }

  static async clearSyncPending(playlistId: string): Promise<void> {
    const ids = await LocalPlaylistRepository.getSyncPendingIds();
    await AppPreferences.putString(SyncPendingState.KEY, SyncPendingState.toJson(SyncPendingState.clearPending(ids, playlistId)));
  }

  static async clearAllSyncPending(): Promise<void> {
    await AppPreferences.putString(SyncPendingState.KEY, '[]');
  }

  static async getDeletedTombstones(): Promise<LocalPlaylistTombstone[]> {
    const json = await AppPreferences.getString(LocalPlaylistRepository.DELETED_KEY, '[]');
    try {
      const raw = JSON.parse(json) as Object[];
      if (!Array.isArray(raw)) {
        return [];
      }
      return raw.map((item: Object): LocalPlaylistTombstone => {
        const value = item as Record<string, Object>;
        return new LocalPlaylistTombstone(String(value['id'] ?? ''), Number(value['deletedAt'] ?? 0));
      }).filter((item: LocalPlaylistTombstone): boolean => item.id.length > 0 && item.deletedAt > 0);
    } catch (error) {
      return [];
    }
  }

  static async replaceDeletedTombstones(tombstones: LocalPlaylistTombstone[]): Promise<void> {
    await AppPreferences.putString(LocalPlaylistRepository.DELETED_KEY, JSON.stringify(tombstones));
  }

  private static async saveAll(playlists: Playlist[], changedIds: string[] = []): Promise<void> {
    await LocalPlaylistRepository.saveAllSilent(playlists);
    if (changedIds.length > 0) {
      let ids = await LocalPlaylistRepository.getSyncPendingIds();
      for (const changedId of changedIds) {
        ids = SyncPendingState.markPending(ids, changedId);
      }
      await AppPreferences.putString(SyncPendingState.KEY, SyncPendingState.toJson(ids));
      AutoSyncScheduler.scheduleMutationSync();
    }
  }

  /**
   * Persists the whole table without touching cross-device pending marks —
   * for device-local bookkeeping only (mirror check timestamps), so a no-op
   * source check does not trigger an upload.
   */
  private static async saveAllSilent(playlists: Playlist[]): Promise<void> {
    const json = JSON.stringify(playlists.map((item: Playlist) => Playlist.fromJson(item.toJson())));
    await SchemaStore.save(LocalPlaylistRepository.KEY, json, (value: string) => value);
  }

  /** Applies a merged remote snapshot without creating another pending marker. */
  static async replaceAllFromSync(playlists: Playlist[]): Promise<void> {
    const json = JSON.stringify(playlists.map((item: Playlist) => Playlist.fromJson(item.toJson())));
    await SchemaStore.save(LocalPlaylistRepository.KEY, json, (value: string) => value);
  }

  static async ensureFavorites(): Promise<Playlist> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const existing = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID);
    if (existing !== undefined) {
      return existing;
    }
    const favorites = new Playlist(LocalPlaylistRepository.FAVORITES_ID, 'Favorites', MusicPlatform.LOCAL);
    playlists.unshift(favorites);
    await LocalPlaylistRepository.saveAll(playlists, [LocalPlaylistRepository.FAVORITES_ID]);
    return favorites;
  }

  static async createPlaylist(name: string): Promise<Playlist> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = new Playlist(`local_${Date.now()}`, name, MusicPlatform.LOCAL);
    playlists.unshift(playlist);
    await LocalPlaylistRepository.saveAll(playlists, [playlist.id]);
    return playlist;
  }

  /**
   * Creates a playlist pre-filled with songs in one save (remote playlist
   * import path): each song is appended once, keyed by stable song key.
   */
  static async createPlaylistWithSongs(
    name: string,
    songs: SongItem[],
    source: MusicPlatform = MusicPlatform.LOCAL
  ): Promise<Playlist> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = new Playlist(`local_${Date.now()}`, name, source);
    const stamped = await LocalPlaylistRepository.stampSongsForInsert(songs, Date.now());
    const merge = mergePlaylistSongs(playlist.songKeys, playlist.songs, stamped);
    playlist.songKeys = merge.keys;
    playlist.songs = merge.songs;
    playlists.unshift(playlist);
    await LocalPlaylistRepository.saveAll(playlists, [playlist.id]);
    return playlist;
  }

  /**
   * Source-sync: finds the deterministic mirror playlist for a remote source
   * or creates it (with optional seed songs) in one save. Re-adding the same
   * source converges on the existing playlist and only refreshes the binding
   * metadata — membership stays under applyMirrorSync's control.
   */
  static async createOrGetMirrorPlaylist(source: PlaylistSyncSource, songs: SongItem[] = []): Promise<Playlist> {
    const id = mirrorPlaylistId(source.platform, source.remoteId);
    const playlists = await LocalPlaylistRepository.loadAll();
    const existing = playlists.find((item: Playlist): boolean => item.id === id);
    if (existing !== undefined) {
      const bound = existing.syncSource;
      if (bound === null) {
        existing.syncSource = source;
      } else {
        bound.remoteName = source.remoteName;
        bound.mode = source.mode;
        bound.enabled = source.enabled;
      }
      await LocalPlaylistRepository.saveAll(playlists, [id]);
      return existing;
    }
    const playlist = new Playlist(id, source.remoteName, MusicPlatform.LOCAL);
    playlist.syncSource = source;
    if (songs.length > 0) {
      const seedStamped = await LocalPlaylistRepository.stampSongsForInsert(songs, Date.now());
      const seedMerge = mergePlaylistSongs(playlist.songKeys, playlist.songs, seedStamped);
      playlist.songKeys = seedMerge.keys;
      playlist.songs = seedMerge.songs;
    }
    playlists.unshift(playlist);
    await LocalPlaylistRepository.saveAll(playlists, [playlist.id]);
    return playlist;
  }

  /** Attaches a sync source to an existing local playlist (绑定已有歌单). */
  static async bindMirrorSource(playlistId: string, source: PlaylistSyncSource): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist): boolean => item.id === playlistId);
    if (playlist === undefined) {
      return false;
    }
    playlist.syncSource = source;
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
    return true;
  }

  /** Detaches the sync source; the playlist itself and its songs stay untouched. */
  static async unbindMirrorSource(playlistId: string): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist): boolean => item.id === playlistId);
    if (playlist === undefined || playlist.syncSource === null) {
      return false;
    }
    playlist.syncSource = null;
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
    return true;
  }

  /** Clears the remembered user deletions of a mirror playlist (device-local status). */
  static async resetMirrorSkips(playlistId: string): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist): boolean => item.id === playlistId);
    if (playlist === undefined || playlist.syncSource === null) {
      return false;
    }
    playlist.syncSource.skipKeys = [];
    await LocalPlaylistRepository.saveAllSilent(playlists);
    return true;
  }

  /** Enables/disables a mirror source for automatic sync (device-local status). */
  static async setMirrorEnabled(playlistId: string, enabled: boolean): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist): boolean => item.id === playlistId);
    if (playlist === undefined || playlist.syncSource === null) {
      return false;
    }
    playlist.syncSource.enabled = enabled;
    await LocalPlaylistRepository.saveAllSilent(playlists);
    return true;
  }

  /** Batch import into an existing playlist; returns how many songs were added. */
  static async importSongs(playlistId: string, songs: SongItem[]): Promise<number> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist) => item.id === playlistId);
    if (playlist === undefined) {
      return 0;
    }
    const stamped = await LocalPlaylistRepository.stampSongsForInsert(songs,
      Math.max(Date.now(), LocalPlaylistRepository.latestAddedAt(playlist) + 1));
    const merge = mergePlaylistSongs(playlist.songKeys, playlist.songs, stamped);
    playlist.songKeys = merge.keys;
    playlist.songs = merge.songs;
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
    return merge.addedCount;
  }

  /**
   * Source-sync: applies one fetched remote snapshot to a mirror playlist in
   * a single save. Mirror mode aligns membership and order to the remote list
   * (skipKeys — user deletions — are never resurrected); append mode only adds
   * missing songs at the tail. Returns true when local content changed.
   */
  static async applyMirrorSync(playlistId: string, remoteSongs: SongItem[], fingerprint: string): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist): boolean => item.id === playlistId);
    if (playlist === undefined || playlist.syncSource === null) {
      return false;
    }
    const syncSource = playlist.syncSource;
    const now = Date.now();
    let applied = false;
    const addedSongs: SongItem[] = [];
    const removedSongs: SongItem[] = [];

    if (syncSource.mode === SOURCE_SYNC_MODE_APPEND) {
      const diff = appendDiff(playlist.songKeys, remoteSongs, syncSource.skipKeys);
      if (diff.toAdd.length > 0) {
        const stamped = await LocalPlaylistRepository.stampSongsForInsert(diff.toAdd,
          Math.max(now, LocalPlaylistRepository.latestAddedAt(playlist) + 1));
        const merge = mergePlaylistSongs(playlist.songKeys, playlist.songs, stamped);
        playlist.songKeys = merge.keys;
        playlist.songs = merge.songs;
        for (const song of stamped) {
          addedSongs.push(song);
        }
        applied = true;
      }
    } else {
      const diff = mirrorDiff(playlist.songKeys, remoteSongs, syncSource.skipKeys);
      if (diff.changed) {
        const byKey = new Map<string, SongItem>();
        for (let i = 0; i < playlist.songs.length; i++) {
          byKey.set(playlist.songKeys[i], playlist.songs[i]);
        }
        const addedByKey = new Map<string, SongItem>();
        for (const song of diff.toAdd) {
          addedByKey.set(stableKeyOf(song), song);
        }
        for (const key of diff.toRemoveKeys) {
          const removed = byKey.get(key);
          if (removed !== undefined) {
            removedSongs.push(removed);
          }
        }
        const nextSongs: SongItem[] = [];
        for (const key of diff.finalOrder) {
          const existingSong = byKey.get(key);
          if (existingSong !== undefined) {
            nextSongs.push(existingSong);
          } else {
            const addedSong = addedByKey.get(key);
            if (addedSong !== undefined) {
              nextSongs.push(addedSong);
            }
          }
        }
        // Re-stamp addedAt along the remote order: the sync layer displays
        // songs by addedAt-descending (normalizedForDisplayOrder), so this is
        // what keeps the remote order intact on every device. Stored metadata
        // of kept songs is preserved; runs only on actual changes.
        const newestAt = Math.max(now, LocalPlaylistRepository.latestAddedAt(playlist) + 1);
        const stamped: SongItem[] = [];
        for (let index = 0; index < nextSongs.length; index++) {
          const copy = SongItem.fromJson(nextSongs[index].toJson());
          copy.addedAt = Math.max(newestAt - index, 1);
          stamped.push(copy);
        }
        playlist.songKeys = diff.finalOrder.slice();
        playlist.songs = stamped;
        for (const song of stamped) {
          if (addedByKey.has(stableKeyOf(song))) {
            addedSongs.push(song);
          }
        }
        applied = true;
      }
    }

    syncSource.lastCheckedAt = now;
    if (applied) {
      playlist.updatedAt = now;
      syncSource.lastSyncAt = now;
      syncSource.lastFingerprint = fingerprint;
      await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
      for (const removed of removedSongs) {
        await LocalPlaylistRepository.recordSongDeletionTombstone(playlistId, removed);
      }
      for (const added of addedSongs) {
        const syncSong = syncSongFromSongItem(added);
        if (syncSong !== null) {
          await SyncDeletionStore.clearPlaylistSongDeletion(
            playlistIdToSync(playlistId), syncSongIdentity(syncSong).stableKey());
        }
      }
    } else {
      // No-op check: persist the check bookkeeping silently so cross-device
      // pending marks (and the upload they trigger) stay untouched.
      syncSource.lastFingerprint = fingerprint;
      await LocalPlaylistRepository.saveAllSilent(playlists);
    }
    return applied;
  }

  static async addSong(playlistId: string, song: SongItem): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist) => item.id === playlistId);
    if (playlist === undefined) {
      return false;
    }
    const songKey = stableKeyOf(song);
    if (playlist.songKeys.indexOf(songKey) >= 0) {
      return false;
    }
    const stamped = (await LocalPlaylistRepository.stampSongsForInsert([song],
      Math.max(Date.now(), LocalPlaylistRepository.latestAddedAt(playlist) + 1)))[0];
    playlist.songKeys.unshift(stableKeyOf(stamped));
    playlist.songs.unshift(stamped);
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
    const syncSong = syncSongFromSongItem(stamped);
    if (syncSong !== null) {
      await SyncDeletionStore.clearPlaylistSongDeletion(
        playlistIdToSync(playlistId), syncSongIdentity(syncSong).stableKey());
    }
    return true;
  }

  static async removeSong(playlistId: string, songKey: string): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist) => item.id === playlistId);
    if (playlist === undefined) {
      return false;
    }
    const index = playlist.songKeys.indexOf(songKey);
    if (index < 0) {
      return false;
    }
    const removedSong = playlist.songs[index];
    playlist.songKeys.splice(index, 1);
    playlist.songs.splice(index, 1);
    playlist.updatedAt = Date.now();
    if (playlist.syncSource !== null && playlist.syncSource.skipKeys.indexOf(songKey) < 0) {
      // Remember user deletions so auto sync never resurrects the song (both
      // mirror and append modes) until the sync state is reset.
      playlist.syncSource.skipKeys.push(songKey);
    }
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
    await LocalPlaylistRepository.recordSongDeletionTombstone(playlistId, removedSong);
    return true;
  }

  /** Cross-device deletion tombstone, shared by the manual and mirror removal paths. */
  private static async recordSongDeletionTombstone(playlistId: string, song: SongItem): Promise<void> {
    const syncSong = syncSongFromSongItem(song);
    if (syncSong === null) {
      return;
    }
    const deviceId = await SyncDeletionStore.getOrCreateDeviceId(
      (): string => util.generateRandomUUID(false));
    await SyncDeletionStore.recordPlaylistSongDeletion(new SyncPlaylistSongDeletion(
      playlistIdToSync(playlistId), syncSong.id, syncSong.album, syncSong.mediaUri,
      Date.now(), deviceId, syncSong.syncMembershipTokens, songIdKeyText(syncSong)
    ));
  }

  static async addFavorite(song: SongItem): Promise<boolean> {
    await LocalPlaylistRepository.ensureFavorites();
    return LocalPlaylistRepository.addSong(LocalPlaylistRepository.FAVORITES_ID, song);
  }

  static async removeFavorite(song: SongItem): Promise<boolean> {
    return LocalPlaylistRepository.removeSong(LocalPlaylistRepository.FAVORITES_ID, stableKeyOf(song));
  }

  static async isFavorite(song: SongItem): Promise<boolean> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const favorites = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID);
    if (favorites === undefined) {
      return false;
    }
    return favorites.songKeys.indexOf(stableKeyOf(song)) >= 0;
  }

  static async renamePlaylist(playlistId: string, name: string): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = playlists.find((item: Playlist) => item.id === playlistId);
    if (playlist === undefined) {
      return;
    }
    playlist.name = name;
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
  }

  static async removePlaylist(playlistId: string): Promise<void> {
    // Compare through the numeric sync id: local ids may appear as
    // "local_<ts>" or plain numeric text (Android import / legacy apply), and
    // an exact string match would silently keep the other shape alive.
    const targetKey = playlistIdToSync(playlistId);
    const playlists = await LocalPlaylistRepository.loadAll();
    const filtered = playlists.filter((item: Playlist): boolean =>
      playlistIdToSync(item.id) !== targetKey);
    await LocalPlaylistRepository.saveAll(filtered, [playlistId]);
    const tombstones = await LocalPlaylistRepository.getDeletedTombstones();
    const next = tombstones.filter((item: LocalPlaylistTombstone): boolean =>
      playlistIdToSync(item.id) !== targetKey);
    next.push(new LocalPlaylistTombstone(playlistId, Date.now()));
    await LocalPlaylistRepository.replaceDeletedTombstones(next);
  }

  /**
   * Applies user-edited metadata (customName/customArtist/customCoverUrl and
   * the matched-lyric fields matchedSongId/matchedLyric/matchedTranslatedLyric)
   * to every stored copy of the song, matched by stable key across all
   * playlists (favorites included). Membership bookkeeping (addedAt, causal
   * tokens) stays on the stored copy. Returns how many playlist entries were
   * touched.
   */
  static async updateSongMetadata(song: SongItem): Promise<number> {
    const key = stableKeyOf(song);
    const playlists = await LocalPlaylistRepository.loadAll();
    const changedIds: string[] = [];
    let replaced = 0;
    for (const playlist of playlists) {
      let changed = false;
      for (let i = 0; i < playlist.songs.length; i++) {
        if (playlist.songKeys[i] !== key) {
          continue;
        }
        const stored = playlist.songs[i];
        if (stored.customName !== song.customName || stored.customArtist !== song.customArtist
          || stored.customCoverUrl !== song.customCoverUrl || stored.matchedSongId !== song.matchedSongId
          || stored.matchedLyric !== song.matchedLyric
          || stored.matchedTranslatedLyric !== song.matchedTranslatedLyric) {
          stored.customName = song.customName;
          stored.customArtist = song.customArtist;
          stored.customCoverUrl = song.customCoverUrl;
          stored.matchedSongId = song.matchedSongId;
          stored.matchedLyric = song.matchedLyric;
          stored.matchedTranslatedLyric = song.matchedTranslatedLyric;
          changed = true;
        }
        replaced++;
      }
      if (changed) {
        playlist.updatedAt = Date.now();
        changedIds.push(playlist.id);
      }
    }
    if (changedIds.length > 0) {
      await LocalPlaylistRepository.saveAll(playlists, changedIds);
    }
    return replaced;
  }

  private static latestAddedAt(playlist: Playlist): number {
    let latest = 0;
    for (const song of playlist.songs) {
      latest = Math.max(latest, song.addedAt);
    }
    return latest;
  }

  private static async stampSongsForInsert(songs: SongItem[], newestAt: number): Promise<SongItem[]> {
    let syncableCount = 0;
    for (const song of songs) {
      if (syncSongFromSongItem(song) !== null) {
        syncableCount++;
      }
    }
    const tokens = await SyncDeletionStore.nextCausalTokens(syncableCount,
      (): string => util.generateRandomUUID(false));
    let tokenIndex = 0;
    const stamped: SongItem[] = [];
    for (let index = 0; index < songs.length; index++) {
      const copy = SongItem.fromJson(songs[index].toJson());
      copy.addedAt = Math.max(newestAt - index, 1);
      if (syncSongFromSongItem(copy) !== null) {
        copy.syncMembershipTokens = [tokens[tokenIndex++]];
      }
      stamped.push(copy);
    }
    return stamped;
  }
}
