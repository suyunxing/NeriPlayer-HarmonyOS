import { describe, it, expect } from '@ohos/hypium';
import { AlbumSongs, AlbumQuery } from '../../../main/ets/util/AlbumSongs';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { Constants } from '../../../main/ets/app/Constants';

function neteaseSong(id: number, album: string, albumId: number): SongItem {
  const song = new SongItem(id, `song${id}`, 'a', album, albumId, 0, '', '', MusicPlatform.NETEASE);
  song.channelId = 'netease';
  song.audioId = `${id}`;
  return song;
}

export default function albumSongsTest(): void {
  describe('AlbumSongs', () => {
    it('placeholderAlbumCarriesNoData', 0, () => {
      const ytm = new SongItem(0, 'y', 'a', Constants.YOUTUBE_MUSIC_IDENTITY_ALBUM, 0, 0, '',
        'youtube_music|v', MusicPlatform.YOUTUBE_MUSIC);
      expect(AlbumSongs.hasAlbumData(ytm)).assertFalse();

      const unnamed = new SongItem(0, 'l', 'a', '  ', 0, 0, '', 'x', MusicPlatform.LOCAL);
      expect(AlbumSongs.hasAlbumData(unnamed)).assertFalse();

      const named = new SongItem(0, 'l', 'a', '华纳精选', 0, 0, '', 'x', MusicPlatform.LOCAL);
      expect(AlbumSongs.hasAlbumData(named)).assertTrue();
    });

    it('albumIdMatchWinsWhenPresent', 0, () => {
      const byId: AlbumQuery = { album: '精选', albumId: 42 };
      expect(AlbumSongs.matches(neteaseSong(1, '精选', 42), byId)).assertTrue();
      // Same album name but a different id: not the same album.
      expect(AlbumSongs.matches(neteaseSong(2, '精选', 43), byId)).assertFalse();
      expect(AlbumSongs.matches(neteaseSong(3, '别的', 42), byId)).assertTrue();
    });

    it('nameMatchUsedWithoutAlbumId', 0, () => {
      const byName: AlbumQuery = { album: '华纳精选', albumId: 0 };
      expect(AlbumSongs.matches(neteaseSong(1, '华纳精选', 0), byName)).assertTrue();
      expect(AlbumSongs.matches(neteaseSong(2, '其他', 0), byName)).assertFalse();
      const empty: AlbumQuery = { album: '', albumId: 0 };
      expect(AlbumSongs.matches(neteaseSong(3, '华纳精选', 0), empty)).assertFalse();
    });

    it('collectDedupesByStableKeyAndKeepsOrder', 0, () => {
      const query: AlbumQuery = { album: '华纳精选', albumId: 0 };
      const first = neteaseSong(1, '华纳精选', 0);
      // Same identity imported twice: deduped to one entry.
      const duplicate = neteaseSong(1, '华纳精选', 0);
      const other = neteaseSong(2, '华纳精选', 0);
      const collected = AlbumSongs.collect([first, duplicate, other, neteaseSong(3, '别的', 0)], query);
      expect(collected.length).assertEqual(2);
      expect(collected[0].id).assertEqual(1);
      expect(collected[1].id).assertEqual(2);
    });
  });
}
