const settings = require('../../common/settings');

Page({
  data: {
    platform: 1,
  },

  onPlatformTap(e) {
    this.setData({ platform: Number(e.currentTarget.dataset.platform) });
  },

  onStart() {
    settings.update({ onboarded: true, selectedPlatform: this.data.platform });
    has.reLaunch({ url: '/pages/main/index' });
  },
});
