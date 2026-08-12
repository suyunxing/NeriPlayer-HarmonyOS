/**
 * 网易云音乐客户端（搜索、歌曲地址、歌词、歌单详情），
 * 移植自 NeriPlayer-HarmonyOS/network/NeteaseApi.ets。
 */

const constants = require('./constants');
const http = require('./http');
const cryptoMod = require('./crypto');
const { newSong } = require('./song');

function toSongItem(song) {
  const artistNames = (song.artists || []).map(function (artist) {
    return artist.name || '';
  });
  const album = song.album || {};
  const item = newSong({
    id: song.id || 0,
    name: song.name || '',
    artist: artistNames.join(' / '),
    album: album.name || '',
    albumId: album.id || 0,
    durationMs: song.duration || song.dt || 0,
    coverUrl: album.picUrl || '',
    platform: 1,
  });
  item.channelId = 'netease';
  item.audioId = '' + (song.id || 0);
  return item;
}

async function search(keyword, limit) {
  const payload = {
    s: keyword,
    type: 1,
    limit: limit || 30,
    offset: 0,
    total: true,
  };
  const params = cryptoMod.weapiParams(payload);
  const text = await http.postForm(constants.neteaseBase + '/weapi/cloudsearch/get/web', params);
  const response = JSON.parse(text);
  const songs = (response.result && response.result.songs) || [];
  return songs.map(toSongItem);
}

async function requestSongUrl(id, level) {
  const payload = {
    ids: '[' + id + ']',
    level: level,
    encodeType: 'aac',
  };
  const params = cryptoMod.weapiParams(payload);
  const text = await http.postForm(
    constants.neteaseBase + '/weapi/song/enhance/player/url/v1',
    params
  );
  const response = JSON.parse(text);
  if (response.data && response.data.length > 0) {
    return response.data[0].url || '';
  }
  return '';
}

async function getSongUrl(id, levels) {
  const candidates = levels || ['exhigh', 'high', 'standard'];
  for (let i = 0; i < candidates.length; i++) {
    const level = candidates[i];
    try {
      const url = await requestSongUrl(id, level);
      if (url.length > 0) {
        return url;
      }
    } catch (e) {
      console.warn('netease getSongUrl level=' + level + ' failed: ' + e.message);
    }
  }
  // 备用免签名接口
  try {
    const legacy = await http.getText(
      constants.neteaseBase + '/api/song/enhance/player/url?ids=[' + id + ']&br=320000'
    );
    const parsed = JSON.parse(legacy);
    if (parsed.data && parsed.data.length > 0 && parsed.data[0].url) {
      return parsed.data[0].url;
    }
  } catch (e) {
    console.warn('netease legacy url failed: ' + e.message);
  }
  return '';
}

async function getLyric(id) {
  const text = await http.getText(
    constants.neteaseBase + '/api/song/lyric?id=' + id + '&lv=-1&kv=-1&tv=-1'
  );
  const response = JSON.parse(text);
  return {
    lyric: (response.lrc && response.lrc.lyric) || '',
    translated: (response.tlyric && response.tlyric.lyric) || '',
  };
}

async function fetchSongDetail(ids) {
  const all = [];
  const chunkSize = 200;
  for (let offset = 0; offset < ids.length; offset += chunkSize) {
    const chunk = ids.slice(offset, offset + chunkSize);
    const text = await http.postForm(constants.neteaseBase + '/api/v3/song/detail', {
      c: JSON.stringify(chunk.map(function (id) { return { id: id }; })),
    });
    const response = JSON.parse(text);
    if (response.songs) {
      all.push.apply(all, response.songs);
    }
  }
  return all;
}

async function getPlaylistDetail(id) {
  const text = await http.getText(constants.neteaseBase + '/api/v6/playlist/detail?id=' + id);
  const response = JSON.parse(text);
  const playlist = response.playlist;
  if (!playlist) {
    return [];
  }
  let songs = playlist.tracks || [];
  if (songs.length === 0 && playlist.trackIds) {
    const ids = playlist.trackIds.slice(0, 200).map(function (track) { return track.id; });
    songs = await fetchSongDetail(ids);
  }
  return songs.map(toSongItem);
}

async function searchPlaylists(keyword, limit) {
  const payload = {
    s: keyword,
    type: 1000,
    limit: limit || 20,
    offset: 0,
    total: true,
  };
  const params = cryptoMod.weapiParams(payload);
  const text = await http.postForm(constants.neteaseBase + '/weapi/cloudsearch/get/web', params);
  const response = JSON.parse(text);
  const playlists = (response.result && response.result.playlists) || [];
  return playlists.map(function (item) {
    return {
      id: item.id,
      name: item.name || '',
      coverImgUrl: item.coverImgUrl || '',
      trackCount: item.trackCount || 0,
      creator: (item.creator && item.creator.nickname) || '',
    };
  });
}

module.exports = {
  search,
  getSongUrl,
  getLyric,
  getPlaylistDetail,
  searchPlaylists,
};
