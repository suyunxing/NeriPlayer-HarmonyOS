// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { SongItem } from '../model/SongItem';
import { stableKeyOf } from '../model/SongIdentity';
import { SchemaStore } from './schema/SchemaStore';
import { util } from '@kit.ArkTS';
import { SyncDeletionStore } from '../sync/SyncDeletionStore';
import { SyncRecentPlayDeletion, songIdKeyText, syncSongIdentity } from '../sync/SyncModels';
import { syncSongFromSongItem } from '../sync/SyncSongConvert';

/** 导出文件的 JSON 载荷（version/app 固定，songs 为 SongItem 数组）。 */
class HistoryExportPayload {
  version: number = 1;
  app: string = 'NeriPlayer-HarmonyOS';
  exportedAt: number = 0;
  count: number = 0;
  songs: SongItem[] = [];
}

/**
 * Recent-play history, mirroring PlayHistoryRepository.
 */
export class HistoryRepository {
  private static readonly KEY: string = 'history';
  // 播放历史容量（参考应用 1000 条，FIFO：新纪录插入队头并挤掉最旧的一条）。
  static readonly LIMIT: number = 1000;

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
    const syncSong = syncSongFromSongItem(song);
    if (syncSong !== null) {
      await SyncDeletionStore.clearRecentPlayDeletion(syncSongIdentity(syncSong).stableKey());
    }
  }

  static async clear(): Promise<void> {
    const recent = await HistoryRepository.getRecent();
    const deviceId = await SyncDeletionStore.getOrCreateDeviceId(
      (): string => util.generateRandomUUID(false));
    const deletedAt = Date.now();
    for (const song of recent) {
      const syncSong = syncSongFromSongItem(song);
      if (syncSong !== null) {
        await SyncDeletionStore.recordRecentPlayDeletion(new SyncRecentPlayDeletion(
          syncSong.id, syncSong.album, syncSong.mediaUri, deletedAt, deviceId,
          songIdKeyText(syncSong)
        ));
      }
    }
    await HistoryRepository.replaceFromSync([]);
  }

  static async replaceFromSync(songs: SongItem[]): Promise<void> {
    const limited = songs.slice(0, HistoryRepository.LIMIT);
    const json = JSON.stringify(limited.map((item: SongItem) => SongItem.fromJson(item.toJson())));
    await SchemaStore.save(HistoryRepository.KEY, json, (value: string) => value);
  }

  // ---- 播放历史导出 / 导入（RecentPage 更多菜单） ---------------------------
  //
  // 导出格式带 version/exportedAt 头部，导入同时兼容该对象与历史裸数组；合并
  // 与序列化都是纯函数，单测直接覆盖（mergeForImport / serializeExport /
  // parseImportJson）。

  static serializeExport(songs: SongItem[], exportedAtMs: number): string {
    const payload = new HistoryExportPayload();
    payload.exportedAt = exportedAtMs;
    payload.count = songs.length;
    payload.songs = songs.map((item: SongItem) => SongItem.fromJson(item.toJson()));
    return JSON.stringify(payload, null, 2);
  }

  static parseImportJson(json: string): SongItem[] | null {
    let parsed: Object;
    try {
      parsed = JSON.parse(json) as Object;
    } catch (_error) {
      return null;
    }
    let rawList: Object[] | null = null;
    if (Array.isArray(parsed)) {
      rawList = parsed as Object[];
    } else {
      const record = parsed as Record<string, Object>;
      const songs = record['songs'];
      if (songs !== undefined && songs !== null && Array.isArray(songs)) {
        rawList = songs as Object[];
      }
    }
    if (rawList === null) {
      return null;
    }
    const songs: SongItem[] = [];
    for (const raw of rawList) {
      try {
        songs.push(SongItem.fromJson(JSON.stringify(raw)));
      } catch (_error) {
        // 单条损坏不拖垮整份导入。
      }
    }
    return songs;
  }

  /**
   * Pure import merge: imported songs win (in their own order), then unseen
   * existing ones, deduped by the stable song key and capped at LIMIT.
   */
  static mergeForImport(existing: SongItem[], imported: SongItem[]): SongItem[] {
    const merged: SongItem[] = [];
    const seen = new Set<string>();
    for (const song of imported) {
      const key = stableKeyOf(song);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      merged.push(song);
    }
    for (const song of existing) {
      const key = stableKeyOf(song);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      merged.push(song);
    }
    if (merged.length > HistoryRepository.LIMIT) {
      merged.splice(HistoryRepository.LIMIT);
    }
    return merged;
  }

  /** Merges an imported list into local history; returns the merged total. */
  static async importSongs(imported: SongItem[]): Promise<number> {
    const existing = await HistoryRepository.getRecent();
    const merged = HistoryRepository.mergeForImport(existing, imported);
    await HistoryRepository.replaceFromSync(merged);
    // 复活的曲目要撤掉它之前「清除记录」留下的同步删除墓碑，否则下一次云同步
    // 会把导入的记录再次删掉（与 addSong 的墓碑清理同一规则）。
    for (const song of imported) {
      const syncSong = syncSongFromSongItem(song);
      if (syncSong !== null) {
        await SyncDeletionStore.clearRecentPlayDeletion(syncSongIdentity(syncSong).stableKey());
      }
    }
    return merged.length;
  }
}
