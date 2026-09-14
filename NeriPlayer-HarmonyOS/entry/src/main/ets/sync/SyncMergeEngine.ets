// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/** Pure three-way merge orchestration over the already ported policy family. */

import {
  DISPLAY_ORDER_SONG_ORDER_VERSION,
  SyncData,
  SyncFavoritePlaylist,
  SyncLogEntry,
  SyncPlaylist,
  SyncPlaylistSongDeletion,
  SyncRecentPlay,
  SyncRecentPlayDeletion,
  mergePositiveTimestamp,
  syncSongIdentity
} from './SyncModels';
import { mergeSongs } from './PlaylistSongMergePolicy';
import {
  applyDeletions,
  mergeDeletions,
  mergeFavoritePlaylists,
  pruneResolvedDeletions
} from './PlaylistDeletionPolicy';
import { finalizeMergedStats, merge, mergeBuckets } from './PlaybackStatsMergePolicy';
import { SyncConflictResolution, SyncConflictSummary, SyncReport } from './SyncReport';

const MAX_RECENT_PLAYS: number = 500;
const MAX_SYNC_LOG: number = 100;

export class SyncMergeResult {
  data: SyncData;
  report: SyncReport;

  constructor(data: SyncData, report: SyncReport) {
    this.data = data;
    this.report = report;
  }
}

class PlaylistMergeResult {
  playlist: SyncPlaylist;
  report: SyncReport;

  constructor(playlist: SyncPlaylist, report: SyncReport) {
    this.playlist = playlist;
    this.report = report;
  }
}

export function buildInitialSyncMerge(local: SyncData, nowMs: number): SyncMergeResult {
  const finalized = finalizeMergedStats(local.playbackStats, local.playbackStatBuckets);
  const data = new SyncData(
    local.version, local.deviceId, local.deviceName, nowMs,
    local.playlists, local.favoritePlaylists, local.recentPlays, local.syncLog,
    local.recentPlayDeletions, finalized.stats, local.playbackStatsClearedAt,
    finalized.buckets, local.playlistSongDeletions
  );
  const report = new SyncReport();
  report.message = '首次同步已上传本地数据';
  for (const playlist of local.playlists) {
    if (playlist.isDeleted) {
      report.playlistsDeleted++;
    } else {
      report.playlistsAdded++;
      report.songsAdded += playlist.songs.length;
    }
  }
  return new SyncMergeResult(data, report);
}

export function performThreeWayMerge(
  local: SyncData,
  remote: SyncData,
  lastSyncTime: number,
  nowMs: number,
  favoritesPlaylistId: number
): SyncMergeResult {
  const report = new SyncReport();
  report.message = '同步与合并完成';
  const mergedDeletions = mergeDeletions(local.playlistSongDeletions,
    remote.playlistSongDeletions);
  const localMap = playlistMap(local.playlists);
  const remoteMap = playlistMap(remote.playlists);
  const ids: number[] = [];
  appendUniqueNumbers(ids, local.playlists.map((item: SyncPlaylist): number => item.id));
  appendUniqueNumbers(ids, remote.playlists.map((item: SyncPlaylist): number => item.id));
  const mergedMap = new Map<number, SyncPlaylist>();

  for (const id of ids) {
    const left = localMap.get(id);
    const right = remoteMap.get(id);
    if (left !== undefined && right === undefined) {
      mergedMap.set(id, left);
      left.isDeleted ? report.playlistsDeleted++ : report.playlistsAdded++;
      continue;
    }
    if (left === undefined && right !== undefined) {
      mergedMap.set(id, right);
      right.isDeleted ? report.playlistsDeleted++ : report.playlistsAdded++;
      continue;
    }
    if (left === undefined || right === undefined) {
      continue;
    }
    if (left.isDeleted || right.isDeleted) {
      mergedMap.set(id, mergeDeletedPlaylist(left, right));
      report.playlistsDeleted++;
      continue;
    }
    const merged = mergePlaylist(left, right, lastSyncTime, mergedDeletions,
      id === favoritesPlaylistId);
    mergedMap.set(id, merged.playlist);
    addReport(report, merged.report);
  }

  const playlists = orderMergedPlaylists(local.playlists, remote.playlists, mergedMap, lastSyncTime);
  const recentDeletions = pruneRecentPlayDeletions(
    mergeRecentPlayDeletions(local.recentPlayDeletions, remote.recentPlayDeletions),
    local.recentPlays.concat(remote.recentPlays)
  );
  const recentPlays = mergeRecentPlays(local.recentPlays, remote.recentPlays, recentDeletions);
  const clearedAt = Math.max(local.playbackStatsClearedAt, remote.playbackStatsClearedAt);
  const finalized = finalizeMergedStats(
    merge(local.playbackStats, remote.playbackStats, clearedAt),
    mergeBuckets(local.playbackStatBuckets, remote.playbackStatBuckets, clearedAt)
  );
  const data = new SyncData(
    local.version, local.deviceId, local.deviceName, nowMs,
    playlists,
    mergeFavorites(local.favoritePlaylists, remote.favoritePlaylists),
    recentPlays,
    mergeSyncLog(local, remote),
    recentDeletions,
    finalized.stats,
    clearedAt,
    finalized.buckets,
    pruneResolvedDeletions(mergedDeletions, playlists)
  );
  return new SyncMergeResult(data, report);
}

