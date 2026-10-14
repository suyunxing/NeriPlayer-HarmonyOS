// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import {
  NETEASE_PLAYLIST_ADD_BATCH_SIZE,
  NeteaseBatchAddResult,
  NeteaseFailedSongResolution,
  NeteaseWritebackResult,
  NeteaseWritebackDeps,
  resolveNeteaseSongId,
  buildNeteasePlaylistAddTracksParams,
  addNeteasePlaylistSongIdsInBatches,
  classifyNeteasePlaylistAddFailures,
  syncSongsToNeteasePlaylist
} from '../../../main/ets/network/NeteasePlaylistWriteback';

function neteaseSong(audioId: string): SongItem {
  const song = new SongItem(1, 'n', 'a', '', 0);
  song.platform = MusicPlatform.NETEASE;
  song.audioId = audioId;
  return song;
}

/** 二分下钻 fake：含坏 id 5 的批失败，并记录每批入参。 */
class BisectFakeDeps extends NeteaseWritebackDeps {
  calls: number[][] = [];

  async addBatch(_playlistId: number, ids: number[]): Promise<boolean> {
    this.calls.push(ids.slice());
    return !ids.includes(5);
  }
}

/** 分批 fake：按 batchSize 分批、第 6 首抛异常。 */
class ChunkFakeDeps extends NeteaseWritebackDeps {
  calls: number[][] = [];

  async addBatch(_playlistId: number, ids: number[]): Promise<boolean> {
    this.calls.push(ids.slice());
    if (ids.includes(6)) {
      throw new Error('boom');
    }
    return true;
  }
}

/** 归因 fake：id 3 视为下架（解析不到）。 */
class ClassifyFakeDeps extends NeteaseWritebackDeps {
  async resolveSongIds(ids: number[]): Promise<Set<number> | null> {
    const set = new Set<number>();
    for (const id of ids) {
      if (id === 3) {
        continue;
      }
      set.add(id);
    }
    return set;
  }
}

/** 编排 fake：首次快照含 11；复核快照含 11+12；12 的写回批报失败。 */
class OrchestrationFakeDeps extends NeteaseWritebackDeps {
  snapshotCalls: number = 0;

  async fetchTargetTrackIds(_playlistId: number): Promise<Set<number> | null> {
    this.snapshotCalls += 1;
    const set = new Set<number>();
    if (this.snapshotCalls === 1) {
      set.add(11);
    } else {
      set.add(11);
      set.add(12);
    }
    return set;
  }

  async addBatch(_playlistId: number, ids: number[]): Promise<boolean> {
    return !ids.includes(12);
  }

  async resolveSongIds(ids: number[]): Promise<Set<number> | null> {
    const set = new Set<number>();
    for (const id of ids) {
      set.add(id);
    }
    return set;
  }
}

