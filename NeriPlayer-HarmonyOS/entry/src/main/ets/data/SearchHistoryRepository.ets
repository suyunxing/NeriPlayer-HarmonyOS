import { AppPreferences } from './AppPreferences';
import { Logger } from '../app/Logger';

/**
 * Recent search keywords per platform, mirroring the Android explore
 * search history behavior.
 */
export class SearchHistoryRepository {
  private static readonly KEY: string = 'search_history';
  private static readonly LIMIT: number = 12;

  static async load(): Promise<string[]> {
    const json = await AppPreferences.getString(SearchHistoryRepository.KEY, '[]');
    try {
      const rawList = JSON.parse(json) as Object[];
      return rawList.map((raw: Object) => String(raw));
    } catch (error) {
      const e = error as Error;
      Logger.warn(`SearchHistoryRepository.load failed: ${e.message}`);
      return [];
    }
  }

  static async add(keyword: string): Promise<string[]> {
    const trimmed = keyword.trim();
    if (trimmed.length === 0) {
      return SearchHistoryRepository.load();
    }
    const history = await SearchHistoryRepository.load();
    const filtered = history.filter((item: string) => item !== trimmed);
    filtered.unshift(trimmed);
    if (filtered.length > SearchHistoryRepository.LIMIT) {
      filtered.splice(SearchHistoryRepository.LIMIT);
    }
    await AppPreferences.putString(SearchHistoryRepository.KEY, JSON.stringify(filtered));
    return filtered;
  }

  static async remove(keyword: string): Promise<string[]> {
    const history = await SearchHistoryRepository.load();
    const filtered = history.filter((item: string) => item !== keyword);
    await AppPreferences.putString(SearchHistoryRepository.KEY, JSON.stringify(filtered));
    return filtered;
  }

  static async clear(): Promise<string[]> {
    await AppPreferences.putString(SearchHistoryRepository.KEY, '[]');
    return [];
  }
}
