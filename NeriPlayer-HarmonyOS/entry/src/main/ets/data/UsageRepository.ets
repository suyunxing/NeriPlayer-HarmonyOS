import { AppPreferences } from './AppPreferences';
import { Logger } from '../app/Logger';

export interface UsageEntry {
  id: string;
  name: string;
  picUrl: string;
  source: string;
  subtype: string;
  trackCount: number;
  updatedAt: number;
}

/**
 * "Continue playing" entries shown on Home, mirroring the Android
 * PlaylistUsageRepository (frequent/recent playlists and local artists).
 */
export class UsageRepository {
  private static readonly KEY: string = 'usage_entries';
  private static readonly LIMIT: number = 30;

  static async load(): Promise<UsageEntry[]> {
    const json = await AppPreferences.getString(UsageRepository.KEY, '[]');
    const entries: UsageEntry[] = [];
    try {
      const rawList = JSON.parse(json) as Object[];
      for (const raw of rawList) {
        const record = raw as Record<string, Object>;
        entries.push({
          id: String(record['id'] ?? ''),
          name: String(record['name'] ?? ''),
          picUrl: String(record['picUrl'] ?? ''),
          source: String(record['source'] ?? ''),
          subtype: String(record['subtype'] ?? ''),
          trackCount: Number(record['trackCount'] ?? 0),
          updatedAt: Number(record['updatedAt'] ?? 0)
        });
      }
    } catch (error) {
      const e = error as Error;
      Logger.warn(`UsageRepository.load failed: ${e.message}`);
    }
    entries.sort((a: UsageEntry, b: UsageEntry) => b.updatedAt - a.updatedAt);
    return entries;
  }

  static async record(entry: UsageEntry): Promise<void> {
    const entries = await UsageRepository.load();
    const filtered = entries.filter((item: UsageEntry) =>
      !(item.id === entry.id && item.source === entry.source && item.subtype === entry.subtype));
    filtered.unshift(entry);
    if (filtered.length > UsageRepository.LIMIT) {
      filtered.splice(UsageRepository.LIMIT);
    }
    await AppPreferences.putString(UsageRepository.KEY, JSON.stringify(filtered));
  }

  static async remove(id: string, source: string, subtype: string): Promise<void> {
    const entries = await UsageRepository.load();
    const filtered = entries.filter((item: UsageEntry) =>
      !(item.id === id && item.source === source && item.subtype === subtype));
    await AppPreferences.putString(UsageRepository.KEY, JSON.stringify(filtered));
  }

  static async clear(): Promise<void> {
    await AppPreferences.putString(UsageRepository.KEY, '[]');
  }
}
