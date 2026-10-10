// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer),
// commit 57eaacd7 "feat: add NetEase playlist picker and support syncing songs
// to custom playlists (#322)".

import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';

/** 写回接口的批量上限（上游 NETEASE_PLAYLIST_ADD_BATCH_SIZE = 50）。 */
export const NETEASE_PLAYLIST_ADD_BATCH_SIZE: number = 50;
/** 歌曲详情解析的批量上限（上游 NETEASE_SONG_DETAIL_BATCH_SIZE = 300）。 */
export const NETEASE_SONG_DETAIL_BATCH_SIZE: number = 300;

/**
 * 本地歌曲解析出的网易云曲目 id：0 表示该歌不支持写回。
 *
 * 上游 resolveNeteaseSongId 的鸿蒙子集：网易云平台直取 audioId；非网易云
 * 平台但经匹配面板/自动匹配写入过网易源 matchedSongId（形如 "netease:123"）
 * 的取匹配 id。上游的专辑前缀/封面 URL 启发式不移植（鸿蒙 SongItem 无对应
 * 稳定标记，误判代价是写错歌）。
 */
export function resolveNeteaseSongId(song: SongItem): number {
  if (song.platform === MusicPlatform.NETEASE) {
    const direct = Number(song.audioId);
    if (Number.isFinite(direct) && direct > 0) {
      return Math.floor(direct);
    }
    return 0;
  }
  if (song.matchedSongId.startsWith('netease:')) {
    const matched = Number(song.matchedSongId.substring('netease:'.length));
    if (Number.isFinite(matched) && matched > 0) {
      return Math.floor(matched);
    }
  }
  return 0;
}

/**
 * /weapi/playlist/manipulate/tracks 的 weapi 参数（上游
 * buildNeteasePlaylistAddTracksParams 直译）：tracks 为 CSV、trackIds 为
 * JSON 数组、imme=true 立即生效。非法输入抛 Error（上游 require 语义）。
 */
export function buildNeteasePlaylistAddTracksParams(playlistId: number,
  songIds: number[]): Record<string, string> {
  if (!(playlistId > 0)) {
    throw new Error('playlistId 必须为正数');
  }
  const ids: number[] = [];
  for (const id of songIds) {
    if (id > 0 && !ids.includes(id)) {
      ids.push(id);
    }
  }
  if (ids.length === 0) {
    throw new Error('songIds 不含可用的正数 id');
  }
  const params: Record<string, string> = {};
  params['op'] = 'add';
  params['pid'] = `${playlistId}`;
  params['id'] = `${playlistId}`;
  params['tracks'] = ids.join(',');
  params['trackIds'] = `[${ids.join(',')}]`;
  params['imme'] = 'true';
  return params;
}

/** 批量写回结果：成功/失败两侧的曲目 id 集合。 */
export class NeteaseBatchAddResult {
  addedIds: Set<number> = new Set<number>();
  failedIds: Set<number> = new Set<number>();
}

/**
 * 同步流程的外部依赖（网络适配注入；基类实现即「全部不可用」，纯逻辑测试
 * 与调用方按需覆写方法）。方法形而非函数值字段：调用点的 await 都落在
 * 实例方法上，与仓库其余网络调用同形状。
 */
export class NeteaseWritebackDeps {
  /** 目标歌单现有曲目 id 集；null = 获取失败（放弃本次比较）。 */
  async fetchTargetTrackIds(playlistId: number): Promise<Set<number> | null> {
    return Promise.resolve(null);
  }

  /** 单批写回（内部处理 301 重试），true = 批成功。 */
  async addBatch(playlistId: number, ids: number[]): Promise<boolean> {
    return false;
  }

  /** 批量解析曲目是否仍存在（/song/detail），null = 查询失败。 */
  async resolveSongIds(ids: number[]): Promise<Set<number> | null> {
    return Promise.resolve(null);
  }
}

