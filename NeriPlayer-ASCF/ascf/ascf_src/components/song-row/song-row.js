Component({
  properties: {
    song: {
      type: Object,
      value: null,
    },
    index: {
      type: Number,
      value: 0,
    },
    showIndex: {
      type: Boolean,
      value: false,
    },
    active: {
      type: Boolean,
      value: false,
    },
  },
  observers: {
    'song': function (song) {
      if (song && song.durationMs) {
        const totalSeconds = Math.floor(song.durationMs / 1000);
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = totalSeconds % 60;
        this.setData({
          durationText: minutes + ':' + (seconds < 10 ? '0' + seconds : '' + seconds),
        });
      } else {
        this.setData({ durationText: '' });
      }
    },
  },
  methods: {
    onTap() {
      this.triggerEvent('tap', { song: this.data.song, index: this.data.index });
    },
    onMenu() {
      this.triggerEvent('menu', { song: this.data.song, index: this.data.index });
    },
  },
});
