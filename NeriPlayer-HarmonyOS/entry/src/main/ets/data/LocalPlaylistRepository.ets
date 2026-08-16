import { AppPreferences } from './AppPreferences';
import { SchemaStore } from './schema/SchemaStore';
import { SyncPendingState } from './AndroidDataParser';
import { Playlist } from '../model/Playlist';
import { MusicPlatform } from '../model/MusicPlatform';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';

/**
 * Local playlist + favorites repository, mirroring LocalPlaylistRepository and
 * FavoritePlaylistRepository. Membership is stable song keys.
 */
export class LocalPlaylistRepository {
  static readonly FAVORITES_ID: string = 'favorites';
  private static readonly KEY: string = 'playlists';

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

  private static async saveAll(playlists: Playlist[], changedId: string = ''): Promise<void> {
    const json = JSON.stringify(playlists.map((item: Playlist) => Playlist.fromJson(item.toJson())));
    await SchemaStore.save(LocalPlaylistRepository.KEY, json, (value: string) => value);
    if (changedId.length > 0) {
      const ids = await LocalPlaylistRepository.getSyncPendingIds();
      await AppPreferences.putString(SyncPendingState.KEY, SyncPendingState.toJson(SyncPendingState.markPending(ids, changedId)));
    }
  }

  static async ensureFavorites(): Promise<Playlist> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const existing = playlists.find((item: Playlist) => item.id === LocalPlaylistRepository.FAVORITES_ID);
    if (existing !== undefined) {
      return existing;
    }
    const favorites = new Playlist(LocalPlaylistRepository.FAVORITES_ID, 'Favorites', MusicPlatform.LOCAL);
    playlists.unshift(favorites);
    await LocalPlaylistRepository.saveAll(playlists, LocalPlaylistRepository.FAVORITES_ID);
    return favorites;
  }

  static async createPlaylist(name: string): Promise<Playlist> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const playlist = new Playlist(`local_${Date.now()}`, name, MusicPlatform.LOCAL);
    playlists.unshift(playlist);
    await LocalPlaylistRepository.saveAll(playlists, playlist.id);
    return playlist;
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
    playlist.songKeys.unshift(songKey);
    playlist.songs.unshift(song);
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, playlistId);
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
    playlist.songKeys.splice(index, 1);
    playlist.songs.splice(index, 1);
    playlist.updatedAt = Date.now();
    await LocalPlaylistRepository.saveAll(playlists, playlistId);
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
    await LocalPlaylistRepository.saveAll(playlists, playlistId);
  }

  static async removePlaylist(playlistId: string): Promise<void> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const filtered = playlists.filter((item: Playlist) => item.id !== playlistId);
    await LocalPlaylistRepository.saveAll(filtered, playlistId);
  }
}
