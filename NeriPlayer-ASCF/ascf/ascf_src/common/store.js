/**
 * 全局播放状态 + 轻量订阅分发（对应 AppStorage + PlayerListener）。
 */

const constants = require('./constants');
const storage = require('./storage');

const listeners = [];

let state = {
  queue: [],
  order: [],
  orderIndex: -1,
  shuffle: false,
  repeatMode: 2, // 0 off / 1 one / 2 all
  speed: 1.0,
  status: 0, // 0 idle / 1 loading / 2 playing / 3 paused / 4 completed / 5 error
  positionMs: 0,
  durationMs: 0,
  currentSong: null,
  lyrics: [],
  lyricSource: '',
  errorMessage: '',
};

function getState() {
  return state;
}

function setState(patch) {
  state = Object.assign({}, state, patch);
  notify();
}

function subscribe(fn) {
  if (listeners.indexOf(fn) < 0) {
    listeners.push(fn);
  }
  return function () {
    const index = listeners.indexOf(fn);
    if (index >= 0) {
      listeners.splice(index, 1);
    }
  };
}

function notify() {
  const snapshot = state;
  for (let i = 0; i < listeners.length; i++) {
    try {
      listeners[i](snapshot);
    } catch (e) {
      console.error('store listener error: ' + e.message);
    }
  }
}

function persistQueue() {
  storage.setJson(constants.keyQueueJson, {
    songs: state.queue,
    queueIndex: state.order.length > 0 ? state.order[Math.max(0, state.orderIndex)] : 0,
    repeatOne: state.repeatMode === 1,
    shuffle: state.shuffle,
  });
}

function restoreQueue() {
  const saved = storage.getJson(constants.keyQueueJson, null);
  if (!saved || !saved.songs || saved.songs.length === 0) {
    return;
  }
  const order = [];
  for (let i = 0; i < saved.songs.length; i++) {
    if (i !== Math.min(saved.queueIndex || 0, saved.songs.length - 1)) {
      order.push(i);
    }
  }
  // Fisher-Yates
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  order.unshift(Math.min(saved.queueIndex || 0, saved.songs.length - 1));
  state = Object.assign({}, state, {
    queue: saved.songs,
    order: saved.shuffle ? order : saved.songs.map(function (_, i) { return i; }),
    orderIndex: 0,
    shuffle: !!saved.shuffle,
    repeatMode: saved.repeatOne ? 1 : 2,
    status: 3,
    currentSong: saved.songs[Math.min(saved.queueIndex || 0, saved.songs.length - 1)] || null,
  });
}

module.exports = {
  getState,
  setState,
  subscribe,
  persistQueue,
  restoreQueue,
};
