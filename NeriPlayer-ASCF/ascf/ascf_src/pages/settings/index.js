const store = require('../../common/store');
const settings = require('../../common/settings');
const constants = require('../../config/global.config');
const player = require('../../common/player');
const pageHelper = require('../../common/page-helper');

Page({
  data: {
    settings: {},
    appVersion: constants.appVersion,
    speedIndex: 1,
  },

  onShow() {
    const current = settings.load();
    this.setData({
      settings: current,
      speedIndex: [1.0, 1.25, 1.5, 2.0].indexOf(current.speed) >= 0
        ? [1.0, 1.25, 1.5, 2.0].indexOf(current.speed)
        : 0,
    });
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

  onPlatformChange(e) {
    const value = Number(e.currentTarget.dataset.value);
    const next = settings.update({ selectedPlatform: value });
    this.setData({ settings: next });
  },

  onQualityChange(e) {
    const value = e.currentTarget.dataset.value;
    const next = settings.update({ quality: value });
    this.setData({ settings: next });
  },

  onSpeedChange(e) {
    const value = Number(e.currentTarget.dataset.value);
    const next = settings.update({ speed: value });
    player.setSpeed(value);
    this.setData({ settings: next });
  },

  onSwitchChange(e) {
    const field = e.currentTarget.dataset.field;
    const value = e.detail.value;
    const next = settings.update({ [field]: value });
    this.setData({ settings: next });
  },

  onThemeChange(e) {
    const value = e.currentTarget.dataset.value;
    const next = settings.update({ theme: value });
    this.setData({ settings: next });
  },

  onDebugTap() {
    has.navigateTo({ url: '/pages/debug/index' });
  },

  onDisclaimerTap() {
    has.navigateTo({ url: '/pages/disclaimer/index' });
  },

  onOpenPlayer() {
    pageHelper.openPlayer();
  },

  onTogglePlayer() {
    player.togglePlayPause();
  },
});
