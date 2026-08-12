const playlistsRepo = require('../../common/playlists');
const storage = require('../../common/storage');

Page({
  data: {
    playlists: [],
    pendingSong: null,
  },

  onShow() {
    this.refresh();
    const pending = storage.getJson('app.pendingAddSong', null);
    if (pending && pending.name) {
      this.setData({ pendingSong: pending });
    }
  },

  refresh() {
    this.setData({ playlists: playlistsRepo.load() });
  },

  onCreateTap() {
    has.navigateTo({ url: '/pages/playlist-create/index' });
  },

  onPlaylistTap(e) {
    const id = e.currentTarget.dataset.id;
    const pending = this.data.pendingSong;
    if (pending) {
      playlistsRepo.addSong(id, pending);
      storage.remove('app.pendingAddSong');
      this.setData({ pendingSong: null });
      has.showToast({ title: '已添加' });
      return;
    }
    has.navigateTo({ url: '/pages/playlist-detail/index?id=' + encodeURIComponent(id) });
  },

  onPendingCancel() {
    storage.remove('app.pendingAddSong');
    this.setData({ pendingSong: null });
  },
});
