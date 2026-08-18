import { AppPreferences } from './AppPreferences';
import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';

/**
 * Recent-play history, mirroring PlayHistoryRepository.
 */
export class HistoryRepository {
  private static readonly KEY: string = 'history';
  private static readonly LIMIT: number = 200;

  static async getRecent(): Promise<SongItem[]> {
    const json = await AppPreferences.getString(HistoryRepository.KEY, '[]');
    const songs: SongItem[] = [];
    try {
      const rawList = JSON.parse(json) as Object[];
      for (const raw of rawList) {
        songs.push(SongItem.fromJson(JSON.stringify(raw)));
      }
    } catch (error) {
      const e = error as Error;
      console.warn(`HistoryRepository.getRecent failed: ${e.message}`);
    }
    return songs;
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
    await AppPreferences.putString(HistoryRepository.KEY, json);
  }

  static async clear(): Promise<void> {
    await AppPreferences.putString(HistoryRepository.KEY, '[]');
  }
}
