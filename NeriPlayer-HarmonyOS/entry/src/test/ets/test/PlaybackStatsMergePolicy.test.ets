import { describe, it, expect } from '@ohos/hypium';
import {
  SyncTrackStat,
  SyncPlaybackStatBucket,
  SyncPlaybackCounterShard,
  trackStatMetadataEquals,
  bucketMetadataEquals
} from '../../../main/ets/sync/SyncModels';
import {
  merge,
  mergeBuckets,
  trimStats,
  trimBuckets,
  liftStatsToBucketTotals,
  finalizeMergedStats,
  MAX_TRACK_STATS,
  MAX_STAT_BUCKETS
} from '../../../main/ets/sync/PlaybackStatsMergePolicy';

const DAY: number = 86400000;

function trackStat(
  identityKey: string,
  totalListenMs: number,
  playCount: number,
  firstPlayedAt: number,
  lastPlayedAt: number,
  name: string = identityKey,
  counterBaseListenMs: number = 0,
  counterBasePlayCount: number = 0,
  counterShards: SyncPlaybackCounterShard[] = []
): SyncTrackStat {
  return new SyncTrackStat(identityKey, name, 'artist', 'album', totalListenMs,
    playCount, lastPlayedAt, firstPlayedAt, null, 0, null, 0, 0,
    counterBaseListenMs, counterBasePlayCount, counterShards);
}

function trackBucket(
  identityKey: string,
  dayStartAt: number,
  totalListenMs: number,
  playCount: number,
  firstPlayedAt: number,
  lastPlayedAt: number,
  name: string = identityKey
): SyncPlaybackStatBucket {
  return new SyncPlaybackStatBucket(dayStartAt, identityKey, name, 'artist', 'album',
    totalListenMs, playCount, lastPlayedAt, firstPlayedAt, null, 0, null, 0, 0, 0, 0, []);
}

function counterShard(
  deviceId: string,
  totalListenMs: number,
  playCount: number,
  firstPlayedAt: number,
  lastPlayedAt: number
): SyncPlaybackCounterShard {
  return new SyncPlaybackCounterShard(deviceId, 0, totalListenMs, playCount,
    firstPlayedAt, lastPlayedAt);
}

