// SPDX-License-Identifier: GPL-3.0

import { AppPreferences } from './AppPreferences';
import { LocalPlaylistRepository } from './LocalPlaylistRepository';
import { HistoryRepository } from './HistoryRepository';
import {
  DailyTrackStats,
  PlaybackStatsRepository,
  StatsRoot,
  TrackStats
} from './PlaybackStatsRepository';
import { Playlist } from '../model/Playlist';
import { SongItem } from '../model/SongItem';
import { legacyFnvStableKey, stableKeyOf } from '../model/SongIdentity';
import { DownloadedSongEntry, DownloadStorage } from '../download/DownloadStorage';
import { normalizeCounterShards } from '../sync/SyncModels';
import { Logger } from '../app/Logger';

/**
 * One-time migration for the SHA-256 stable-key alignment (backlog §1.1):
 * keys persisted before the switch were derived with the legacy FNV-1a
 * algorithm, so playlists / stats / the download catalog would silently
 * orphan every B 站/YTM entry. The remap is rebuilt from the SongItem
 * snapshots that travel next to the persisted keys, then applied to all
 * stores in a single pass guarded by a preferences flag.
 *
 * Keys that cannot be resolved (the song object is gone everywhere) are kept
 * verbatim: unmatched stats rows still contribute to totals, they simply
 * never match a live song again.
 */
export class StableKeyMigration {
  private static readonly FLAG_KEY: string = 'np.stable_key_sha256_migrated';

  static async runIfNeeded(): Promise<boolean> {
    const done = await AppPreferences.getString(StableKeyMigration.FLAG_KEY, '');
    if (done === '1') {
      return false;
    }
    const playlists = await LocalPlaylistRepository.loadAll();
    const history = await HistoryRepository.getRecent();
    const catalog = await DownloadStorage.getCatalog();

    const songs: SongItem[] = [];
    for (const playlist of playlists) {
      for (const song of playlist.songs) {
        songs.push(song);
      }
    }
    for (const song of history) {
      songs.push(song);
    }
    for (const entry of catalog) {
      if (entry.songJson.length > 0) {
        songs.push(SongItem.fromJson(entry.songJson));
      }
    }

    const remap = buildLegacyKeyRemap(songs);
    let touchedPlaylists = 0;
    for (const playlist of playlists) {
      if (remapPlaylist(playlist, remap)) {
        touchedPlaylists++;
      }
    }
    if (touchedPlaylists > 0) {
      await LocalPlaylistRepository.replaceAllFromSync(playlists);
    }

    const dedupedHistory = dedupeSongsByKey(history);
    if (dedupedHistory.length !== history.length) {
      await HistoryRepository.replaceFromSync(dedupedHistory);
    }

    let statsRewritten = false;
    if (remap.size > 0) {
      const stats = await PlaybackStatsRepository.snapshot();
      const nextStats = remapStatsRoot(stats, remap);
      await PlaybackStatsRepository.replaceFromSync(nextStats);
      statsRewritten = true;
    }

    if (remap.size > 0) {
      const nextCatalog = remapCatalogEntries(catalog, remap);
      await DownloadStorage.replaceCatalog(nextCatalog);
    }

    await AppPreferences.putString(StableKeyMigration.FLAG_KEY, '1');
    Logger.info(`StableKeyMigration: ${remap.size} legacy keys remapped, `
      + `${touchedPlaylists} playlists, statsRewritten=${statsRewritten}`);
    return true;
  }
}

/** old FNV key -> SHA-256 key; ambiguous legacy keys are dropped. */
export function buildLegacyKeyRemap(songs: SongItem[]): Map<string, string> {
  const remap = new Map<string, string>();
  const conflicts = new Set<string>();
  for (const song of songs) {
    const legacy = legacyFnvStableKey(song);
    const next = stableKeyOf(song);
    if (legacy === next) {
      continue;
    }
    const existing = remap.get(legacy);
    if (existing === undefined) {
      remap.set(legacy, next);
      continue;
    }
    if (existing !== next) {
      conflicts.add(legacy);
    }
  }
  for (const legacy of conflicts) {
    remap.delete(legacy);
  }
  return remap;
}

/**
 * Rewrites a playlist in place. songs[] and songKeys[] are index-aligned, so
 * the keys are rebuilt from the songs themselves; entries that collide after
 * the remap are merged (first occurrence wins).
 */
