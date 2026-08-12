const store = require('../../common/store');
const player = require('../../common/player');
const format = require('../../common/format');
const { displayName, displayArtist, effectiveCoverUrl } = require('../../common/song');

Page({
  data: {
    title: '',
    artist: '',
    coverUrl: '',
    statusText: '',
    playing: false,
    loading: false,
    positionText: '0:00',
    durationText: '0:00',
    positionMs: 0,
    durationMs: 0,
    sliderValue: 0,
    seeking: false,
    repeatMode: 2,
    shuffle: false,
    lyrics: [],
    lyricSource: '',
    currentLine: -1,
    errorMessage: '',
  },

  onLoad() {
    if (this.unsubscribe) {
      this.unsubscribe();
    }
    this.unsubscribe = store.subscribe(
      function (snapshot) {
        this.applySnapshot(snapshot);
      }.bind(this)
    );
    this.applySnapshot(store.getState());
  },

  onUnload() {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  },

  applySnapshot(snapshot) {
    const song = snapshot.currentSong;
    let currentLine = -1;
    const lyrics = snapshot.lyrics || [];
    for (let i = 0; i < lyrics.length; i++) {
      if (lyrics[i].timeMs <= snapshot.positionMs) {
        currentLine = i;
      } else {
        break;
      }
    }
    let statusText = '未播放';
    if (snapshot.status === 1) {
      statusText = '加载中';
    } else if (snapshot.status === 2) {
      statusText = '播放中';
    } else if (snapshot.status === 3) {
      statusText = '已暂停';
    } else if (snapshot.status === 4) {
      statusText = '播放完成';
    } else if (snapshot.status === 5) {
      statusText = '出错了';
    }
    const durationMs = snapshot.durationMs || (song && song.durationMs) || 0;
    this.setData({
      title: song ? displayName(song) : '',
      artist: song ? displayArtist(song) : '',
      coverUrl: song ? effectiveCoverUrl(song) : '',
      statusText: statusText,
      playing: snapshot.status === 2,
      loading: snapshot.status === 1,
      positionMs: snapshot.positionMs,
      durationMs: durationMs,
      positionText: format.formatTime(snapshot.positionMs),
      durationText: format.formatTime(durationMs),
      sliderValue: durationMs > 0 ? snapshot.positionMs : 0,
      repeatMode: snapshot.repeatMode,
      shuffle: snapshot.shuffle,
      lyrics: lyrics,
      lyricSource: snapshot.lyricSource || '',
      currentLine: currentLine,
      errorMessage: snapshot.errorMessage || '',
    });
  },

  onTogglePlay() {
    player.togglePlayPause();
  },

  onNext() {
    player.next(false);
  },

  onPrev() {
    player.previous();
  },

  onRepeatTap() {
    const modes = [0, 1, 2];
    const next = modes[(this.data.repeatMode + 1) % 3];
    player.setRepeatMode(next);
  },

  onShuffleTap() {
    player.setShuffle(!this.data.shuffle);
  },

  onSliderChanging(e) {
    const value = e.detail.value;
    this.setData({
      seeking: true,
      positionMs: value,
      positionText: format.formatTime(value),
      sliderValue: value,
    });
  },

  onSliderChange(e) {
    const value = e.detail.value;
    this.setData({ seeking: false });
    player.seekTo(value);
  },

  onLyricTap() {
    has.showToast({ title: this.data.lyricSource === 'ok' ? '歌词已加载' : '暂无歌词' });
  },
});
