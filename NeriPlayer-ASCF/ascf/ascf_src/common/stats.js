/**
 * 播放统计仓库（对应 PlaybackStatsRepository.ets）。
 */

const constants = require('./constants');
const storage = require('./storage');
const { stableKeyOf } = require('./song');

function load() {
  return storage.getJson(constants.keyStats, { songs: {}, totalMs: 0 });
}

function recordPlay(song, listenedMs) {
  const stats = load();
  const key = stableKeyOf(song);
  const entry = stats.songs[key] || {
    name: song.name,
    artist: song.artist,
    platform: song.platform,
    playCount: 0,
    listenedMs: 0,
    song: song,
  };
  entry.name = song.name;
  entry.artist = song.artist;
  entry.platform = song.platform;
  entry.song = song;
  entry.playCount += 1;
  entry.listenedMs += listenedMs || 0;
  stats.songs[key] = entry;
  stats.totalMs += listenedMs || 0;
  storage.setJson(constants.keyStats, stats);
  return stats;
}

function topSongs(limit) {
  const stats = load();
  const list = Object.keys(stats.songs).map(function (key) {
    return Object.assign({ key: key }, stats.songs[key]);
  });
  list.sort(function (a, b) {
    return b.listenedMs - a.listenedMs;
  });
  return list.slice(0, limit || 20);
}

module.exports = { load, recordPlay, topSongs };
