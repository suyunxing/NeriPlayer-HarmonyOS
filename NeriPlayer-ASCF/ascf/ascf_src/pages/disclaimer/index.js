const settings = require('../../common/settings');

Page({
  onAgree() {
    settings.update({ disclaimerAgreed: true });
    const current = settings.load();
    if (!current.onboarded) {
      has.reLaunch({ url: '/pages/onboarding/index' });
    } else {
      has.reLaunch({ url: '/pages/main/index' });
    }
  },

  onDisagree() {
    has.showToast({ title: '需要同意后才能使用' });
  },
});
