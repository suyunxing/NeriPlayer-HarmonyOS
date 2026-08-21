/**
 * Port of listentogether/playback/ListenTogetherPlayerStateApplier.kt: turns an
 * authoritative room snapshot into concrete player corrections — reload the
 * queue, seek, play, pause, or nudge with a soft playback rate.
 *
 * Every decision is delegated to already-tested pieces: the sync plan comes from
 * `resolveListenTogetherPlayerSyncPlanner` (M7.3a), the zero-rollback guard and
 * soft-rate choice from `ListenTogetherPlaybackSyncPolicies`, the authoritative
 * stream check from `ListenTogetherStreamPolicy`, position math from
 * `ListenTogetherPlaybackPosition`. What remains here is exactly upstream's
 * orchestration, in upstream order, against the injectable
 * [ListenTogetherPlayerSurface] instead of a player singleton.
 */
import { Logger } from '../../app/Logger';
import { SongItem } from '../../model/SongItem';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import {
  shouldReloadListenTogetherAuthoritativeStream,
  shouldWaitForListenTogetherAuthoritativeStreamPlayback
} from './ListenTogetherStreamPolicy';
import {
  resolveListenTogetherSoftSyncPlaybackRate,
  shouldIgnoreListenTogetherUnexpectedZeroPositionRollback
} from './ListenTogetherPlaybackSyncPolicies';
import {
  clampListenTogetherPositionMs,
  listenTogetherExpectedPositionMs,
  wrapListenTogetherSingleTrackRepeatPosition
} from './ListenTogetherPlaybackPosition';
import {
  hasSameListenTogetherTrackSequence,
  indexOfListenTogetherTrack,
  sameListenTogetherTrack
} from './ListenTogetherPlaybackTrack';
import { mergeListenTogetherCurrentTrack } from './ListenTogetherShareableQueueSnapshot';
import {
  ListenTogetherTrack,
  cloneListenTogetherTrack
} from '../protocol/ListenTogetherTrack';
import { listenTogetherTrackToSongItem } from '../mapping/ListenTogetherTrackMapping';
import { LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE } from './ListenTogetherListenerSafetyPausePolicy';
import {
  ListenTogetherPlayerSurface,
  ListenTogetherPlayerStateApplierConfig
} from './ListenTogetherPlayerSurface';
import {
  resolveListenTogetherPlayerSyncPlan,
  ListenTogetherPlayerSyncContext,
  ListenTogetherPlayerSyncPlan
} from './sync/ListenTogetherPlayerSyncPlanner';

const TAG: string = 'LtStateApplier';

export class ListenTogetherPlayerStateApplier {
  private readonly config: ListenTogetherPlayerStateApplierConfig;
  private readonly surface: ListenTogetherPlayerSurface;
  private readonly roomStateProvider: () => ListenTogetherRoomState | null;
  private readonly isControllerProvider: () => boolean;
  private readonly serverClockOffsetProvider: () => number;
  private lastTrackSwitchAtElapsedMs: number = 0;

  constructor(
    config: ListenTogetherPlayerStateApplierConfig,
    surface: ListenTogetherPlayerSurface,
    roomStateProvider: () => ListenTogetherRoomState | null,
    isControllerProvider: () => boolean,
    serverClockOffsetProvider: () => number
  ) {
    this.config = config;
    this.surface = surface;
    this.roomStateProvider = roomStateProvider;
    this.isControllerProvider = isControllerProvider;
    this.serverClockOffsetProvider = serverClockOffsetProvider;
  }

