import { AppPreferences } from './AppPreferences';

/**
 * Per-track playback statistics with a bounded daily-bucket window,
 * mirroring PlaybackStatsRepository.
 */
class TrackStats {
  playCount: number = 0;
  listenMs: number = 0;
  firstPlayedAt: number = 0;
  lastPlayedAt: number = 0;
}

export class PlaybackStatsRepository {
  private static readonly KEY: string = 'playback_stats';
  private static readonly BUCKET_DAYS: number = 30;

  static async recordPlay(songKey: string, listenMs: number): Promise<void> {
    const all = await PlaybackStatsRepository.loadStats();
    const today = PlaybackStatsRepository.dayKey(Date.now());
    let track = all.tracks[songKey];
    if (track === undefined) {
      track = new TrackStats();
      track.firstPlayedAt = Date.now();
      all.tracks[songKey] = track;
    }
    track.playCount += 1;
    track.listenMs += listenMs;
    track.lastPlayedAt = Date.now();
    const daily = all.daily[today];
    if (daily === undefined) {
      all.daily[today] = {};
    }
    all.daily[today][songKey] = (all.daily[today][songKey] ?? 0) + listenMs;
    // Trim buckets older than the window.
    const cutoff = PlaybackStatsRepository.dayKey(Date.now() - PlaybackStatsRepository.BUCKET_DAYS * 86400000);
    const trimmed: Record<string, Record<string, number>> = {};
    for (const key of Object.keys(all.daily)) {
      if (key >= cutoff) {
        trimmed[key] = all.daily[key];
      }
    }
    all.daily = trimmed;
    const json = JSON.stringify(all);
    await AppPreferences.putString(PlaybackStatsRepository.KEY, json);
  }

  static async getPlayCount(songKey: string): Promise<number> {
    const all = await PlaybackStatsRepository.loadStats();
    const track = all.tracks[songKey];
    return track === undefined ? 0 : track.playCount;
  }

  static async getTotalListenMs(): Promise<number> {
    const all = await PlaybackStatsRepository.loadStats();
    let total = 0;
    for (const key of Object.keys(all.tracks)) {
      total += all.tracks[key].listenMs;
    }
    return total;
  }

  static async getTotalPlayCount(): Promise<number> {
    const all = await PlaybackStatsRepository.loadStats();
    let total = 0;
    for (const key of Object.keys(all.tracks)) {
      total += all.tracks[key].playCount;
    }
    return total;
  }

  static async clear(): Promise<void> {
    await AppPreferences.putString(PlaybackStatsRepository.KEY, '{}');
  }

  private static async loadStats(): Promise<StatsRoot> {
    const json = await AppPreferences.getString(PlaybackStatsRepository.KEY, '{}');
    try {
      const parsed = JSON.parse(json) as Record<string, Object>;
      const root = new StatsRoot();
      const tracks = parsed['tracks'] as Record<string, Object> | undefined;
      if (tracks !== undefined) {
        for (const key of Object.keys(tracks)) {
          const raw = tracks[key] as Record<string, Object>;
          const stats = new TrackStats();
          stats.playCount = Number(raw['playCount'] ?? 0);
          stats.listenMs = Number(raw['listenMs'] ?? 0);
          stats.firstPlayedAt = Number(raw['firstPlayedAt'] ?? 0);
          stats.lastPlayedAt = Number(raw['lastPlayedAt'] ?? 0);
          root.tracks[key] = stats;
        }
      }
      const daily = parsed['daily'] as Record<string, Record<string, number>> | undefined;
      if (daily !== undefined) {
        root.daily = daily;
      }
      return root;
    } catch (error) {
      const e = error as Error;
      console.warn(`PlaybackStatsRepository.loadStats failed: ${e.message}`);
      return new StatsRoot();
    }
  }

  private static dayKey(timeMs: number): string {
    const date = new Date(timeMs);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }
}

class StatsRoot {
  tracks: Record<string, TrackStats> = {};
  daily: Record<string, Record<string, number>> = {};
}
