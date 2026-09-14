// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/ListenTogetherListenerStallRecovery.kt: a
 * listener whose player is wedged while the room plays on must eventually be
 * kicked back into life instead of sitting silent.
 *
 * **Divergence: the player state arrives as an injected snapshot.** Upstream
 * reads `PlayerManager.isPlayingFlow`, `playWhenReadyFlow`,
 * `isPendingMediaLoadActive()` and the ExoPlayer `playbackState` as global
 * singletons, which makes it untestable off-device. Here every input comes in via
 * [ListenTogetherStallPlayerSnapshot], so the gate order can be pinned by the
 * host unit suite and the wiring stays at the M7.3b integration point.
 *
 * That seam also absorbs a real platform gap, recorded here rather than papered
 * over. This project's `PlaybackStatus` is
 * `IDLE/LOADING/PLAYING/PAUSED/COMPLETED/ERROR` — it has **no BUFFERING** value,
 * because AVPlayer's `initialized`/`preparing`/`buffering` phases all surface as
 * `LOADING`. So upstream's
 * `playbackState == STATE_BUFFERING || playbackState == STATE_IDLE` becomes
 * `status == LOADING || status == IDLE`, which is the same *intent* (the player
 * is not producing audio) over a coarser vocabulary. `PlayerManager` likewise
 * exposes no `playWhenReady` flow and no pending-media-load flag, so
 * `playWhenReady` and `pendingMediaLoadActive` must be filled from the state
 * applier's own bookkeeping in M7.3b — they are **not** yet sourced from the
 * player, and until they are, this detector runs on the status alone.
 *
 * Upstream's `NPLogger.w` on the firing tick is deliberately dropped rather than
 * ported: the caller already knows a recovery fired (that is what the `true`
 * means) and has the room context to log it usefully. Importing `app/Logger`
 * would pull `@kit.PerformanceAnalysisKit` into a tree that is otherwise kit-free
 * by design. Note that this is a design convention, not a technical limit — kit
 * imports do load in the local host suite (`DownloadTaskStore.test.ets` pulls in
 * `DownloadEngine.ets`, which imports three kits) — but the convention is worth
 * keeping so this file stays trivially loadable anywhere, including a worker.
 */
import { SongItem } from '../../model/SongItem';
import { PlaybackStatus } from '../../player/PlaybackConstants';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { listenTogetherCurrentStableKey, listenTogetherTargetSongItem, sameListenTogetherTrack } from './ListenTogetherPlaybackTrack';

/** Everything the detector needs to know about the local player, at one instant. */
export class ListenTogetherStallPlayerSnapshot {
  /** True when the player is actually producing audio right now. */
  isPlaying: boolean = false;
  /** What the player believes it is playing, or null when nothing is loaded. */
  currentSong: SongItem | null = null;
  /** A play was requested and has not been observed to start. */
  playWhenReady: boolean = false;
  /** A stream resolve or an AVPlayer prepare is still in flight. */
  pendingMediaLoadActive: boolean = false;
  /** The player's own status; LOADING and IDLE both mean "no audio". */
  status: PlaybackStatus = PlaybackStatus.IDLE;
}

export class ListenTogetherListenerStallRecovery {
  private readonly stallTimeoutMs: number;
  private readonly recoveryCooldownMs: number;
  private bufferingStartedAtElapsedMs: number = 0;
  private bufferingTrackStableKey: string | null = null;
  private lastRecoveryAtElapsedMs: number = 0;

  constructor(stallTimeoutMs: number, recoveryCooldownMs: number) {
    this.stallTimeoutMs = stallTimeoutMs;
    this.recoveryCooldownMs = recoveryCooldownMs;
  }

  /**
   * True exactly on the tick where a recovery should be triggered. The gate order
   * is upstream's and matters: every "this is not a stall" case resets the timer,
   * so a stall must be continuous to count, while the two timing gates only
   * withhold the verdict and leave the accumulated wait intact.
   */
  shouldRecover(
    state: ListenTogetherRoomState,
    player: ListenTogetherStallPlayerSnapshot,
    nowElapsedMs: number
  ): boolean {
    if (state.playback.state !== 'playing') {
      this.reset();
      return false;
    }
    if (player.isPlaying) {
      this.reset();
      return false;
    }
    const targetSong = listenTogetherTargetSongItem(state);
    if (targetSong === null) {
      this.reset();
      return false;
    }
    const currentSong = player.currentSong;
    // A different track loaded locally is a sync problem, not a stall; the sync
    // planner owns that case and will reload the playlist.
    if (currentSong === null || !sameListenTogetherTrack(currentSong, targetSong)) {
      this.reset();
      return false;
    }
    const looksStalled = player.playWhenReady ||
      player.pendingMediaLoadActive ||
      player.status === PlaybackStatus.LOADING ||
      player.status === PlaybackStatus.IDLE;
    if (!looksStalled) {
      this.reset();
      return false;
    }
    const stableKey = listenTogetherCurrentStableKey(state);
    if (stableKey === null) {
      this.reset();
      return false;
    }
    if (this.bufferingTrackStableKey !== stableKey) {
      // First tick on this track: start the clock, never fire immediately.
      this.bufferingTrackStableKey = stableKey;
      this.bufferingStartedAtElapsedMs = nowElapsedMs;
      return false;
    }
    if (nowElapsedMs - this.bufferingStartedAtElapsedMs < this.stallTimeoutMs) {
      return false;
    }
    if (nowElapsedMs - this.lastRecoveryAtElapsedMs < this.recoveryCooldownMs) {
      return false;
    }
    this.bufferingStartedAtElapsedMs = nowElapsedMs;
    this.lastRecoveryAtElapsedMs = nowElapsedMs;
    return true;
  }

  /**
   * Clears the stall clock *and* the cooldown. Upstream does the same: leaving the
   * room or switching tracks is a fresh start, and a stale cooldown would delay
   * the first real recovery of the next track.
   */
  reset(): void {
    this.bufferingStartedAtElapsedMs = 0;
    this.bufferingTrackStableKey = null;
    this.lastRecoveryAtElapsedMs = 0;
  }
}
