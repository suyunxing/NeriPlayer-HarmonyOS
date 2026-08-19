/**
 * Per-client failure suppression, porting Android PlayerClientHealthTracker
 * (YouTubeMusicPlaybackRepository.kt:280-313):
 *
 * - three consecutive rejections suppress the client for 30 minutes;
 * - expired suppressions self-clear on read;
 * - a success resets both counters;
 * - when every client in the chain is suppressed, the full chain is returned
 *   (Android selectUsablePlayerClients: usable.ifEmpty { profiles }).
 *
 * Clock is injected so the local hypium suite can time-travel.
 */

const DEFAULT_FAILURE_THRESHOLD: number = 3;
const DEFAULT_SUPPRESSION_WINDOW_MS: number = 30 * 60 * 1000;

export class YtmClientHealthTracker {
  private readonly failureThreshold: number;
  private readonly suppressionWindowMs: number;
  private readonly failures: Map<string, number> = new Map<string, number>();
  private readonly suppressedUntilMs: Map<string, number> = new Map<string, number>();

  constructor(
    failureThreshold: number = DEFAULT_FAILURE_THRESHOLD,
    suppressionWindowMs: number = DEFAULT_SUPPRESSION_WINDOW_MS
  ) {
    this.failureThreshold = failureThreshold;
    this.suppressionWindowMs = suppressionWindowMs;
  }

  /** True while the client is suppressed; expired entries self-clear. */
  isSuppressed(clientKey: string, nowMs: number): boolean {
    const until = this.suppressedUntilMs.get(clientKey);
    if (until === undefined) {
      return false;
    }
    if (nowMs >= until) {
      this.suppressedUntilMs.delete(clientKey);
      this.failures.delete(clientKey);
      return false;
    }
    return true;
  }

  /** Counts one rejection; hitting the threshold suppresses for the window. */
  recordRejection(clientKey: string, nowMs: number): void {
    const hits = (this.failures.get(clientKey) ?? 0) + 1;
    this.failures.set(clientKey, hits);
    if (hits >= this.failureThreshold) {
      this.suppressedUntilMs.set(clientKey, nowMs + this.suppressionWindowMs);
    }
  }

  /** A successful request clears both the counter and any suppression. */
  recordSuccess(clientKey: string): void {
    this.failures.delete(clientKey);
    this.suppressedUntilMs.delete(clientKey);
  }

  /**
   * Ordered chain with suppressed clients filtered out; returns the full
   * chain when everything is suppressed so resolution never dead-ends.
   */
  selectUsableChain<T>(clients: T[], keyOf: (client: T) => string, nowMs: number): T[] {
    const usable: T[] = [];
    for (const client of clients) {
      if (!this.isSuppressed(keyOf(client), nowMs)) {
        usable.push(client);
      }
    }
    return usable.length > 0 ? usable : clients.slice();
  }

  failureCount(clientKey: string): number {
    return this.failures.get(clientKey) ?? 0;
  }

  resetForTest(): void {
    this.failures.clear();
    this.suppressedUntilMs.clear();
  }
}