function mergePlaylist(local: SyncPlaylist, remote: SyncPlaylist, lastSyncTime: number,
  deletions: SyncPlaylistSongDeletion[], isFavorites: boolean): PlaylistMergeResult {
  const report = new SyncReport();
  const localChanged = local.modifiedAt > lastSyncTime;
  const remoteChanged = remote.modifiedAt > lastSyncTime;
  let finalName = local.name;
  if (local.name !== remote.name) {
    let resolution = SyncConflictResolution.MANUAL_REQUIRED;
    if (remoteChanged && !localChanged) {
      finalName = remote.name;
      resolution = SyncConflictResolution.REMOTE_WINS;
    } else if (localChanged && !remoteChanged) {
      resolution = SyncConflictResolution.LOCAL_WINS;
    }
    report.conflicts.push(new SyncConflictSummary(
      local.id, finalName, `歌单“${local.name}”与“${remote.name}”同时存在重命名差异`, resolution));
  }
  const localKeys = identitySet(local);
  const songResult = mergeSongs(local.songs, remote.songs, local.modifiedAt, remote.modifiedAt,
    localChanged, remoteChanged, lastSyncTime, isFavorites);
  const songs = applyDeletions(local.id, songResult.songs, deletions);
  const mergedKeys = new Set<string>();
  for (const song of songs) {
    mergedKeys.add(syncSongIdentity(song).stableKey());
  }
  mergedKeys.forEach((key: string) => {
    if (!localKeys.has(key)) {
      report.songsAdded++;
    }
  });
  localKeys.forEach((key: string) => {
    if (!mergedKeys.has(key)) {
      report.songsRemoved++;
    }
  });
  if (songResult.isUpdated || report.songsAdded > 0 || report.songsRemoved > 0 ||
    finalName !== local.name) {
    report.playlistsUpdated = 1;
  }
  return new PlaylistMergeResult(new SyncPlaylist(
    local.id, finalName, songs,
    mergePositiveTimestamp(local.createdAt, remote.createdAt),
    Math.max(local.modifiedAt, remote.modifiedAt), false,
    DISPLAY_ORDER_SONG_ORDER_VERSION
  ), report);
}

function mergeDeletedPlaylist(local: SyncPlaylist, remote: SyncPlaylist): SyncPlaylist {
  const name = local.name.trim().length > 0 ? local.name : remote.name;
  return new SyncPlaylist(local.id, name, [],
    mergePositiveTimestamp(local.createdAt, remote.createdAt),
    Math.max(local.modifiedAt, remote.modifiedAt), true, DISPLAY_ORDER_SONG_ORDER_VERSION);
}

function orderMergedPlaylists(local: SyncPlaylist[], remote: SyncPlaylist[],
  merged: Map<number, SyncPlaylist>, lastSyncTime: number): SyncPlaylist[] {
  const localChanged = collectionChanged(local, lastSyncTime);
  const remoteChanged = collectionChanged(remote, lastSyncTime);
  const primary = remoteChanged && !localChanged ? remote : local;
  const secondary = primary === local ? remote : local;
  const ids: number[] = [];
  appendLiveIds(ids, primary, merged);
  appendLiveIds(ids, secondary, merged);
  merged.forEach((_value: SyncPlaylist, key: number) => appendUniqueNumbers(ids, [key]));
  const result: SyncPlaylist[] = [];
  for (const id of ids) {
    const playlist = merged.get(id);
    if (playlist !== undefined) {
      result.push(playlist);
    }
  }
  return result;
}

function mergeRecentPlays(local: SyncRecentPlay[], remote: SyncRecentPlay[],
  deletions: SyncRecentPlayDeletion[]): SyncRecentPlay[] {
  const deletedAt = new Map<string, number>();
  for (const deletion of deletions) {
    deletedAt.set(deletion.stableKey(), deletion.deletedAt);
  }
  const all = local.concat(remote);
  all.sort((a: SyncRecentPlay, b: SyncRecentPlay): number => {
    if (a.playedAt !== b.playedAt) {
      return b.playedAt - a.playedAt;
    }
    if (a.resumePositionMs !== b.resumePositionMs) {
      return b.resumePositionMs - a.resumePositionMs;
    }
    return a.deviceId < b.deviceId ? 1 : (a.deviceId > b.deviceId ? -1 : 0);
  });
  const seen = new Set<string>();
  const result: SyncRecentPlay[] = [];
  for (const play of all) {
    const key = syncSongIdentity(play.song).stableKey();
    const deletionTime = deletedAt.get(key);
    if (seen.has(key) || (deletionTime !== undefined && play.playedAt <= deletionTime)) {
      continue;
    }
    seen.add(key);
    result.push(play);
    if (result.length >= MAX_RECENT_PLAYS) {
      break;
    }
  }
  return result;
}

