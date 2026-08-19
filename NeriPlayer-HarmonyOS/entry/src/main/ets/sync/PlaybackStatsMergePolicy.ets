/**
 * Port of data/sync/github/SyncPlaybackStatsMergePolicy.kt.
 *
 * Stats merging is a pure max/union two-way merge (no base): it converges even
 * if endpoints drift, as long as trim thresholds and the finalize order
 * (lift with untrimmed buckets, then trim) stay identical to the desktop
 * implementation — otherwise both sides keep echoing each other's trimmed data.
 */
import {
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaybackCounterShard,
  normalizeCounterShards
} from './SyncModels';

export const MAX_TRACK_STATS: number = 2000;
export const BUCKET_RETENTION_DAYS: number = 400;
export const MAX_STAT_BUCKETS: number = 8000;
const MILLIS_PER_DAY: number = 86400000;

export function shouldKeepStatAfterClear(stat: SyncTrackStat, playbackStatsClearedAt: number): boolean {
  if (playbackStatsClearedAt <= 0) {
    return true;
  }
  return stat.lastPlayedAt >= playbackStatsClearedAt;
}

export function shouldKeepBucketAfterClear(
  bucket: SyncPlaybackStatBucket,
  playbackStatsClearedAt: number
): boolean {
  if (playbackStatsClearedAt <= 0) {
    return true;
  }
  return bucket.lastPlayedAt >= playbackStatsClearedAt;
}

function counterBaseListenMsOf(
  totalListenMs: number,
  counterBaseListenMs: number,
  counterShards: SyncPlaybackCounterShard[]
): number {
  if (counterShards.length === 0 && counterBaseListenMs === 0) {
    return Math.max(totalListenMs, 0);
  }
  return Math.max(counterBaseListenMs, 0);
}

function counterBasePlayCountOf(
  playCount: number,
  counterBasePlayCount: number,
  counterShards: SyncPlaybackCounterShard[]
): number {
  if (counterShards.length === 0 && counterBasePlayCount === 0) {
    return Math.max(playCount, 0);
  }
  return Math.max(counterBasePlayCount, 0);
}

class CounterMergeResult {
  totalListenMs: number;
  playCount: number;
  firstPlayedAt: number;
  lastPlayedAt: number;
  baseListenMs: number;
  basePlayCount: number;
  shards: SyncPlaybackCounterShard[];

  constructor(
    totalListenMs: number,
    playCount: number,
    firstPlayedAt: number,
    lastPlayedAt: number,
    baseListenMs: number,
    basePlayCount: number,
    shards: SyncPlaybackCounterShard[]
  ) {
    this.totalListenMs = totalListenMs;
    this.playCount = playCount;
    this.firstPlayedAt = firstPlayedAt;
    this.lastPlayedAt = lastPlayedAt;
    this.baseListenMs = baseListenMs;
    this.basePlayCount = basePlayCount;
    this.shards = shards;
  }
}

function minPositivePlayedAt(left: number, right: number): number {
  if (left <= 0) {
    return right;
  }
  if (right <= 0) {
    return left;
  }
  return Math.min(left, right);
}

function mergeCounters(
  existingTotalListenMs: number,
  existingPlayCount: number,
  existingFirstPlayedAt: number,
  existingLastPlayedAt: number,
  existingBaseListenMs: number,
  existingBasePlayCount: number,
  existingShards: SyncPlaybackCounterShard[],
  incomingTotalListenMs: number,
  incomingPlayCount: number,
  incomingFirstPlayedAt: number,
  incomingLastPlayedAt: number,
  incomingBaseListenMs: number,
  incomingBasePlayCount: number,
  incomingShards: SyncPlaybackCounterShard[]
): CounterMergeResult {
  const shards = normalizeCounterShards(existingShards.concat(incomingShards));
  if (shards.length === 0) {
    return new CounterMergeResult(
      Math.max(Math.max(existingTotalListenMs, incomingTotalListenMs), 0),
      Math.max(Math.max(existingPlayCount, incomingPlayCount), 0),
      minPositivePlayedAt(existingFirstPlayedAt, incomingFirstPlayedAt),
      Math.max(existingLastPlayedAt, incomingLastPlayedAt),
      0,
      0,
      []
    );
  }

  const baseListenMs = Math.max(Math.max(existingBaseListenMs, incomingBaseListenMs), 0);
  const basePlayCount = Math.max(Math.max(existingBasePlayCount, incomingBasePlayCount), 0);
  let shardListenMs = baseListenMs;
  let shardPlayCount = basePlayCount;
  let shardMinFirstPlayedAt = 0;
  let shardMaxLastPlayedAt = 0;
  for (const shard of shards) {
    shardListenMs += Math.max(shard.totalListenMs, 0);
    shardPlayCount += Math.max(shard.playCount, 0);
    if (shard.firstPlayedAt > 0 &&
      (shardMinFirstPlayedAt === 0 || shard.firstPlayedAt < shardMinFirstPlayedAt)) {
      shardMinFirstPlayedAt = shard.firstPlayedAt;
    }
    if (shard.lastPlayedAt > shardMaxLastPlayedAt) {
      shardMaxLastPlayedAt = shard.lastPlayedAt;
    }
  }
  return new CounterMergeResult(
    Math.max(Math.max(shardListenMs, existingTotalListenMs), incomingTotalListenMs),
    Math.max(Math.max(shardPlayCount, existingPlayCount), incomingPlayCount),
    minPositivePlayedAt(
      minPositivePlayedAt(existingFirstPlayedAt, incomingFirstPlayedAt),
      shardMinFirstPlayedAt
    ),
    Math.max(Math.max(existingLastPlayedAt, incomingLastPlayedAt), shardMaxLastPlayedAt),
    baseListenMs,
    basePlayCount,
    shards
  );
}

