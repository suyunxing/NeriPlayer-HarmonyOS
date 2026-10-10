// SPDX-License-Identifier: GPL-3.0

import { describe, it, expect } from '@ohos/hypium';
import {
  NETEASE_RADAR_PLAYLIST_DEFINITIONS,
  NETEASE_PRIVATE_RADAR_PLAYLIST_ID,
  NeteaseHomeSongSource,
  NeteaseHomePlaylistSource,
  NeteaseApiCodeError,
  isNeteaseRadarPlaylist,
  radarDefinitionToSummary,
  songSourceRequiresLogin,
  playlistSourceRequiresLogin,
  availableNeteaseHomeSongSources,
  availableNeteaseHomePlaylistSources,
  parseNeteaseHomeSongs,
  parseNeteaseHomePlaylists,
  parseNeteasePlaylistDetailSummary,
  appendUniqueNeteaseHomeSongs
} from '../../../main/ets/network/NeteaseHomeRecommendations';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

function homeSong(audioId: string, name: string): SongItem {
  const song = new SongItem(1, name, 'a', '', 0);
  song.audioId = audioId;
  return song;
}

/** /v3/discovery/recommend/songs 形状：data.dailySongs，ar/al/dt。 */
function dailySongsJson(): string {
  const artist: Record<string, Object> = {};
  artist['name'] = '周杰伦';
  const album: Record<string, Object> = {};
  album['id'] = 9;
  album['name'] = '叶惠美';
  album['picUrl'] = 'http://p3.music.126.net/x.jpg';
  const song: Record<string, Object> = {};
  song['id'] = 111;
  song['name'] = '晴天';
  song['dt'] = 269000;
  song['ar'] = [artist];
  song['al'] = album;
  const badId: Record<string, Object> = {};
  badId['id'] = 0;
  badId['name'] = '坏数据';
  const blankName: Record<string, Object> = {};
  blankName['id'] = 222;
  blankName['name'] = '';
  const data: Record<string, Object> = {};
  data['dailySongs'] = [song, badId, blankName];
  const root: Record<string, Object> = {};
  root['code'] = 200;
  root['data'] = data;
  return JSON.stringify(root);
}

/** /personalized/newsong 形状：result 数组、曲目包在 song 字段。 */
function newsongJson(): string {
  const artistA: Record<string, Object> = {};
  artistA['name'] = 'A';
  const artistB: Record<string, Object> = {};
  artistB['name'] = 'B';
  const album: Record<string, Object> = {};
  album['id'] = 1;
  album['name'] = 'AL';
  album['picUrl'] = '';
  const inner: Record<string, Object> = {};
  inner['id'] = 333;
  inner['name'] = '新歌';
  inner['duration'] = 180000;
  inner['artists'] = [artistA, artistB];
  inner['album'] = album;
  const container: Record<string, Object> = {};
  container['id'] = 333;
  container['song'] = inner;
  const root: Record<string, Object> = {};
  root['code'] = 200;
  root['result'] = [container];
  return JSON.stringify(root);
}

/** /v1/discovery/recommend/resource 形状：recommend 数组 + playcount/songCount 变体。 */
function recommendResourceJson(): string {
  const playlist: Record<string, Object> = {};
  playlist['id'] = 7;
  playlist['name'] = '雷达';
  playlist['picUrl'] = 'http://p.music.126.net/a.jpg';
  playlist['playcount'] = 12;
  playlist['songCount'] = 30;
  const bad: Record<string, Object> = {};
  bad['id'] = 0;
  bad['name'] = '坏';
  const root: Record<string, Object> = {};
  root['code'] = 200;
  root['recommend'] = [playlist, bad];
  return JSON.stringify(root);
}

