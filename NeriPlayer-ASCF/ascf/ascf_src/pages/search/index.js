const netease = require('../../common/netease');
const player = require('../../common/player');

Page({
  data: {
    keyword: '',
    mode: 'song', // song | playlist
    songs: [],
    playlists: [],
    searching: false,
    searched: false,
    errorMessage: '',
  },

  onKeywordInput(e) {
    this.setData({ keyword: e.detail.value });
  },

  onModeChange(e) {
    this.setData({
      mode: e.currentTarget.dataset.mode,
      songs: [],
      playlists: [],
      searched: false,
    });
  },

  onSearchTap() {
    const keyword = this.data.keyword.trim();
    if (!keyword) {
      has.showToast({ title: '请输入关键词' });
      return;
    }
    this.setData({ searching: true, searched: true, errorMessage: '' });
    if (this.data.mode === 'playlist') {
      netease
        .searchPlaylists(keyword, 20)
        .then(
          function (playlists) {
            this.setData({ playlists: playlists, searching: false });
          }.bind(this)
        )
        .catch(
          function (e) {
            this.setData({ searching: false, errorMessage: e.message });
          }.bind(this)
        );
    } else {
      netease
        .search(keyword, 30)
        .then(
          function (songs) {
            this.setData({ songs: songs, searching: false });
          }.bind(this)
        )
        .catch(
          function (e) {
            this.setData({ searching: false, errorMessage: e.message });
          }.bind(this)
        );
    }
  },

  onSongTap(e) {
    const index = e.detail.index;
    player.playPlaylist(this.data.songs, index);
    has.navigateTo({ url: '/pages/now-playing/index' });
  },

  onPlaylistTap(e) {
    const id = e.currentTarget.dataset.id;
    has.showLoading({ title: '加载歌单' });
    netease
      .getPlaylistDetail(id)
      .then(
        function (songs) {
          has.hideLoading();
          if (songs.length === 0) {
            has.showToast({ title: '歌单为空或加载失败' });
            return;
          }
          player.playPlaylist(songs, 0);
          has.navigateTo({ url: '/pages/now-playing/index' });
        }.bind(this)
      )
      .catch(function (e) {
        has.hideLoading();
        has.showToast({ title: '歌单加载失败' });
      });
  },
});
