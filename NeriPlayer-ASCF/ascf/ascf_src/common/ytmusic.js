/**
 * YouTube Music 客户端（匿名搜索）。
 * 说明：YouTube 流地址解析需要签名/EJS 引擎，ASCF 端暂不支持，见 PORTING.md。
 */

const constants = require('./constants');
const http = require('./http');
const format = require('./format');
const { newSong } = require('./song');

async function search(keyword, limit) {
  const url =
    constants.ytmBase +
    '/youtubei/v1/music/search?key=' +
    constants.ytmWebApiKey +
    '&prettyPrint=false';
  const body = {
    context: {
      client: {
        clientName: 'WEB_REMIX',
        clientVersion: '1.20250203.00.00',
        hl: 'en',
        gl: 'US',
      },
    },
    params: 'EgWKAQIIAWoKEAoQCRADEAA%3D',
    query: keyword,
  };
  const text = await http.postJson(url, JSON.stringify(body));
  const response = JSON.parse(text);
  const items = [];
  const contents =
    (response.contents &&
      response.contents.tabbedSearchResultsRenderer &&
      response.contents.tabbedSearchResultsRenderer.tabs &&
      response.contents.tabbedSearchResultsRenderer.tabs[0] &&
      response.contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer &&
      response.contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content &&
      response.contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer &&
      response.contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents) ||
    [];
  for (let s = 0; s < contents.length; s++) {
    const rows = (contents[s].musicShelfRenderer && contents[s].musicShelfRenderer.contents) || [];
    for (let r = 0; r < rows.length; r++) {
      const renderer = rows[r].musicResponsiveListItemRenderer;
      if (!renderer) {
        continue;
      }
      const videoId =
        (renderer.playlistItemData && renderer.playlistItemData.videoId) || '';
      if (!videoId) {
        continue;
      }
      const flexColumns = renderer.flexColumns || [];
      const title =
        (flexColumns[0] &&
          flexColumns[0].musicResponsiveListItemFlexColumnRenderer &&
          flexColumns[0].musicResponsiveListItemFlexColumnRenderer.text &&
          flexColumns[0].musicResponsiveListItemFlexColumnRenderer.text.runs &&
          flexColumns[0].musicResponsiveListItemFlexColumnRenderer.text.runs[0] &&
          flexColumns[0].musicResponsiveListItemFlexColumnRenderer.text.runs[0].text) ||
        '';
      const metaRuns =
        (flexColumns[1] &&
          flexColumns[1].musicResponsiveListItemFlexColumnRenderer &&
          flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text &&
          flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text.runs) ||
        [];
      const artist = metaRuns.length > 0 ? metaRuns[0].text || '' : '';
      const album = metaRuns.length >= 3 ? metaRuns[2].text || '' : '';
      const fixedColumns = renderer.fixedColumns || [];
      const durationText =
        (fixedColumns[0] &&
          fixedColumns[0].musicResponsiveListItemFixedColumnRenderer &&
          fixedColumns[0].musicResponsiveListItemFixedColumnRenderer.text &&
          fixedColumns[0].musicResponsiveListItemFixedColumnRenderer.text.runs &&
          fixedColumns[0].musicResponsiveListItemFixedColumnRenderer.text.runs[0] &&
          fixedColumns[0].musicResponsiveListItemFixedColumnRenderer.text.runs[0].text) ||
        '';
      const song = newSong({
        name: title,
        artist: artist,
        album: album,
        durationMs: format.parseDurationMs(durationText),
        mediaUri: constants.youtubeMusicMediaPrefix + videoId,
        platform: 3,
      });
      song.channelId = constants.youtubeMusicIdentityAlbum;
      song.audioId = videoId;
      items.push(song);
      if (items.length >= (limit || 20)) {
        return items;
      }
    }
  }
  return items;
}

async function resolveStream(videoId) {
  throw new Error('YouTube 流地址解析需要 EJS 引擎移植（见 PORTING.md）');
}

module.exports = { search, resolveStream };
