Component({
  data: {
    visible: false,
    title: '',
    artist: '',
    coverUrl: '',
    playing: false,
    loading: false,
  },
  methods: {
    refresh(snapshot) {
      const song = snapshot.currentSong;
      this.setData({
        visible: !!song,
        title: song ? song.customName || song.name || '' : '',
        artist: song ? song.customArtist || song.artist || '' : '',
        coverUrl: song ? song.customCoverUrl || song.coverUrl || '' : '',
        playing: snapshot.status === 2,
        loading: snapshot.status === 1,
      });
    },
    onOpen() {
      this.triggerEvent('open');
    },
    onToggle() {
      this.triggerEvent('toggle');
    },
  },
});