export function remapPlaylist(playlist: Playlist, remap: Map<string, string>): boolean {
  if (playlist.songKeys.length === playlist.songs.length) {
    const keys: string[] = [];
    const songs: SongItem[] = [];
    const seen = new Set<string>();
    let changed = false;
    for (let i = 0; i < playlist.songs.length; i++) {
      const key = stableKeyOf(playlist.songs[i]);
      if (playlist.songKeys[i] !== key) {
        changed = true;
      }
      if (seen.has(key)) {
        changed = true;
        continue;
      }
      seen.add(key);
      keys.push(key);
      songs.push(playlist.songs[i]);
    }
    if (playlist.songKeys.length !== keys.length) {
      changed = true;
    }
    if (changed) {
      playlist.songKeys = keys;
      playlist.songs = songs;
    }
    return changed;
  }
  // Legacy rows without song snapshots: remap the keys through the table.
  let changed = false;
  const keys: string[] = [];
  const seen = new Set<string>();
  for (const key of playlist.songKeys) {
    const next = remap.get(key) ?? key;
    if (next !== key || seen.has(next)) {
      changed = true;
    }
    if (seen.has(next)) {
      continue;
    }
    seen.add(next);
    keys.push(next);
  }
  if (changed) {
    playlist.songKeys = keys;
  }
  return changed;
}

/** Order-preserving dedupe by the (new) stable key. */
export function dedupeSongsByKey(songs: SongItem[]): SongItem[] {
  const seen = new Set<string>();
  const result: SongItem[] = [];
  for (const song of songs) {
    const key = stableKeyOf(song);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(song);
  }
  return result;
}

function fillMergedStats(target: TrackStats, a: TrackStats, b: TrackStats): void {
  target.playCount = a.playCount + b.playCount;
  target.listenMs = a.listenMs + b.listenMs;
  target.firstPlayedAt = a.firstPlayedAt > 0 && b.firstPlayedAt > 0
    ? Math.min(a.firstPlayedAt, b.firstPlayedAt)
    : Math.max(a.firstPlayedAt, b.firstPlayedAt);
  target.lastPlayedAt = Math.max(a.lastPlayedAt, b.lastPlayedAt);
  target.counterShards = normalizeCounterShards(a.counterShards.concat(b.counterShards));
}

function mergeTrackStats(a: TrackStats, b: TrackStats): TrackStats {
  const merged = new TrackStats();
  fillMergedStats(merged, a, b);
  return merged;
}

function mergeDailyStats(a: DailyTrackStats, b: DailyTrackStats): DailyTrackStats {
  const merged = new DailyTrackStats();
  fillMergedStats(merged, a, b);
  return merged;
}

/** Remaps stats keys through the table, summing rows that collide. */
export function remapStatsRoot(root: StatsRoot, remap: Map<string, string>): StatsRoot {
  const next = new StatsRoot();
  next.clearedAt = root.clearedAt;
  for (const key of Object.keys(root.tracks)) {
    const target = remap.get(key) ?? key;
    const existing = next.tracks[target];
    next.tracks[target] = existing === undefined ? root.tracks[key] : mergeTrackStats(existing, root.tracks[key]);
  }
  for (const day of Object.keys(root.daily)) {
    const entries = root.daily[day];
    const nextDay: Record<string, DailyTrackStats> = {};
    for (const key of Object.keys(entries)) {
      const target = remap.get(key) ?? key;
      const existing = nextDay[target];
      nextDay[target] = existing === undefined ? entries[key] : mergeDailyStats(existing, entries[key]);
    }
    next.daily[day] = nextDay;
  }
  return next;
}

/** Catalog keys are recomputed from each entry's stored song snapshot. */
export function remapCatalogEntries(
  entries: DownloadedSongEntry[],
  remap: Map<string, string>
): DownloadedSongEntry[] {
  const result: DownloadedSongEntry[] = [];
  const byKey = new Map<string, DownloadedSongEntry>();
  for (const entry of entries) {
    let nextKey = remap.get(entry.stableKey) ?? entry.stableKey;
    if (entry.songJson.length > 0) {
      try {
        nextKey = stableKeyOf(SongItem.fromJson(entry.songJson));
      } catch (error) {
        // Corrupt snapshot: keep the table-based key.
      }
    }
    const merged = new DownloadedSongEntry(nextKey, entry.audioPath, entry.songJson, entry.committedAt);
    const existing = byKey.get(nextKey);
    if (existing === undefined || merged.committedAt >= existing.committedAt) {
      if (existing !== undefined) {
        result.splice(result.indexOf(existing), 1);
      }
      byKey.set(nextKey, merged);
      result.push(merged);
    }
  }
  return result;
}
