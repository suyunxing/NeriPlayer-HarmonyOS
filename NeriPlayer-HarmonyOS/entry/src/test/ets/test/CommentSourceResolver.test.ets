// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import { resolveCommentSource } from '../../../main/ets/network/comments/CommentSourceResolver';
import { CommentPlatform } from '../../../main/ets/model/CommentModels';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

function neteaseSong(id: number, audioId: string): SongItem {
  const song = new SongItem(id, '晴天', '周杰伦', 'Netease 叶惠美', 9, 269000, '', '', MusicPlatform.NETEASE);
  song.channelId = 'netease';
  song.audioId = audioId;
  return song;
}

function biliSong(bvid: string, cid: string): SongItem {
  const song = new SongItem(0, '视频标题', 'UP主', 'Bilibili', 0, 240000, '', '', MusicPlatform.BILIBILI);
  song.channelId = 'bilibili';
  song.audioId = bvid;
  song.subAudioId = cid;
  return song;
}

export default function commentSourceResolverTest(): void {
  describe('CommentSourceResolverTest', () => {
    it('resolvesNeteaseByChannelIdWithAudioIdPreferred', 0, () => {
      const source = resolveCommentSource(neteaseSong(111, '222'));
      expect(source !== null).assertTrue();
      if (source === null) {
        return;
      }
      expect(source.platform).assertEqual(CommentPlatform.NETEASE);
      // audioId 数字优先于 SongItem.id。
      expect(source.resourceId).assertEqual(222);
      expect(source.secondaryId).assertNull();
      expect(source.subResourceId).assertNull();
    });

    it('neteaseFallsBackToSongIdThenNull', 0, () => {
      const fallback = resolveCommentSource(neteaseSong(333, ''));
      expect(fallback !== null).assertTrue();
      if (fallback !== null) {
        expect(fallback.resourceId).assertEqual(333);
      }
      expect(resolveCommentSource(neteaseSong(0, ''))).assertNull();
      expect(resolveCommentSource(null)).assertNull();
    });

    it('resolvesBiliByChannelIdWithBvidAndCid', 0, () => {
      const source = resolveCommentSource(biliSong('BV1xx411c7mD', '456'));
      expect(source !== null).assertTrue();
      if (source === null) {
        return;
      }
      expect(source.platform).assertEqual(CommentPlatform.BILIBILI);
      // 鸿蒙 B 站歌曲 audioId 是 bvid：resourceId 占位 0，由仓库解析 avid。
      expect(source.resourceId).assertEqual(0);
      expect(source.secondaryId).assertEqual('BV1xx411c7mD');
      expect(source.subResourceId).assertEqual(456);
      expect(source.hasExplicitResourceId).assertFalse();
      expect(source.key()).assertEqual('BILIBILI:0');
    });

    it('fallsBackToAlbumPrefixWhenChannelMissing', 0, () => {
      const noChannel = new SongItem(777, 'n', 'a', 'Bilibili 分区', 0, 1000, '', '', MusicPlatform.BILIBILI);
      noChannel.audioId = 'BV1ab';
      const bili = resolveCommentSource(noChannel);
      expect(bili !== null).assertTrue();
      if (bili !== null) {
        expect(bili.platform).assertEqual(CommentPlatform.BILIBILI);
        expect(bili.secondaryId).assertEqual('BV1ab');
      }

      const neteaseAlbum = new SongItem(888, 'n', 'a', 'Netease 来源', 0, 1000, '', '', MusicPlatform.NETEASE);
      neteaseAlbum.audioId = '888';
      const netease = resolveCommentSource(neteaseAlbum);
      expect(netease !== null).assertTrue();
      if (netease !== null) {
        expect(netease.platform).assertEqual(CommentPlatform.NETEASE);
      }
    });

    it('returnsNullForUnsupportedSources', 0, () => {
      // 本地歌曲：无 channelId、album 无平台前缀。
      const local = new SongItem(1, '本地', 'a', '本地专辑', 0, 1, '', '', MusicPlatform.LOCAL);
      expect(resolveCommentSource(local)).assertNull();
      // YouTube Music：channelId 是身份专辑标记，不是评论平台。
      const ytm = new SongItem(0, 'ytm', 'a', 'YouTube Music', 0, 1, '', '', MusicPlatform.YOUTUBE_MUSIC);
      ytm.channelId = 'youtube_music';
      ytm.audioId = 'vid';
      expect(resolveCommentSource(ytm)).assertNull();
    });

    it('sameVideoKeyIsStableAcrossCidVariants', 0, () => {
      const first = resolveCommentSource(biliSong('BV1same', '1'));
      const second = resolveCommentSource(biliSong('BV1same', '2'));
      expect(first !== null && second !== null).assertTrue();
      if (first !== null && second !== null) {
        expect(first.key()).assertEqual(second.key());
      }
    });
  });

}
