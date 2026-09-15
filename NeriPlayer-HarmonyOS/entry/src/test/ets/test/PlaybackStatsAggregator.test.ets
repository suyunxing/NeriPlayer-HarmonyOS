import { describe, it, expect } from '@ohos/hypium';
import {
  StatsTimeRange,
  aggregateTrackStats,
  attachTrackSongMeta,
  aggregateArtistStats,
  compareTracksByCountDesc,
  compareTracksByListenMsDesc,
  statsRangeCutoffDay
} from '../../../main/ets/data/PlaybackStatsAggregator';
import { DailyTrackStats, StatsRoot, TrackStats } from '../../../main/ets/data/PlaybackStatsRepository';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

function bucket(playCount: number, listenMs: number): DailyTrackStats {
  const stats = new DailyTrackStats();
  stats.playCount = playCount;
  stats.listenMs = listenMs;
  return stats;
}

function root(): StatsRoot {
  const root = new StatsRoot();
  const lifetime = new TrackStats();
  lifetime.playCount = 10;
  lifetime.listenMs = 100000;
  root.tracks['123|netease|'] = lifetime;
  root.daily['2026-09-14'] = { '123|netease|': bucket(3, 30000), '456|bilibili|': bucket(2, 20000) };
  root.daily['2026-09-01'] = { '123|netease|': bucket(4, 40000) };
  root.daily['2025-09-14'] = { '123|netease|': bucket(3, 30000) };
  return root;
}

export default function playbackStatsAggregatorTest(): void {
  describe('PlaybackStatsAggregator', () => {
    it('allRangeReadsLifetimeTotals', 0, () => {
      const tracks = aggregateTrackStats(root(), StatsTimeRange.ALL, Date.parse('2026-09-14T12:00:00'));
      expect(tracks.length).assertEqual(1);
      expect(tracks[0].playCount).assertEqual(10);
      expect(tracks[0].listenMs).assertEqual(100000);
    });

    it('dayRangeOnlyCountsTodayBuckets', 0, () => {
      const now = Date.parse('2026-09-14T12:00:00');
      const tracks = aggregateTrackStats(root(), StatsTimeRange.DAY, now);
      expect(tracks.length).assertEqual(2);
      const sorted = tracks.sort(compareTracksByCountDesc);
      expect(sorted[0].key).assertEqual('123|netease|');
      expect(sorted[0].playCount).assertEqual(3);
      expect(sorted[1].playCount).assertEqual(2);
    });

    it('monthRangeIncludesRecentExcludesYearOld', 0, () => {
      const now = Date.parse('2026-09-14T12:00:00');
      const tracks = aggregateTrackStats(root(), StatsTimeRange.MONTH, now);
      // 2025-09-14 is ~365 days old: out of the 30-day window.
      const netease = tracks.find((t) => t.key === '123|netease|');
      expect(netease === undefined).assertFalse();
      expect(netease!.playCount).assertEqual(7);
    });

    it('yearRangeIncludesYearOldBuckets', 0, () => {
      const now = Date.parse('2026-09-14T12:00:00');
      const tracks = aggregateTrackStats(root(), StatsTimeRange.YEAR, now);
      const netease = tracks.find((t) => t.key === '123|netease|');
      expect(netease!.playCount).assertEqual(10);
    });

    it('cutoffDayUsesLocalCalendarDays', 0, () => {
      const now = Date.parse('2026-09-14T23:59:00');
      expect(statsRangeCutoffDay(StatsTimeRange.DAY, now)).assertEqual('2026-09-14');
      expect(statsRangeCutoffDay(StatsTimeRange.WEEK, now)).assertEqual('2026-09-08');
    });

    it('attachMetaFillsDisplayFields', 0, () => {
      const song = new SongItem(123, '歌曲', '歌手', 'album', 0);
      song.channelId = 'netease';
      song.audioId = '123';
      song.durationMs = 200000;
      const tracks = aggregateTrackStats(root(), StatsTimeRange.DAY, Date.parse('2026-09-14T12:00:00'));
      attachTrackSongMeta(tracks, new Map<string, SongItem>([['123|netease|', song]]));
      const netease = tracks.find((t) => t.key === '123|netease|');
      expect(netease!.name).assertEqual('歌曲');
      expect(netease!.artist).assertEqual('歌手');
      expect(netease!.durationMs).assertEqual(200000);
      expect(netease!.song === null).assertFalse();
      // Unresolvable keys keep placeholders.
      const bili = tracks.find((t) => t.key === '456|bilibili|');
      expect(bili!.name).assertEqual('');
    });

    it('artistAggregationGroupsAndRanks', 0, () => {
      const now = Date.parse('2026-09-14T12:00:00');
      const tracks = aggregateTrackStats(root(), StatsTimeRange.DAY, now);
      const songs = new Map<string, SongItem>();
      const a = new SongItem(123, 'A1', '歌手甲', 'x', 0);
      a.channelId = 'netease';
      a.audioId = '123';
      const b = new SongItem(456, 'B1', '歌手甲', 'x', 0);
      b.channelId = 'bilibili';
      b.audioId = '456';
      songs.set('123|netease|', a);
      songs.set('456|bilibili|', b);
      attachTrackSongMeta(tracks, songs);
      const artists = aggregateArtistStats(tracks, compareTracksByCountDesc);
      expect(artists.length).assertEqual(1);
      expect(artists[0].artist).assertEqual('歌手甲');
      expect(artists[0].playCount).assertEqual(5);
      expect(artists[0].trackCount).assertEqual(2);
    });

    it('durationSortOrdersByListenMs', 0, () => {
      const tracks = aggregateTrackStats(root(), StatsTimeRange.DAY, Date.parse('2026-09-14T12:00:00'));
      const sorted = tracks.sort(compareTracksByListenMsDesc);
      expect(sorted[0].key).assertEqual('123|netease|');
      expect(sorted[0].listenMs).assertEqual(30000);
    });

    it('emptyRootYieldsEmptyList', 0, () => {
      expect(aggregateTrackStats(new StatsRoot(), StatsTimeRange.ALL, 0).length).assertEqual(0);
    });
  });
}
