// SPDX-License-Identifier: GPL-3.0

import { AppPreferences } from './AppPreferences';
import { Logger } from '../app/Logger';
import { updatedSearchHistory } from './SearchHistoryPolicy';

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
    // 上游 updatedExploreSearchHistory：忽略大小写去重（旧数据里的重复项
    // 顺带被归一掉），超限截断。
    const history = await SearchHistoryRepository.load();
    const updated = updatedSearchHistory(history, keyword, SearchHistoryRepository.LIMIT);
    if (updated.length === 0) {
      return SearchHistoryRepository.load();
    }
    await AppPreferences.putString(SearchHistoryRepository.KEY, JSON.stringify(updated));
    return updated;
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
