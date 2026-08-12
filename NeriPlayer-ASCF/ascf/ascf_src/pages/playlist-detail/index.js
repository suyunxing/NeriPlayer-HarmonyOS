const playlistsRepo = require('../../common/playlists');
const player = require('../../common/player');
const downloadsRepo = require('../../common/downloads');
const resolver = require('../../common/resolver');

Page({
  data: {
    playlist: null,
    songs: [],
  },

  onLoad(options) {
    const id = decodeURIComponent(options.id || '');
    const playlist = playlistsRepo.load().find(function (item) {
      return item.id === id;
    });
    this.setData({
      playlist: playlist || null,
      songs: playlist ? playlist.songs : [],
    });
  },

  onPlayAll() {
    if (this.data.songs.length === 0) {
      has.showToast({ title: '歌单为空' });
      return;
    }
    player.playPlaylist(this.data.songs, 0);
    has.navigateTo({ url: '/pages/now-playing/index' });
  },

  onSongTap(e) {
    const index = e.detail.index;
    player.playPlaylist(this.data.songs, index);
    has.navigateTo({ url: '/pages/now-playing/index' });
  },

  onSongMenu(e) {
    const song = e.detail.song;
    has.showActionSheet({
      itemList: ['从歌单移除', '下载'],
      success: function (res) {
        if (res.tapIndex === 0) {
          playlistsRepo.removeSong(this.data.playlist.id, song);
          this.reload();
        } else if (res.tapIndex === 1) {
          this.downloadSong(song);
        }
      }.bind(this),
    });
  },

  downloadSong(song) {
    has.showLoading({ title: '解析地址' });
    resolver
      .resolve(song)
      .then(
        function (url) {
          if (!url) {
            has.hideLoading();
            has.showToast({ title: '无法解析播放地址' });
            return;
          }
          has.downloadFile({
            url: url,
            success: function (res) {
              has.hideLoading();
              if (res.statusCode === 200 && res.tempFilePath) {
                downloadsRepo.add(song, res.tempFilePath);
                has.showToast({ title: '下载完成' });
              } else {
                has.showToast({ title: '下载失败' });
              }
            },
            fail: function () {
              has.hideLoading();
              has.showToast({ title: '下载失败' });
            },
          });
        }.bind(this)
      )
      .catch(function () {
        has.hideLoading();
        has.showToast({ title: '下载失败' });
      });
  },

  reload() {
    const id = this.data.playlist.id;
    const playlist = playlistsRepo.load().find(function (item) {
      return item.id === id;
    });
    this.setData({
      playlist: playlist || null,
      songs: playlist ? playlist.songs : [],
    });
  },

  onDeletePlaylist() {
    has.showModal({
      title: '删除歌单',
      content: '确定删除这个歌单吗？',
      confirmText: '删除',
      confirmColor: '#e57373',
      success: function (res) {
        if (res.confirm) {
          playlistsRepo.remove(this.data.playlist.id);
          has.navigateBack();
        }
      }.bind(this),
    });
  },
});
