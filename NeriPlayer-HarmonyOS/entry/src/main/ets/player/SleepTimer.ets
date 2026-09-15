// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Sleep timer modes, mirroring Android SleepTimerMode.
 */
export enum SleepTimerMode {
  NONE = 0,
  COUNTDOWN = 1,
  FINISH_CURRENT = 2,
  FINISH_PLAYLIST = 3
}

export class SleepTimerState {
  isActive: boolean = false;
  mode: SleepTimerMode = SleepTimerMode.NONE;
  remainingMs: number = 0;
  totalMs: number = 0;
  finishCurrentOnExpiry: boolean = false;
}

/**
 * Injectable tick scheduler so tests can drive the countdown manually.
 */
export interface TickScheduler {
  schedule(callback: () => void, intervalMs: number): number;
  cancel(id: number): void;
}

class SystemTickScheduler implements TickScheduler {
  schedule(callback: () => void, intervalMs: number): number {
    return setInterval(callback, intervalMs);
  }

  cancel(id: number): void {
    clearInterval(id);
  }
}

/**
 * Pure sleep-timer state machine, mirroring Android SleepTimerManager:
 * - countdown with optional finish-current-on-expiry transition;
 * - finish-current / finish-playlist modes decided on natural track end
 *   (see shouldStopOnTrackEnd);
 * - restart/switch silently cancels the previous timer;
 * - expiry calls the ordinary pause path and resets state.
 *
 * The clock (nowMs) and scheduler are injectable for deterministic tests.
 */
export class SleepTimer {
  private state: SleepTimerState = new SleepTimerState();
  private deadlineMs: number = 0;
  private tickId: number = -1;
  private readonly nowMs: () => number;
  private readonly scheduler: TickScheduler;
  private readonly onExpired: () => void;
  private readonly onStateChanged: () => void;

  constructor(
    nowMs: () => number,
    scheduler: TickScheduler | undefined,
    onExpired: () => void,
    onStateChanged: () => void = () => {
    }
  ) {
    this.nowMs = nowMs;
    this.scheduler = scheduler ?? new SystemTickScheduler();
    this.onExpired = onExpired;
    this.onStateChanged = onStateChanged;
  }

  getState(): SleepTimerState {
    return this.state;
  }

  startCountdown(minutes: number, finishCurrentOnExpiry: boolean): void {
    this.cancel(false);
    this.state = new SleepTimerState();
    this.state.isActive = true;
    this.state.mode = SleepTimerMode.COUNTDOWN;
    this.state.totalMs = minutes * 60000;
    this.state.remainingMs = this.state.totalMs;
    this.state.finishCurrentOnExpiry = finishCurrentOnExpiry;
    this.deadlineMs = this.nowMs() + this.state.totalMs;
    this.tickId = this.scheduler.schedule(() => this.tick(), 1000);
    this.onStateChanged();
  }

  startFinishCurrent(): void {
    this.cancel(false);
    this.state = new SleepTimerState();
    this.state.isActive = true;
    this.state.mode = SleepTimerMode.FINISH_CURRENT;
    this.onStateChanged();
  }

  startFinishPlaylist(): void {
    this.cancel(false);
    this.state = new SleepTimerState();
    this.state.isActive = true;
    this.state.mode = SleepTimerMode.FINISH_PLAYLIST;
    this.onStateChanged();
  }

  cancel(notify: boolean = true): void {
    if (this.tickId >= 0) {
      this.scheduler.cancel(this.tickId);
      this.tickId = -1;
    }
    const wasActive = this.state.isActive;
    this.state = new SleepTimerState();
    if (notify && wasActive) {
      this.onStateChanged();
    }
  }

  /**
   * Whether playback should stop instead of advancing when the current
   * track naturally ends. Mirrors Android shouldStopOnTrackEnd.
   */
  shouldStopOnTrackEnd(isLastInPlaylist: boolean): boolean {
    if (!this.state.isActive) {
      return false;
    }
    if (this.state.mode === SleepTimerMode.FINISH_CURRENT) {
      return true;
    }
    return this.state.mode === SleepTimerMode.FINISH_PLAYLIST && isLastInPlaylist;
  }

  /** Drives the countdown; invoked by the scheduler each second. */
  tick(): void {
    if (!this.state.isActive || this.state.mode !== SleepTimerMode.COUNTDOWN) {
      return;
    }
    const remaining = this.deadlineMs - this.nowMs();
    if (remaining > 0) {
      this.state.remainingMs = remaining;
      this.onStateChanged();
      return;
    }
    this.state.remainingMs = 0;
    if (this.state.finishCurrentOnExpiry) {
      // Countdown elapsed: transition to finish-current instead of pausing.
      this.state.mode = SleepTimerMode.FINISH_CURRENT;
      this.state.totalMs = 0;
      if (this.tickId >= 0) {
        this.scheduler.cancel(this.tickId);
        this.tickId = -1;
      }
      this.onStateChanged();
      return;
    }
    this.state = new SleepTimerState();
    if (this.tickId >= 0) {
      this.scheduler.cancel(this.tickId);
      this.tickId = -1;
    }
    this.onStateChanged();
    this.onExpired();
  }

  dispose(): void {
    this.cancel(false);
  }
}
