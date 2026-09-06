/**
 * Port of ListenTogetherSessionManager.kt's clock-sync half: the estimated
 * offset between this client's wall clock and the room server's, which
 * `computeListenTogetherPlaybackPosition` needs to turn a server-stamped
 * position into a local one.
 *
 * Extracted into its own object because upstream keeps four correlated fields
 * (`pingSentAtElapsedMs`, `pingSentAtWallMs`, `estimatedServerClockOffsetMs`,
 * `clockSyncPingSupported`) as session-manager privates, and a smoothing filter
 * that cannot be unit-tested is a smoothing filter nobody can verify.
 *
 * Both clocks are passed in rather than read here: `nowElapsedMs` is a monotonic
 * uptime (upstream `SystemClock.elapsedRealtime()`), `nowWallMs` a wall clock
 * (`System.currentTimeMillis()`). Mixing them up is the whole bug class this
 * class exists to avoid — the round trip is measured on the monotonic clock,
 * because the wall clock can jump mid-flight, while the *offset* is by
 * definition a wall-clock quantity.
 *
 * Kotlin-parity note: upstream does `rtt / 2` and `(prev * 7 + newOffset * 3) / 10`
 * on `Long`, so both truncate toward zero. TypeScript `/` is floating point, so
 * every such division is wrapped in `Math.trunc()`. For a negative offset —
 * a client clock ahead of the server's — truncation rounds *up*, and dropping
 * the trunc would let a fractional offset leak into every computed position.
 */

/**
 * Upstream `CLOCK_SYNC_MAX_RTT_MS`. A sample this slow says nothing useful about
 * the offset: half of a 30 s round trip is a worse estimate than the previous
 * value, so the sample is discarded rather than smoothed in.
 */
export const LISTEN_TOGETHER_CLOCK_SYNC_MAX_RTT_MS: number = 30_000;

/** The new sample's weight in the smoothing filter, out of ten. */
export const LISTEN_TOGETHER_CLOCK_OFFSET_SAMPLE_WEIGHT: number = 3;

/**
 * True when a server rejected `np_ping` as an unknown event type, which is how a
 * pre-clock-sync worker answers. Upstream
 * `isUnsupportedClockSyncPingError()`; the match is case-insensitive and on a
 * substring, because the surrounding error envelope is not stable.
 */
export function isUnsupportedListenTogetherClockSyncPingError(message: string | null): boolean {
  if (message === null) {
    return false;
  }
  return message.toLowerCase().includes('unsupported event type: np_ping');
}

/**
 * Why a sample was refused, so callers (and tests) can tell "we ignored this on
 * purpose" from "we have no estimate yet". Plain string codes rather than a
 * literal union, matching how the protocol models spell their enumerations.
 */
export const LISTEN_TOGETHER_CLOCK_SAMPLE_ACCEPTED: string = 'accepted';
/** The message carried no usable `nowMs`, so there is nothing to compare against. */
export const LISTEN_TOGETHER_CLOCK_SAMPLE_MISSING_SERVER_TIME: string = 'missing_server_time';
/** The monotonic clock appears to have run backwards: a stale or forged echo. */
export const LISTEN_TOGETHER_CLOCK_SAMPLE_NEGATIVE_ROUND_TRIP: string = 'negative_round_trip';
/** The round trip exceeded [LISTEN_TOGETHER_CLOCK_SYNC_MAX_RTT_MS]. */
export const LISTEN_TOGETHER_CLOCK_SAMPLE_ROUND_TRIP_TOO_SLOW: string = 'round_trip_too_slow';

export class ListenTogetherServerClockOffset {
  private offsetMs: number = 0;
  private pingSentAtElapsedMs: number = 0;
  private pingSentAtWallMs: number = 0;
  /**
   * Tri-state, matching upstream's `Boolean?`: null means "not asked yet", so the
   * next keep-alive still tries `np_ping`. Only an explicit rejection turns it
   * into the legacy ping forever.
   */
  private clockSyncPingSupported: boolean | null = null;

  /** The current estimate, in milliseconds to add to a local wall clock. */
  estimatedOffsetMs(): number {
    return this.offsetMs;
  }

  /** Exposed for diagnostics; null means no `np_pong` has been seen yet. */
  clockSyncPingSupport(): boolean | null {
    return this.clockSyncPingSupported;
  }

  /**
   * True when the keep-alive must fall back to the legacy `{"type":"ping"}`
   * frame. Upstream gates on `== false`, not on falsiness: an unknown state
   * still gets the timestamped ping, which is the only way to ever learn the
   * answer.
   */
  shouldSendLegacyPing(): boolean {
    return this.clockSyncPingSupported === false;
  }

  /** Record the send side of a round trip, immediately before the frame goes out. */
  markPingSent(nowElapsedMs: number, nowWallMs: number): void {
    this.pingSentAtElapsedMs = nowElapsedMs;
    this.pingSentAtWallMs = nowWallMs;
  }

