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

/** toJson 的声明形态（ArkTS 对象字面量必须对应显式类）。 */
class PlaylistDeleteSnapshotJson {
  playlistJson: string = '';
  index: number = 0;
  deletedAt: number = 0;
}

/** 跨页撤销载荷（AppStorage ui.playlistUndoPending 的 JSON 形态）。 */
export class PlaylistUndoOffer {
  snapshotJson: string = '';
  name: string = '';
  offeredAt: number = 0;

  static fromJson(json: string): PlaylistUndoOffer | null {
    try {
      const raw = JSON.parse(json) as Record<string, Object>;
      const offer = new PlaylistUndoOffer();
      offer.snapshotJson = String(raw['snapshot'] ?? '');
      offer.name = String(raw['name'] ?? '');
      offer.offeredAt = Number(raw['offeredAt'] ?? 0);
      return offer.snapshotJson.length > 0 && offer.offeredAt > 0 ? offer : null;
    } catch (error) {
      return null;
    }
  }

  toJson(): string {
    const holder = new PlaylistUndoOfferJson();
    holder.snapshot = this.snapshotJson;
    holder.name = this.name;
    holder.offeredAt = this.offeredAt;
    return JSON.stringify(holder);
  }
}

class PlaylistUndoOfferJson {
  snapshot: string = '';
  name: string = '';
  offeredAt: number = 0;
}

/** F-10 删除撤销：删除前捕获的歌单深拷贝 + 原下标。 */
export class PlaylistDeleteSnapshot {
  playlistJson: string = '';
  index: number = 0;
  deletedAt: number = 0;

  static fromJson(json: string): PlaylistDeleteSnapshot | null {
    try {
      const raw = JSON.parse(json) as Record<string, Object>;
      const snapshot = new PlaylistDeleteSnapshot();
      snapshot.playlistJson = String(raw['playlistJson'] ?? '');
      snapshot.index = Number(raw['index'] ?? 0);
      snapshot.deletedAt = Number(raw['deletedAt'] ?? 0);
      return snapshot.playlistJson.length > 0 ? snapshot : null;
    } catch (error) {
      return null;
    }
  }

  toJson(): string {
    const holder = new PlaylistDeleteSnapshotJson();
    holder.playlistJson = this.playlistJson;
    holder.index = this.index;
    holder.deletedAt = this.deletedAt;
    return JSON.stringify(holder);
  }
}

