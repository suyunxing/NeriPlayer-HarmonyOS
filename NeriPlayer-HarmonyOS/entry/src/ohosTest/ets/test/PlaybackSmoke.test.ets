import { describe, it, expect } from '@ohos/hypium';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlaybackStatsRepository } from '../../../main/ets/data/PlaybackStatsRepository';

const SAMPLE_URL = 'https://www.w3schools.com/html/horse.mp3';

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function waitState(player: media.AVPlayer, targets: string[], timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`state wait timeout (${targets.join(',')})`));
    }, timeoutMs);
    const check = (): void => {
      const current = player.state;
      if (current !== undefined && targets.indexOf(current) >= 0) {
        clearTimeout(timer);
        player.off('stateChange', check);
        resolve();
      }
    };
    player.on('stateChange', check);
    check();
  });
}

export default function playbackSmokeTest(): void {
  describe('ActsPlaybackSmokeTest', () => {
    it('avPlayerPlaysPausesAndHandlesInterruptMode', 0, async () => {
      // Network playback of a small stable sample: initialized -> prepared
      // -> playing -> paused, with the interrupt mode applied before play.
      const player = await media.createAVPlayer();
      let interruptEvents = 0;
      player.on('audioInterrupt', (event: audio.InterruptEvent) => {
        interruptEvents += 1;
        hilog.info(0x0000, 'playbackSmoke', 'audioInterrupt hint=%{public}d force=%{public}d',
          event.hintType, event.forceType);
      });
      player.url = SAMPLE_URL;
      await waitState(player, ['initialized'], 20000);
      await player.prepare();
      await waitState(player, ['prepared'], 20000);
      player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
      await player.play();
      await waitState(player, ['playing'], 10000);
      expect(player.state).assertEqual('playing');
      await player.pause();
      await waitState(player, ['paused'], 10000);
      expect(player.state).assertEqual('paused');
      await player.release();
      expect(interruptEvents >= 0).assertTrue();
    });

    // UPSTREAM_SYNC_PLAN P1-3: pause/interrupt flushes persist listenMs but
    // must not count plays; only the terminal flush of a continuous session
    // counts (pause/resume cycles = 1 play). Uses a throwaway key so real
    // user statistics are never touched.
    it('playStatsCountContinuousSessionNotPauseFlushes', 0, async () => {
      const key = `test-session|probe|${Date.now()}`;
      await PlaybackStatsRepository.recordPlay(key, 30000, false);
      await PlaybackStatsRepository.recordPlay(key, 20000, false);
      await PlaybackStatsRepository.recordPlay(key, 10000, true);
      expect(await PlaybackStatsRepository.getPlayCount(key)).assertEqual(1);
      const snapshot = await PlaybackStatsRepository.snapshot();
      const track = snapshot.tracks[key];
      expect(track !== undefined).assertTrue();
      expect(track.listenMs).assertEqual(60000);
      let shardPlays = 0;
      for (const shard of track.counterShards) {
        shardPlays += shard.playCount;
      }
      expect(shardPlays).assertEqual(1);
    });
  });
}
