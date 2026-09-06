/** Persists Android-compatible favorite-playlist snapshots for synchronization. */

import { SchemaStore } from './schema/SchemaStore';
import { SyncData, SyncFavoritePlaylist } from '../sync/SyncModels';
import {
  deserializeSyncContent,
  serializeSyncDataJson,
  utf8Decode,
  utf8EncodeText
} from '../sync/SyncDataJsonCodec';

export class FavoritePlaylistRepository {
  private static readonly KEY: string = 'favorite_playlists_sync';

  static async snapshot(): Promise<SyncFavoritePlaylist[]> {
    return SchemaStore.load<SyncFavoritePlaylist[]>(
      FavoritePlaylistRepository.KEY, [], FavoritePlaylistRepository.parse);
  }

  static async replaceFromSync(favorites: SyncFavoritePlaylist[]): Promise<void> {
    const data = new SyncData();
    data.favoritePlaylists = favorites;
    const json = utf8Decode(serializeSyncDataJson(data));
    await SchemaStore.save(FavoritePlaylistRepository.KEY, json,
      (value: string): string => value);
  }

  static parse(json: string): SyncFavoritePlaylist[] | null {
    const decoded = deserializeSyncContent(utf8EncodeText(json));
    return decoded.data === null ? null : decoded.data.favoritePlaylists;
  }
}
