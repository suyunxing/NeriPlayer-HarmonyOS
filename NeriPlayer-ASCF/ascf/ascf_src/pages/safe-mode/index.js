const settings = require('../../common/settings');

Page({
  onExit() {
    settings.update({ safeMode: false });
    has.reLaunch({ url: '/pages/main/index' });
  },
});
