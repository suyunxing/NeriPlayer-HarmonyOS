// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { DownloadProgress, DownloadStatus, DownloadTask } from './DownloadModels';
import { DownloadedSongEntry } from './DownloadStorage';

/**
 * One 下载管理 row: an engine task and/or the committed download it refers to.
 */
export class DownloadRow {
  stableKey: string = '';
  song: SongItem = new SongItem();
  status: DownloadStatus = DownloadStatus.QUEUED;
  attemptId: number = 0;
  progress: DownloadProgress | null = null;
  /** Non-null when a committed download (file + catalog row) backs this key. */
  entry: DownloadedSongEntry | null = null;
}

/**
 * Merges the engine task list with the download catalog. Catalog rows without
 * a task record (e.g. after 清空记录, or restored from sync) must stay visible:
 * hiding them left committed downloads that no screen could list or delete,
 * while the library "已下载" count kept counting them.
 */
export function buildDownloadRows(tasks: DownloadTask[], catalog: DownloadedSongEntry[]): DownloadRow[] {
  const rows: DownloadRow[] = [];
  const seen: Set<string> = new Set<string>();
  for (const task of tasks) {
    const key = stableKeyOf(task.song);
    seen.add(key);
    const entry = catalog.find((item: DownloadedSongEntry) => item.stableKey === key) ?? null;
    // A COMPLETED task whose catalog row is gone points at a purged file
    // (self-heal or payload purge): nothing left to play or delete offline.
    if (task.status === DownloadStatus.COMPLETED && entry === null) {
      continue;
    }
    const row = new DownloadRow();
    row.stableKey = key;
    row.song = task.song;
    row.status = task.status;
    row.attemptId = task.attemptId;
    row.progress = task.progress;
    row.entry = entry;
    rows.push(row);
  }
  for (const entry of catalog) {
    if (seen.has(entry.stableKey)) {
      continue;
    }
    const row = new DownloadRow();
    row.stableKey = entry.stableKey;
    row.song = SongItem.fromJson(entry.songJson);
    row.status = DownloadStatus.COMPLETED;
    row.entry = entry;
    rows.push(row);
  }
  return rows;
}
