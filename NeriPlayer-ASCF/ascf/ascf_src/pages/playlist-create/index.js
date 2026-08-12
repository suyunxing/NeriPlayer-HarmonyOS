const playlistsRepo = require('../../common/playlists');

Page({
  data: {
    name: '',
  },

  onNameInput(e) {
    this.setData({ name: e.detail.value });
  },

  onCreate() {
    const name = this.data.name.trim();
    if (!name) {
      has.showToast({ title: '请输入歌单名称' });
      return;
    }
    playlistsRepo.create(name);
    has.navigateBack();
  },
});
