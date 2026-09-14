import { describe, it, expect } from '@ohos/hypium';
import {
  DailyTrackStats,
  PlaybackStatsRepository
} from '../../../main/ets/data/PlaybackStatsRepository';

function dayBucket(playCount: number): DailyTrackStats {
  const stats = new DailyTrackStats();
  stats.playCount = playCount;
  stats.listenMs = playCount * 1000;
  return stats;
}

export default function playbackStatsRetentionTest(): void {
  describe('PlaybackStatsRetention', () => {
    it('keepsBucketsInsideThe400DayWindow', 0, () => {
      const daily: Record<string, Record<string, DailyTrackStats>> = {
        '2025-01-01': { 'a|netease|': dayBucket(1) },
        '2026-01-01': { 'b|netease|': dayBucket(2) },
        '2026-09-14': { 'c|netease|': dayBucket(3) }
      };
      const trimmed = PlaybackStatsRepository.trimDailyBuckets(daily);
      // Newest bucket 2026-09-14 anchors the 400-day cutoff: 2025-01-01 is
      // out (over a year older), 2026-01-01 stays.
      expect(trimmed['2025-01-01']).assertUndefined();
      expect(trimmed['2026-01-01'] === undefined).assertFalse();
      expect(trimmed['2026-09-14'] === undefined).assertFalse();
    });

    it('keepsRecentWindowUntouchedUnderTheCap', 0, () => {
      const daily: Record<string, Record<string, DailyTrackStats>> = {
        '2026-09-12': { 'a|netease|': dayBucket(1) },
        '2026-09-13': { 'b|netease|': dayBucket(1) },
        '2026-09-14': { 'c|netease|': dayBucket(1) }
      };
      const trimmed = PlaybackStatsRepository.trimDailyBuckets(daily);
      expect(Object.keys(trimmed).length).assertEqual(3);
      expect(trimmed['2026-09-12']['a|netease|'].playCount).assertEqual(1);
    });

    it('enforcesThe8000BucketCapDroppingOldestDaysFirst', 0, () => {
      const daily: Record<string, Record<string, DailyTrackStats>> = {};
      // 8001 buckets spread over 8001 days: the oldest day must be dropped.
      const start = new Date(2020, 0, 1).getTime();
      for (let i = 0; i <= PlaybackStatsRepository.MAX_DAILY_BUCKETS; i++) {
        const key = PlaybackStatsRepository.dayKey(start + i * 86400000);
        daily[key] = {};
        daily[key][`song${i}|netease|`] = dayBucket(1);
      }
      const trimmed = PlaybackStatsRepository.trimDailyBuckets(daily);
      let total = 0;
      for (const day of Object.keys(trimmed)) {
        total += Object.keys(trimmed[day]).length;
      }
      expect(total).assertEqual(PlaybackStatsRepository.MAX_DAILY_BUCKETS);
      expect(trimmed['2020-01-01']).assertUndefined();
      expect(trimmed['2020-01-02'] === undefined).assertFalse();
    });

    it('returnsEmptyInputUnchanged', 0, () => {
      const trimmed = PlaybackStatsRepository.trimDailyBuckets({});
      expect(Object.keys(trimmed).length).assertEqual(0);
    });
  });
}