/**
 * 一批写回的递归执行体（模块级函数：ArkTS 禁止嵌套函数声明）。整批失败
 * 时二分下钻到单曲，隔离真正加不进去的歌。
 */
async function submitNeteaseBatch(ids: number[], deps: NeteaseWritebackDeps,
  targetPlaylistId: number, result: NeteaseBatchAddResult): Promise<void> {
  if (ids.length === 0) {
    return;
  }
  let added = false;
  try {
    added = await deps.addBatch(targetPlaylistId, ids);
  } catch (error) {
    added = false;
  }
  if (added) {
    for (const id of ids) {
      result.addedIds.add(id);
    }
    return;
  }
  if (ids.length === 1) {
    result.failedIds.add(ids[0]);
    return;
  }
  const midpoint = Math.floor(ids.length / 2);
  await submitNeteaseBatch(ids.slice(0, midpoint), deps, targetPlaylistId, result);
  await submitNeteaseBatch(ids.slice(midpoint), deps, targetPlaylistId, result);
}

/**
 * 分批写回（上游 addNeteasePlaylistSongIdsInBatches 直译）：按 batchSize
 * 分批，批失败二分下钻隔离坏歌（整批一起失败时网易云不给是哪首导致的）。
 */
export async function addNeteasePlaylistSongIdsInBatches(songIds: number[],
  batchSize: number, deps: NeteaseWritebackDeps, targetPlaylistId: number):
  Promise<NeteaseBatchAddResult> {
  if (batchSize <= 0) {
    throw new Error('batchSize 必须为正数');
  }
  const distinct: number[] = [];
  for (const id of songIds) {
    if (id > 0 && !distinct.includes(id)) {
      distinct.push(id);
    }
  }
  const result = new NeteaseBatchAddResult();
  if (distinct.length === 0) {
    return result;
  }
  for (let offset = 0; offset < distinct.length; offset += batchSize) {
    await submitNeteaseBatch(distinct.slice(offset, offset + batchSize), deps,
      targetPlaylistId, result);
  }
  return result;
}

/** 失败归因结果：仍算失败的 id 与「下架/不可解析」被跳过的数量。 */
export class NeteaseFailedSongResolution {
  unresolvedFailedIds: Set<number> = new Set<number>();
  skippedUnsupported: number = 0;
}

/**
 * 失败归因（上游 classifyNeteasePlaylistAddFailures 直译）：对失败 id 批量
 * 查详情，仍能解析的是真失败（服务端拒绝）；解析不到的视为下架/不支持，
 * 从失败里剔除计入跳过。resolveSongIds 抛异常/返回 null（查询失败）的批
 * 整批保留为失败，不猜测。
 */
export async function classifyNeteasePlaylistAddFailures(failedIds: number[],
  batchSize: number, deps: NeteaseWritebackDeps): Promise<NeteaseFailedSongResolution> {
  if (batchSize <= 0) {
    throw new Error('batchSize 必须为正数');
  }
  const distinct: number[] = [];
  for (const id of failedIds) {
    if (id > 0 && !distinct.includes(id)) {
      distinct.push(id);
    }
  }
  const resolution = new NeteaseFailedSongResolution();
  if (distinct.length === 0) {
    return resolution;
  }
  for (let offset = 0; offset < distinct.length; offset += batchSize) {
    const chunk = distinct.slice(offset, offset + batchSize);
    let resolved: Set<number> | null = null;
    try {
      resolved = await deps.resolveSongIds(chunk);
    } catch (error) {
      resolved = null;
    }
    if (resolved === null) {
      for (const id of chunk) {
        resolution.unresolvedFailedIds.add(id);
      }
      continue;
    }
    for (const id of chunk) {
      if (resolved.has(id)) {
        resolution.unresolvedFailedIds.add(id);
      } else {
        resolution.skippedUnsupported += 1;
      }
    }
  }
  return resolution;
}

