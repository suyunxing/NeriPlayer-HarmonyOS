// SPDX-License-Identifier: GPL-3.0

import { StatsRoot } from './PlaybackStatsRepository';
import { SongItem } from '../model/SongItem';

/**
 * Pure aggregation over the playback stats store (backlog §5.1, Android
 * PlaybackStatsScreen semantics): time-range bucket sums, per-track display
 * metadata attachment and per-artist grouping. All functions are pure so the
 * day-window and grouping behavior is unit-testable without preferences.
 */

export enum StatsTimeRange {
  DAY = 0,
  WEEK = 1,
  MONTH = 2,
  YEAR = 3,
  ALL = 4
}

export const STATS_RANGE_LABELS: string[] = ['今日', '近7天', '近30天', '近1年', '全部'];

export class AggregatedTrackStat {
  key: string = '';
  playCount: number = 0;
  listenMs: number = 0;
  lastPlayedAt: number = 0;
  // Display metadata attached from the local song index; may stay empty for
  // keys whose song object no longer exists anywhere.
  name: string = '';
  artist: string = '';
  coverUrl: string = '';
  durationMs: number = 0;
  song: SongItem | null = null;
}

export class AggregatedArtistStat {
  artist: string = '';
  playCount: number = 0;
  listenMs: number = 0;
  trackCount: number = 0;
  coverUrl: string = '';
}

function dayKeyOf(timeMs: number): string {
  const date = new Date(timeMs);
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/** First local day (inclusive, YYYY-MM-DD lexicographic compare) kept by the range. */
export function statsRangeCutoffDay(range: StatsTimeRange, nowMs: number): string {
  switch (range) {
    case StatsTimeRange.DAY:
      return dayKeyOf(nowMs);
    case StatsTimeRange.WEEK:
      return dayKeyOf(nowMs - 6 * 86400000);
    case StatsTimeRange.MONTH:
      return dayKeyOf(nowMs - 29 * 86400000);
    case StatsTimeRange.YEAR:
      return dayKeyOf(nowMs - 364 * 86400000);
    default:
      return '';
  }
}

/**
 * Sums play stats per stable key inside the range. ALL reads the lifetime
 * `tracks` table (authoritative totals); ranged reads the daily buckets so
 * 400-day-old plays fall out of 近1年 windows exactly like Android.
 */
export function aggregateTrackStats(
  root: StatsRoot,
  range: StatsTimeRange,
  nowMs: number
): AggregatedTrackStat[] {
  const byKey = new Map<string, AggregatedTrackStat>();
  const take = (key: string): AggregatedTrackStat => {
    let entry = byKey.get(key);
    if (entry === undefined) {
      entry = new AggregatedTrackStat();
      entry.key = key;
      byKey.set(key, entry);
    }
    return entry;
  };
  if (range === StatsTimeRange.ALL) {
    for (const key of Object.keys(root.tracks)) {
      const track = root.tracks[key];
      const entry = take(key);
      entry.playCount = track.playCount;
      entry.listenMs = track.listenMs;
      entry.lastPlayedAt = track.lastPlayedAt;
    }
  } else {
    const cutoff = statsRangeCutoffDay(range, nowMs);
    for (const day of Object.keys(root.daily)) {
      if (day < cutoff) {
        continue;
      }
      const entries = root.daily[day];
      for (const key of Object.keys(entries)) {
        const daily = entries[key];
        const entry = take(key);
        entry.playCount += daily.playCount;
        entry.listenMs += daily.listenMs;
        entry.lastPlayedAt = Math.max(entry.lastPlayedAt, daily.lastPlayedAt);
      }
    }
  }
  const result: AggregatedTrackStat[] = [];
  byKey.forEach((entry) => {
    if (entry.playCount > 0 || entry.listenMs > 0) {
      result.push(entry);
    }
  });
  return result;
}

/** Fills display metadata from the stableKey -> SongItem index (in place). */
export function attachTrackSongMeta(
  tracks: AggregatedTrackStat[],
  songsByKey: Map<string, SongItem>
): void {
  for (const track of tracks) {
    const song = songsByKey.get(track.key);
    if (song === undefined) {
      continue;
    }
    track.song = song;
    track.name = song.displayName;
    track.artist = song.displayArtist;
    track.coverUrl = song.effectiveCoverUrl;
    track.durationMs = song.durationMs;
  }
}

export function compareTracksByCountDesc(a: AggregatedTrackStat, b: AggregatedTrackStat): number {
  if (a.playCount !== b.playCount) {
    return a.playCount > b.playCount ? -1 : 1;
  }
  return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0);
}

export function compareTracksByListenMsDesc(a: AggregatedTrackStat, b: AggregatedTrackStat): number {
  if (a.listenMs !== b.listenMs) {
    return a.listenMs > b.listenMs ? -1 : 1;
  }
  return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0);
}

/** Groups track stats per artist; the cover comes from the top track. */
export function aggregateArtistStats(
  tracks: AggregatedTrackStat[],
  compare: (a: AggregatedTrackStat, b: AggregatedTrackStat) => number
): AggregatedArtistStat[] {
  const sorted = tracks.slice().sort(compare);
  const byArtist = new Map<string, AggregatedArtistStat>();
  for (const track of sorted) {
    const artist = track.artist.trim().length > 0 ? track.artist.trim() : '未知艺术家';
    let entry = byArtist.get(artist);
    if (entry === undefined) {
      entry = new AggregatedArtistStat();
      entry.artist = artist;
      byArtist.set(artist, entry);
    }
    entry.playCount += track.playCount;
    entry.listenMs += track.listenMs;
    entry.trackCount += 1;
    if (entry.coverUrl.length === 0 && track.coverUrl.length > 0) {
      entry.coverUrl = track.coverUrl;
    }
  }
  const result: AggregatedArtistStat[] = [];
  byArtist.forEach((entry) => {
    result.push(entry);
  });
  result.sort((a: AggregatedArtistStat, b: AggregatedArtistStat): number => {
    if (a.playCount !== b.playCount) {
      return a.playCount > b.playCount ? -1 : 1;
    }
    return a.artist < b.artist ? -1 : (a.artist > b.artist ? 1 : 0);
  });
  return result;
}