function normalizeStatAfterClear(
  stat: SyncTrackStat,
  playbackStatsClearedAt: number
): SyncTrackStat | null {
  if (!shouldKeepStatAfterClear(stat, playbackStatsClearedAt)) {
    return null;
  }
  const counterShards = normalizeCounterShards(stat.counterShards);
  if (playbackStatsClearedAt <= 0) {
    return new SyncTrackStat(
      stat.identityKey, stat.name, stat.artist, stat.album, stat.totalListenMs,
      stat.playCount, stat.lastPlayedAt, stat.firstPlayedAt, stat.coverUrl,
      stat.durationMs, stat.mediaUri, stat.id, stat.albumId,
      stat.counterBaseListenMs, stat.counterBasePlayCount, counterShards
    );
  }
  const normalizedFirstPlayedAt =
    stat.firstPlayedAt >= playbackStatsClearedAt && stat.firstPlayedAt <= stat.lastPlayedAt
      ? stat.firstPlayedAt
      : stat.lastPlayedAt;
  const survivingShards: SyncPlaybackCounterShard[] = [];
  for (const shard of counterShards) {
    if (shard.lastPlayedAt >= playbackStatsClearedAt) {
      survivingShards.push(shard);
    }
  }
  return new SyncTrackStat(
    stat.identityKey, stat.name, stat.artist, stat.album, stat.totalListenMs,
    stat.playCount, stat.lastPlayedAt, normalizedFirstPlayedAt, stat.coverUrl,
    stat.durationMs, stat.mediaUri, stat.id, stat.albumId,
    counterShards.length === 0 ? stat.counterBaseListenMs : 0,
    counterShards.length === 0 ? stat.counterBasePlayCount : 0,
    normalizeCounterShards(survivingShards)
  );
}

function normalizeBucketAfterClear(
  bucket: SyncPlaybackStatBucket,
  playbackStatsClearedAt: number
): SyncPlaybackStatBucket | null {
  if (!shouldKeepBucketAfterClear(bucket, playbackStatsClearedAt)) {
    return null;
  }
  const counterShards = normalizeCounterShards(bucket.counterShards);
  if (playbackStatsClearedAt <= 0) {
    return new SyncPlaybackStatBucket(
      bucket.dayStartAt, bucket.identityKey, bucket.name, bucket.artist, bucket.album,
      bucket.totalListenMs, bucket.playCount, bucket.lastPlayedAt, bucket.firstPlayedAt,
      bucket.coverUrl, bucket.durationMs, bucket.mediaUri, bucket.id, bucket.albumId,
      bucket.counterBaseListenMs, bucket.counterBasePlayCount, counterShards
    );
  }
  const normalizedFirstPlayedAt =
    bucket.firstPlayedAt >= playbackStatsClearedAt && bucket.firstPlayedAt <= bucket.lastPlayedAt
      ? bucket.firstPlayedAt
      : bucket.lastPlayedAt;
  const survivingShards: SyncPlaybackCounterShard[] = [];
  for (const shard of counterShards) {
    if (shard.lastPlayedAt >= playbackStatsClearedAt) {
      survivingShards.push(shard);
    }
  }
  return new SyncPlaybackStatBucket(
    bucket.dayStartAt, bucket.identityKey, bucket.name, bucket.artist, bucket.album,
    bucket.totalListenMs, bucket.playCount, bucket.lastPlayedAt, normalizedFirstPlayedAt,
    bucket.coverUrl, bucket.durationMs, bucket.mediaUri, bucket.id, bucket.albumId,
    counterShards.length === 0 ? bucket.counterBaseListenMs : 0,
    counterShards.length === 0 ? bucket.counterBasePlayCount : 0,
    normalizeCounterShards(survivingShards)
  );
}

