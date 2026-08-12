const constants = require('../../config/global.config');
const storage = require('../../common/storage');
const netease = require('../../common/netease');

Page({
  data: {
    appVersion: constants.appVersion,
    systemInfo: null,
    networkType: '未知',
    storageInfo: null,
    testResult: '',
    testing: false,
    apiChecks: [],
  },

  onLoad() {
    this.runChecks();
  },

  runChecks() {
    const checks = [];
    const candidates = [
      ['has.request', function () { return typeof has.request === 'function'; }],
      ['getBackgroundAudioManager', function () { return typeof has.getBackgroundAudioManager === 'function'; }],
      ['setStorageSync', function () { return typeof has.setStorageSync === 'function'; }],
      ['downloadFile', function () { return typeof has.downloadFile === 'function'; }],
      ['getFileSystemManager', function () { return typeof has.getFileSystemManager === 'function'; }],
      ['getNetworkType', function () { return typeof has.getNetworkType === 'function'; }],
      ['showActionSheet', function () { return typeof has.showActionSheet === 'function'; }],
      ['getRandomValues', function () { return typeof has.getRandomValues === 'function'; }],
    ];
    for (let i = 0; i < candidates.length; i++) {
      try {
        checks.push({ name: candidates[i][0], ok: candidates[i][1]() });
      } catch (e) {
        checks.push({ name: candidates[i][0], ok: false });
      }
    }
    let systemInfo = null;
    try {
      systemInfo = has.getSystemInfoSync();
    } catch (e) {
      systemInfo = { error: e.message };
    }
    this.setData({ apiChecks: checks, systemInfo: systemInfo });
    has.getNetworkType({
      success: function (res) {
        this.setData({ networkType: res.networkType || '未知' });
      }.bind(this),
    });
    try {
      const info = has.getStorageInfoSync();
      this.setData({ storageInfo: info });
    } catch (e) {
      this.setData({ storageInfo: { error: e.message } });
    }
  },

  onTestNetease() {
    if (this.data.testing) {
      return;
    }
    this.setData({ testing: true, testResult: '测试中...' });
    netease
      .search('周杰伦', 3)
      .then(
        function (songs) {
          this.setData({
            testing: false,
            testResult: '搜索成功，返回 ' + songs.length + ' 首：' + (songs[0] ? songs[0].name + ' - ' + songs[0].artist : ''),
          });
        }.bind(this)
      )
      .catch(function (e) {
        this.setData({ testing: false, testResult: '搜索失败：' + e.message });
      }.bind(this));
  },

  onClearStorage() {
    has.showModal({
      title: '清空数据',
      content: '将清空历史、歌单、统计与下载记录，确定？',
      confirmText: '清空',
      confirmColor: '#e57373',
      success: function (res) {
        if (res.confirm) {
          has.clearStorageSync();
          has.showToast({ title: '已清空' });
        }
      },
    });
  },
});
