import { describe, it, expect } from '@ohos/hypium';
import {
  parseBiliFavFolderList,
  parseBiliFavResourcePage,
  biliFavMediaToSongItem,
  biliFavMediaDedupKey,
  ensureBiliHttps,
  stripBiliEm,
  BiliFavMedia,
  BiliFavFolderSummary
} from '../../../main/ets/network/BiliFavParser';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

/** Field shapes mirror bilibili-API-collect / Android parseFavFolder. */
const FOLDER_LIST_ALL_JSON =
  '{"code":0,"message":"0","ttl":1,"data":{"count":3,"list":[' +
  '{"id":1234567,"fid":111,"mid":42,"title":"默认收藏夹","cover":"http://i0.hdslb.com/bfs/a.jpg","media_count":12},' +
  '{"id":2233445,"fid":222,"mid":42,"name":"音乐收藏","cover":"//i0.hdslb.com/bfs/b.jpg","total":5},' +
  '{"id":0,"fid":333,"mid":42,"title":"坏的条目","media_count":1},' +
  '{"id":1234567,"fid":111,"mid":42,"title":"重复条目","media_count":1},' +
  '{"id":9988776,"fid":444,"mid":42,"title":"","media_count":1}' +
  ']}}';

const RESOURCE_PAGE_JSON =
  '{"code":0,"data":{"info":{"id":1234567,"fid":111,"mid":42,"title":"默认收藏夹","cover":"http://i0.hdslb.com/bfs/a.jpg","media_count":42},' +
  '"has_more":true,"medias":[' +
  '{"id":901,"type":2,"bvid":"BV1xx411c7mD","title":"<em class=\\"keyword\\">晴天</em> 钢琴版","cover":"//i0.hdslb.com/bfs/c.jpg","intro":"好听的钢琴","duration":315,"upper":{"mid":42,"name":"UP主甲"},"cnt_info":{"play":1000,"danmaku":3}},' +
  '{"id":902,"type":2,"bv_id":"BV1yy411c8mE","title":"无bvid字段的备选","cover":"https://i0.hdslb.com/bfs/d.jpg","duration":200,"upper":{"mid":43,"name":"UP主乙"}},' +
  '{"id":903,"type":2,"bvid":"","title":"空bvid条目应被过滤","duration":10,"upper":{"mid":44,"name":"UP主丙"}}' +
  ']}}';

const RESOURCE_LAST_PAGE_JSON =
  '{"code":0,"data":{"info":{"id":1234567,"media_count":3},"has_more":false,"medias":[' +
  '{"id":903,"type":2,"bvid":"BV1zz411c9mF","title":"最后一页","duration":60,"upper":{"mid":45,"name":"UP主丁"}}' +
  ']}}';

const NOT_LOGGED_IN_JSON = '{"code":-101,"message":"账号未登录"}';

