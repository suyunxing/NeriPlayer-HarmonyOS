// SPDX-License-Identifier: GPL-3.0
// 「本地音乐」系统歌单装配的单元测试（上游 LocalFilesPlaylist /
// SystemLocalPlaylists.normalize 的鸿蒙注入式形态，2026-10-13 反馈补齐）。

import { describe, it, expect } from '@ohos/hypium';
import { LocalPlaylistRepository } from '../../../main/ets/data/LocalPlaylistRepository';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';

function localSong(name: string, fileName: string): SongItem {
  const item = new SongItem(0, name, '本地艺人', '本地专辑', 0, 200000, '',
    `file://docs/storage/Users/currentUser/Music/${fileName}`, MusicPlatform.LOCAL);
  item.audioId = fileName;
  item.localFileName = fileName;
  return item;
}

export default function localMusicPlaylistTest(): void {
  describe('LocalMusicPlaylist', () => {
    it('buildLocalMusicPlaylist_mapsKeysInScanOrder', 0, () => {
      const songs = [localSong('晴天', 'a.mp3'), localSong('测试', 'b.flac')];
      const playlist = LocalPlaylistRepository.buildLocalMusicPlaylist(songs);
      expect(playlist.id).assertEqual(LocalPlaylistRepository.LOCAL_MUSIC_ID);
      expect(playlist.name).assertEqual('本地音乐');
      expect(playlist.songs.length).assertEqual(2);
      expect(playlist.songKeys.length).assertEqual(2);
      // 成员键按扫描顺序全量生成，与歌曲一一对应。
      expect(playlist.songKeys[0]).assertEqual(stableKeyOf(songs[0]));
      expect(playlist.songKeys[1]).assertEqual(stableKeyOf(songs[1]));
      // 稳定键互不相同：歌单内过滤视图按 stableKeyOf 定位点歌才能命中
      // 点击的那首——三元组 platform/audioId/id 对本地歌全部相同（LOCAL/
      // ''/0），不可用于列表定位（2026-10-13 真机反馈的点歌错位根因）。
      expect(playlist.songKeys[0] === playlist.songKeys[1]).assertFalse();
      // 引用保持：详情页直接以 songs 播放，无需再拷贝。
      expect(playlist.songs[0] === songs[0]).assertTrue();
    });

    it('buildLocalMusicPlaylist_emptyListYieldsEmptyView', 0, () => {
      const playlist = LocalPlaylistRepository.buildLocalMusicPlaylist([]);
      expect(playlist.id).assertEqual(LocalPlaylistRepository.LOCAL_MUSIC_ID);
      expect(playlist.songKeys.length).assertEqual(0);
      expect(playlist.songs.length).assertEqual(0);
      // 系统歌单不参与镜像同步。
      expect(playlist.syncSource).assertNull();
    });
  });
}
