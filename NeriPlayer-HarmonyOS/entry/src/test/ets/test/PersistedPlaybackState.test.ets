import { describe, it, expect } from '@ohos/hypium';
import { PersistedPlaybackState } from '../../../main/ets/model/PersistedPlaybackState';
import { SongItem } from '../../../main/ets/model/SongItem';
import { MusicPlatform } from '../../../main/ets/model/MusicPlatform';
import { RepeatMode } from '../../../main/ets/player/PlaybackConstants';

function sampleSongs(): SongItem[] {
  const first = new SongItem(1, 'First', 'Artist A', 'Album', 0, 200000, '', 'netease://1');
  const second = new SongItem(2, 'Second', 'Artist B', 'Album', 0, 180000, '', 'netease://2', MusicPlatform.BILIBILI);
  const third = new SongItem(3, 'Local', 'Artist C', 'Album', 0, 0, '', 'file:///a.flac', MusicPlatform.LOCAL);
  third.localFilePath = '/data/a.flac';
  return [first, second, third];
}

export default function persistedPlaybackStateTest(): void {
  describe('PersistedPlaybackState', () => {
    it('roundTripsAllFieldsThroughJson', 0, () => {
      const state = new PersistedPlaybackState(
        sampleSongs(), 2, 125000, RepeatMode.OFF, true, 1.5
      );

      const restored = PersistedPlaybackState.fromJson(state.toJson());

      expect(restored !== null).assertTrue();
      expect(restored!.version).assertEqual(PersistedPlaybackState.CURRENT_VERSION);
      expect(restored!.songs.length).assertEqual(3);
      expect(restored!.songs[1].name).assertEqual('Second');
      expect(restored!.songs[1].platform).assertEqual(MusicPlatform.BILIBILI);
      expect(restored!.songs[2].localFilePath).assertEqual('/data/a.flac');
      expect(restored!.queueIndex).assertEqual(2);
      expect(restored!.positionMs).assertEqual(125000);
      expect(restored!.repeatMode).assertEqual(RepeatMode.OFF);
      expect(restored!.shuffle).assertTrue();
      expect(restored!.speed).assertEqual(1.5);
    });

    it('preservesDistinctRepeatModes', 0, () => {
      const modes: RepeatMode[] = [RepeatMode.OFF, RepeatMode.ONE, RepeatMode.ALL];
      for (const mode of modes) {
        const state = new PersistedPlaybackState(sampleSongs(), 0, 0, mode);
        const restored = PersistedPlaybackState.fromJson(state.toJson());
        expect(restored!.repeatMode).assertEqual(mode);
      }
    });

    it('fallsBackToDefaultsForMissingFields', 0, () => {
      const restored = PersistedPlaybackState.fromJson('{"songs":[]}');

      expect(restored !== null).assertTrue();
      expect(restored!.songs.length).assertEqual(0);
      expect(restored!.queueIndex).assertEqual(0);
      expect(restored!.positionMs).assertEqual(0);
      expect(restored!.repeatMode).assertEqual(RepeatMode.ALL);
      expect(restored!.shuffle).assertFalse();
      expect(restored!.speed).assertEqual(1.0);
    });

    it('rejectsInvalidRepeatModeAndClampsPosition', 0, () => {
      const restored = PersistedPlaybackState.fromJson(
        '{"repeatMode": 9, "positionMs": -50, "queueIndex": -3, "speed": 0}'
      );

      expect(restored!.repeatMode).assertEqual(RepeatMode.ALL);
      expect(restored!.positionMs).assertEqual(0);
      expect(restored!.queueIndex).assertEqual(0);
      expect(restored!.speed).assertEqual(1.0);
    });

    it('returnsNullForCorruptedPayload', 0, () => {
      expect(PersistedPlaybackState.fromJson('not json {')).assertNull();
      expect(PersistedPlaybackState.fromJson('{"songs": "unexpected"}')).assertNull();
    });
  });
}