  /** An `np_pong` arrived, so this server does speak clock sync. */
  markClockSyncPingSupported(): void {
    this.clockSyncPingSupported = true;
  }

  /** An `np_ping` was rejected as an unknown event type; stop sending it. */
  markClockSyncPingUnsupported(): void {
    this.clockSyncPingSupported = false;
  }

  /**
   * Full reset on disconnect. The offset goes back to 0 rather than being kept
   * across sessions on purpose: 0 is also the filter's "no estimate yet"
   * sentinel, and the next room may be served by a different worker.
   *
   * `clockSyncPingSupported` returns to null, not false — a reconnect gets to
   * re-probe, since the far side may have been upgraded.
   */
  reset(): void {
    this.offsetMs = 0;
    this.pingSentAtElapsedMs = 0;
    this.pingSentAtWallMs = 0;
    this.clockSyncPingSupported = null;
  }

  /**
   * Feed a `pong` / `np_pong`. `echoedSentAtElapsedMs` is the `t` field the
   * server echoes back; when present it is authoritative, because it survives a
   * ping we have already overwritten our own bookkeeping for. Its wall-clock
   * counterpart is then reconstructed by walking the monotonic delta back from
   * now, which is exactly what makes the echo usable at all.
   */
  acceptPong(
    serverNowMs: number | null,
    echoedSentAtElapsedMs: number | null,
    nowElapsedMs: number,
    nowWallMs: number
  ): string {
    const echoed: number | null =
      echoedSentAtElapsedMs !== null && echoedSentAtElapsedMs > 0 ? echoedSentAtElapsedMs : null;
    const sentAtElapsedMs: number = echoed !== null ? echoed : this.pingSentAtElapsedMs;
    const sentAtWallMs: number =
      echoed !== null ? nowWallMs - (nowElapsedMs - echoed) : this.pingSentAtWallMs;
    return this.acceptRoundTrip(serverNowMs, sentAtWallMs, sentAtElapsedMs, nowElapsedMs, nowWallMs);
  }

  /**
   * Feed any other server message that carries a `nowMs`. There is no send
   * timestamp to pair it with, so upstream passes zeros: the round trip is
   * unknown, the local reference is simply "now", and the sample is therefore
   * biased late by roughly one one-way trip — which is what the 70/30 filter
   * absorbs.
   */
  acceptServerMessage(serverNowMs: number | null, nowWallMs: number): string {
    return this.acceptRoundTrip(serverNowMs, 0, 0, 0, nowWallMs);
  }

  /** Feed the timestamp returned by an HTTP state request. */
  acceptHttpRoundTrip(
    serverNowMs: number | null,
    sentAtElapsedMs: number,
    sentAtWallMs: number,
    nowElapsedMs: number,
    nowWallMs: number
  ): string {
    return this.acceptRoundTrip(
      serverNowMs,
      sentAtWallMs,
      sentAtElapsedMs,
      nowElapsedMs,
      nowWallMs
    );
  }

  private acceptRoundTrip(
    serverNowMs: number | null,
    sentAtWallMs: number,
    sentAtElapsedMs: number,
    nowElapsedMs: number,
    nowWallMs: number
  ): string {
    if (serverNowMs === null || serverNowMs <= 0) {
      return LISTEN_TOGETHER_CLOCK_SAMPLE_MISSING_SERVER_TIME;
    }
    const hasRoundTrip: boolean = sentAtWallMs > 0 && sentAtElapsedMs > 0;
    const rtt: number = hasRoundTrip ? nowElapsedMs - sentAtElapsedMs : 0;
    if (rtt < 0) {
      // The monotonic clock cannot run backwards, so this is a stale or forged
      // echo rather than a slow network.
      return LISTEN_TOGETHER_CLOCK_SAMPLE_NEGATIVE_ROUND_TRIP;
    }
    if (rtt > LISTEN_TOGETHER_CLOCK_SYNC_MAX_RTT_MS) {
      return LISTEN_TOGETHER_CLOCK_SAMPLE_ROUND_TRIP_TOO_SLOW;
    }
    // The server stamped `serverNowMs` somewhere in flight; assuming a symmetric
    // path puts that instant half an RTT after we sent.
    const clientReferenceWallMs: number = hasRoundTrip
      ? sentAtWallMs + Math.trunc(rtt / 2)
      : nowWallMs;
    const newOffset: number = serverNowMs - clientReferenceWallMs;
    const prev: number = this.offsetMs;
    this.offsetMs =
      prev === 0
        ? newOffset
        : Math.trunc(
            (prev * (10 - LISTEN_TOGETHER_CLOCK_OFFSET_SAMPLE_WEIGHT) +
              newOffset * LISTEN_TOGETHER_CLOCK_OFFSET_SAMPLE_WEIGHT) /
              10
          );
    return LISTEN_TOGETHER_CLOCK_SAMPLE_ACCEPTED;
  }
}
