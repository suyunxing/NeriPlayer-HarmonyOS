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
import { SyncPlaylistSongDeletion, songIdKeyText, syncSongIdentity } from '../sync/SyncModels';
import { playlistIdToSync, syncSongFromSongItem } from '../sync/SyncSongConvert';

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
    const json = JSON.stringify(playlists.map((item: Playlist) => Playlist.fromJson(item.toJson())));
    await SchemaStore.save(LocalPlaylistRepository.KEY, json, (value: string) => value);
    if (changedIds.length > 0) {
      let ids = await LocalPlaylistRepository.getSyncPendingIds();
      for (const changedId of changedIds) {
        ids = SyncPendingState.markPending(ids, changedId);
      }
      await AppPreferences.putString(SyncPendingState.KEY, SyncPendingState.toJson(ids));
    }
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
    await LocalPlaylistRepository.saveAll(playlists, [playlistId]);
    const syncSong = syncSongFromSongItem(removedSong);
    if (syncSong !== null) {
      const deviceId = await SyncDeletionStore.getOrCreateDeviceId(
        (): string => util.generateRandomUUID(false));
      await SyncDeletionStore.recordPlaylistSongDeletion(new SyncPlaylistSongDeletion(
        playlistIdToSync(playlistId), syncSong.id, syncSong.album, syncSong.mediaUri,
        Date.now(), deviceId, syncSong.syncMembershipTokens, songIdKeyText(syncSong)
      ));
    }
    return true;
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
