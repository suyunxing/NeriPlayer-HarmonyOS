// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

import { TickScheduler } from './SleepTimer';

/**
 * Receives each interpolated volume step. Implementations must tolerate calls
 * in any player state (they no-op when no renderer is attached).
 */
export type VolumeApplier = (volume: number) => void;

/**
 * Settled exactly once per fade: `true` when the fade ran to its target,
 * `false` when it was canceled or superseded by a newer fade.
 */
export type VolumeSettled = (completed: boolean) => void;

/**
 * Fade durations mirror the Android app's playback fade defaults
 * (playback_fade_in/out_duration_ms = 500). The 25ms tick keeps every step
 * within the 0.02-0.05 gain increment recommended for AVPlayer.setVolume
 * interpolation; below ~20Hz the cross-process IPC jitter turns the ramp into
 * audible zipper noise instead of a smooth fade.
 */
export const FADE_IN_DURATION_MS = 500;
export const FADE_OUT_DURATION_MS = 500;
const FADE_TICK_INTERVAL_MS = 25;
const VOLUME_EPSILON = 0.001;

class SystemTickScheduler implements TickScheduler {
  schedule(callback: () => void, intervalMs: number): number {
    return setInterval(callback, intervalMs);
  }

  cancel(id: number): void {
    clearInterval(id);
  }
}

function clampVolume(volume: number): number {
  return Math.min(1, Math.max(0, volume));
}

/**
 * Volume fade state machine behind play/pause/track-switch (Android playback
 * fade parity). Pure interpolation over an injected clock and scheduler so
 * tests drive it deterministically; the only platform touch point is the
 * single VolumeApplier callback.
 *
 * Fades never nest: fadeTo() while a fade is in flight settles the previous
 * one with `false` and restarts from the current (mid-fade) volume, which is
 * what makes rapid play/pause toggling reverse smoothly.
 */
export class VolumeFader {
  private tickId: number = -1;
  private fadeStartMs: number = 0;
  private fadeDurationMs: number = 0;
  private fadeFrom: number = 1.0;
  private fadeTarget: number = 1.0;
  private currentVolume: number = 1.0;
  private onSettled: VolumeSettled | null = null;
  private readonly nowMs: () => number;
  private readonly scheduler: TickScheduler;
  private readonly applier: VolumeApplier;
  private readonly tickIntervalMs: number;

  constructor(
    applier: VolumeApplier,
    nowMs: () => number,
    scheduler?: TickScheduler,
    tickIntervalMs: number = FADE_TICK_INTERVAL_MS
  ) {
    this.applier = applier;
    this.nowMs = nowMs;
    this.scheduler = scheduler ?? new SystemTickScheduler();
    this.tickIntervalMs = tickIntervalMs;
  }

  getVolume(): number {
    return this.currentVolume;
  }

  isFading(): boolean {
    return this.tickId >= 0;
  }

  /** True while a fade toward silence is in flight (a pause/switch pending). */
  isFadingOut(): boolean {
    return this.tickId >= 0 && this.fadeTarget <= 0;
  }

  /** Jumps to a volume immediately, canceling any active fade. */
  snapTo(volume: number): void {
    this.abortActiveFade();
    this.currentVolume = clampVolume(volume);
    this.applier(this.currentVolume);
  }

  /**
   * Fades from the current volume to the target. The start volume is applied
   * synchronously so callers can arm silence before resuming playback. A zero
   * duration (or a no-op distance) snaps and settles as completed.
   */
  fadeTo(target: number, durationMs: number, onSettled?: VolumeSettled): void {
    this.abortActiveFade();
    const clamped = clampVolume(target);
    if (durationMs <= 0 || Math.abs(clamped - this.currentVolume) < VOLUME_EPSILON) {
      this.currentVolume = clamped;
      this.applier(this.currentVolume);
      if (onSettled !== undefined) {
        onSettled(true);
      }
      return;
    }
    this.fadeFrom = this.currentVolume;
    this.fadeTarget = clamped;
    this.fadeDurationMs = durationMs;
    this.fadeStartMs = this.nowMs();
    this.onSettled = onSettled ?? null;
    this.tickId = this.scheduler.schedule(() => this.tick(), this.tickIntervalMs);
  }

  /** Stops the active fade where it is; a pending settle fires with false. */
  cancel(): void {
    this.abortActiveFade();
  }

  dispose(): void {
    this.abortActiveFade();
  }

  /** Tears the timer down and settles an in-flight fade as canceled. */
  private abortActiveFade(): void {
    if (this.tickId < 0) {
      return;
    }
    this.scheduler.cancel(this.tickId);
    this.tickId = -1;
    const settled = this.onSettled;
    this.onSettled = null;
    if (settled !== null) {
      settled(false);
    }
  }

  /** Drives the interpolation; invoked by the scheduler every tick. */
  private tick(): void {
    if (this.tickId < 0) {
      return;
    }
    const elapsedMs = this.nowMs() - this.fadeStartMs;
    const progress = this.fadeDurationMs > 0 ? elapsedMs / this.fadeDurationMs : 1;
    if (progress >= 1) {
      this.complete();
      return;
    }
    this.currentVolume = clampVolume(this.fadeFrom + (this.fadeTarget - this.fadeFrom) * progress);
    this.applier(this.currentVolume);
  }

  private complete(): void {
    this.scheduler.cancel(this.tickId);
    this.tickId = -1;
    this.currentVolume = this.fadeTarget;
    this.applier(this.currentVolume);
    const settled = this.onSettled;
    this.onSettled = null;
    if (settled !== null) {
      settled(true);
    }
  }
}
