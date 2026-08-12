const store = require('../../common/store');
const settings = require('../../common/settings');
const netease = require('../../common/netease');
const bili = require('../../common/bili');
const ytmusic = require('../../common/ytmusic');
const player = require('../../common/player');
const pageHelper = require('../../common/page-helper');
const storage = require('../../common/storage');

const SUGGESTIONS = {
  1: ['周杰伦', '陈奕迅', '许嵩', 'Taylor Swift', '钢琴曲'],
  2: ['周深 音乐', '纯音乐', '古风', '钢琴 演奏'],
  3: ['lofi', 'jazz', 'pop hits', 'classical'],
};

Page({
  data: {
    platform: 1,
    keyword: '',
    results: [],
    searching: false,
    searched: false,
    suggestions: SUGGESTIONS[1],
    errorMessage: '',
  },

  onLoad(options) {
    const platform = Number(options.platform || settings.get('selectedPlatform', 1));
    this.setData({
      platform: platform,
      suggestions: SUGGESTIONS[platform] || SUGGESTIONS[1],
    });
  },

  onShow() {
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
    const platform = Number(e.currentTarget.dataset.platform);
    settings.update({ selectedPlatform: platform });
    this.setData({
      platform: platform,
      suggestions: SUGGESTIONS[platform] || SUGGESTIONS[1],
      results: [],
      searched: false,
    });
  },

  onKeywordInput(e) {
    this.setData({ keyword: e.detail.value });
  },

  onSuggestionTap(e) {
    const keyword = e.currentTarget.dataset.keyword;
    this.setData({ keyword: keyword });
    this.doSearch(keyword);
  },

  onSearchTap() {
    const keyword = this.data.keyword.trim();
    if (!keyword) {
      has.showToast({ title: '请输入搜索关键词' });
      return;
    }
    this.doSearch(keyword);
  },

  doSearch(keyword) {
    const platform = this.data.platform;
    this.setData({ searching: true, errorMessage: '', searched: true });
    const promise =
      platform === 1
        ? netease.search(keyword, 30)
        : platform === 2
          ? bili.search(keyword, 20)
          : ytmusic.search(keyword, 20);
    promise
      .then(function (results) {
        this.setData({ results: results || [], searching: false });
      }.bind(this))
      .catch(function (e) {
        this.setData({
          searching: false,
          errorMessage: e && e.message ? e.message : '搜索失败，请检查网络',
        });
      }.bind(this));
  },

  onResultTap(e) {
    const index = e.detail.index;
    player.playPlaylist(this.data.results, index);
    has.navigateTo({ url: '/pages/now-playing/index' });
  },

  onResultMenu(e) {
    const song = e.detail.song;
    has.showActionSheet({
      itemList: ['加入歌单'],
      success: function () {
        storage.setJson('app.pendingAddSong', song);
        has.navigateTo({ url: '/pages/playlists/index' });
      },
    });
  },

  onOpenPlayer() {
    pageHelper.openPlayer();
  },

  onTogglePlayer() {
    player.togglePlayPause();
  },
});
