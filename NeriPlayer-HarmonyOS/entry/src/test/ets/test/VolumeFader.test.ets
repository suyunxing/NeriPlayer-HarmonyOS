import { describe, it, expect } from '@ohos/hypium';
import { TickScheduler } from '../../../main/ets/player/SleepTimer';
import { VolumeFader } from '../../../main/ets/player/VolumeFader';

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
  scheduleCount: number = 0;
  canceled: number[] = [];
  private nextId: number = 1;

  schedule(callback: () => void, intervalMs: number): number {
    this.callback = callback;
    this.intervalMs = intervalMs;
    this.scheduleCount++;
    return this.nextId++;
  }

  cancel(id: number): void {
    this.canceled.push(id);
  }
}

export default function volumeFaderTest(): void {
  describe('VolumeFader', () => {
    it('fadeToAppliesStartImmediatelyAndRampsLinearlyToTarget', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      const applied: number[] = [];
      let settleCount: number = 0;
      let settledCompleted: boolean = false;
      const fader = new VolumeFader((volume: number): void => {
        applied.push(volume);
      }, () => clock.now, scheduler);

      fader.snapTo(0);
      fader.fadeTo(1, 100, (completed: boolean): void => {
        settleCount++;
        settledCompleted = completed;
      });
      // The start volume is applied synchronously so callers can arm silence
      // before resuming playback.
      expect(applied[applied.length - 1]).assertEqual(0);

      clock.advance(50);
      scheduler.callback();
      expect(applied[applied.length - 1]).assertEqual(0.5);

      clock.advance(50);
      scheduler.callback();
      expect(fader.getVolume()).assertEqual(1);
      expect(settleCount).assertEqual(1);
      expect(settledCompleted).assertTrue();
      expect(fader.isFading()).assertFalse();
      expect(scheduler.canceled.length).assertEqual(1);
    });

    it('replacingFadeSettlesPreviousWithFalseAndRestartsFromCurrent', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      const applied: number[] = [];
      let firstSettles: number = 0;
      let firstCompleted: boolean = true;
      let secondSettles: number = 0;
      const fader = new VolumeFader((volume: number): void => {
        applied.push(volume);
      }, () => clock.now, scheduler);

      fader.snapTo(0);
      fader.fadeTo(1, 100, (completed: boolean): void => {
        firstSettles++;
        firstCompleted = completed;
      });
      clock.advance(50);
      scheduler.callback();

      fader.fadeTo(0, 100, (): void => {
        secondSettles++;
      });
      expect(firstSettles).assertEqual(1);
      expect(firstCompleted).assertFalse();
      expect(secondSettles).assertEqual(0);
      expect(fader.isFadingOut()).assertTrue();

      clock.advance(100);
      scheduler.callback();
      expect(fader.getVolume()).assertEqual(0);
      expect(secondSettles).assertEqual(1);
    });

    it('cancelMidFadeStopsTicksAndSettlesFalse', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      let settleCount: number = 0;
      let settledCompleted: boolean = true;
      const fader = new VolumeFader((): void => {
      }, () => clock.now, scheduler);

      fader.snapTo(1);
      fader.fadeTo(0, 100, (completed: boolean): void => {
        settleCount++;
        settledCompleted = completed;
      });
      clock.advance(50);
      scheduler.callback();
      expect(fader.getVolume()).assertEqual(0.5);

      fader.cancel();
      expect(settleCount).assertEqual(1);
      expect(settledCompleted).assertFalse();

      // A stale timer callback after cancel must be inert.
      const volumeAtCancel = fader.getVolume();
      clock.advance(50);
      scheduler.callback();
      expect(fader.getVolume()).assertEqual(volumeAtCancel);
      expect(settleCount).assertEqual(1);
    });

    it('snapToCancelsActiveFadeAndAppliesImmediately', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      const applied: number[] = [];
      const fader = new VolumeFader((volume: number): void => {
        applied.push(volume);
      }, () => clock.now, scheduler);

      fader.snapTo(1);
      fader.fadeTo(0, 100);
      clock.advance(50);
      scheduler.callback();

      fader.snapTo(0.75);
      expect(fader.getVolume()).assertEqual(0.75);
      expect(applied[applied.length - 1]).assertEqual(0.75);
      expect(fader.isFading()).assertFalse();
    });

    it('zeroDurationSnapsAndSettlesCompletedWithoutScheduling', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      const applied: number[] = [];
      let settleCount: number = 0;
      let settledCompleted: boolean = false;
      const fader = new VolumeFader((volume: number): void => {
        applied.push(volume);
      }, () => clock.now, scheduler);

      fader.snapTo(0);
      fader.fadeTo(1, 0, (completed: boolean): void => {
        settleCount++;
        settledCompleted = completed;
      });
      expect(fader.getVolume()).assertEqual(1);
      expect(settleCount).assertEqual(1);
      expect(settledCompleted).assertTrue();
      expect(scheduler.scheduleCount).assertEqual(0);
    });

    it('sameTargetSettlesImmediatelyWithoutScheduling', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      let settleCount: number = 0;
      let settledCompleted: boolean = false;
      const fader = new VolumeFader((): void => {
      }, () => clock.now, scheduler);

      fader.snapTo(0.5);
      fader.fadeTo(0.5, 100, (completed: boolean): void => {
        settleCount++;
        settledCompleted = completed;
      });
      expect(settleCount).assertEqual(1);
      expect(settledCompleted).assertTrue();
      expect(scheduler.scheduleCount).assertEqual(0);
      expect(fader.isFading()).assertFalse();
    });

    it('fadeTargetAndSnapValuesAreClamped', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      const fader = new VolumeFader((): void => {
      }, () => clock.now, scheduler);

      fader.snapTo(0);
      fader.fadeTo(2, 100);
      clock.advance(100);
      scheduler.callback();
      expect(fader.getVolume()).assertEqual(1);

      fader.snapTo(-1);
      expect(fader.getVolume()).assertEqual(0);
    });

    it('isFadingOutReportsOnlyTowardSilenceFades', 0, () => {
      const clock = new ManualClock();
      const scheduler = new ManualScheduler();
      const fader = new VolumeFader((): void => {
      }, () => clock.now, scheduler);

      fader.snapTo(1);
      fader.fadeTo(0, 100);
      expect(fader.isFadingOut()).assertTrue();

      clock.advance(100);
      scheduler.callback();
      expect(fader.isFadingOut()).assertFalse();

      fader.fadeTo(1, 100);
      expect(fader.isFadingOut()).assertFalse();
      expect(fader.isFading()).assertTrue();
    });
  });
}