function mergeRecentPlayDeletions(local: SyncRecentPlayDeletion[], remote: SyncRecentPlayDeletion[]):
  SyncRecentPlayDeletion[] {
  const newest = new Map<string, SyncRecentPlayDeletion>();
  for (const deletion of local.concat(remote)) {
    const key = deletion.stableKey();
    const current = newest.get(key);
    if (current === undefined || deletion.deletedAt > current.deletedAt ||
      (deletion.deletedAt === current.deletedAt && deletion.deviceId > current.deviceId)) {
      newest.set(key, deletion);
    }
  }
  const result: SyncRecentPlayDeletion[] = [];
  newest.forEach((value: SyncRecentPlayDeletion) => result.push(value));
  result.sort((a: SyncRecentPlayDeletion, b: SyncRecentPlayDeletion): number => b.deletedAt - a.deletedAt);
  return result.slice(0, MAX_RECENT_PLAYS);
}

function pruneRecentPlayDeletions(deletions: SyncRecentPlayDeletion[],
  plays: SyncRecentPlay[]): SyncRecentPlayDeletion[] {
  const latest = new Map<string, number>();
  for (const play of plays) {
    const key = syncSongIdentity(play.song).stableKey();
    const current = latest.get(key) ?? 0;
    if (play.playedAt > current) {
      latest.set(key, play.playedAt);
    }
  }
  return deletions.filter((deletion: SyncRecentPlayDeletion): boolean =>
    (latest.get(deletion.stableKey()) ?? 0) <= deletion.deletedAt);
}

function mergeFavorites(local: SyncFavoritePlaylist[], remote: SyncFavoritePlaylist[]):
  SyncFavoritePlaylist[] {
  const merged = new Map<string, SyncFavoritePlaylist>();
  for (const favorite of local.concat(remote)) {
    const key = `${favorite.id}_${favorite.source}`;
    const current = merged.get(key);
    merged.set(key, current === undefined ? favorite : mergeFavoritePlaylists(current, favorite));
  }
  const result: SyncFavoritePlaylist[] = [];
  merged.forEach((value: SyncFavoritePlaylist) => result.push(value));
  return result.sort((a: SyncFavoritePlaylist, b: SyncFavoritePlaylist): number => b.sortOrder - a.sortOrder);
}

function mergeSyncLog(local: SyncData, remote: SyncData): SyncLogEntry[] {
  const seen = new Set<number>();
  const result: SyncLogEntry[] = [];
  const all = local.syncLog.concat(remote.syncLog);
  all.sort((a: SyncLogEntry, b: SyncLogEntry): number => b.timestamp - a.timestamp);
  for (const entry of all) {
    if (!seen.has(entry.timestamp)) {
      seen.add(entry.timestamp);
      result.push(entry);
      if (result.length >= MAX_SYNC_LOG) {
        break;
      }
    }
  }
  return result;
}

function playlistMap(playlists: SyncPlaylist[]): Map<number, SyncPlaylist> {
  const result = new Map<number, SyncPlaylist>();
  for (const playlist of playlists) {
    result.set(playlist.id, playlist);
  }
  return result;
}

function identitySet(playlist: SyncPlaylist): Set<string> {
  const result = new Set<string>();
  for (const song of playlist.songs) {
    result.add(syncSongIdentity(song).stableKey());
  }
  return result;
}

function collectionChanged(playlists: SyncPlaylist[], lastSyncTime: number): boolean {
  return playlists.some((playlist: SyncPlaylist): boolean =>
    !playlist.isDeleted && playlist.modifiedAt > lastSyncTime);
}

function appendLiveIds(target: number[], source: SyncPlaylist[], merged: Map<number, SyncPlaylist>): void {
  for (const playlist of source) {
    if (!playlist.isDeleted && merged.has(playlist.id)) {
      appendUniqueNumbers(target, [playlist.id]);
    }
  }
}

function appendUniqueNumbers(target: number[], values: number[]): void {
  for (const value of values) {
    if (target.indexOf(value) < 0) {
      target.push(value);
    }
  }
}

function addReport(target: SyncReport, source: SyncReport): void {
  target.playlistsAdded += source.playlistsAdded;
  target.playlistsUpdated += source.playlistsUpdated;
  target.playlistsDeleted += source.playlistsDeleted;
  target.songsAdded += source.songsAdded;
  target.songsRemoved += source.songsRemoved;
  target.conflicts = target.conflicts.concat(source.conflicts);
}
