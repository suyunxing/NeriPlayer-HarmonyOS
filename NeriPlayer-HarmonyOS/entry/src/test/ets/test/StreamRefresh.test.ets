import { describe, it, expect } from '@ohos/hypium';
import { YtmUrlCache } from '../../../main/ets/network/ytm/YtmUrlCache';
import { StreamResolver } from '../../../main/ets/network/StreamResolver';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';

const LONG_TTL_URL = 'https://host/audio?expire=9999999999&id=x';

export default function streamRefreshTest(): void {
  describe('StreamRefresh', () => {
    it('evictVideoDropsOnlyThatVideo', 0, () => {
      const cache = new YtmUrlCache();
      cache.put('vidA', 'high', LONG_TTL_URL, Date.now());
      cache.put('vidA', 'low', LONG_TTL_URL, Date.now());
      cache.put('vidB', 'high', LONG_TTL_URL, Date.now());
      expect(cache.size()).assertEqual(3);
      cache.evictVideo('vidA');
      expect(cache.size()).assertEqual(1);
      expect(cache.get('vidA', 'high', Date.now())).assertNull();
      expect(cache.get('vidA', 'low', Date.now())).assertNull();
      expect(cache.get('vidB', 'high', Date.now())).assertEqual(LONG_TTL_URL);
    });

    it('evictVideoToleratesPrefixCollisions', 0, () => {
      const cache = new YtmUrlCache();
      cache.put('vid', 'high', LONG_TTL_URL, Date.now());
      cache.put('vid2', 'high', LONG_TTL_URL, Date.now());
      cache.evictVideo('vid');
      // "vid2|" must not be caught by the "vid|" prefix.
      expect(cache.get('vid2', 'high', Date.now())).assertEqual(LONG_TTL_URL);
      expect(cache.get('vid', 'high', Date.now())).assertNull();
    });

    it('invalidateResolvedUrlClearsSongCache', 0, () => {
      const song = new SongItem(1, 'S', 'A', 'Album', 0);
      song.platform = MusicPlatform.NETEASE;
      song.audioId = '123';
      song.streamUrl = 'https://expired/netease.mp3';
      StreamResolver.invalidateResolvedUrl(song);
      expect(song.streamUrl).assertEqual('');
    });

    it('invalidateResolvedUrlEvictsYtmResolverCache', 0, () => {
      const song = new SongItem(1, 'Y', 'A', 'Album', 0);
      song.platform = MusicPlatform.YOUTUBE_MUSIC;
      song.audioId = 'vidX';
      song.streamUrl = 'https://expired/googlevideo';
      StreamResolver.invalidateResolvedUrl(song);
      expect(song.streamUrl).assertEqual('');
    });
  });
}
