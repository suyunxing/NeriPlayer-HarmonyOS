// SPDX-License-Identifier: GPL-3.0
// Unit tests for the playback card state helpers (Form Kit port of the
// upstream playback widgets, #472 reference).

import { describe, it, expect } from '@ohos/hypium';
import {
  PlaybackCardSnapshot,
  buildPlaybackCardPayload,
  nextCoverImageKey,
  parsePlaybackCardControlAction
} from '../../../main/ets/widget/PlaybackCardState';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { PlaybackStatus } from '../../../main/ets/player/PlaybackConstants';

function song(name: string, artist: string, cover: string): SongItem {
  return new SongItem(0, name, artist, '专辑', 0, 0, cover, '', MusicPlatform.NETEASE);
}

export default function PlaybackCardStateTest() {
  describe('PlaybackCardState', () => {
    it('fromSong_carriesMetadataAndPlayingFlag', 0, () => {
      const playing = PlaybackCardSnapshot.fromSong(song('晴天', '周杰伦', 'https://a/b.jpg'),
        PlaybackStatus.PLAYING);
      expect(playing.hasSong).assertEqual('true');
      expect(playing.playing).assertEqual('true');
      expect(playing.title).assertEqual('晴天');
      expect(playing.artist).assertEqual('周杰伦');
      expect(playing.coverUrl).assertEqual('https://a/b.jpg');
      const paused = PlaybackCardSnapshot.fromSong(song('晴天', '周杰伦', ''),
        PlaybackStatus.PAUSED);
      expect(paused.playing).assertEqual('false');
      const empty = PlaybackCardSnapshot.fromSong(null, PlaybackStatus.IDLE);
      expect(empty.hasSong).assertEqual('false');
      expect(empty.playing).assertEqual('false');
    });

    it('json_roundTripPreservesFields', 0, () => {
      const snapshot = PlaybackCardSnapshot.fromSong(song('A', 'B', 'https://c/d.jpg'),
        PlaybackStatus.PLAYING);
      const restored = PlaybackCardSnapshot.fromJson(snapshot.toJson());
      expect(restored !== null).assertTrue();
      expect(restored?.title).assertEqual('A');
      expect(restored?.artist).assertEqual('B');
      expect(restored?.playing).assertEqual('true');
      expect(restored?.hasSong).assertEqual('true');
      expect(restored?.coverUrl).assertEqual('https://c/d.jpg');
      expect(PlaybackCardSnapshot.fromJson('not json')).assertNull();
    });

    it('payload_fallsBackTitleWhenNoSong', 0, () => {
      const idle = PlaybackCardSnapshot.fromSong(null, PlaybackStatus.IDLE);
      const payload = buildPlaybackCardPayload(idle, '');
      expect(payload['title']).assertEqual('未在播放');
      expect(payload['hasCover']).assertEqual('false');
      const withCover = PlaybackCardSnapshot.fromSong(song('A', 'B', 'https://x'),
        PlaybackStatus.PLAYING);
      const payload2 = buildPlaybackCardPayload(withCover, 'cover7');
      expect(payload2['title']).assertEqual('A');
      expect(payload2['coverKey']).assertEqual('cover7');
      expect(payload2['hasCover']).assertEqual('true');
      expect(payload2['playing']).assertEqual('true');
    });

    it('coverKey_generationChangesEveryCall', 0, () => {
      // formImages 同 key 不刷新：key 必须随代数变化。
      const first = nextCoverImageKey(1);
      const second = nextCoverImageKey(2);
      expect(first).assertEqual('cover1');
      expect(second).assertEqual('cover2');
      expect(first === second).assertFalse();
    });

    it('controlAction_parsesOnlyKnownActions', 0, () => {
      expect(parsePlaybackCardControlAction({ action: 'toggle' })).assertEqual('toggle');
      expect(parsePlaybackCardControlAction({ action: 'prev' })).assertEqual('prev');
      expect(parsePlaybackCardControlAction({ action: 'next' })).assertEqual('next');
      expect(parsePlaybackCardControlAction({ action: 'seek' })).assertEqual('');
      expect(parsePlaybackCardControlAction({})).assertEqual('');
    });
  });
}
