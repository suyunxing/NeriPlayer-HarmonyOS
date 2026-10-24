// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// storage usage analysis (#328/#335), adapted to the HarmonyOS sandbox.

import { DownloadStorage } from '../download/DownloadStorage';
import { PlaybackCacheManager } from '../player/PlaybackCacheManager';
import { LyricDispatcher } from '../lyrics/LyricDispatcher';
import { DiagnosticsStore } from '../app/diagnostics/DiagnosticsStore';
import { AppPreferences } from './AppPreferences';
import { dirSizeBytes, formatStorageBytes } from '../util/StorageBytes';

/** One storage bucket shown in the settings storage section. */
export class StorageUsageCategory {
  key: string = '';
  label: string = '';
  /** Disk bytes; 0 for count-only categories (detail carries the value). */
  bytes: number = 0;
  /** Rendered value, e.g. "1.2 MB" or "12 首" (overrides bytes when set). */
  detail: string = '';

  constructor(key: string, label: string, bytes: number, detail: string = '') {
    this.key = key;
    this.label = label;
    this.bytes = bytes;
    this.detail = detail;
  }
}

export class StorageUsageSummary {
  categories: StorageUsageCategory[] = [];
  totalBytes: number = 0;
}

/**
 * Scans the app's storage buckets for the settings storage-analysis section
 * (F-8): downloaded music (catalog-driven, custom download directory
 * included), download staging, the opt-in playback cache dirs, the lyric
 * cache table (entry count — it lives in preferences), diagnostics detail
 * files and the preferences store itself. Every bucket degrades to 0 on
 * error; the scan never throws.
 */
export async function analyzeStorageUsage(): Promise<StorageUsageSummary> {
  const summary = new StorageUsageSummary();

  let downloadBytes = 0;
  try {
    const catalog = await DownloadStorage.getCatalog();
    for (const entry of catalog) {
      downloadBytes += DownloadStorage.fileSize(entry.audioPath);
    }
  } catch (error) {
    // Unreadable custom directory: reported as 0, not fatal.
  }
  summary.categories.push(new StorageUsageCategory('downloads', '已下载音乐', downloadBytes,
    formatStorageBytes(downloadBytes)));

  const stagingBytes = dirSizeBytes(DownloadStorage.stagingDir());
  summary.categories.push(new StorageUsageCategory('staging', '下载暂存区', stagingBytes,
    formatStorageBytes(stagingBytes)));

  const playbackBytes = await PlaybackCacheManager.totalCacheBytes().catch((_e: Error) => 0);
  summary.categories.push(new StorageUsageCategory('playback_cache', '播放缓存', playbackBytes,
    formatStorageBytes(playbackBytes)));

  const lyricCount = await LyricDispatcher.cachedLyricEntryCount().catch((_e: Error) => 0);
  summary.categories.push(new StorageUsageCategory('lyric_cache', '歌词缓存', 0,
    `${lyricCount} 首`));

  const diagnosticsBytes = dirSizeBytes(DiagnosticsStore.directory());
  summary.categories.push(new StorageUsageCategory('diagnostics', '诊断记录', diagnosticsBytes,
    formatStorageBytes(diagnosticsBytes)));

  let prefChars = 0;
  try {
    const all = await AppPreferences.getAll();
    for (const key of Object.keys(all)) {
      const value = all[key];
      if (typeof value === 'string') {
        prefChars += key.length + value.length;
      } else {
        prefChars += key.length + 8;
      }
    }
  } catch (error) {
    // Preferences unreadable: reported as 0.
  }
  const prefBytes = prefChars * 2;
  summary.categories.push(new StorageUsageCategory('app_data', '应用数据（配置/歌单/历史）', prefBytes,
    formatStorageBytes(prefBytes)));

  for (const category of summary.categories) {
    summary.totalBytes += category.bytes;
  }
  return summary;
}
