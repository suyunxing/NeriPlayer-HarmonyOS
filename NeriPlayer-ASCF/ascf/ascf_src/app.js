const store = require('./common/store');
const settings = require('./common/settings');

App({
  onLaunch(options) {
    console.log('NeriPlayer ASCF onLaunch', JSON.stringify(options));
    const current = settings.load();
    if (!current.disclaimerAgreed) {
      has.reLaunch({
        url: '/pages/disclaimer/index',
      });
      return;
    }
    if (!current.onboarded) {
      has.reLaunch({
        url: '/pages/onboarding/index',
      });
      return;
    }
    store.restoreQueue();
  },
  onShow(options) {
    console.log('NeriPlayer ASCF onShow', JSON.stringify(options));
  },
  onHide() {
    console.log('NeriPlayer ASCF onHide');
  },
  onError(msg) {
    console.error('NeriPlayer ASCF onError', JSON.stringify(msg));
  },
});
