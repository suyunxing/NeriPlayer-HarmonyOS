import { describe, it, expect } from '@ohos/hypium';
import { AppPreferences } from '../../../main/ets/data/AppPreferences';
import { PlaybackStateRepository } from '../../../main/ets/data/PlaybackStateRepository';
import { PersistedPlaybackState } from '../../../main/ets/model/PersistedPlaybackState';
import { SongItem } from '../../../main/ets/model/SongItem';
import { PlayerManager } from '../../../main/ets/player/PlayerManager';
import { PlaybackConstants, PlaybackStatus, RepeatMode } from '../../../main/ets/player/PlaybackConstants';

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

export default function playbackStateRestoreTest(): void {
  describe('ActsPlaybackStateRestoreTest', () => {
    // The preferences store is initialized from TestAbility's context in
    // onCreate (see there); repository calls await that init internally.
    it('persistAndRestoreQueueAcrossRestart', 0, async () => {
      // Reset first so a previous run (or the app smoke that follows this
      // suite) does not leak state into this case.
      await PlaybackStateRepository.clear();
      // Simulate the previous session having persisted its state.
      const songs: SongItem[] = [
        new SongItem(11, 'Song One', 'Artist', 'Album', 0, 200000, '', 'netease://11'),
        new SongItem(22, 'Song Two', 'Artist', 'Album', 0, 180000, '', 'netease://22'),
        new SongItem(33, 'Song Three', 'Artist', 'Album', 0, 160000, '', 'netease://33')
      ];
      const saved = new PersistedPlaybackState(songs, 1, 95000, RepeatMode.OFF, false, 1.25);
      await PlaybackStateRepository.save(saved);

      // Cold-start path: repository load + PlayerManager restore.
      const loaded = await PlaybackStateRepository.load();
      expect(loaded !== null).assertTrue();
      PlayerManager.applyRestoredState(loaded!);

      expect(PlayerManager.getQueue().length).assertEqual(3);
      expect(PlayerManager.getCurrentSong()!.id).assertEqual(22);
      expect(PlayerManager.getPositionMs()).assertEqual(95000);
      expect(AppStorage.get<number>(PlaybackConstants.KEY_STATUS)).assertEqual(PlaybackStatus.PAUSED);
      expect(AppStorage.get<number>(PlaybackConstants.KEY_REPEAT_MODE)).assertEqual(RepeatMode.OFF);
      expect(AppStorage.get<number>(PlaybackConstants.KEY_SPEED)).assertEqual(1.25);
      const queueJson = AppStorage.get<string>(PlaybackConstants.KEY_QUEUE_JSON) ?? '';
      expect(queueJson.length > 0).assertTrue();

      // Let the debounced persist triggered by publishQueue settle so the
      // restored queue is on disk again for the app cold-start smoke.
      await sleep(400);
    });

    it('restoreFallsBackGracefullyOnCorruptedState', 0, async () => {
      await AppPreferences.putString('playback_state', 'corrupted {');
      const loaded = await PlaybackStateRepository.load();
      expect(loaded).assertNull();
      await PlaybackStateRepository.clear();
    });
  });
}
