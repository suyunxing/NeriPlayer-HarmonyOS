import { describe, it, expect } from '@ohos/hypium';
import {
  parseUserPlaylistsResponse,
  parseRecommendPlaylistsResponse,
  parseNeteaseUserId,
  shouldFallbackRecommendToAnonymous,
  neteaseSongToSongItem,
  NeteaseSong
} from '../../../main/ets/network/NeteasePlaylistParser';

/**
 * Fixtures are minimal samples of the netease response shapes, field names
 * aligned with the Android parsers (NeteaseClient.getUserPlaylists /
 * HomeViewModel.parseRecommend / getCurrentUserId).
 */

function userPlaylistEntry(id: number, name: string, cover: string, playCount: number, trackCount: number): Record<string, Object> {
  const entry: Record<string, Object> = {};
  entry['id'] = id;
  entry['name'] = name;
  entry['coverImgUrl'] = cover;
  entry['playCount'] = playCount;
  entry['trackCount'] = trackCount;
  return entry;
}

const USER_PLAYLISTS_JSON: string = JSON.stringify(((): Record<string, Object> => {
  const root: Record<string, Object> = {};
  root['code'] = 200;
  root['playlist'] = [
    userPlaylistEntry(73215112, '我喜欢的音乐', 'http://p3.music.126.net/abc/1.jpg', 0, 521),
    userPlaylistEntry(0, 'bad id', 'https://p3.music.126.net/x/0.jpg', 9, 9),
    userPlaylistEntry(42, '', 'https://p3.music.126.net/x/0.jpg', 1, 1),
    userPlaylistEntry(91234567, '跑步专用', 'https://p4.music.126.net/def/2.jpg', 42, 30)
  ];
  return root;
})());

function recommendJson(count: number): string {
  const items: object[] = [];
  for (let i = 0; i < count; i++) {
    const entry: Record<string, Object> = {};
    entry['id'] = 1000 + i;
    entry['name'] = `推荐歌单${i}`;
    entry['picUrl'] = i === 2 ? 'http://p1.music.126.net/img/1.jpg' : 'https://p1.music.126.net/img/1.jpg';
    entry['playCount'] = 999999;
    entry['trackCount'] = 40;
    items.push(entry);
  }
  const root: Record<string, Object> = {};
  root['code'] = 200;
  root['result'] = items;
  return JSON.stringify(root);
}