function mergeStat(existing: SyncTrackStat, stat: SyncTrackStat): SyncTrackStat {
  const newer = stat.lastPlayedAt >= existing.lastPlayedAt ? stat : existing;
  const counter = mergeCounters(
    existing.totalListenMs, existing.playCount, existing.firstPlayedAt, existing.lastPlayedAt,
    counterBaseListenMsOf(existing.totalListenMs, existing.counterBaseListenMs, existing.counterShards),
    counterBasePlayCountOf(existing.playCount, existing.counterBasePlayCount, existing.counterShards),
    existing.counterShards,
    stat.totalListenMs, stat.playCount, stat.firstPlayedAt, stat.lastPlayedAt,
    counterBaseListenMsOf(stat.totalListenMs, stat.counterBaseListenMs, stat.counterShards),
    counterBasePlayCountOf(stat.playCount, stat.counterBasePlayCount, stat.counterShards),
    stat.counterShards
  );
  return new SyncTrackStat(
    stat.identityKey,
    newer.name,
    newer.artist,
    newer.album,
    counter.totalListenMs,
    counter.playCount,
    counter.lastPlayedAt,
    counter.firstPlayedAt,
    newer.coverUrl,
    newer.durationMs,
    newer.mediaUri,
    newer.id,
    newer.albumId,
    counter.baseListenMs,
    counter.basePlayCount,
    counter.shards
  );
}

function mergeBucket(existing: SyncPlaybackStatBucket, bucket: SyncPlaybackStatBucket): SyncPlaybackStatBucket {
  const newer = bucket.lastPlayedAt >= existing.lastPlayedAt ? bucket : existing;
  const counter = mergeCounters(
    existing.totalListenMs, existing.playCount, existing.firstPlayedAt, existing.lastPlayedAt,
    counterBaseListenMsOf(existing.totalListenMs, existing.counterBaseListenMs, existing.counterShards),
    counterBasePlayCountOf(existing.playCount, existing.counterBasePlayCount, existing.counterShards),
    existing.counterShards,
    bucket.totalListenMs, bucket.playCount, bucket.firstPlayedAt, bucket.lastPlayedAt,
    counterBaseListenMsOf(bucket.totalListenMs, bucket.counterBaseListenMs, bucket.counterShards),
    counterBasePlayCountOf(bucket.playCount, bucket.counterBasePlayCount, bucket.counterShards),
    bucket.counterShards
  );
  return new SyncPlaybackStatBucket(
    existing.dayStartAt,
    existing.identityKey,
    newer.name,
    newer.artist,
    newer.album,
    counter.totalListenMs,
    counter.playCount,
    counter.lastPlayedAt,
    counter.firstPlayedAt,
    newer.coverUrl,
    newer.durationMs,
    newer.mediaUri,
    newer.id,
    newer.albumId,
    counter.baseListenMs,
    counter.basePlayCount,
    counter.shards
  );
}

export function merge(
  local: SyncTrackStat[],
  remote: SyncTrackStat[],
  playbackStatsClearedAt: number
): SyncTrackStat[] {
  const merged = new Map<string, SyncTrackStat>();
  for (const source of local.concat(remote)) {
    const stat = normalizeStatAfterClear(source, playbackStatsClearedAt);
    if (stat === null) {
      continue;
    }
    const existing = merged.get(stat.identityKey);
    merged.set(stat.identityKey, existing === undefined ? stat : mergeStat(existing, stat));
  }
  const result: SyncTrackStat[] = [];
  merged.forEach((stat: SyncTrackStat) => {
    result.push(stat);
  });
  return result;
}

export function mergeBuckets(
  local: SyncPlaybackStatBucket[],
  remote: SyncPlaybackStatBucket[],
  playbackStatsClearedAt: number
): SyncPlaybackStatBucket[] {
  const merged = new Map<string, SyncPlaybackStatBucket>();
  for (const source of local.concat(remote)) {
    const bucket = normalizeBucketAfterClear(source, playbackStatsClearedAt);
    if (bucket === null) {
      continue;
    }
    const key = `${bucket.dayStartAt}\u0000${bucket.identityKey}`;
    const existing = merged.get(key);
    merged.set(key, existing === undefined ? bucket : mergeBucket(existing, bucket));
  }
  const result: SyncPlaybackStatBucket[] = [];
  merged.forEach((bucket: SyncPlaybackStatBucket) => {
    result.push(bucket);
  });
  return result;
}