  /**
   * Applies the room state to the player; false when deliberately skipped
   * (stale version, safety-pause hold, empty queue).
   */
  apply(state: ListenTogetherRoomState, causeType: string | null, expectedPositionMs: number | null): boolean {
    const latestRoomVersion = this.latestAcceptedRoomVersion(state);
    if (state.version < latestRoomVersion) {
      Logger.debug(
        `${TAG}: skip stale state, roomId=${state.roomId}, version=${state.version}, latest=${latestRoomVersion}, causeType=${causeType}`
      );
      return false;
    }
    if (this.surface.shouldHoldPlaybackForSafetyPause(causeType)) {
      Logger.debug(
        `${TAG}: hold listener safety pause, roomId=${state.roomId}, version=${state.version}, causeType=${causeType}`
      );
      return false;
    }
    const queue = this.roomQueue(state);
    if (queue.length === 0) {
      Logger.warn(`${TAG}: skip empty queue, roomId=${state.roomId}, version=${state.version}, causeType=${causeType}`);
      return false;
    }

    const targetIndex = Math.min(Math.max(state.currentIndex, 0), queue.length - 1);
    const targetSong = queue[targetIndex];
    const currentQueue = this.surface.currentQueue();
    const currentSong = this.surface.currentSong();
    const localCurrentIndex = indexOfListenTogetherTrack(currentQueue, currentSong);
    const needsAuthoritativeStreamReload =
      this.shouldReloadForAuthoritativeStream(targetSong, currentSong);
    const forcePlaybackStallReload =
      causeType === 'WATCHDOG_STALL' &&
      state.playback.state === 'playing' &&
      currentSong !== null &&
      sameListenTogetherTrack(currentSong, targetSong);
    const playbackContextChanged =
      !hasSameListenTogetherTrackSequence(currentQueue, queue) ||
      needsAuthoritativeStreamReload ||
      forcePlaybackStallReload;
    const targetIndexChanged = localCurrentIndex !== targetIndex;
    const trackSwitchGracePeriodActive = this.isTrackSwitchGracePeriodActive();

    if (playbackContextChanged || targetIndexChanged) {
      this.lastTrackSwitchAtElapsedMs = this.surface.elapsedRealtimeMs();
      this.surface.resetSyncPlaybackRate();
      this.surface.playPlaylistForRemoteSync(queue, targetIndex);
    }
    this.surface.applyListenTogetherPlaybackMode(state.playback.repeatMode, state.playback.shuffleEnabled);

    let rawExpectedPositionMs: number;
    if (expectedPositionMs !== null) {
      rawExpectedPositionMs = expectedPositionMs;
    } else {
      rawExpectedPositionMs = listenTogetherExpectedPositionMs(
        state.playback,
        this.surface.wallClockMs(),
        this.serverClockOffsetProvider(),
        targetSong.durationMs
      );
    }
    const repeatAwareExpectedPositionMs = wrapListenTogetherSingleTrackRepeatPosition(
      rawExpectedPositionMs,
      state.playback.repeatMode,
      targetSong.durationMs
    );
    // 用目标曲目时长钳上限, 防止异常大的 position 把播放器推到曲末造成误切/卡顿
    const resolvedExpectedPositionMs = clampListenTogetherPositionMs(
      repeatAwareExpectedPositionMs,
      targetSong.durationMs
    );
    const localPositionMs = Math.max(0, this.surface.currentPositionMs());
    const desiredPlaying = state.playback.state === 'playing';
    const localPlaying = this.surface.isPlaying();
    const localPlaybackAlreadyStarting = this.surface.isPlayWhenReady();
    const awaitingAuthoritativeStream = shouldWaitForListenTogetherAuthoritativeStreamPlayback(
      this.surface.shouldWaitForAuthoritativeStream(targetSong),
      currentSong !== null && sameListenTogetherTrack(currentSong, targetSong),
      currentSong === null ? null : currentSong.streamUrl,
      this.surface.currentMediaUrl()
    );
    const ignoreUnexpectedZeroPositionRollback =
      shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        causeType,
        desiredPlaying,
        resolvedExpectedPositionMs,
        localPositionMs,
        playbackContextChanged,
        targetIndexChanged,
        this.config.zeroPositionRollbackGuardMs
      );
    const syncPlan = resolveListenTogetherPlayerSyncPlan(this.buildSyncContext(
      playbackContextChanged,
      targetIndexChanged,
      desiredPlaying,
      localPlaying,
      localPlaybackAlreadyStarting,
      awaitingAuthoritativeStream,
      resolvedExpectedPositionMs,
      localPositionMs,
      ignoreUnexpectedZeroPositionRollback,
      trackSwitchGracePeriodActive,
      causeType
    ));
    Logger.debug(
      `${TAG}: causeType=${causeType}, desiredPlaying=${desiredPlaying}, localPlaying=${localPlaying}, ` +
      `starting=${localPlaybackAlreadyStarting}, awaitingStream=${awaitingAuthoritativeStream}, ` +
      `localIndex=${localCurrentIndex}, targetIndex=${targetIndex}, contextChanged=${playbackContextChanged}, ` +
      `indexChanged=${targetIndexChanged}, grace=${trackSwitchGracePeriodActive}, ` +
      `reload=${syncPlan.shouldReloadPlaylist}, effectiveMs=${syncPlan.effectiveExpectedPositionMs}, ` +
      `drift=${syncPlan.driftMs}, signedDrift=${syncPlan.signedDriftMs}, seek=${syncPlan.shouldSeek}, ` +
      `play=${syncPlan.shouldIssuePlay}, pause=${syncPlan.shouldIssuePause}`
    );
    this.applySyncPlan(syncPlan);
    return true;
  }

  private buildSyncContext(
    playbackContextChanged: boolean,
    targetIndexChanged: boolean,
    desiredPlaying: boolean,
    localPlaying: boolean,
    localPlaybackAlreadyStarting: boolean,
    awaitingAuthoritativeStream: boolean,
    expectedPositionMs: number,
    localPositionMs: number,
    ignoreUnexpectedZeroPositionRollback: boolean,
    trackSwitchGracePeriodActive: boolean,
    causeType: string | null
  ): ListenTogetherPlayerSyncContext {
    const context = new ListenTogetherPlayerSyncContext();
    context.playbackContextChanged = playbackContextChanged;
    context.targetIndexChanged = targetIndexChanged;
    context.desiredPlaying = desiredPlaying;
    context.localPlaying = localPlaying;
    context.localPlaybackAlreadyStarting = localPlaybackAlreadyStarting;
    context.awaitingAuthoritativeStream = awaitingAuthoritativeStream;
    context.expectedPositionMs = expectedPositionMs;
    context.localPositionMs = localPositionMs;
    context.ignoreUnexpectedZeroPositionRollback = ignoreUnexpectedZeroPositionRollback;
    context.trackSwitchGracePeriodActive = trackSwitchGracePeriodActive;
    context.forcePositionSync = causeType === LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE;
    context.causeType = causeType;
    context.trackSwitchForceSyncMs = this.config.trackSwitchForceSyncMs;
    context.heartbeatDriftForceSyncMs = this.config.heartbeatDriftForceSyncMs;
    context.playingDriftForceSyncMs = this.config.playingDriftForceSyncMs;
    context.pausedDriftForceSyncMs = this.config.pausedDriftForceSyncMs;
    return context;
  }

  private latestAcceptedRoomVersion(incoming: ListenTogetherRoomState): number {
    const current = this.roomStateProvider();
    return current === null ? incoming.version : current.version;
  }

  private isTrackSwitchGracePeriodActive(): boolean {
    const switchedAt = this.lastTrackSwitchAtElapsedMs;
    if (switchedAt <= 0) {
      return false;
    }
    return this.surface.elapsedRealtimeMs() - switchedAt < this.config.trackSwitchGracePeriodMs;
  }

  /**
   * Upstream `ListenTogetherRoomState.toSongQueue`: the full queue when present
   * (with the authoritative track merged into its slot), else the single track,
   * else nothing.
   */
  private roomQueue(state: ListenTogetherRoomState): SongItem[] {
    if (state.queue.length > 0) {
      const merged: ListenTogetherTrack[] =
        mergeListenTogetherCurrentTrack(state.queue, state.currentIndex, state.track);
      const songs: SongItem[] = [];
      for (const track of merged) {
        songs.push(listenTogetherTrackToSongItem(track));
      }
      return songs;
    }
    if (state.track !== null) {
      return [listenTogetherTrackToSongItem(cloneListenTogetherTrack(state.track))];
    }
    return [];
  }

  private applySyncPlan(syncPlan: ListenTogetherPlayerSyncPlan): void {
    if (syncPlan.desiredPlaying) {
      this.applyPlayingSyncPlan(syncPlan);
      return;
    }
    this.surface.resetSyncPlaybackRate();
    if (syncPlan.shouldSeek) {
      this.surface.seekToForRemoteSync(syncPlan.effectiveExpectedPositionMs);
    }
    if (syncPlan.shouldIssuePause) {
      this.surface.pauseForRemoteSync();
    }
  }

  private applyPlayingSyncPlan(syncPlan: ListenTogetherPlayerSyncPlan): void {
    if (syncPlan.shouldSeek) {
      this.surface.resetSyncPlaybackRate();
      this.surface.seekToForRemoteSync(syncPlan.effectiveExpectedPositionMs);
    } else {
      this.applySoftDriftCorrection(syncPlan.driftMs, syncPlan.signedDriftMs, true);
    }
    if (syncPlan.shouldIssuePlay) {
      this.surface.resetSyncPlaybackRate();
      this.surface.playForRemoteSync();
    }
  }

  private applySoftDriftCorrection(driftMs: number, signedDriftMs: number, allowSoftSync: boolean): void {
    const rate = resolveListenTogetherSoftSyncPlaybackRate(
      driftMs,
      signedDriftMs,
      allowSoftSync,
      this.isControllerProvider(),
      this.config.softSyncMinDriftMs,
      this.config.softSyncFastDriftMs,
      this.config.playingDriftForceSyncMs
    );
    if (rate === null) {
      Logger.debug(`${TAG}: reset sync rate, driftMs=${driftMs}, signedDriftMs=${signedDriftMs}`);
      this.surface.resetSyncPlaybackRate();
      return;
    }
    Logger.debug(`${TAG}: apply rate ${rate}, driftMs=${driftMs}, signedDriftMs=${signedDriftMs}`);
    this.surface.setSyncPlaybackRate(rate);
  }

  private shouldReloadForAuthoritativeStream(targetSong: SongItem, currentSong: SongItem | null): boolean {
    if (this.isControllerProvider()) {
      return false;
    }
    const room = this.roomStateProvider();
    if (room === null || !room.settings.shareAudioLinks) {
      return false;
    }
    if (currentSong === null || !sameListenTogetherTrack(currentSong, targetSong)) {
      return false;
    }
    return shouldReloadListenTogetherAuthoritativeStream(
      targetSong.streamUrl,
      this.surface.currentMediaUrl()
    );
  }
}