// 上游 NeteasePlaylistTrackParamsTest / NeteasePlaylistBatchAddTest /
// NeteaseRemotePlaylistPicker 流程（#322）镜像。
export default function neteasePlaylistWritebackTest(): void {
  describe('NeteasePlaylistWriteback', () => {
    it('resolveNeteaseSongIdSupportsDirectAndMatched', 0, () => {
      expect(resolveNeteaseSongId(neteaseSong('12345'))).assertEqual(12345);
      const matched = new SongItem(2, 'b', 'a', '', 0, 0, '', '', MusicPlatform.BILIBILI);
      matched.matchedSongId = 'netease:777';
      expect(resolveNeteaseSongId(matched)).assertEqual(777);
      // 非网易匹配、无匹配的跨平台歌、坏数字都不可写回。
      const qqMatched = new SongItem(3, 'c', 'a', '', 0, 0, '', '', MusicPlatform.BILIBILI);
      qqMatched.matchedSongId = 'qq:777';
      expect(resolveNeteaseSongId(qqMatched)).assertEqual(0);
      expect(resolveNeteaseSongId(new SongItem(4, 'd', 'a', '', 0, 0, '', '', MusicPlatform.LOCAL)))
        .assertEqual(0);
      expect(resolveNeteaseSongId(neteaseSong('abc'))).assertEqual(0);
      expect(resolveNeteaseSongId(neteaseSong('-5'))).assertEqual(0);
    });

    it('buildManipulateTracksParamsMirrorsUpstreamShape', 0, () => {
      const params = buildNeteasePlaylistAddTracksParams(9, [3, 3, 7, 0, -1]);
      expect(params['op']).assertEqual('add');
      expect(params['pid']).assertEqual('9');
      expect(params['id']).assertEqual('9');
      expect(params['tracks']).assertEqual('3,7');
      expect(params['trackIds']).assertEqual('[3,7]');
      expect(params['imme']).assertEqual('true');
      let threw = false;
      try {
        buildNeteasePlaylistAddTracksParams(0, [1]);
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
      threw = false;
      try {
        buildNeteasePlaylistAddTracksParams(1, [0, -2]);
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('batchAddBisectsFailedBatchToIsolateBadSong', 0, async () => {
      // 整批 4 首里 5 是坏 id：二分下钻后 5 失败、其余成功；首层整批
      // 失败 → [1,3]/[5,7] → [5] 定罪。
      const deps = new BisectFakeDeps();
      const r: NeteaseBatchAddResult = await addNeteasePlaylistSongIdsInBatches(
        [1, 3, 5, 7], 50, deps, 99);
      expect(r.addedIds.has(1)).assertTrue();
      expect(r.addedIds.has(3)).assertTrue();
      expect(r.addedIds.has(7)).assertTrue();
      expect(r.failedIds.has(5)).assertTrue();
      expect(r.failedIds.size).assertEqual(1);
      expect(deps.calls.length >= 3).assertTrue();
    });

    it('batchAddRespectsBatchSizeAndRecoversFromThrows', 0, async () => {
      const deps = new ChunkFakeDeps();
      const r: NeteaseBatchAddResult = await addNeteasePlaylistSongIdsInBatches(
        [1, 2, 3, 4, 5, 6], 2, deps, 99);
      expect(r.addedIds.size).assertEqual(5);
      expect(r.failedIds.has(6)).assertTrue();
      // 3 个分批 + 末批抛错后的二分下钻（[5]、[6]）= 5 次调用，每批 ≤ 2。
      expect(deps.calls.length).assertEqual(5);
      for (const call of deps.calls) {
        expect(call.length <= 2).assertTrue();
      }
    });

    it('classifyFailuresSplitsUnresolvedFromUnsupported', 0, async () => {
      // 仍可解析=真失败；下架（解析不到）=跳过；resolveSongIds null 整批保留失败。
      const r: NeteaseFailedSongResolution = await classifyNeteasePlaylistAddFailures(
        [1, 2, 3], 300, new ClassifyFakeDeps());
      expect(r.unresolvedFailedIds.has(1)).assertTrue();
      expect(r.unresolvedFailedIds.has(2)).assertTrue();
      expect(r.unresolvedFailedIds.has(3)).assertFalse();
      expect(r.skippedUnsupported).assertEqual(1);

      const unknown: NeteaseFailedSongResolution = await classifyNeteasePlaylistAddFailures(
        [9], 300, new NeteaseWritebackDeps());
      expect(unknown.unresolvedFailedIds.has(9)).assertTrue();
      expect(unknown.skippedUnsupported).assertEqual(0);
    });

    it('syncOrchestratesSnapshotDedupeAndRecovery', 0, async () => {
      const songs: SongItem[] = [
        neteaseSong('10'),
        neteaseSong('11'),
        neteaseSong('12'),
        new SongItem(9, 'local', 'a', '', 0, 0, '', '', MusicPlatform.LOCAL)
      ];
      const deps = new OrchestrationFakeDeps();
      const r: NeteaseWritebackResult = await syncSongsToNeteasePlaylist(songs, 99, deps);
      expect(r.totalSongs).assertEqual(4);
      expect(r.supportedSongs).assertEqual(3);
      expect(r.skippedUnsupported).assertEqual(1);
      expect(r.skippedExisting).assertEqual(1);
      expect(r.added).assertEqual(2);
      expect(r.failed).assertEqual(0);
      expect(deps.snapshotCalls).assertEqual(2);
      expect(r.message.includes('已添加 2 首')).assertTrue();
    });

    it('syncHandlesEmptyAndCompareFailure', 0, async () => {
      const empty: NeteaseWritebackResult = await syncSongsToNeteasePlaylist([], 1,
        new NeteaseWritebackDeps());
      expect(empty.totalSongs).assertEqual(0);
      expect(empty.message.length > 0).assertTrue();

      // 基类 fetchTargetTrackIds 恒 null = 快照获取失败路径。
      const failed: NeteaseWritebackResult =
        await syncSongsToNeteasePlaylist([neteaseSong('5')], 1, new NeteaseWritebackDeps());
      expect(failed.failed).assertEqual(0);
      expect(failed.added).assertEqual(0);
      expect(failed.message.length > 0).assertTrue();
    });

    it('batchSizeConstantsMatchUpstream', 0, () => {
      expect(NETEASE_PLAYLIST_ADD_BATCH_SIZE).assertEqual(50);
    });
  });
}
