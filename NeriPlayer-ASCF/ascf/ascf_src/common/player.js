/**
 * 播放核心：队列、随机/循环、流解析、失败重试、统计采集。
 * 基于 has.getBackgroundAudioManager()（ASCF 框架全局背景音频），
 * 行为对齐 PlayerManager.ets。
 */

const store = require('./store');
const settingsRepo = require('./settings');
const history = require('./history');
const stats = require('./stats');
const resolver = require('./resolver');
const lyric = require('./lyric');
const { stableKeyOf } = require('./song');

let manager = null;
let errorAttempts = 0;
let listenedMs = 0;
let lastTimeMs = 0;
let lastPublishMs = 0;
let eventsAttached = false;

function getManager() {
  if (!manager) {
    manager = has.getBackgroundAudioManager();
  }
  return manager;
}

function attachEvents() {
  if (eventsAttached) {
    return;
  }
  eventsAttached = true;
  const bgm = getManager();

  bgm.onPlay(function () {
    store.setState({ status: 2, errorMessage: '' });
  });

  bgm.onPause(function () {
    store.setState({ status: 3 });
    flushStats();
  });

  bgm.onStop(function () {
    store.setState({ status: 3 });
    flushStats();
  });

  bgm.onTimeUpdate(function () {
    const timeMs = Math.floor((bgm.currentTime || 0) * 1000);
    const st = store.getState();
    if (st.status === 2) {
      const delta = Math.max(0, timeMs - lastTimeMs);
      listenedMs += delta;
    }
    lastTimeMs = timeMs;
    const durationMs = Math.floor((bgm.duration || 0) * 1000);
    const now = Date.now();
    if (now - lastPublishMs > 400) {
      lastPublishMs = now;
      store.setState({
        positionMs: timeMs,
        durationMs: durationMs > 0 ? durationMs : st.durationMs,
      });
    }
  });

  bgm.onEnded(function () {
    flushStats();
    const st = store.getState();
    if (st.repeatMode === 1) {
      try {
        bgm.seek(0);
        bgm.play();
      } catch (e) {
        console.warn('repeat-one restart failed: ' + e.message);
      }
      return;
    }
    next(true);
  });

  bgm.onNext(function () {
    next(false);
  });

  bgm.onPrev(function () {
    previous();
  });

  bgm.onError(function (res) {
    const message = (res && (res.errMsg || res.errCode)) || 'audio error';
    store.setState({ status: 5, errorMessage: '' + message });
    console.error('BackgroundAudioManager error: ' + message);
    handleLoadFailure();
  });
}

function getCurrentSong() {
  const st = store.getState();
  if (st.orderIndex < 0 || st.orderIndex >= st.order.length) {
    return null;
  }
  const queueIndex = st.order[st.orderIndex];
  if (queueIndex < 0 || queueIndex >= st.queue.length) {
    return null;
  }
  return st.queue[queueIndex];
}

async function playPlaylist(songs, startIndex) {
  if (!songs || songs.length === 0) {
    return;
  }
  attachEvents();
  const queue = songs.slice();
  const order = buildOrder(queue, startIndex || 0);
  store.setState({ queue: queue, order: order, orderIndex: 0 });
  store.persistQueue();
  await loadSong(0);
}

async function play() {
  const bgm = getManager();
  const st = store.getState();
  if (st.status === 3 && bgm.src) {
    try {
      bgm.play();
      return;
    } catch (e) {
      console.warn('play resume failed: ' + e.message);
    }
  }
  if (!getCurrentSong()) {
    if (st.queue.length > 0) {
      await loadSong(0);
    }
    return;
  }
  if (st.status === 4) {
    try {
      bgm.seek(0);
      bgm.play();
    } catch (e) {
      console.warn('replay failed: ' + e.message);
    }
  }
}

function pause() {
  const bgm = getManager();
  if (!bgm.src) {
    return;
  }
  try {
    bgm.pause();
  } catch (e) {
    console.warn('pause failed: ' + e.message);
  }
}

function togglePlayPause() {
  const st = store.getState();
  if (st.status === 2) {
    pause();
  } else {
    play();
  }
}

async function next(auto) {
  const st = store.getState();
  const nextIndex = nextOrderIndex();
  if (nextIndex < 0) {
    if (!auto) {
      pause();
    }
    store.setState({ status: 4, positionMs: 0 });
    return;
  }
  await loadSong(nextIndex);
}

async function previous() {
  const st = store.getState();
  if (st.order.length === 0) {
    return;
  }
  const prevIndex = st.orderIndex - 1;
  const target = prevIndex < 0 ? st.order.length - 1 : prevIndex;
  await loadSong(target);
}

