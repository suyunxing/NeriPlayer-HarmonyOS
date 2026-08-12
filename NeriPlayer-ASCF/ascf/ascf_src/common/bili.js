/**
 * 哔哩哔哩客户端（视频搜索 + DASH 音频解析），
 * 移植自 NeriPlayer-HarmonyOS/network/BiliApi.ets。
 */

const constants = require('./constants');
const http = require('./http');
const format = require('./format');
const { newSong } = require('./song');

async function search(keyword, limit) {
  const url =
    constants.biliBase +
    '/x/web-interface/search/type?search_type=video&keyword=' +
    encodeURIComponent(keyword);
  const text = await http.getText(url, { Referer: 'https://www.bilibili.com' });
  const response = JSON.parse(text);
  const results = (response.data && response.data.result) || [];
  const items = [];
  for (let i = 0; i < Math.min(results.length, limit || 20); i++) {
    const item = results[i];
    const song = newSong({
      name: format.stripHtml(item.title || ''),
      artist: item.author || '',
      album: 'Bilibili',
      durationMs: format.parseDurationMs(item.duration || ''),
      coverUrl: (item.pic || '').startsWith('http://')
        ? 'https://' + item.pic.substring(7)
        : item.pic || '',
      platform: 2,
    });
    song.channelId = 'bilibili';
    song.audioId = item.bvid || '';
    items.push(song);
  }
  return items;
}

async function resolveAudioUrl(bvid) {
  const url =
    constants.biliBase + '/x/player/playurl?bvid=' + bvid + '&fnval=16&fourk=1';
  const text = await http.getText(url, { Referer: 'https://www.bilibili.com' });
  const response = JSON.parse(text);
  const audioList = (response.data && response.data.dash && response.data.dash.audio) || [];
  if (audioList.length === 0) {
    return '';
  }
  let best = audioList[0];
  for (let i = 1; i < audioList.length; i++) {
    if (audioList[i].bandwidth > best.bandwidth) {
      best = audioList[i];
    }
  }
  let stream = best.baseUrl || '';
  if (stream.length === 0 && best.backupUrl && best.backupUrl.length > 0) {
    stream = best.backupUrl[0];
  }
  if (stream.startsWith('http://')) {
    stream = 'https://' + stream.substring(7);
  }
  return stream;
}

module.exports = { search, resolveAudioUrl };
