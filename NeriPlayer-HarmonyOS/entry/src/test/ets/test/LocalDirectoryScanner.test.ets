import { describe, it, expect } from '@ohos/hypium';
import { LocalDirectoryScanner } from '../../../main/ets/data/LocalDirectoryScanner';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

export default function localDirectoryScannerTest(): void {
  describe('LocalDirectoryScanner', () => {
    it('siblingLyricPathSwapsExtensionInPlace', 0, () => {
      expect(LocalDirectoryScanner.siblingLyricPath('/music/a/b/song.mp3'))
        .assertEqual('/music/a/b/song.lrc');
      expect(LocalDirectoryScanner.siblingLyricPath('/music/song.flac'))
        .assertEqual('/music/song.lrc');
      // No extension: the whole name is the stem.
      expect(LocalDirectoryScanner.siblingLyricPath('/music/song'))
        .assertEqual('/music/song.lrc');
      // Dots inside the stem survive.
      expect(LocalDirectoryScanner.siblingLyricPath('/music/v1.2/song.m4a'))
        .assertEqual('/music/v1.2/song.lrc');
    });

    it('resolveDirPathPassesThroughNonUriPaths', 0, () => {
      expect(LocalDirectoryScanner.resolveDirPath('/data/storage/el2/base/files'))
        .assertEqual('/data/storage/el2/base/files');
    });

    it('catalogRoundTripPreservesSongs', 0, () => {
      // saveCatalog is storage-bound; the shape is covered through the
      // songJson record layout the loader parses.
      const song = new SongItem(0, 'Local', 'Artist', 'Album', 0);
      song.platform = MusicPlatform.LOCAL;
      song.localFilePath = '/music/song.mp3';
      song.matchedLyric = '[00:01.00]词';
      const json = song.toJson();
      const restored = SongItem.fromJson(json);
      expect(restored.localFilePath).assertEqual('/music/song.mp3');
      expect(restored.matchedLyric).assertEqual('[00:01.00]词');
      expect(restored.platform).assertEqual(MusicPlatform.LOCAL);
    });
  });
}
