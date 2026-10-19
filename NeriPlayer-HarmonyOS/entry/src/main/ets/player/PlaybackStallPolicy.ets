// SPDX-License-Identifier: GPL-3.0

/**
 * Silent-stall detection for the playing state (audit A-3, upstream #401):
 * AVPlayer can freeze without ever emitting `error` — status stays PLAYING
 * while `timeUpdate` stops advancing. The detector tracks the last wall-clock
 * moment the position actually moved; a playing session whose position has
 * been frozen beyond the threshold is treated like a load failure and fed
 * into the same bounded recovery policy instead of hanging forever.
 */
export const DEFAULT_STALL_THRESHOLD_MS: number = 15000;

export class PlaybackStallDetector {
  private readonly thresholdMs: number;
  private lastAdvanceAtMs: number = -1;
  private lastPositionMs: number = -1;
  private everObserved: boolean = false;

  constructor(thresholdMs: number = DEFAULT_STALL_THRESHOLD_MS) {
    this.thresholdMs = thresholdMs;
  }

  /**
   * Feed one timeUpdate sample. Any position change counts as progress —
   * including a seek landing on an earlier position, which is still evidence
   * the transport is alive.
   */
  observe(atMs: number, positionMs: number): void {
    if (this.lastPositionMs !== positionMs) {
      this.lastAdvanceAtMs = atMs;
      this.lastPositionMs = positionMs;
      this.everObserved = true;
    }
  }

  /** True only after real samples existed and then froze past the threshold. */
  isStalled(atMs: number): boolean {
    if (!this.everObserved || this.lastAdvanceAtMs < 0) {
      return false;
    }
    return atMs - this.lastAdvanceAtMs >= this.thresholdMs;
  }

  reset(): void {
    this.lastAdvanceAtMs = -1;
    this.lastPositionMs = -1;
    this.everObserved = false;
  }
}
