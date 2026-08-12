const store = require('../../common/store');
const history = require('../../common/history');
const playlists = require('../../common/playlists');
const downloads = require('../../common/downloads');
const stats = require('../../common/stats');
const player = require('../../common/player');
const pageHelper = require('../../common/page-helper');

Page({
  data: {
    playlistCount: 0,
    historyCount: 0,
    downloadCount: 0,
    totalListenMs: 0,
    topSongs: [],
    localNotice: true,
  },

  onShow() {
    this.refresh();
    if (this.unsubscribe) {
      this.unsubscribe();
    }
    this.unsubscribe = pageHelper.subscribePage(this, null);
  },

  onHide() {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  },

  onUnload() {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  },

  refresh() {
    const statsData = stats.load();
    this.setData({
      playlistCount: playlists.load().length,
      historyCount: history.load().length,
      downloadCount: downloads.load().length,
      totalListenMs: statsData.totalMs || 0,
      totalListenHours: Math.round(((statsData.totalMs || 0) / 3600000) * 10) / 10,
      topSongs: stats.topSongs(5),
    });
  },

  onPlaylistsTap() {
    has.navigateTo({ url: '/pages/playlists/index' });
  },

  onDownloadsTap() {
    has.navigateTo({ url: '/pages/downloads/index' });
  },

  onLocalNoticeTap() {
    this.setData({ localNotice: !this.data.localNotice });
  },

  onTopSongTap(e) {
    const index = e.currentTarget.dataset.index;
    const songs = stats.topSongs(50).map(function (entry) {
      return entry.song;
    });
    player.playPlaylist(songs, index);
  },

  onOpenPlayer() {
    pageHelper.openPlayer();
  },

  onTogglePlayer() {
    player.togglePlayPause();
  },
});