export default function neteasePlaylistParserTest(): void {
  describe('NeteasePlaylistParser', () => {
    it('userPlaylistsKeepsValidEntriesAndUpgradesHttpCover', 0, () => {
      const parsed = parseUserPlaylistsResponse(USER_PLAYLISTS_JSON);
      expect(parsed.code).assertEqual(200);
      expect(parsed.items.length).assertEqual(2);
      expect(parsed.items[0].id).assertEqual(73215112);
      expect(parsed.items[0].name).assertEqual('我喜欢的音乐');
      expect(parsed.items[0].coverUrl).assertEqual('https://p3.music.126.net/abc/1.jpg');
      expect(parsed.items[0].trackCount).assertEqual(521);
      expect(parsed.items[1].name).assertEqual('跑步专用');
      expect(parsed.items[1].playCount).assertEqual(42);
    });

    it('userPlaylistsToleratesBadShapes', 0, () => {
      expect(parseUserPlaylistsResponse('not json').items.length).assertEqual(0);
      expect(parseUserPlaylistsResponse('{"code":301}').code).assertEqual(301);
      expect(parseUserPlaylistsResponse('{"code":200,"playlist":"oops"}').items.length).assertEqual(0);
      expect(parseUserPlaylistsResponse('{"code":200}').items.length).assertEqual(0);
    });

    it('recommendCapsAt30AndFiltersBlankCovers', 0, () => {
      const parsed = parseRecommendPlaylistsResponse(recommendJson(35), 30);
      expect(parsed.code).assertEqual(200);
      expect(parsed.items.length).assertEqual(30);
      for (const item of parsed.items) {
        expect(item.coverUrl.startsWith('https://')).assertTrue();
      }
      // Entry with a http cover must have been upgraded, not dropped.
      const third = parsed.items.filter((item) => item.id === 1002);
      expect(third.length).assertEqual(1);
      expect(third[0].coverUrl).assertEqual('https://p1.music.126.net/img/1.jpg');
    });

    it('recommendDropsEntriesWithoutCover', 0, () => {
      const root: Record<string, Object> = {};
      root['code'] = 200;
      const noCover: Record<string, Object> = {};
      noCover['id'] = 5;
      noCover['name'] = 'no cover';
      noCover['picUrl'] = '';
      const withCover: Record<string, Object> = {};
      withCover['id'] = 6;
      withCover['name'] = 'with cover';
      withCover['picUrl'] = 'https://p/1.jpg';
      root['result'] = [noCover, withCover];
      const parsed = parseRecommendPlaylistsResponse(JSON.stringify(root));
      expect(parsed.items.length).assertEqual(1);
      expect(parsed.items[0].id).assertEqual(6);
    });

    it('recommendFallbackCodesMatchAndroid', 0, () => {
      expect(shouldFallbackRecommendToAnonymous(301)).assertTrue();
      expect(shouldFallbackRecommendToAnonymous(50000005)).assertTrue();
      expect(shouldFallbackRecommendToAnonymous(400)).assertFalse();
      expect(shouldFallbackRecommendToAnonymous(200)).assertFalse();
    });

    it('userIdParsesProfileUserId', 0, () => {
      const root: Record<string, Object> = {};
      root['code'] = 200;
      const profile: Record<string, Object> = {};
      profile['userId'] = 36559833;
      root['profile'] = profile;
      expect(parseNeteaseUserId(JSON.stringify(root))).assertEqual(36559833);
    });

    it('userIdThrowsWhenAnonymousOrMissingProfile', 0, () => {
      let threw301 = false;
      try {
        parseNeteaseUserId('{"code":301}');
      } catch (error) {
        threw301 = (error as Error).message.indexOf('code=301') >= 0;
      }
      expect(threw301).assertTrue();

      let threwProfile = false;
      try {
        parseNeteaseUserId('{"code":200,"profile":null}');
      } catch (error) {
        threwProfile = (error as Error).message.indexOf('profile.userId') >= 0;
      }
      expect(threwProfile).assertTrue();
    });
  });

  describe('NeteaseSongMapper', () => {
    it('mapsShortShapeFromPlaylistAndSongDetail', 0, () => {
      // Shape returned by /api/v6/playlist/detail (verified 2026-08-17):
      // ar/al/dt instead of artists/album/duration, http cover urls.
      const raw = JSON.parse(`{"id":185868,"name":"Happy","dt":232780,`
        + `"ar":[{"id":41151,"name":"Pharrell Williams"}],`
        + `"al":{"id":2767233,"name":"G I R L","picUrl":"http://p4.music.126.net/s38NM0QqXYzMHtt1y9NxlQ==/109951168143732458.jpg"}}`) as NeteaseSong;
      const item = neteaseSongToSongItem(raw);
      expect(item.id).assertEqual(185868);
      expect(item.name).assertEqual('Happy');
      expect(item.artist).assertEqual('Pharrell Williams');
      expect(item.album).assertEqual('G I R L');
      expect(item.albumId).assertEqual(2767233);
      expect(item.durationMs).assertEqual(232780);
      expect(item.coverUrl).assertEqual('https://p4.music.126.net/s38NM0QqXYzMHtt1y9NxlQ==/109951168143732458.jpg');
      expect(item.audioId).assertEqual('185868');
    });

    it('mapsFullShapeFromCloudsearch', 0, () => {
      // Shape returned by /weapi/cloudsearch/get/web.
      const raw = JSON.parse(`{"id":1,"name":"晴天","duration":269000,`
        + `"artists":[{"id":6452,"name":"周杰伦"}],`
        + `"album":{"id":18918,"name":"叶惠美","picUrl":"https://p3.music.126.net/x/1.jpg"}}`) as NeteaseSong;
      const item = neteaseSongToSongItem(raw);
      expect(item.artist).assertEqual('周杰伦');
      expect(item.album).assertEqual('叶惠美');
      expect(item.albumId).assertEqual(18918);
      expect(item.durationMs).assertEqual(269000);
      expect(item.coverUrl).assertEqual('https://p3.music.126.net/x/1.jpg');
    });

    it('joinsMultipleArtistsAndFallsBackToPicStr', 0, () => {
      const raw = JSON.parse(`{"id":9,"name":"N","dt":1000,`
        + `"ar":[{"name":"A"},{"name":"B"},{"name":""}],`
        + `"al":{"id":7,"name":"AL","picStr":"http://p/2.jpg"}}`) as NeteaseSong;
      const item = neteaseSongToSongItem(raw);
      expect(item.artist).assertEqual('A / B');
      expect(item.coverUrl).assertEqual('https://p/2.jpg');
    });

    it('missingAlbumYieldsEmptyCoverFields', 0, () => {
      const raw = JSON.parse(`{"id":3,"name":"Bare","dt":500}`) as NeteaseSong;
      const item = neteaseSongToSongItem(raw);
      expect(item.artist).assertEqual('');
      expect(item.album).assertEqual('');
      expect(item.albumId).assertEqual(0);
      expect(item.coverUrl).assertEqual('');
      expect(item.durationMs).assertEqual(500);
    });
  });
}
