/**
 * 统一流地址解析（按平台分发 + 失败回退），
 * 移植自 StreamResolver.ets。
 */

const netease = require('./netease');
const bili = require('./bili');
const ytmusic = require('./ytmusic');

async function resolve(song) {
  if (song.streamUrl && song.streamUrl.length > 0) {
    return song.streamUrl;
  }
  switch (song.platform) {
    case 0:
      return song.localFilePath && song.localFilePath.length > 0
        ? song.localFilePath
        : song.mediaUri || '';
    case 1: {
      const numericId = Number(song.audioId);
      if (!Number.isNaN(numericId) && numericId > 0) {
        return netease.getSongUrl(numericId);
      }
      return '';
    }
    case 2: {
      const bvid = song.audioId || '';
      if (!bvid) {
        return '';
      }
      return bili.resolveAudioUrl(bvid);
    }
    case 3: {
      const videoId = song.audioId || '';
      if (!videoId) {
        return '';
      }
      return ytmusic.resolveStream(videoId);
    }
    default:
      return '';
  }
}

module.exports = { resolve };
