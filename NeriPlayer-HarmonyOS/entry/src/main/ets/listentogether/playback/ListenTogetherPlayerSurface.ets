/**
 * The seam between the listen-together state applier and the player.
 *
 * Upstream `ListenTogetherPlayerStateApplier` calls the `PlayerManager` object
 * directly, which is why none of its correction logic has a unit test. This port
 * narrows everything the applier needs into this interface: the applier (and its
 * tests) see only this, and a thin production binding forwards to the real
 * `PlayerManager` statics. Every method is named after the upstream call it
 * stands for.
 *
 * All transport methods are fire-and-forget from the applier's point of view:
 * the underlying PlayerManager calls are async promises, and ordering is
 * guaranteed by ArkUI's single-threaded event loop rather than by awaiting.
 */
import { SongItem } from '../../model/SongItem';

export interface ListenTogetherPlayerSurface {
  currentQueue(): SongItem[];
  currentSong(): SongItem | null;
  currentPositionMs(): number;
  isPlaying(): boolean;
  /** Upstream `playWhenReadyFlow.value`. */
  isPlayWhenReady(): boolean;
  /** Upstream `currentMediaUrlFlow.value`. */
  currentMediaUrl(): string | null;
  /** Upstream `playPlaylist(queue, index, commandSource = REMOTE_SYNC)`. */
  playPlaylistForRemoteSync(queue: SongItem[], index: number): void;
  /** Upstream `applyListenTogetherPlaybackMode(repeatMode, shuffleEnabled)`. */
  applyListenTogetherPlaybackMode(repeatMode: number | null, shuffleEnabled: boolean | null): void;
  resetSyncPlaybackRate(): void;
  setSyncPlaybackRate(rate: number): void;
  seekToForRemoteSync(positionMs: number): void;
  pauseForRemoteSync(): void;
  playForRemoteSync(): void;
  shouldHoldPlaybackForSafetyPause(causeType: string | null): boolean;
  shouldWaitForAuthoritativeStream(song: SongItem): boolean;
  /** Monotonic uptime, upstream `SystemClock.elapsedRealtime()`. */
  elapsedRealtimeMs(): number;
  /** Wall clock, upstream `System.currentTimeMillis()`. */
  wallClockMs(): number;
}

/** Upstream `ListenTogetherPlayerStateApplierConfig`, same fields. */
export class ListenTogetherPlayerStateApplierConfig {
  readonly tag: string;
  readonly trackSwitchForceSyncMs: number;
  readonly heartbeatDriftForceSyncMs: number;
  readonly playingDriftForceSyncMs: number;
  readonly pausedDriftForceSyncMs: number;
  readonly softSyncMinDriftMs: number;
  readonly softSyncFastDriftMs: number;
  readonly trackSwitchGracePeriodMs: number;
  readonly zeroPositionRollbackGuardMs: number;

  constructor(
    tag: string,
    trackSwitchForceSyncMs: number,
    heartbeatDriftForceSyncMs: number,
    playingDriftForceSyncMs: number,
    pausedDriftForceSyncMs: number,
    softSyncMinDriftMs: number,
    softSyncFastDriftMs: number,
    trackSwitchGracePeriodMs: number,
    zeroPositionRollbackGuardMs: number
  ) {
    this.tag = tag;
    this.trackSwitchForceSyncMs = trackSwitchForceSyncMs;
    this.heartbeatDriftForceSyncMs = heartbeatDriftForceSyncMs;
    this.playingDriftForceSyncMs = playingDriftForceSyncMs;
    this.pausedDriftForceSyncMs = pausedDriftForceSyncMs;
    this.softSyncMinDriftMs = softSyncMinDriftMs;
    this.softSyncFastDriftMs = softSyncFastDriftMs;
    this.trackSwitchGracePeriodMs = trackSwitchGracePeriodMs;
    this.zeroPositionRollbackGuardMs = zeroPositionRollbackGuardMs;
  }
}