// 上游 NeteaseHomeRecommendations（#319/#338）核心纯逻辑镜像。
export default function neteaseHomeRecommendationsTest(): void {
  describe('NeteaseHomeRecommendations', () => {
    it('radarDefinitionsCoverFiveRadars', 0, () => {
      expect(NETEASE_RADAR_PLAYLIST_DEFINITIONS.length).assertEqual(5);
      expect(isNeteaseRadarPlaylist(NETEASE_PRIVATE_RADAR_PLAYLIST_ID)).assertTrue();
      expect(isNeteaseRadarPlaylist(12345)).assertFalse();
      const fallback = radarDefinitionToSummary(NETEASE_RADAR_PLAYLIST_DEFINITIONS[0]);
      expect(fallback.name).assertEqual('时光雷达');
      expect(fallback.coverUrl).assertEqual('');
    });

    it('songAndPlaylistSourcesGateOnLogin', 0, () => {
      expect(songSourceRequiresLogin(NeteaseHomeSongSource.DAILY_RECOMMEND)).assertTrue();
      expect(songSourceRequiresLogin(NeteaseHomeSongSource.PRIVATE_FM)).assertTrue();
      expect(songSourceRequiresLogin(NeteaseHomeSongSource.PERSONAL_RADAR)).assertFalse();
      const anonymous = availableNeteaseHomeSongSources(
        [NeteaseHomeSongSource.PERSONAL_RADAR, NeteaseHomeSongSource.DAILY_RECOMMEND,
          NeteaseHomeSongSource.PRIVATE_FM], false);
      expect(anonymous.length).assertEqual(1);
      expect(anonymous[0]).assertEqual(NeteaseHomeSongSource.PERSONAL_RADAR);
      const loggedIn = availableNeteaseHomePlaylistSources(
        [NeteaseHomePlaylistSource.PERSONALIZED, NeteaseHomePlaylistSource.DAILY_RESOURCE],
        true);
      expect(loggedIn.length).assertEqual(2);
      expect(playlistSourceRequiresLogin(NeteaseHomePlaylistSource.DAILY_RESOURCE)).assertTrue();
    });

    it('parsesDailySongsResponseShape', 0, () => {
      const songs = parseNeteaseHomeSongs(dailySongsJson());
      expect(songs.length).assertEqual(1);
      expect(songs[0].audioId).assertEqual('111');
      expect(songs[0].artist).assertEqual('周杰伦');
      expect(songs[0].album).assertEqual('叶惠美');
      expect(songs[0].durationMs).assertEqual(269000);
      expect(songs[0].coverUrl.startsWith('https://')).assertTrue();
    });

    it('parsesWrappedNewsongShapeAndThrowsOnBadCode', 0, () => {
      const songs = parseNeteaseHomeSongs(newsongJson());
      expect(songs.length).assertEqual(1);
      expect(songs[0].audioId).assertEqual('333');
      expect(songs[0].artist).assertEqual('A / B');
      expect(songs[0].durationMs).assertEqual(180000);
      expect(songs[0].platform).assertEqual(MusicPlatform.NETEASE);
      let threw = false;
      let code = -1;
      try {
        parseNeteaseHomeSongs('{"code":301,"data":{}}');
      } catch (error) {
        threw = true;
        code = (error as NeteaseApiCodeError).code;
      }
      expect(threw).assertTrue();
      expect(code).assertEqual(301);
    });

    it('parsesPlaylistArraysAndDetailFallback', 0, () => {
      const playlists = parseNeteaseHomePlaylists(recommendResourceJson());
      expect(playlists.length).assertEqual(1);
      expect(playlists[0].id).assertEqual(7);
      expect(playlists[0].coverUrl.startsWith('https://')).assertTrue();
      expect(playlists[0].playCount).assertEqual(12);
      expect(playlists[0].trackCount).assertEqual(30);

      // 详情缺歌单对象时回落静态定义。
      const fallback = parseNeteasePlaylistDetailSummary('{"code":200}',
        radarDefinitionToSummary(NETEASE_RADAR_PLAYLIST_DEFINITIONS[1]));
      expect(fallback.name).assertEqual('宝藏雷达');
      const detailPlaylist: Record<string, Object> = {};
      detailPlaylist['id'] = 9;
      detailPlaylist['name'] = '详情';
      detailPlaylist['coverImgUrl'] = 'http://x/a.jpg';
      const detailRoot: Record<string, Object> = {};
      detailRoot['code'] = 200;
      detailRoot['playlist'] = detailPlaylist;
      const detail = parseNeteasePlaylistDetailSummary(JSON.stringify(detailRoot),
        radarDefinitionToSummary(NETEASE_RADAR_PLAYLIST_DEFINITIONS[0]));
      expect(detail.name).assertEqual('详情');
      expect(detail.coverUrl.startsWith('https://')).assertTrue();
    });

    it('appendUniqueMergesDedupesAndCapsLimit', 0, () => {
      const current = [homeSong('1', 'a'), homeSong('2', 'b')];
      const next = [homeSong('2', 'b-dup'), homeSong('3', 'c'), homeSong('4', 'd')];
      const merged = appendUniqueNeteaseHomeSongs(current, next, 3);
      expect(merged.length).assertEqual(3);
      expect(merged[0].audioId).assertEqual('1');
      expect(merged[1].audioId).assertEqual('2');
      expect(merged[2].audioId).assertEqual('3');
      expect(appendUniqueNeteaseHomeSongs(current, next, 0).length).assertEqual(0);
      // 无 audioId 的键回退 platform:id:name。
      const bareA = new SongItem(10, 'x', '', '', 0);
      const bareB = new SongItem(10, 'x', '', '', 0);
      expect(appendUniqueNeteaseHomeSongs([bareA], [bareB], 5).length).assertEqual(1);
    });
  });
}
