const store = require('../../common/store');
const settings = require('../../common/settings');
const history = require('../../common/history');
const player = require('../../common/player');
const pageHelper = require('../../common/page-helper');

Page({
  data: {
    greeting: '',
    history: [],
    statsSummary: '',
  },

  onLoad() {
    const current = settings.load();
    if (!current.disclaimerAgreed) {
      has.reLaunch({ url: '/pages/disclaimer/index' });
      return;
    }
    if (!current.onboarded) {
      has.reLaunch({ url: '/pages/onboarding/index' });
      return;
    }
    this.refresh();
  },

  onShow() {
    this.refresh();
    if (this.unsubscribe) {
      this.unsubscribe();
    }
    this.unsubscribe = pageHelper.subscribePage(this, function (snapshot) {
      return { playing: snapshot.status === 2 };
    });
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
    const hour = new Date().getHours();
    let greeting = '你好';
    if (hour >= 5 && hour < 12) {
      greeting = '早上好';
    } else if (hour >= 12 && hour < 18) {
      greeting = '下午好';
    } else {
      greeting = '晚上好';
    }
    this.setData({
      greeting: greeting,
      history: history.load().slice(0, 20),
    });
  },

  onSearchTap() {
    has.navigateTo({ url: '/pages/search/index?platform=' + settings.get('selectedPlatform', 1) });
  },

  onHistoryTap(e) {
    const index = e.currentTarget.dataset.index;
    const songs = history.load();
    player.playPlaylist(songs, index);
  },

  onOpenPlayer() {
    pageHelper.openPlayer();
  },

  onTogglePlayer() {
    player.togglePlayPause();
  },
});
