import { describe, it, expect } from '@ohos/hypium';
import { mergePlaylistSongs } from '../../../main/ets/model/Playlist';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { stableKeyOf } from '../../../main/ets/model/SongIdentity';

function neteaseSong(id: number, name: string): SongItem {
  const item = new SongItem(id, name, '歌手', '专辑', id * 10, 100, `https://p/${id}.jpg`, '', MusicPlatform.NETEASE);
  item.channelId = 'netease';
  item.audioId = `${id}`;
  return item;
}

export default function playlistMergeTest(): void {
  describe('PlaylistMerge', () => {
    it('appendsInOrderIntoEmptyPlaylist', 0, () => {
      const additions = [neteaseSong(1, 'A'), neteaseSong(2, 'B'), neteaseSong(3, 'C')];
      const merge = mergePlaylistSongs([], [], additions);
      expect(merge.addedCount).assertEqual(3);
      expect(merge.keys.length).assertEqual(3);
      expect(merge.songs.length).assertEqual(3);
      expect(merge.songs[0].name).assertEqual('A');
      expect(merge.songs[2].name).assertEqual('C');
      expect(merge.keys[0]).assertEqual(stableKeyOf(additions[0]));
    });

    it('skipsExistingAndIntraBatchDuplicates', 0, () => {
      const existingSong = neteaseSong(1, 'A');
      const existingKeys = [stableKeyOf(existingSong)];
      // 1 duplicates the existing entry; 2 appears twice inside the batch.
      const additions = [neteaseSong(1, 'A-again'), neteaseSong(2, 'B'), neteaseSong(2, 'B-again'), neteaseSong(3, 'C')];
      const merge = mergePlaylistSongs(existingKeys, [existingSong], additions);
      expect(merge.addedCount).assertEqual(2);
      expect(merge.songs.length).assertEqual(3);
      // Existing entry keeps its original metadata; first occurrence wins in-batch.
      expect(merge.songs[0].name).assertEqual('A');
      expect(merge.songs[1].name).assertEqual('B');
      expect(merge.songs[2].name).assertEqual('C');
      expect(merge.keys.length).assertEqual(merge.songs.length);
    });

    it('emptyBatchLeavesPlaylistUntouched', 0, () => {
      const existing = [neteaseSong(9, 'Z')];
      const merge = mergePlaylistSongs([stableKeyOf(existing[0])], existing, []);
      expect(merge.addedCount).assertEqual(0);
      expect(merge.songs.length).assertEqual(1);
      expect(merge.keys.length).assertEqual(1);
    });
  });
}
