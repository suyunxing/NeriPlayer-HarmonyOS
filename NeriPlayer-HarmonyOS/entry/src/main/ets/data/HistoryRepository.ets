import { AppPreferences } from './AppPreferences';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { SchemaStore } from './schema/SchemaStore';

/**
 * Recent-play history, mirroring PlayHistoryRepository.
 */
export class HistoryRepository {
  private static readonly KEY: string = 'history';
  private static readonly LIMIT: number = 200;

  static parseJson(json: string): SongItem[] | null {
    const rawList = JSON.parse(json) as Object[];
    if (!Array.isArray(rawList)) {
      return null;
    }
    const songs: SongItem[] = [];
    for (const raw of rawList) {
      songs.push(SongItem.fromJson(JSON.stringify(raw)));
    }
    return songs;
  }

  static async getRecent(): Promise<SongItem[]> {
    return SchemaStore.load<SongItem[]>(HistoryRepository.KEY, [], HistoryRepository.parseJson);
  }

  static async addSong(song: SongItem): Promise<void> {
    const recent = await HistoryRepository.getRecent();
    const key = stableKeyOf(song);
    const filtered = recent.filter((item: SongItem) => stableKeyOf(item) !== key);
    filtered.unshift(song);
    if (filtered.length > HistoryRepository.LIMIT) {
      filtered.splice(HistoryRepository.LIMIT);
    }
    const json = JSON.stringify(filtered.map((item: SongItem) => SongItem.fromJson(item.toJson())));
    await SchemaStore.save(HistoryRepository.KEY, json, (value: string) => value);
  }

  static async clear(): Promise<void> {
    await AppPreferences.putString(HistoryRepository.KEY, '[]');
  }
}
