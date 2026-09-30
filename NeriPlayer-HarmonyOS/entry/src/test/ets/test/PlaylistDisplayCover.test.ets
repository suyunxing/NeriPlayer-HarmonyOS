import { describe, it, expect } from '@ohos/hypium';
import { Playlist } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

function neteaseSong(id: number, coverUrl: string): SongItem {
  const item = new SongItem(id, `歌${id}`, '歌手', '专辑', id * 10, 100, coverUrl, '', MusicPlatform.NETEASE);
  item.channelId = 'netease';
  item.audioId = `${id}`;
  return item;
}

function playlistWith(coverUrl: string, songs: SongItem[]): Playlist {
  const playlist = new Playlist('local_1', '测试歌单', MusicPlatform.LOCAL);
  playlist.coverUrl = coverUrl;
  playlist.songs = songs;
  playlist.songKeys = songs.map((song: SongItem): string => `${song.platform}_${song.audioId}`);
  return playlist;
}

export default function playlistDisplayCoverTest(): void {
  describe('PlaylistDisplayCover', () => {
    it('firstSongCoverWins', 0, () => {
      const playlist = playlistWith('https://legacy/cover.jpg',
        [neteaseSong(1, 'https://p/1.jpg'), neteaseSong(2, 'https://p/2.jpg')]);
      expect(playlist.displayCoverUrl).assertEqual('https://p/1.jpg');
    });

    it('customCoverBeatsFirstSongCover', 0, () => {
      const first = neteaseSong(1, 'https://p/1.jpg');
      first.customCoverUrl = 'https://custom/1.jpg';
      const playlist = playlistWith('', [first]);
      expect(playlist.displayCoverUrl).assertEqual('https://custom/1.jpg');
    });

    it('emptyPlaylistFallsBackToPlaylistCover', 0, () => {
      const playlist = playlistWith('https://legacy/cover.jpg', []);
      expect(playlist.displayCoverUrl).assertEqual('https://legacy/cover.jpg');
    });

    it('coverlessFirstSongFallsBackToPlaylistCover', 0, () => {
      const playlist = playlistWith('https://legacy/cover.jpg', [neteaseSong(1, '')]);
      expect(playlist.displayCoverUrl).assertEqual('https://legacy/cover.jpg');
    });

    it('allEmptyYieldsEmptyForPlaceholder', 0, () => {
      const playlist = playlistWith('', [neteaseSong(1, '')]);
      expect(playlist.displayCoverUrl).assertEqual('');
    });
  });
}