export default function playbackStatsMergePolicyTest(): void {
  describe('StatsClearBarrier', () => {
    it('dropsRemoteStatsRecordedBeforeClear', 0, () => {
      const merged = merge([], [trackStat('remote-old', 1000, 1, 100, 900)], 1000);
      expect(merged.length).assertEqual(0);
    });

    it('keepsStatsCreatedAfterClear', 0, () => {
      const remote = trackStat('remote-new', 1000, 1, 1100, 1200);
      const merged = merge([], [remote], 1000);
      expect(trackStatMetadataEquals(merged[0], remote)).assertTrue();
      expect(merged.length).assertEqual(1);
    });

    it('keepsStatsUpdatedAfterClearEvenWhenFirstPlayIsOld', 0, () => {
      const merged = merge([trackStat('local-resumed', 1000, 1, 100, 1200)], [], 1000);
      expect(merged.length).assertEqual(1);
      expect(merged[0].identityKey).assertEqual('local-resumed');
      expect(merged[0].firstPlayedAt).assertEqual(1200);
      expect(merged[0].lastPlayedAt).assertEqual(1200);
    });

    it('dropsStaleBuckets', 0, () => {
      const merged = mergeBuckets([], [trackBucket('old', 1000, 1000, 1, 1100, 1900)], 2000);
      expect(merged.length).assertEqual(0);
    });
  });

  describe('StatsCounterMerge', () => {
    it('mergeWithoutClearBarrierKeepsLargerCounters', 0, () => {
      const local = trackStat('same', 1000, 1, 100, 200);
      const remote = trackStat('same', 2000, 3, 50, 300, 'newer');
      const merged = merge([local], [remote], 0);
      expect(merged.length).assertEqual(1);
      expect(merged[0].name).assertEqual('newer');
      expect(merged[0].totalListenMs).assertEqual(2000);
      expect(merged[0].playCount).assertEqual(3);
      expect(merged[0].firstPlayedAt).assertEqual(50);
      expect(merged[0].lastPlayedAt).assertEqual(300);
    });

    it('mergeShardedCountersSumsIndependentDeviceDeltasOnce', 0, () => {
      const local = trackStat('same', 1500, 12, 100, 200, 'same',
        1000, 10, [counterShard('device-a', 500, 2, 150, 200)]);
      const remote = trackStat('same', 1700, 13, 100, 300, 'newer',
        1000, 10, [counterShard('device-b', 700, 3, 220, 300)]);
      const merged = merge([local], [remote], 0);
      expect(merged.length).assertEqual(1);
      expect(merged[0].name).assertEqual('newer');
      expect(merged[0].totalListenMs).assertEqual(2200);
      expect(merged[0].playCount).assertEqual(15);
      expect(merged[0].counterShards.length).assertEqual(2);

      const repeated = merge(merged, [remote], 0);
      expect(repeated[0].totalListenMs).assertEqual(2200);
      expect(repeated[0].playCount).assertEqual(15);
    });

    it('mergeMixedLegacyAndShardedCountersDoesNotDoubleCountLegacyBase', 0, () => {
      const legacyRemote = trackStat('same', 2000, 10, 100, 200);
      const local = trackStat('same', 2300, 11, 100, 300, 'same',
        2000, 10, [counterShard('device-a', 300, 1, 250, 300)]);
      const merged = merge([local], [legacyRemote], 0);
      expect(merged[0].totalListenMs).assertEqual(2300);
      expect(merged[0].playCount).assertEqual(11);
      expect(merged[0].counterShards.length).assertEqual(1);
    });

    it('mergeBucketsKeepsPerDayBreakdown', 0, () => {
      const local = trackBucket('same', DAY, 1000, 1, DAY + 1000, DAY + 2000);
      const remote = trackBucket('same', DAY, 2000, 3, DAY + 500, DAY + 3000, 'newer');
      const merged = mergeBuckets([local], [remote], 0);
      expect(merged.length).assertEqual(1);
      expect(merged[0].dayStartAt).assertEqual(DAY);
      expect(merged[0].name).assertEqual('newer');
      expect(merged[0].totalListenMs).assertEqual(2000);
      expect(merged[0].playCount).assertEqual(3);
      expect(merged[0].firstPlayedAt).assertEqual(DAY + 500);
      expect(merged[0].lastPlayedAt).assertEqual(DAY + 3000);
    });
  });

  describe('StatsTrim', () => {
    it('trimStatsCapsToMaxKeepingMostRecent', 0, () => {
      const stats: SyncTrackStat[] = [];
      for (let i = 1; i <= MAX_TRACK_STATS + 1; i++) {
        stats.push(trackStat(`k-${i}`, 1000, 1, 1, i));
      }
      const trimmed = trimStats(stats);
      expect(trimmed.length).assertEqual(MAX_TRACK_STATS);
      let min = Number.MAX_SAFE_INTEGER;
      for (const stat of trimmed) {
        if (stat.lastPlayedAt < min) {
          min = stat.lastPlayedAt;
        }
      }
      expect(min).assertEqual(2);
    });

    it('trimStatsKeepsDeterministicIdentityKeyOnTiesAtBoundary', 0, () => {
      const stats: SyncTrackStat[] = [];
      for (let i = 1; i <= MAX_TRACK_STATS - 1; i++) {
        stats.push(trackStat(`high-${i}`, 1000, 1, 1, 1000 + i));
      }
      const tieKept = trackStat('tie-a', 1000, 1, 1, 50);
      const tieDropped = trackStat('tie-b', 1000, 1, 1, 50);
      const trimmed = trimStats(stats.concat([tieDropped, tieKept]));
      expect(trimmed.length).assertEqual(MAX_TRACK_STATS);
      let keptA = false;
      let keptB = false;
      for (const stat of trimmed) {
        if (stat.identityKey === 'tie-a') {
          keptA = true;
        }
        if (stat.identityKey === 'tie-b') {
          keptB = true;
        }
      }
      expect(keptA).assertTrue();
      expect(keptB).assertFalse();
    });

    it('trimStatsIsIdempotent', 0, () => {
      const stats: SyncTrackStat[] = [];
      for (let i = 1; i <= MAX_TRACK_STATS + 5; i++) {
        stats.push(trackStat(`k-${i}`, 1000, 1, 1, i));
      }
      const once = trimStats(stats);
      const twice = trimStats(once);
      expect(once.length).assertEqual(twice.length);
      for (let i = 0; i < once.length; i++) {
        expect(once[i].identityKey).assertEqual(twice[i].identityKey);
      }
    });

    it('trimStatsUnderCapIsUnchanged', 0, () => {
      const stats = [
        trackStat('a', 1000, 1, 1, 10),
        trackStat('b', 1000, 1, 1, 20)
      ];
      const trimmed = trimStats(stats);
      expect(trimmed.length).assertEqual(2);
      expect(trimmed[0].identityKey).assertEqual('a');
      expect(trimmed[1].identityKey).assertEqual('b');
    });

    it('trimBucketsDropsBucketsOutsideRetentionWindow', 0, () => {
      const newest = trackBucket('a', 500 * DAY, 1000, 1, 1, 500 * DAY);
      const within = trackBucket('b', 200 * DAY, 1000, 1, 1, 200 * DAY);
      const outside = trackBucket('c', 50 * DAY, 1000, 1, 1, 50 * DAY);
      const trimmed = trimBuckets([newest, within, outside]);
      const days = new Set<number>();
      for (const bucket of trimmed) {
        days.add(bucket.dayStartAt);
      }
      expect(days.has(500 * DAY)).assertTrue();
      expect(days.has(200 * DAY)).assertTrue();
      expect(days.has(50 * DAY)).assertFalse();
    });

    it('trimBucketsWindowAnchorUsesDatasetMaxNotWallClock', 0, () => {
      const ancient = [
        trackBucket('a', 1 * DAY, 1000, 1, 1, 1 * DAY),
        trackBucket('b', 2 * DAY, 1000, 1, 1, 2 * DAY),
        trackBucket('c', 3 * DAY, 1000, 1, 1, 3 * DAY)
      ];
      const trimmed = trimBuckets(ancient);
      expect(trimmed.length).assertEqual(3);
    });

    it('trimBucketsCapsToMaxBucketsByPlayCount', 0, () => {
      const buckets: SyncPlaybackStatBucket[] = [];
      for (let i = 1; i <= MAX_STAT_BUCKETS + 1; i++) {
        buckets.push(trackBucket(`k-${i}`, 10 * DAY, 1000, i, 1, 10 * DAY));
      }
      const trimmed = trimBuckets(buckets);
      expect(trimmed.length).assertEqual(MAX_STAT_BUCKETS);
      let hasPlayCountOne = false;
      for (const bucket of trimmed) {
        if (bucket.playCount === 1) {
          hasPlayCountOne = true;
        }
      }
      expect(hasPlayCountOne).assertFalse();
    });

    it('trimBucketsIsIdempotentAcrossWindowAndCount', 0, () => {
      const buckets: SyncPlaybackStatBucket[] = [];
      for (let i = 1; i <= MAX_STAT_BUCKETS + 3; i++) {
        buckets.push(trackBucket(`k-${i}`, 500 * DAY, 1000, i, 1, 500 * DAY));
      }
      buckets.push(trackBucket('old', 10 * DAY, 1000, 1, 1, 10 * DAY));
      const once = trimBuckets(buckets);
      const twice = trimBuckets(once);
      expect(once.length).assertEqual(twice.length);
      for (let i = 0; i < once.length; i++) {
        expect(once[i].identityKey).assertEqual(twice[i].identityKey);
      }
    });
  });

  describe('StatsLift', () => {
    it('raisesStatTotalToBucketSum', 0, () => {
      const stats = [trackStat('song', 100, 1, 1, 2)];
      const buckets = [
        trackBucket('song', 1 * DAY, 120, 2, 1, 2),
        trackBucket('song', 2 * DAY, 180, 3, 1, 2)
      ];
      const lifted = liftStatsToBucketTotals(stats, buckets);
      expect(lifted[0].totalListenMs).assertEqual(300);
      expect(lifted[0].playCount).assertEqual(5);
    });

    it('neverLowersStatTotal', 0, () => {
      const stats = [trackStat('song', 500, 9, 1, 2)];
      const buckets = [trackBucket('song', 1 * DAY, 120, 2, 1, 2)];
      const lifted = liftStatsToBucketTotals(stats, buckets);
      expect(lifted[0].totalListenMs).assertEqual(500);
      expect(lifted[0].playCount).assertEqual(9);
    });

    it('guaranteesTotalNotBelowBucketSumAndIsIdempotent', 0, () => {
      const stats = [trackStat('song', 100, 1, 1, 2)];
      const buckets = [trackBucket('song', 1 * DAY, 200, 4, 1, 2)];
      const once = liftStatsToBucketTotals(stats, buckets);
      const twice = liftStatsToBucketTotals(once, buckets);
      expect(once[0].totalListenMs >= 200).assertTrue();
      expect(trackStatMetadataEquals(once[0], twice[0])).assertTrue();
    });
  });

  describe('StatsFinalize', () => {
    it('liftsUsingUntrimmedBucketsCoveringOutOfWindowSum', 0, () => {
      const newestDay = 500 * DAY;
      const stats = [trackStat('song', 100, 1, 1, newestDay)];
      const buckets = [
        trackBucket('song', newestDay, 120, 2, 1, newestDay),
        trackBucket('song', newestDay - 401 * DAY, 50, 1, 1, newestDay - 401 * DAY)
      ];
      const finalized = finalizeMergedStats(stats, buckets);
      // Full bucket sum = 120 + 50 = 170 / 2 + 1 = 3; trimming first would
      // only see 120 / 2 (desktop three_way_merge parity).
      expect(finalized.stats[0].totalListenMs).assertEqual(170);
      expect(finalized.stats[0].playCount).assertEqual(3);
      const days = new Set<number>();
      for (const bucket of finalized.buckets) {
        days.add(bucket.dayStartAt);
      }
      expect(days.size).assertEqual(1);
      expect(days.has(newestDay)).assertTrue();
    });

    it('appliesStatAndBucketCountCaps', 0, () => {
      const newestDay = 10 * DAY;
      const stats: SyncTrackStat[] = [];
      for (let i = 1; i <= MAX_TRACK_STATS + 5; i++) {
        stats.push(trackStat(`s-${i}`, 1000, 1, 1, i));
      }
      const buckets: SyncPlaybackStatBucket[] = [];
      for (let i = 1; i <= MAX_STAT_BUCKETS + 5; i++) {
        buckets.push(trackBucket(`b-${i}`, newestDay, 1000, i, 1, newestDay));
      }
      const finalized = finalizeMergedStats(stats, buckets);
      expect(finalized.stats.length).assertEqual(MAX_TRACK_STATS);
      expect(finalized.buckets.length).assertEqual(MAX_STAT_BUCKETS);
    });
  });
}
