import { SchemaStore } from './schema/SchemaStore';
import { util } from '@kit.ArkTS';
import { SyncDeletionStore } from '../sync/SyncDeletionStore';
import {
  SyncPlaybackCounterShard,
  normalizeCounterShards
} from '../sync/SyncModels';

/**
 * Per-track playback statistics with a bounded daily-bucket window,
 * mirroring PlaybackStatsRepository.
 */
export class TrackStats {
  playCount: number = 0;
  listenMs: number = 0;
  firstPlayedAt: number = 0;
  lastPlayedAt: number = 0;
  counterShards: SyncPlaybackCounterShard[] = [];
}

export class DailyTrackStats extends TrackStats {
}

export class PlaybackStatsRepository {
  private static readonly KEY: string = 'playback_stats';
  private static readonly BUCKET_DAYS: number = 30;

  static async recordPlay(songKey: string, listenMs: number): Promise<void> {
    const all = await PlaybackStatsRepository.loadStats();
    const now = Date.now();
    const today = PlaybackStatsRepository.dayKey(now);
    const deviceId = await SyncDeletionStore.getOrCreateDeviceId(
      (): string => util.generateRandomUUID(false));
    let track = all.tracks[songKey];
    if (track === undefined) {
      track = new TrackStats();
      track.firstPlayedAt = now;
      all.tracks[songKey] = track;
    }
    track.playCount += 1;
    track.listenMs += listenMs;
    track.lastPlayedAt = now;
    track.counterShards = PlaybackStatsRepository.recordCounterDelta(
      track.counterShards, deviceId, all.clearedAt, listenMs, 1, now);
    if (all.daily[today] === undefined) {
      all.daily[today] = {};
    }
    let daily = all.daily[today][songKey];
    if (daily === undefined) {
      daily = new DailyTrackStats();
      daily.firstPlayedAt = now;
      all.daily[today][songKey] = daily;
    }
    daily.playCount += 1;
    daily.listenMs += listenMs;
    daily.lastPlayedAt = now;
    daily.counterShards = PlaybackStatsRepository.recordCounterDelta(
      daily.counterShards, deviceId, all.clearedAt, listenMs, 1, now);
    // Trim buckets older than the window.
    const cutoff = PlaybackStatsRepository.dayKey(Date.now() - PlaybackStatsRepository.BUCKET_DAYS * 86400000);
    const trimmed: Record<string, Record<string, DailyTrackStats>> = {};
    for (const key of Object.keys(all.daily)) {
      if (key >= cutoff) {
        trimmed[key] = all.daily[key];
      }
    }
    all.daily = trimmed;
    const json = JSON.stringify(all);
    await SchemaStore.save(PlaybackStatsRepository.KEY, json, (value: string) => value);
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
    const root = new StatsRoot();
    root.clearedAt = Date.now();
    await PlaybackStatsRepository.replaceFromSync(root);
  }

  static async snapshot(): Promise<StatsRoot> {
    return PlaybackStatsRepository.loadStats();
  }

  static async replaceFromSync(root: StatsRoot): Promise<void> {
    await SchemaStore.save(PlaybackStatsRepository.KEY, JSON.stringify(root),
      (value: string) => value);
  }

  static parseJson(json: string): StatsRoot | null {
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
        stats.counterShards = PlaybackStatsRepository.parseCounterShards(raw['counterShards']);
        root.tracks[key] = stats;
      }
    }
    const daily = parsed['daily'] as Record<string, Record<string, Object>> | undefined;
    if (daily !== undefined) {
      for (const day of Object.keys(daily)) {
        root.daily[day] = {};
        for (const key of Object.keys(daily[day])) {
          const raw = daily[day][key];
          const stats = new DailyTrackStats();
          if (typeof raw === 'number') {
            stats.listenMs = raw;
          } else {
            const value = raw as Record<string, Object>;
            stats.playCount = Number(value['playCount'] ?? 0);
            stats.listenMs = Number(value['listenMs'] ?? 0);
            stats.firstPlayedAt = Number(value['firstPlayedAt'] ?? 0);
            stats.lastPlayedAt = Number(value['lastPlayedAt'] ?? 0);
            stats.counterShards = PlaybackStatsRepository.parseCounterShards(
              value['counterShards']);
          }
          root.daily[day][key] = stats;
        }
      }
    }
    root.clearedAt = Number(parsed['clearedAt'] ?? 0);
    return root;
  }

  private static async loadStats(): Promise<StatsRoot> {
    return SchemaStore.load<StatsRoot>(PlaybackStatsRepository.KEY, new StatsRoot(), PlaybackStatsRepository.parseJson);
  }

  private static dayKey(timeMs: number): string {
    const date = new Date(timeMs);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  private static parseCounterShards(raw: Object | undefined): SyncPlaybackCounterShard[] {
    if (!(raw instanceof Array)) {
      return [];
    }
    const items: Object[] = raw as Object[];
    const shards: SyncPlaybackCounterShard[] = [];
    for (const item of items) {
      const value = item as Record<string, Object>;
      shards.push(new SyncPlaybackCounterShard(
        String(value['deviceId'] ?? ''),
        Number(value['epochStartedAt'] ?? 0),
        Number(value['totalListenMs'] ?? 0),
        Number(value['playCount'] ?? 0),
        Number(value['firstPlayedAt'] ?? 0),
        Number(value['lastPlayedAt'] ?? 0)
      ));
    }
    return normalizeCounterShards(shards);
  }

  private static recordCounterDelta(shards: SyncPlaybackCounterShard[], deviceId: string,
    epochStartedAt: number, listenMs: number, playCount: number,
    playedAt: number): SyncPlaybackCounterShard[] {
    const normalized = normalizeCounterShards(shards);
    const result: SyncPlaybackCounterShard[] = [];
    let found = false;
    for (const shard of normalized) {
      if (shard.deviceId === deviceId && shard.epochStartedAt === epochStartedAt) {
        result.push(new SyncPlaybackCounterShard(
          deviceId,
          epochStartedAt,
          shard.totalListenMs + Math.max(listenMs, 0),
          shard.playCount + Math.max(playCount, 0),
          shard.firstPlayedAt > 0 ? Math.min(shard.firstPlayedAt, playedAt) : playedAt,
          Math.max(shard.lastPlayedAt, playedAt)
        ));
        found = true;
      } else {
        result.push(shard);
      }
    }
    if (!found) {
      result.push(new SyncPlaybackCounterShard(
        deviceId, epochStartedAt, Math.max(listenMs, 0), Math.max(playCount, 0),
        playedAt, playedAt));
    }
    return normalizeCounterShards(result);
  }
}

export class StatsRoot {
  tracks: Record<string, TrackStats> = {};
  daily: Record<string, Record<string, DailyTrackStats>> = {};
  clearedAt: number = 0;
}
