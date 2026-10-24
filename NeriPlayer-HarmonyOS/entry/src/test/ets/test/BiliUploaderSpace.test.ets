// SPDX-License-Identifier: GPL-3.0
// Unit tests for the Bilibili uploader-space parsers (upstream
// BiliUploaderSpaceJsonTest / BiliImageUrlTest, commit e95b2ef9).

import { describe, it, expect } from '@ohos/hypium';
import {
  BiliUploaderContentKind,
  parseBiliUploaderProfile,
  parseBiliUploaderVideoPage,
  parseBiliUploaderContentPage,
  parseBiliSeriesArchivePage,
  parseBiliCollectionArchivePage,
  normalizeBiliImageUrl,
  parseBiliSpaceDurationSeconds,
  biliUploaderVideoToSongItem,
  biliArchiveItemToSongItem
} from '../../../main/ets/network/BiliUploaderSpace';
import { finalRedirectUrl, isShortLinkHost } from '../../../main/ets/network/ShortLinkExpander';

function data(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function BiliUploaderSpaceTest() {
  describe('BiliUploaderSpace', () => {
    it('parseProfile_normalizesImagesAndKeepsFallbackMid', 0, () => {
      const profile = parseBiliUploaderProfile(data(`{
        "name": "测试 UP 主",
        "face": "//i0.hdslb.com/bfs/face.jpg",
        "sign": "简介",
        "top_photo": "http://i0.hdslb.com/bfs/banner.jpg"
      }`), 123);
      expect(profile.mid).assertEqual(123);
      expect(profile.name).assertEqual('测试 UP 主');
      expect(profile.faceUrl).assertEqual('https://i0.hdslb.com/bfs/face.jpg');
      expect(profile.topPhotoUrl).assertEqual('https://i0.hdslb.com/bfs/banner.jpg');
      // 响应带 mid 时优先响应值（0/负数回退请求 mid）。
      const withMid = parseBiliUploaderProfile(data('{"name":"a","mid":456}'), 123);
      expect(withMid.mid).assertEqual(456);
      const zeroMid = parseBiliUploaderProfile(data('{"name":"a","mid":0}'), 123);
      expect(zeroMid.mid).assertEqual(123);
    });

    it('parseVideoPage_readsPagingDurationAndCoauthorMid', 0, () => {
      const page = parseBiliUploaderVideoPage(data(`{
        "page": {"pn": 2, "ps": 30, "count": 61},
        "list": {
          "vlist": [
            {
              "aid": 1,
              "bvid": "BV1test",
              "title": "<em class=\\"keyword\\">测试</em>投稿",
              "pic": "//i0.hdslb.com/bfs/archive.jpg",
              "length": "1:02:03",
              "mid": 456,
              "author": "共同创作 UP 主",
              "play": "321",
              "created": 1700000000
            },
            {"aid": 0, "bvid": "BV1bad", "title": "无效条目被丢弃"},
            {"aid": 2, "bvid": "", "title": "缺 bvid 也被丢弃"}
          ]
        }
      }`), 1, 30, 123);
      expect(page.page).assertEqual(2);
      expect(page.total).assertEqual(61);
      expect(page.hasMore).assertTrue();
      expect(page.items.length).assertEqual(1);
      const item = page.items[0];
      expect(item.title).assertEqual('测试投稿');
      expect(item.durationSec).assertEqual(3723);
      expect(item.uploaderMid).assertEqual(456);
      expect(item.play).assertEqual(321);
      expect(item.coverUrl).assertEqual('https://i0.hdslb.com/bfs/archive.jpg');
    });

    it('parseVideoPage_hasMoreFollowsPagingMath', 0, () => {
      // page 缺席时回退请求页；count 覆盖条目数；页×大小 >= 总数时收口。
      const exact = parseBiliUploaderVideoPage(data(`{
        "page": {"pn": 3, "ps": 30, "count": 90},
        "list": {"vlist": []}
      }`), 3, 30, 1);
      expect(exact.hasMore).assertFalse();
      const missingPage = parseBiliUploaderVideoPage(
        data('{"list": {"vlist": []}}'), 1, 30, 1);
      expect(missingPage.page).assertEqual(1);
      expect(missingPage.total).assertEqual(0);
      expect(missingPage.hasMore).assertFalse();
    });

    it('parseContents_keepsCollectionAndSeriesSeparate', 0, () => {
      const page = parseBiliUploaderContentPage(data(`{
        "items_lists": {
          "page": {"page_num": 1, "page_size": 20, "total": 3},
          "seasons_list": [
            {"meta": {"season_id": 10, "mid": 1, "name": "合集甲", "cover": "//i0.hdslb.com/a.jpg", "total": 5}},
            {"meta": {"season_id": 10, "name": "重复 id 去重"}},
            {"meta": {"season_id": 0, "name": "无效 id 丢弃"}}
          ],
          "series_list": [
            {"meta": {"series_id": 20, "name": "", "title": "系列乙回退 title", "total": 2}}
          ]
        }
      }`), 1, 20, 1);
      expect(page.collections.length).assertEqual(1);
      expect(page.series.length).assertEqual(1);
      expect(page.collections[0].title).assertEqual('合集甲');
      expect(page.collections[0].kind).assertEqual(BiliUploaderContentKind.COLLECTION);
      expect(page.series[0].title).assertEqual('系列乙回退 title');
      expect(page.series[0].kind).assertEqual(BiliUploaderContentKind.SERIES);
      expect(page.series[0].mid).assertEqual(1);
      expect(page.hasMore).assertTrue();
    });

    it('parseSeriesArchivePage_countsAndDropsInvalidEntries', 0, () => {
      const page = parseBiliSeriesArchivePage(data(`{
        "archives": [
          {"aid": 1, "bvid": "BV1a", "title": "第一集", "pic": "//i0.hdslb.com/1.jpg",
           "duration": 120, "pubdate": 1700000000, "stat": {"view": 88}},
          {"aid": 2, "bvid": "BV1b", "title": "第二集"},
          {"aid": 0, "bvid": "BV1c", "title": "丢弃"}
        ],
        "page": {"num": 1, "size": 30, "total": 45}
      }`), 1, 30);
      expect(page.items.length).assertEqual(2);
      expect(page.items[0].play).assertEqual(88);
      expect(page.items[0].durationSec).assertEqual(120);
      expect(page.total).assertEqual(45);
      expect(page.hasMore).assertTrue();
    });

    it('parseCollectionArchivePage_metaFallsBackToRequest', 0, () => {
      const page = parseBiliCollectionArchivePage(data(`{
        "meta": {"name": "合集标题", "cover": "//i0.hdslb.com/c.jpg", "total": 7},
        "archives": [{"aid": 1, "bvid": "BV1a", "title": "单集"}]
      }`), 555, 666);
      expect(page.meta.title).assertEqual('合集标题');
      expect(page.meta.seasonId).assertEqual(555);
      expect(page.meta.mid).assertEqual(666);
      expect(page.meta.total).assertEqual(7);
      expect(page.hasMore).assertTrue();
      // meta 完全缺席：标题空、id 回退请求值，hasMore 按 total>items 收口。
      const empty = parseBiliCollectionArchivePage(data('{"archives": []}'), 555, 666);
      expect(empty.meta.seasonId).assertEqual(555);
      expect(empty.meta.total).assertEqual(0);
      expect(empty.hasMore).assertFalse();
    });

    it('imageAndDurationHelpers', 0, () => {
      expect(normalizeBiliImageUrl('  //i0.hdslb.com/a.jpg ')).assertEqual('https://i0.hdslb.com/a.jpg');
      expect(normalizeBiliImageUrl('http://i0.hdslb.com/a.jpg')).assertEqual('https://i0.hdslb.com/a.jpg');
      expect(normalizeBiliImageUrl('https://i0.hdslb.com/a.jpg')).assertEqual('https://i0.hdslb.com/a.jpg');
      expect(normalizeBiliImageUrl('')).assertEqual('');
      expect(parseBiliSpaceDurationSeconds('10:30')).assertEqual(630);
      expect(parseBiliSpaceDurationSeconds('1:02:03')).assertEqual(3723);
      expect(parseBiliSpaceDurationSeconds('45')).assertEqual(45);
      expect(parseBiliSpaceDurationSeconds('')).assertEqual(0);
      expect(parseBiliSpaceDurationSeconds('1:xx')).assertEqual(0);
    });

    it('songItemMappings', 0, () => {
      const video = parseBiliUploaderVideoPage(data(`{
        "list": {"vlist": [{"aid": 1, "bvid": "BV1x", "title": "投稿",
          "length": "1:00", "mid": 7, "author": "UP 名"}]}
      }`), 1, 30, 7).items[0];
      const song = biliUploaderVideoToSongItem(video);
      expect(song.audioId).assertEqual('BV1x');
      expect(song.channelId).assertEqual('bilibili');
      expect(song.artist).assertEqual('UP 名');
      expect(song.durationMs).assertEqual(60000);

      const archiveSong = biliArchiveItemToSongItem(
        parseBiliSeriesArchivePage(data(
          '{"archives": [{"aid": 2, "bvid": "BV1y", "title": "单集", "duration": 90}]}'
        ), 1, 30).items[0], '合集 UP');
      expect(archiveSong.audioId).assertEqual('BV1y');
      expect(archiveSong.artist).assertEqual('合集 UP');
      expect(archiveSong.durationMs).assertEqual(90000);
    });
  });

  describe('ShortLinkExpander', () => {
    it('finalRedirectUrl_lastHopWins', 0, () => {
      const original = 'https://b23.tv/abcd123';
      expect(finalRedirectUrl([], original)).assertEqual(original);
      expect(finalRedirectUrl(['https://www.bilibili.com/video/BV1x'], original))
        .assertEqual('https://www.bilibili.com/video/BV1x');
      expect(finalRedirectUrl([
        'https://www.bilibili.com/video/BV1x',
        'https://www.bilibili.com/video/BV1x?p=2'
      ], original)).assertEqual('https://www.bilibili.com/video/BV1x?p=2');
      // 末跳空白回落原链。
      expect(finalRedirectUrl(['  '], original)).assertEqual(original);
    });

    it('isShortLinkHost_detectsKnownHosts', 0, () => {
      expect(isShortLinkHost('https://b23.tv/abcd123')).assertTrue();
      expect(isShortLinkHost('http://b23.tv/abcd123')).assertTrue();
      expect(isShortLinkHost('https://163cn.tv/xyz')).assertTrue();
      expect(isShortLinkHost('https://www.bilibili.com/video/BV1x')).assertFalse();
      expect(isShortLinkHost('https://b23.tv.evil.com/abcd')).assertFalse();
    });
  });
}