function seekTo(timeMs) {
  const bgm = getManager();
  if (!bgm.src) {
    return;
  }
  try {
    bgm.seek(Math.max(0, timeMs) / 1000);
  } catch (e) {
    console.warn('seek failed: ' + e.message);
  }
}

function setShuffle(enabled) {
  const st = store.getState();
  const currentQueueIndex =
    st.order.length > 0 ? st.order[Math.min(st.orderIndex, st.order.length - 1)] : 0;
  const order = buildOrder(st.queue, currentQueueIndex, enabled);
  store.setState({ shuffle: enabled, order: order, orderIndex: 0 });
  store.persistQueue();
}

function setRepeatMode(mode) {
  store.setState({ repeatMode: mode });
  store.persistQueue();
}

function setSpeed(speed) {
  store.setState({ speed: speed });
  const settings = settingsRepo.load();
  settings.speed = speed;
  settingsRepo.save(settings);
}

async function loadSong(orderIndex) {
  const st = store.getState();
  if (orderIndex < 0 || orderIndex >= st.order.length) {
    return;
  }
  attachEvents();
  store.setState({ orderIndex: orderIndex });
  errorAttempts = 0;
  const song = getCurrentSong();
  if (!song) {
    return;
  }
  flushStats();
  lastTimeMs = 0;
  const settings = settingsRepo.load();
  store.setState({
    positionMs: 0,
    durationMs: song.durationMs || 0,
    status: 1,
    currentSong: song,
    lyrics: [],
    lyricSource: '',
    errorMessage: '',
    speed: settings.speed || 1.0,
  });
  store.persistQueue();

  if (settings.enableHistory !== false) {
    history.addSong(song);
  }
  loadLyrics(song);

  try {
    const uri = await resolver.resolve(song);
    if (!uri || uri.length === 0) {
      throw new Error('无法解析可播放的流地址');
    }
    const bgm = getManager();
    bgm.title = song.customName || song.name;
    bgm.singer = song.customArtist || song.artist;
    bgm.epname = song.album;
    if (song.customCoverUrl || song.coverUrl) {
      bgm.coverImgUrl = song.customCoverUrl || song.coverUrl;
    }
    bgm.src = uri;
    bgm.play();
  } catch (e) {
    console.error('loadSong failed for ' + song.name + ': ' + e.message);
    store.setState({ status: 5, errorMessage: e.message });
    handleLoadFailure();
  }
}

function handleLoadFailure() {
  errorAttempts += 1;
  const st = store.getState();
  if (errorAttempts < 2) {
    console.warn('retrying playback (attempt ' + errorAttempts + ')');
    loadSong(st.orderIndex);
    return;
  }
  console.warn('giving up, skipping to next');
  next(true);
}

function nextOrderIndex() {
  const st = store.getState();
  if (st.order.length === 0) {
    return -1;
  }
  const nextIndex = st.orderIndex + 1;
  if (nextIndex < st.order.length) {
    return nextIndex;
  }
  return st.repeatMode === 2 ? 0 : -1;
}

function buildOrder(queue, startQueueIndex, shuffleOverride) {
  const st = store.getState();
  const shuffle = shuffleOverride !== undefined ? shuffleOverride : st.shuffle;
  const count = queue.length;
  if (!shuffle) {
    const order = [];
    for (let i = 0; i < count; i++) {
      order.push(i);
    }
    return order;
  }
  const remaining = [];
  for (let i = 0; i < count; i++) {
    if (i !== startQueueIndex) {
      remaining.push(i);
    }
  }
  for (let i = remaining.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = remaining[i];
    remaining[i] = remaining[j];
    remaining[j] = tmp;
  }
  return [startQueueIndex].concat(remaining);
}

function flushStats() {
  const st = store.getState();
  const song = getCurrentSong();
  if (!song || listenedMs <= 0) {
    return;
  }
  const amount = listenedMs;
  listenedMs = 0;
  const settings = settingsRepo.load();
  if (settings.enableStats !== false) {
    stats.recordPlay(song, amount);
  }
}

async function loadLyrics(song) {
  try {
    const payload = await lyric.fetchLyrics(song);
    const lines = lyric.mergeTranslation(
      lyric.parse(payload.lyric),
      payload.translated
    );
    const st = store.getState();
    if (st.currentSong && stableKeyOf(st.currentSong) === stableKeyOf(song)) {
      store.setState({ lyrics: lines, lyricSource: lines.length > 0 ? 'ok' : 'none' });
    }
  } catch (e) {
    console.warn('lyrics load failed: ' + e.message);
  }
}

module.exports = {
  playPlaylist,
  play,
  pause,
  togglePlayPause,
  next,
  previous,
  seekTo,
  setShuffle,
  setRepeatMode,
  setSpeed,
  getCurrentSong,
};
