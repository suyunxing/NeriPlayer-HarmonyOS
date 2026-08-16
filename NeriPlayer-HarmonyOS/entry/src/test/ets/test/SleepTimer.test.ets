import { describe, it, expect } from '@ohos/hypium';
import { SleepTimer, SleepTimerMode, TickScheduler } from '../../../main/ets/player/SleepTimer';

class ManualClock {
  now: number = 1000000;

  advance(ms: number): void {
    this.now += ms;
  }
}

class ManualScheduler implements TickScheduler {
  callback: () => void = () => {
  };
  intervalMs: number = 0;
  canceled: number[] = [];

  schedule(callback: () => void, intervalMs: number): number {
    this.callback = callback;
    this.intervalMs = intervalMs;
    return 1;
  }

  cancel(id: number): void {
    this.canceled.push(id);
  }
}

export default function sleepTimerTest(): void {
  describe('SleepTimer', () => {
    it('countdownTicksRemainingAndExpiresToPause', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      let expired = 0;
      const timer = new SleepTimer(() => clock.now, scheduler, () => {
        expired += 1;
      });

      timer.startCountdown(10, false);
      expect(timer.getState().isActive).assertTrue();
      expect(timer.getState().mode).assertEqual(SleepTimerMode.COUNTDOWN);
      expect(timer.getState().remainingMs).assertEqual(600000);

      clock.advance(1000);
      timer.tick();
      expect(timer.getState().remainingMs).assertEqual(599000);

      clock.advance(599000);
      timer.tick();
      expect(expired).assertEqual(1);
      expect(timer.getState().isActive).assertFalse();
    });

    it('countdownExpiryTransitionsToFinishCurrentWhenConfigured', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      let expired = 0;
      const timer = new SleepTimer(() => clock.now, scheduler, () => {
        expired += 1;
      });

      timer.startCountdown(5, true);
      clock.advance(300000);
      timer.tick();
      expect(expired).assertEqual(0);
      expect(timer.getState().isActive).assertTrue();
      expect(timer.getState().mode).assertEqual(SleepTimerMode.FINISH_CURRENT);
      expect(timer.getState().remainingMs).assertEqual(0);
      // No further countdown ticks are scheduled after the transition.
      expect(scheduler.canceled.length).assertEqual(1);
    });

    it('finishCurrentStopsOnAnyTrackEnd', 0, () => {
      const timer = new SleepTimer(() => 0, new ManualScheduler(), () => {
      });
      timer.startFinishCurrent();
      expect(timer.shouldStopOnTrackEnd(false)).assertTrue();
      expect(timer.shouldStopOnTrackEnd(true)).assertTrue();
    });

    it('finishPlaylistStopsOnlyOnLastTrack', 0, () => {
      const timer = new SleepTimer(() => 0, new ManualScheduler(), () => {
      });
      timer.startFinishPlaylist();
      expect(timer.shouldStopOnTrackEnd(false)).assertFalse();
      expect(timer.shouldStopOnTrackEnd(true)).assertTrue();
    });

    it('inactiveTimerNeverStopsTrackEnd', 0, () => {
      const timer = new SleepTimer(() => 0, new ManualScheduler(), () => {
      });
      expect(timer.shouldStopOnTrackEnd(true)).assertFalse();
    });

    it('restartSilentlyReplacesPreviousTimer', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      let expired = 0;
      const timer = new SleepTimer(() => clock.now, scheduler, () => {
        expired += 1;
      });

      timer.startCountdown(10, false);
      timer.startFinishPlaylist();
      expect(timer.getState().mode).assertEqual(SleepTimerMode.FINISH_PLAYLIST);
      // The old countdown deadline no longer exists; ticking is inert.
      clock.advance(600000);
      timer.tick();
      expect(expired).assertEqual(0);
      expect(timer.getState().isActive).assertTrue();
    });

    it('cancelResetsState', 0, () => {
      const clock = new ManualClock();
      const timer = new SleepTimer(() => clock.now, new ManualScheduler(), () => {
      });
      timer.startCountdown(10, false);
      timer.cancel();
      expect(timer.getState().isActive).assertFalse();
      expect(timer.getState().mode).assertEqual(SleepTimerMode.NONE);
      expect(timer.shouldStopOnTrackEnd(true)).assertFalse();
    });
  });
}
