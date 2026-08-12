/**
 * 本地歌单仓库（对应 LocalPlaylistRepository.ets）。
 */

const constants = require('./constants');
const storage = require('./storage');
const { stableKeyOf } = require('./song');

function load() {
  return storage.getJson(constants.keyPlaylists, []);
}

function save(playlists) {
  storage.setJson(constants.keyPlaylists, playlists);
}

function create(name) {
  const playlists = load();
  const playlist = {
    id: 'pl_' + Date.now() + '_' + Math.floor(Math.random() * 10000),
    name: name || '新建歌单',
    coverUrl: '',
    description: '',
    source: 0,
    songKeys: [],
    songs: [],
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  playlists.unshift(playlist);
  save(playlists);
  return playlist;
}

function remove(id) {
  const playlists = load().filter(function (item) {
    return item.id !== id;
  });
  save(playlists);
  return playlists;
}

function addSong(playlistId, song) {
  const playlists = load();
  const playlist = playlists.find(function (item) {
    return item.id === playlistId;
  });
  if (!playlist) {
    return null;
  }
  const key = stableKeyOf(song);
  if (playlist.songKeys.indexOf(key) < 0) {
    playlist.songKeys.push(key);
    playlist.songs.push(song);
    playlist.updatedAt = Date.now();
    save(playlists);
  }
  return playlist;
}

function removeSong(playlistId, song) {
  const playlists = load();
  const playlist = playlists.find(function (item) {
    return item.id === playlistId;
  });
  if (!playlist) {
    return null;
  }
  const key = stableKeyOf(song);
  const index = playlist.songKeys.indexOf(key);
  if (index >= 0) {
    playlist.songKeys.splice(index, 1);
    playlist.songs.splice(index, 1);
    playlist.updatedAt = Date.now();
    save(playlists);
  }
  return playlist;
}

module.exports = { load, save, create, remove, addSong, removeSong };
