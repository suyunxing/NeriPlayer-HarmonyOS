// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import {
  ExploreLinkKind,
  recognizeExploreLink,
  extractExploreHttpUrl
} from '../../../main/ets/network/ExploreLinkRecognizer';

// 上游 ExploreLinkRecognizerTest / ExploreBiliLinkResolutionTest
// （a8440275/1dbb2964）镜像。
export default function exploreLinkRecognizerTest(): void {
  describe('ExploreLinkRecognizer', () => {
    it('recognizesNeteaseSongPlaylistAndHashRoutes', 0, () => {
      const song = recognizeExploreLink('https://music.163.com/song/?id=186016');
      expect(song !== null).assertTrue();
      expect(song?.kind).assertEqual(ExploreLinkKind.NETEASE_SONG);
      expect(song?.id).assertEqual(186016);
      // 分享短文案 + #/ 哈希路由 + 中文句读尾缀。
      const playlist = recognizeExploreLink(
        '听歌 https://music.163.com/#/playlist?id=73215116。');
      expect(playlist !== null).assertTrue();
      expect(playlist?.kind).assertEqual(ExploreLinkKind.NETEASE_PLAYLIST);
      expect(playlist?.id).assertEqual(73215116);
      const artist = recognizeExploreLink('https://music.163.com/#/artist?id=6452');
      expect(artist !== null).assertTrue();
      expect(artist?.kind).assertEqual(ExploreLinkKind.NETEASE_ARTIST);
      expect(artist?.id).assertEqual(6452);
      const short = recognizeExploreLink('https://163cn.tv/AbCdEf');
      expect(short?.kind).assertEqual(ExploreLinkKind.NETEASE_SHORT_LINK);
    });

    it('recognizesBiliVideoWithPageAndCollectionShare', 0, () => {
      const video = recognizeExploreLink('https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
      expect(video !== null).assertTrue();
      expect(video?.kind).assertEqual(ExploreLinkKind.BILI_VIDEO);
      expect(video?.bvid).assertEqual('BV1GJ411x7h7');
      expect(video?.page).assertEqual(2);
      const withCid = recognizeExploreLink(
        'https://www.bilibili.com/video/BV1GJ411x7h7?cid=123456&season_id=777');
      expect(withCid !== null).assertTrue();
      expect(withCid?.cid).assertEqual(123456);
      expect(withCid?.isCollectionShare).assertTrue();
      // av 号：路径与 aid 参数两种形态。
      const avPath = recognizeExploreLink('https://www.bilibili.com/video/av170001');
      expect(avPath?.kind).assertEqual(ExploreLinkKind.BILI_VIDEO);
      expect(avPath?.avid).assertEqual(170001);
      const aidParam = recognizeExploreLink('https://www.bilibili.com/?aid=928862045');
      expect(aidParam?.avid).assertEqual(928862045);
      const short = recognizeExploreLink('https://b23.tv/abcd123');
      expect(short?.kind).assertEqual(ExploreLinkKind.BILI_SHORT_LINK);
    });

    it('recognizesBiliSpaceLinks', 0, () => {
      // space/{mid}/lists/{seasonId}?type=season → 合集；type=series → 不支持。
      const season = recognizeExploreLink('https://space.bilibili.com/529249/lists/777831?type=season');
      expect(season?.kind).assertEqual(ExploreLinkKind.BILI_COLLECTION);
      expect(season?.ownerMid).assertEqual(529249);
      expect(season?.seasonId).assertEqual(777831);
      const series = recognizeExploreLink('https://space.bilibili.com/529249/lists/777831?type=series');
      expect(series?.kind).assertEqual(ExploreLinkKind.UNSUPPORTED);
      // favlist fid 带 ml 前缀；medialist 路径直接给 mediaId。
      const favlist = recognizeExploreLink('https://space.bilibili.com/529249/favlist?fid=ml2265867256');
      expect(favlist?.kind).assertEqual(ExploreLinkKind.BILI_FAV_FOLDER_BY_OWNER);
      expect(favlist?.folderId).assertEqual(2265867256);
      const medialist = recognizeExploreLink('https://www.bilibili.com/medialist/detail/ml2265867256');
      expect(medialist?.kind).assertEqual(ExploreLinkKind.BILI_FAV_FOLDER);
      expect(medialist?.id).assertEqual(2265867256);
      const up = recognizeExploreLink('https://space.bilibili.com/529249');
      expect(up?.kind).assertEqual(ExploreLinkKind.BILI_ARTIST);
      expect(up?.id).assertEqual(529249);
    });

    it('recognizesYouTubeLinks', 0, () => {
      const watch = recognizeExploreLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(watch?.kind).assertEqual(ExploreLinkKind.YOUTUBE_VIDEO);
      expect(watch?.videoId).assertEqual('dQw4w9WgXcQ');
      const withList = recognizeExploreLink('https://www.youtube.com/watch?v=abc123&list=PLxyz');
      expect(withList?.playlistId).assertEqual('PLxyz');
      const short = recognizeExploreLink('https://youtu.be/dQw4w9WgXcQ');
      expect(short?.kind).assertEqual(ExploreLinkKind.YOUTUBE_VIDEO);
      expect(short?.videoId).assertEqual('dQw4w9WgXcQ');
      const shorts = recognizeExploreLink('https://www.youtube.com/shorts/vid01');
      expect(shorts?.videoId).assertEqual('vid01');
      const listOnly = recognizeExploreLink('https://www.youtube.com/playlist?list=PLabc');
      expect(listOnly?.kind).assertEqual(ExploreLinkKind.YOUTUBE_PLAYLIST);
      const channel = recognizeExploreLink('https://www.youtube.com/@someone');
      expect(channel?.kind).assertEqual(ExploreLinkKind.UNSUPPORTED);
    });

    it('extractsHttpUrlFromArbitraryText', 0, () => {
      expect(extractExploreHttpUrl('随便什么话 https://b23.tv/aa 没有 http 的 b23.tv/bb 后面这句'))
        .assertEqual('https://b23.tv/aa');
      // 尾缀句点（含 ASCII '.'）一并剪掉。
      expect(extractExploreHttpUrl('https://music.163.com/song/?id=1。】'))
        .assertEqual('https://music.163.com/song/?id=1');
      expect(extractExploreHttpUrl('只是关键词')).assertNull();
      expect(extractExploreHttpUrl('')).assertNull();
    });

    it('nonLinkInputYieldsNull', 0, () => {
      expect(recognizeExploreLink('周杰伦 晴天')).assertNull();
      expect(recognizeExploreLink('')).assertNull();
      // 无法识别的 host 也返回 null（继续按关键词搜索）。
      expect(recognizeExploreLink('https://example.com/video/1')).assertNull();
    });
  });
}
