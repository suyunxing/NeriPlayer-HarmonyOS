/**
 * 播放历史仓库（对应 HistoryRepository.ets），按稳定 key 去重。
 */

const constants = require('./constants');
const storage = require('./storage');
const { stableKeyOf } = require('./song');

const MAX_HISTORY = 200;

function load() {
  return storage.getJson(constants.keyHistory, []);
}

function save(items) {
  storage.setJson(constants.keyHistory, items);
}

function addSong(song) {
  if (!song || !song.name) {
    return load();
  }
  const key = stableKeyOf(song);
  const items = load();
  const filtered = items.filter(function (item) {
    return stableKeyOf(item) !== key;
  });
  filtered.unshift(song);
  const trimmed = filtered.slice(0, MAX_HISTORY);
  save(trimmed);
  return trimmed;
}

function clear() {
  save([]);
}

module.exports = { load, save, addSong, clear, MAX_HISTORY };
