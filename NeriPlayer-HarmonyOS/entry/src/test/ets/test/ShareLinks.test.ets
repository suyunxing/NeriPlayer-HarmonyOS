import { describe, it, expect } from '@ohos/hypium';
import { ShareLinks } from '../../../main/ets/util/ShareLinks';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

export default function shareLinksTest(): void {
  describe('ShareLinks', () => {
    it('neteaseLinkFromAudioIdThenNumericId', 0, () => {
      const withAudioId = new SongItem(0, 'n', 'a', '', 0, 0, '', '', MusicPlatform.NETEASE);
      withAudioId.audioId = '186016';
      expect(ShareLinks.songLink(withAudioId)).assertEqual('https://music.163.com/song/?id=186016');

      const withNumericId = new SongItem(347230, 'n', 'a', '', 0, 0, '', '', MusicPlatform.NETEASE);
      expect(ShareLinks.songLink(withNumericId)).assertEqual('https://music.163.com/song/?id=347230');
    });

    it('biliLinkFromAudioId', 0, () => {
      const song = new SongItem(0, 'b', 'a', '', 0, 0, '', '', MusicPlatform.BILIBILI);
      song.audioId = 'BV1xx411c7mD';
      expect(ShareLinks.songLink(song)).assertEqual('https://www.bilibili.com/video/BV1xx411c7mD');
    });

    it('ytmLinkPrefersMediaUriVideoId', 0, () => {
      const fromMediaUri = new SongItem(0, 'y', 'a', 'youtube_music', 0, 0, '', 'youtube_music|dQw4w9WgXcQ',
        MusicPlatform.YOUTUBE_MUSIC);
      expect(ShareLinks.songLink(fromMediaUri)).assertEqual('https://music.youtube.com/watch?v=dQw4w9WgXcQ');

      const fromAudioId = new SongItem(0, 'y', 'a', 'youtube_music', 0, 0, '', '', MusicPlatform.YOUTUBE_MUSIC);
      fromAudioId.audioId = 'abc123';
      expect(ShareLinks.songLink(fromAudioId)).assertEqual('https://music.youtube.com/watch?v=abc123');
    });

    it('localSongHasNoLink', 0, () => {
      const song = new SongItem(0, 'l', 'a', '', 0, 0, '', 'local://x', MusicPlatform.LOCAL);
      expect(ShareLinks.songLink(song)).assertEqual('');
    });

    it('songTextUsesDisplayFields', 0, () => {
      const plain = new SongItem(0, 'Title', 'Artist', '', 0, 0, '', '', MusicPlatform.NETEASE);
      expect(ShareLinks.songText(plain)).assertEqual('Title - Artist');

      plain.customName = 'Edited';
      plain.customArtist = 'Editor';
      expect(ShareLinks.songText(plain)).assertEqual('Edited - Editor');

      const noArtist = new SongItem(0, 'Solo', '', '', 0, 0, '', '', MusicPlatform.LOCAL);
      expect(ShareLinks.songText(noArtist)).assertEqual('Solo');
    });
  });
}