/** 写回执行结果（上游 NeteaseLikeSyncResult 子集）。 */
export class NeteaseWritebackResult {
  totalSongs: number = 0;
  supportedSongs: number = 0;
  skippedUnsupported: number = 0;
  skippedExisting: number = 0;
  added: number = 0;
  failed: number = 0;
  message: string = '';
}

/**
 * 整套写回编排（上游 syncSongsToNeteasePlaylist 直译，不含上游的跨平台
 * 搜索匹配管线）：解析可写回 id → 拉目标歌单快照去重 → 分批写回（失败
 * 二分下钻）→ 快照复核把「其实已加上」的失败捞回 → 剩余失败按可解析性
 * 归因为失败/下架跳过。
 */
export async function syncSongsToNeteasePlaylist(songs: SongItem[], targetPlaylistId: number,
  deps: NeteaseWritebackDeps): Promise<NeteaseWritebackResult> {
  const result = new NeteaseWritebackResult();
  result.totalSongs = songs.length;
  if (songs.length === 0) {
    result.message = '歌单为空，没有可同步的歌曲';
    return result;
  }

  // 候选解析：每首歌（含重复出现的曲目）各自归入支持/不支持，保持上游
  // 对 skippedUnsupported/skippedExisting 按歌曲数（而非去重 id 数）计数。
  const candidateIds: number[] = [];
  for (const song of songs) {
    const id = resolveNeteaseSongId(song);
    if (id > 0) {
      candidateIds.push(id);
    }
  }
  result.supportedSongs = candidateIds.length;
  result.skippedUnsupported = songs.length - candidateIds.length;

  const snapshot = await deps.fetchTargetTrackIds(targetPlaylistId);
  if (snapshot === null) {
    result.message = '无法获取目标歌单内容，请稍后重试';
    return result;
  }

  const pending: number[] = [];
  for (const id of candidateIds) {
    if (snapshot.has(id)) {
      result.skippedExisting += 1;
    } else {
      pending.push(id);
    }
  }
  if (pending.length === 0) {
    result.message = '没有新歌需要同步';
    return result;
  }

  const addResult = await addNeteasePlaylistSongIdsInBatches(pending,
    NETEASE_PLAYLIST_ADD_BATCH_SIZE, deps, targetPlaylistId);
  const addedIds = addResult.addedIds;
  const failedIds = addResult.failedIds;
  if (failedIds.size > 0) {
    // 快照复核：写回接口报失败但曲目实际已在歌单里（超时后落库、批量
    // 接口的模糊错误等）的捞回成功侧。
    const rechecked = await deps.fetchTargetTrackIds(targetPlaylistId);
    if (rechecked !== null) {
      const recovered: number[] = [];
      for (const id of failedIds) {
        if (rechecked.has(id) && !addedIds.has(id)) {
          recovered.push(id);
        }
      }
      for (const id of recovered) {
        addedIds.add(id);
        failedIds.delete(id);
      }
    }
  }

  let failedCount = 0;
  if (failedIds.size > 0) {
    const remaining: number[] = [];
    for (const id of failedIds) {
      remaining.push(id);
    }
    const resolution = await classifyNeteasePlaylistAddFailures(remaining,
      NETEASE_SONG_DETAIL_BATCH_SIZE, deps);
    result.skippedUnsupported += resolution.skippedUnsupported;
    failedCount = resolution.unresolvedFailedIds.size;
  }

  result.added = addedIds.size;
  result.failed = failedCount;

  const parts: string[] = [];
  if (result.added > 0) {
    parts.push(`已添加 ${result.added} 首`);
  }
  if (result.skippedExisting > 0) {
    parts.push(`已存在 ${result.skippedExisting} 首`);
  }
  if (failedCount > 0) {
    parts.push(`失败 ${failedCount} 首`);
  }
  if (result.skippedUnsupported > 0) {
    parts.push(`不支持/下架 ${result.skippedUnsupported} 首`);
  }
  result.message = parts.length > 0 ? parts.join('，') : '同步完成';
  return result;
}