export default function biliFavParserTest(): void {
  describe('BiliFavParser', () => {
    it('parseFolderListDropsInvalidAndDedups', 0, () => {
      const result = parseBiliFavFolderList(FOLDER_LIST_ALL_JSON);
      expect(result.totalCount).assertEqual(3);
      expect(result.folders.length).assertEqual(2);
      const first = result.folders[0];
      expect(first instanceof BiliFavFolderSummary).assertTrue();
      expect(first.mediaId).assertEqual(1234567);
      expect(first.title).assertEqual('默认收藏夹');
      expect(first.coverUrl).assertEqual('https://i0.hdslb.com/bfs/a.jpg');
      expect(first.mediaCount).assertEqual(12);
      const second = result.folders[1];
      // title fallback to "name", media_count fallback to "total", "//" cover fix.
      expect(second.title).assertEqual('音乐收藏');
      expect(second.mediaCount).assertEqual(5);
      expect(second.coverUrl).assertEqual('https://i0.hdslb.com/bfs/b.jpg');
    });

    it('parseFolderListHandlesEmptyAndCorrupt', 0, () => {
      const empty = parseBiliFavFolderList('{"code":0,"data":{"count":0}}');
      expect(empty.folders.length).assertEqual(0);
      const noData = parseBiliFavFolderList(NOT_LOGGED_IN_JSON);
      expect(noData.folders.length).assertEqual(0);
      expect(noData.totalCount).assertEqual(0);
      const corrupt = parseBiliFavFolderList('not json at all');
      expect(corrupt.folders.length).assertEqual(0);
    });

    it('parseResourcePageMapsInfoAndMedias', 0, () => {
      const page = parseBiliFavResourcePage(RESOURCE_PAGE_JSON);
      expect(page.info !== null).assertTrue();
      expect(page.info!.mediaId).assertEqual(1234567);
      expect(page.totalCount).assertEqual(42);
      expect(page.hasMore).assertTrue();
      expect(page.items.length).assertEqual(2); // blank bvid entry dropped

      const first = page.items[0];
      expect(first instanceof BiliFavMedia).assertTrue();
      expect(first.bvid).assertEqual('BV1xx411c7mD');
      expect(first.title).assertEqual('晴天 钢琴版');
      expect(first.coverUrl).assertEqual('https://i0.hdslb.com/bfs/c.jpg');
      expect(first.durationSec).assertEqual(315);
      expect(first.upperName).assertEqual('UP主甲');
      // bvid fallback to bv_id
      expect(page.items[1].bvid).assertEqual('BV1yy411c8mE');
    });

    it('parseResourcePageLastPageHasNoMore', 0, () => {
      const page = parseBiliFavResourcePage(RESOURCE_LAST_PAGE_JSON);
      expect(page.hasMore).assertFalse();
      expect(page.totalCount).assertEqual(3);
      expect(page.items.length).assertEqual(1);
      expect(page.items[0].bvid).assertEqual('BV1zz411c9mF');
    });

    it('parseResourcePageNotLoggedInYieldsEmpty', 0, () => {
      const page = parseBiliFavResourcePage(NOT_LOGGED_IN_JSON);
      expect(page.info).assertNull();
      expect(page.items.length).assertEqual(0);
      expect(page.hasMore).assertFalse();
    });

    it('mediaToSongItemMapsFields', 0, () => {
      const media = new BiliFavMedia();
      media.id = 901;
      media.type = 2;
      media.bvid = 'BV1xx411c7mD';
      media.title = '晴天 钢琴版';
      media.coverUrl = 'https://i0.hdslb.com/bfs/c.jpg';
      media.durationSec = 315;
      media.upperName = 'UP主甲';
      const song = biliFavMediaToSongItem(media);
      expect(song.platform).assertEqual(MusicPlatform.BILIBILI);
      expect(song.audioId).assertEqual('BV1xx411c7mD');
      expect(song.id).assertEqual(901);
      expect(song.name).assertEqual('晴天 钢琴版');
      expect(song.artist).assertEqual('UP主甲');
      expect(song.album).assertEqual('Bilibili');
      expect(song.durationMs).assertEqual(315000);
      expect(song.channelId).assertEqual('bilibili');
    });

    it('mediaToSongItemDefaultsArtist', 0, () => {
      const media = new BiliFavMedia();
      media.bvid = 'BV1aa';
      media.title = 'T';
      const song = biliFavMediaToSongItem(media);
      expect(song.artist).assertEqual('Bilibili');
    });

    it('dedupKeyCombinesTypeIdBvid', 0, () => {
      const a = new BiliFavMedia();
      a.type = 2;
      a.id = 1;
      a.bvid = 'BV1x';
      expect(biliFavMediaDedupKey(a)).assertEqual('2:1:BV1x');
    });

    it('ensureHttpsUpgradesProtocols', 0, () => {
      expect(ensureBiliHttps('http://x.com/a.jpg')).assertEqual('https://x.com/a.jpg');
      expect(ensureBiliHttps('//x.com/a.jpg')).assertEqual('https://x.com/a.jpg');
      expect(ensureBiliHttps('https://x.com/a.jpg')).assertEqual('https://x.com/a.jpg');
      expect(ensureBiliHttps('')).assertEqual('');
    });

    it('stripEmRemovesHighlightTags', 0, () => {
      expect(stripBiliEm('<em class="keyword">晴天</em> 钢琴版')).assertEqual('晴天 钢琴版');
      expect(stripBiliEm('A &amp; B')).assertEqual('A & B');
    });
  });
}
