import { describe, it, expect } from '@ohos/hypium';
import { NeteaseApi } from '../../../main/ets/network/NeteaseApi';
import { NeteaseCookieRepository } from '../../../main/ets/data/auth/NeteaseCookieRepository';

/**
 * Device smoke for the netease login-state library features (M4.3). The
 * recommend endpoint works anonymously, so it validates the full weapi path
 * (crypto -> session -> request -> parse) against the real network. The user
 * playlist endpoint must surface a clear error while logged out.
 */
export default function neteaseLibraryTest(): void {
  describe('ActsNeteaseLibraryTest', () => {
    it('recommendPlaylistsFetchOverRealNetwork', 0, async () => {
      const items = await NeteaseApi.getRecommendedPlaylists(30);
      expect(items.length > 0).assertTrue();
      const first = items[0];
      expect(first.id > 0).assertTrue();
      expect(first.name.length > 0).assertTrue();
      expect(first.coverUrl.startsWith('https://')).assertTrue();
      expect(first.trackCount >= 0).assertTrue();
    });

    it('userPlaylistsRejectedWhenLoggedOut', 0, async () => {
      if (NeteaseCookieRepository.isLoggedIn()) {
        // A logged-in emulator session would make this test meaningless.
        return;
      }
      // Anonymous account/get yields either code=301 or code=200 with a null
      // profile (verified on the real endpoint); both must surface as errors,
      // matching Android getCurrentUserId's two failure branches.
      let message = '';
      try {
        await NeteaseApi.getUserPlaylists(0, 30);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.length > 0).assertTrue();
      const rejected = message.indexOf('code=301') >= 0 || message.indexOf('profile.userId') >= 0;
      expect(rejected).assertTrue();
    });

    it('playlistOverviewFetchesSongsOverRealNetwork', 0, async () => {
      const items = await NeteaseApi.getRecommendedPlaylists(1);
      expect(items.length > 0).assertTrue();
      const overview = await NeteaseApi.getPlaylistOverview(items[0].id);
      expect(overview.id).assertEqual(items[0].id);
      expect(overview.name.length > 0).assertTrue();
      expect(overview.songs.length > 0).assertTrue();
      expect(overview.songs[0].id > 0).assertTrue();
      expect(overview.songs[0].audioId.length > 0).assertTrue();
      // v6 playlist detail returns ar/al short fields; the mapper must still
      // produce covers (https-upgraded) or the UI shows placeholders.
      const withCover = overview.songs.find((song) => song.coverUrl.length > 0);
      expect(withCover !== undefined).assertTrue();
      if (withCover !== undefined) {
        expect(withCover.coverUrl.startsWith('https://')).assertTrue();
      }
    });
  });
}
