const downloadsRepo = require('../../common/downloads');
const player = require('../../common/player');

Page({
  data: {
    items: [],
  },

  onShow() {
    this.refresh();
  },

  refresh() {
    this.setData({ items: downloadsRepo.load() });
  },

  onSongTap(e) {
    const index = e.detail.index;
    const items = this.data.items;
    const songs = items.map(function (item) {
      const song = item.song;
      song.streamUrl = song.streamUrl || item.localPath;
      return song;
    });
    player.playPlaylist(songs, index);
    has.navigateTo({ url: '/pages/now-playing/index' });
  },

  onSongMenu(e) {
    const item = this.data.items[e.detail.index];
    has.showModal({
      title: '删除下载',
      content: '确定删除这条下载记录吗？',
      confirmText: '删除',
      confirmColor: '#e57373',
      success: function (res) {
        if (res.confirm) {
          downloadsRepo.remove(item.key);
          this.refresh();
        }
      }.bind(this),
    });
  },
});