function compareStatsForTrim(a: SyncTrackStat, b: SyncTrackStat): number {
  if (a.lastPlayedAt !== b.lastPlayedAt) {
    return a.lastPlayedAt > b.lastPlayedAt ? -1 : 1;
  }
  if (a.identityKey !== b.identityKey) {
    return a.identityKey < b.identityKey ? -1 : 1;
  }
  return 0;
}

/** Keep the MAX_TRACK_STATS most recently played stats; ties by identityKey. Idempotent. */
export function trimStats(stats: SyncTrackStat[]): SyncTrackStat[] {
  if (stats.length <= MAX_TRACK_STATS) {
    return stats;
  }
  return stats.slice().sort(compareStatsForTrim).slice(0, MAX_TRACK_STATS);
}

function compareBucketsForTrim(a: SyncPlaybackStatBucket, b: SyncPlaybackStatBucket): number {
  if (a.dayStartAt !== b.dayStartAt) {
    return a.dayStartAt > b.dayStartAt ? -1 : 1;
  }
  if (a.playCount !== b.playCount) {
    return a.playCount > b.playCount ? -1 : 1;
  }
  if (a.identityKey !== b.identityKey) {
    return a.identityKey < b.identityKey ? -1 : 1;
  }
  return 0;
}

/** Retention window anchored at the dataset's max dayStartAt (never wall clock). */
export function trimBuckets(buckets: SyncPlaybackStatBucket[]): SyncPlaybackStatBucket[] {
  if (buckets.length === 0) {
    return buckets;
  }
  let maxDayStartAt = buckets[0].dayStartAt;
  for (const bucket of buckets) {
    if (bucket.dayStartAt > maxDayStartAt) {
      maxDayStartAt = bucket.dayStartAt;
    }
  }
  const cutoff = maxDayStartAt - BUCKET_RETENTION_DAYS * MILLIS_PER_DAY;
  const windowed: SyncPlaybackStatBucket[] = [];
  for (const bucket of buckets) {
    if (bucket.dayStartAt >= cutoff) {
      windowed.push(bucket);
    }
  }
  if (windowed.length <= MAX_STAT_BUCKETS) {
    return windowed;
  }
  return windowed.slice().sort(compareBucketsForTrim).slice(0, MAX_STAT_BUCKETS);
}

/** Monotonic lift: per-track totals never below the sum of their buckets. */
export function liftStatsToBucketTotals(
  stats: SyncTrackStat[],
  buckets: SyncPlaybackStatBucket[]
): SyncTrackStat[] {
  if (stats.length === 0) {
    return stats;
  }
  const bucketListenByKey = new Map<string, number>();
  const bucketPlayByKey = new Map<string, number>();
  for (const bucket of buckets) {
    const key = bucket.identityKey;
    bucketListenByKey.set(key,
      (bucketListenByKey.get(key) ?? 0) + Math.max(bucket.totalListenMs, 0));
    bucketPlayByKey.set(key,
      (bucketPlayByKey.get(key) ?? 0) + Math.max(bucket.playCount, 0));
  }
  return stats.map((stat: SyncTrackStat): SyncTrackStat => {
    const liftedListen = Math.max(stat.totalListenMs, bucketListenByKey.get(stat.identityKey) ?? 0);
    const liftedPlayLong = Math.max(stat.playCount, bucketPlayByKey.get(stat.identityKey) ?? 0);
    const liftedPlay = Math.min(liftedPlayLong, 2147483647);
    if (liftedListen === stat.totalListenMs && liftedPlay === stat.playCount) {
      return stat;
    }
    return new SyncTrackStat(
      stat.identityKey, stat.name, stat.artist, stat.album, liftedListen,
      liftedPlay, stat.lastPlayedAt, stat.firstPlayedAt, stat.coverUrl,
      stat.durationMs, stat.mediaUri, stat.id, stat.albumId,
      stat.counterBaseListenMs, stat.counterBasePlayCount, stat.counterShards
    );
  });
}

export class FinalizedPlaybackStats {
  stats: SyncTrackStat[];
  buckets: SyncPlaybackStatBucket[];

  constructor(stats: SyncTrackStat[], buckets: SyncPlaybackStatBucket[]) {
    this.stats = stats;
    this.buckets = buckets;
  }
}

/**
 * Finalize order must match the desktop three_way_merge verbatim: lift with
 * the UNTRIMMED merged buckets first, then trim both collections. Trimming
 * first would exclude out-of-window buckets from the lift and the per-track
 * totals would never converge across endpoints.
 */
export function finalizeMergedStats(
  mergedStats: SyncTrackStat[],
  mergedBuckets: SyncPlaybackStatBucket[]
): FinalizedPlaybackStats {
  const liftedStats = liftStatsToBucketTotals(mergedStats, mergedBuckets);
  return new FinalizedPlaybackStats(trimStats(liftedStats), trimBuckets(mergedBuckets));
}