/** F-10 删除撤销：从歌单移除的单曲快照（歌单 id + 原下标 + 歌曲深拷贝）。 */
export class PlaylistSongDeleteSnapshot {
  playlistId: string = '';
  songKey: string = '';
  songJson: string = '';
  index: number = 0;
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
    LocalPlaylistRepository.invalidateFavoriteKeys();
    const json = JSON.stringify(playlists.map((item: Playlist) => Playlist.fromJson(item.toJson())));
    await SchemaStore.save(LocalPlaylistRepository.KEY, json, (value: string) => value);
  }

  /** Applies a merged remote snapshot without creating another pending marker. */
  static async replaceAllFromSync(playlists: Playlist[]): Promise<void> {
    const json = JSON.stringify(playlists.map((item: Playlist) => Playlist.fromJson(item.toJson())));
    await SchemaStore.save(LocalPlaylistRepository.KEY, json, (value: string) => value);
    LocalPlaylistRepository.invalidateFavoriteKeys();
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

  /**
   * 收藏键集合的进程内缓存。行重建（LazyForEach 回滚重进视口）会再次调
   * isFavorite，旧实现每次都 loadAll() 全量读取+解析整个歌单库（真机实测
   * 滚动持续掉帧的主因之一）；缓存后仅首次与任意写盘后重建一次。
   */
  private static favoriteKeysCache: Set<string> | null = null;

  private static invalidateFavoriteKeys(): void {
    LocalPlaylistRepository.favoriteKeysCache = null;
  }

  private static async getFavoriteKeySet(): Promise<Set<string>> {
    const cached = LocalPlaylistRepository.favoriteKeysCache;
    if (cached !== null) {
      return cached;
    }
    const playlists = await LocalPlaylistRepository.loadAll();
    const favorites = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID);
    const keySet = new Set<string>(favorites !== undefined ? favorites.songKeys : []);
    LocalPlaylistRepository.favoriteKeysCache = keySet;
    return keySet;
  }

  static async isFavorite(song: SongItem): Promise<boolean> {
    const keySet = await LocalPlaylistRepository.getFavoriteKeySet();
    return keySet.has(stableKeyOf(song));
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

  // ---- F-10 删除撤销（上游 90ee4f46 PlaylistDeleteFeedback 的仓库侧原语）----

  static async removeSongForUndo(playlistId: string, songKey: string): Promise<PlaylistSongDeleteSnapshot | null> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = LocalPlaylistRepository.findBySyncId(playlists, playlistId);
    if (playlist === undefined) {
      return null;
    }
    const index = playlist.songKeys.indexOf(songKey);
    if (index < 0) {
      return null;
    }
    const snapshot = new PlaylistSongDeleteSnapshot();
    snapshot.playlistId = playlist.id;
    snapshot.songKey = songKey;
    snapshot.index = index;
    snapshot.songJson = playlist.songs[index].toJson();
    const removed = await LocalPlaylistRepository.removeSong(playlist.id, songKey);
    return removed ? snapshot : null;
  }

  /**
   * 撤销单曲移除：原位插回，并回退镜像 skipKeys 与跨端歌曲删除墓碑
   * （清墓碑与 addSong 同路径），否则下一次同步仍会把移除传播出去。
   */
  static async restoreRemovedSong(snapshot: PlaylistSongDeleteSnapshot): Promise<boolean> {
    if (snapshot.playlistId.length === 0 || snapshot.songKey.length === 0 || snapshot.songJson.length === 0) {
      return false;
    }
    let song: SongItem;
    try {
      song = SongItem.fromJson(snapshot.songJson);
    } catch (error) {
      return false;
    }
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = LocalPlaylistRepository.findBySyncId(playlists, snapshot.playlistId);
    if (playlist === undefined || playlist.songKeys.indexOf(snapshot.songKey) >= 0) {
      return false;
    }
    const insertAt = Math.min(Math.max(snapshot.index, 0), playlist.songKeys.length);
    playlist.songKeys.splice(insertAt, 0, snapshot.songKey);
    playlist.songs.splice(insertAt, 0, song);
    playlist.updatedAt = Date.now();
    if (playlist.syncSource !== null) {
      const skipIndex = playlist.syncSource.skipKeys.indexOf(snapshot.songKey);
      if (skipIndex >= 0) {
        playlist.syncSource.skipKeys.splice(skipIndex, 1);
      }
    }
    await LocalPlaylistRepository.saveAll(playlists, [playlist.id]);
    const syncSong = syncSongFromSongItem(song);
    if (syncSong !== null) {
      await SyncDeletionStore.clearPlaylistSongDeletion(
        playlistIdToSync(playlist.id), syncSongIdentity(syncSong).stableKey());
    }
    return true;
  }

  /** 删除前的歌单深拷贝与原下标；收藏夹（本就不可删）或不存在返回 null。 */
  static async snapshotPlaylistForUndo(playlistId: string): Promise<PlaylistDeleteSnapshot | null> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const index = playlists.findIndex((item: Playlist): boolean =>
      playlistIdToSync(item.id) === playlistIdToSync(playlistId));
    if (index < 0 || playlists[index].id === LocalPlaylistRepository.FAVORITES_ID) {
      return null;
    }
    const snapshot = new PlaylistDeleteSnapshot();
    snapshot.playlistJson = playlists[index].toJson();
    snapshot.index = index;
    snapshot.deletedAt = Date.now();
    return snapshot;
  }

  /**
   * 撤销歌单删除：按快照原位恢复（镜像绑定随快照回来），并撤掉跨端删除
   * 墓碑——saveAll 已把该歌单标为待上传，墓碑不撤的话下一次上传仍会把它
   * 当作 isDeleted 传播。同 id 重新存在或收藏夹则拒绝（false）。
   */
  static async restorePlaylistFromUndo(snapshot: PlaylistDeleteSnapshot): Promise<boolean> {
    if (snapshot.playlistJson.length === 0) {
      return false;
    }
    let restored: Playlist;
    try {
      restored = Playlist.fromJson(snapshot.playlistJson);
    } catch (error) {
      return false;
    }
    if (restored.id === LocalPlaylistRepository.FAVORITES_ID) {
      return false;
    }
    const targetKey = playlistIdToSync(restored.id);
    const playlists = await LocalPlaylistRepository.loadAll();
    if (playlists.some((item: Playlist): boolean => playlistIdToSync(item.id) === targetKey)) {
      return false;
    }
    const insertAt = Math.min(Math.max(snapshot.index, 0), playlists.length);
    playlists.splice(insertAt, 0, restored);
    await LocalPlaylistRepository.saveAll(playlists, [restored.id]);
    const tombstones = await LocalPlaylistRepository.getDeletedTombstones();
    await LocalPlaylistRepository.replaceDeletedTombstones(
      tombstones.filter((item: LocalPlaylistTombstone): boolean => playlistIdToSync(item.id) !== targetKey));
    return true;
  }

  private static findBySyncId(playlists: Playlist[], playlistId: string): Playlist | undefined {
    const targetKey = playlistIdToSync(playlistId);
    return playlists.find((item: Playlist): boolean => playlistIdToSync(item.id) === targetKey);
  }

  /**
   * Applies user-edited metadata (customName/customArtist/customCoverUrl and
   * the matched-lyric fields matchedSongId/matchedLyric/matchedTranslatedLyric/
   * matchedPhoneticLyric)
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
          || stored.matchedTranslatedLyric !== song.matchedTranslatedLyric
          || stored.matchedPhoneticLyric !== song.matchedPhoneticLyric) {
          stored.customName = song.customName;
          stored.customArtist = song.customArtist;
          stored.customCoverUrl = song.customCoverUrl;
          stored.matchedSongId = song.matchedSongId;
          stored.matchedLyric = song.matchedLyric;
          stored.matchedTranslatedLyric = song.matchedTranslatedLyric;
          stored.matchedPhoneticLyric = song.matchedPhoneticLyric;
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
