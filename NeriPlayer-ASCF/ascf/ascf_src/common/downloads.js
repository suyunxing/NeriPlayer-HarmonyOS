/**
 * 下载仓库（has.downloadFile 保存到沙箱，记录本地路径）。
 */

const constants = require('./constants');
const storage = require('./storage');
const { stableKeyOf } = require('./song');

function load() {
  return storage.getJson(constants.keyDownloads, []);
}

function save(items) {
  storage.setJson(constants.keyDownloads, items);
}

function add(song, localPath) {
  const items = load();
  const key = stableKeyOf(song);
  const existing = items.find(function (item) {
    return item.key === key;
  });
  const entry = {
    key: key,
    song: song,
    localPath: localPath,
    downloadedAt: Date.now(),
    status: 'done',
  };
  if (existing) {
    existing.song = song;
    existing.localPath = localPath;
    existing.downloadedAt = entry.downloadedAt;
  } else {
    items.unshift(entry);
  }
  save(items);
  return items;
}

function remove(key) {
  const items = load().filter(function (item) {
    return item.key !== key;
  });
  save(items);
  return items;
}

module.exports = { load, save, add, remove };
