// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/playback/sync/ListenTogetherPlayerSyncPlanner.kt: given
 * the room's authoritative state and what the local player is doing, decide the
 * whole correction in one shot — reload, seek, play, pause — with no side
 * effects. The applier in M7.3b executes the plan; this file only computes it.
 *
 * Two shape divergences, no behaviour change:
 *
 * 1. **The context is a mutable field bag, not a 16-argument constructor.** The
 *    Kotlin data class is built with named arguments, which ArkTS has no
 *    equivalent for; sixteen positional parameters would be unreadable and easy
 *    to transpose silently. The codebase already builds `ListenTogetherRoomState`
 *    this way, so callers construct and assign.
 * 2. **The four drift thresholds live here, with the upstream production values
 *    as defaults.** Upstream declares them as private constants inside
 *    `ListenTogetherSessionManager` and injects them. Keeping them next to the
 *    rule that reads them means a context built without them still behaves like
 *    production instead of like a caller who forgot; M7.3b's session manager
 *    imports these rather than redeclaring them.
 */
import { isListenTogetherPassivePositionUpdateType } from '../../control/ListenTogetherControlEventTypes';

/** Upstream `TRACK_SWITCH_FORCE_SYNC_MS`. */
export const LISTEN_TOGETHER_TRACK_SWITCH_FORCE_SYNC_MS: number = 500;
/** Upstream `HEARTBEAT_DRIFT_FORCE_SYNC_MS`: heartbeats tolerate far more drift, because correcting one is an audible jump and a heartbeat is not a user action. */
export const LISTEN_TOGETHER_HEARTBEAT_DRIFT_FORCE_SYNC_MS: number = 5_000;
/** Upstream `PLAYING_DRIFT_FORCE_SYNC_MS`. */
export const LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS: number = 2_500;
/** Upstream `PAUSED_DRIFT_FORCE_SYNC_MS`: tightest of the four, because a paused seek costs nothing. */
export const LISTEN_TOGETHER_PAUSED_DRIFT_FORCE_SYNC_MS: number = 800;

/** Upstream `ListenTogetherPlayerSyncContext`. */
export class ListenTogetherPlayerSyncContext {
  /** The room points at a different queue than the one loaded locally. */
  playbackContextChanged: boolean = false;
  /** Same queue, different index. */
  targetIndexChanged: boolean = false;
  /** What the room says playback should be doing. */
  desiredPlaying: boolean = false;
  /** What the local player is actually doing. */
  localPlaying: boolean = false;
  /** A local play has been issued but has not been observed to start yet. */
  localPlaybackAlreadyStarting: boolean = false;
  /** The controller's direct stream link has not arrived; playing now would use the wrong source. */
  awaitingAuthoritativeStream: boolean = false;
  expectedPositionMs: number = 0;
  localPositionMs: number = 0;
  /** Decided by `shouldIgnoreListenTogetherUnexpectedZeroPositionRollback`. */
  ignoreUnexpectedZeroPositionRollback: boolean = false;
  /** A track switch is still settling locally, so passive positions are not trustworthy. */
  trackSwitchGracePeriodActive: boolean = false;
  /** The caller knows the local position is wrong regardless of drift (e.g. a safety resume). */
  forcePositionSync: boolean = false;
  causeType: string | null = null;
  trackSwitchForceSyncMs: number = LISTEN_TOGETHER_TRACK_SWITCH_FORCE_SYNC_MS;
  heartbeatDriftForceSyncMs: number = LISTEN_TOGETHER_HEARTBEAT_DRIFT_FORCE_SYNC_MS;
  playingDriftForceSyncMs: number = LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS;
  pausedDriftForceSyncMs: number = LISTEN_TOGETHER_PAUSED_DRIFT_FORCE_SYNC_MS;
}

/** Upstream `ListenTogetherPlayerSyncPlan`. */
export class ListenTogetherPlayerSyncPlan {
  readonly shouldReloadPlaylist: boolean;
  /** The position the plan actually targets, which is not always the room's. */
  readonly effectiveExpectedPositionMs: number;
  /** Positive when the room is ahead of the local player. */
  readonly signedDriftMs: number;
  readonly driftMs: number;
  readonly shouldSeek: boolean;
  readonly shouldIssuePlay: boolean;
  readonly shouldIssuePause: boolean;
  readonly shouldForcePauseAfterRemoteLoad: boolean;
  readonly desiredPlaying: boolean;
  readonly localPlaying: boolean;

  constructor(
    shouldReloadPlaylist: boolean,
    effectiveExpectedPositionMs: number,
    signedDriftMs: number,
    driftMs: number,
    shouldSeek: boolean,
    shouldIssuePlay: boolean,
    shouldIssuePause: boolean,
    shouldForcePauseAfterRemoteLoad: boolean,
    desiredPlaying: boolean,
    localPlaying: boolean
  ) {
    this.shouldReloadPlaylist = shouldReloadPlaylist;
    this.effectiveExpectedPositionMs = effectiveExpectedPositionMs;
    this.signedDriftMs = signedDriftMs;
    this.driftMs = driftMs;
    this.shouldSeek = shouldSeek;
    this.shouldIssuePlay = shouldIssuePlay;
    this.shouldIssuePause = shouldIssuePause;
    this.shouldForcePauseAfterRemoteLoad = shouldForcePauseAfterRemoteLoad;
    this.desiredPlaying = desiredPlaying;
    this.localPlaying = localPlaying;
  }
}

export function resolveListenTogetherPlayerSyncPlan(
  context: ListenTogetherPlayerSyncContext
): ListenTogetherPlayerSyncPlan {
  const shouldReloadPlaylist = context.playbackContextChanged || context.targetIndexChanged;
  const causeType = context.causeType;
  // During a track switch the room's position for the *old* track is still in
  // flight; a passive update carrying it must not drag the new track's clock.
  const shouldDeferPassiveTrackSwitchSync = context.trackSwitchGracePeriodActive &&
    causeType !== null &&
    isListenTogetherPassivePositionUpdateType(causeType);

  let effectiveExpectedPositionMs = context.expectedPositionMs;
  if (context.ignoreUnexpectedZeroPositionRollback || shouldDeferPassiveTrackSwitchSync) {
    effectiveExpectedPositionMs = context.localPositionMs;
  }
  const signedDriftMs = effectiveExpectedPositionMs - context.localPositionMs;
  const driftMs = Math.abs(signedDriftMs);
  const isHeartbeatUpdate = causeType === 'HEARTBEAT';

  let shouldSeek: boolean;
  if (context.forcePositionSync) {
    shouldSeek = true;
  } else if (shouldDeferPassiveTrackSwitchSync) {
    shouldSeek = false;
  } else if (shouldReloadPlaylist) {
    // A reload restarts the track at 0, so any non-zero target needs a seek even
    // when the numeric drift looks small.
    shouldSeek = effectiveExpectedPositionMs > 0 || driftMs > context.trackSwitchForceSyncMs;
  } else if (isHeartbeatUpdate && context.desiredPlaying) {
    shouldSeek = driftMs > context.heartbeatDriftForceSyncMs;
  } else if (context.desiredPlaying) {
    shouldSeek = driftMs > context.playingDriftForceSyncMs;
  } else {
    shouldSeek = driftMs > context.pausedDriftForceSyncMs;
  }

  // A reload normally ends with the player already starting, so re-issuing play
  // would double-start it. LINK_READY is the exception: that reload swaps the
  // source of a track that was deliberately held, and playback must resume.
  const shouldResumeAfterReload = shouldReloadPlaylist &&
    causeType === 'LINK_READY' &&
    !context.awaitingAuthoritativeStream;
  const shouldIssuePause = !context.desiredPlaying &&
    (shouldReloadPlaylist || context.localPlaying || context.localPlaybackAlreadyStarting);
  const shouldIssuePlay = context.desiredPlaying &&
    !context.localPlaying &&
    (!shouldReloadPlaylist || shouldResumeAfterReload) &&
    !context.awaitingAuthoritativeStream;
  const shouldForcePauseAfterRemoteLoad = !context.desiredPlaying && shouldReloadPlaylist;

  return new ListenTogetherPlayerSyncPlan(
    shouldReloadPlaylist,
    effectiveExpectedPositionMs,
    signedDriftMs,
    driftMs,
    shouldSeek,
    shouldIssuePlay,
    shouldIssuePause,
    shouldForcePauseAfterRemoteLoad,
    context.desiredPlaying,
    context.localPlaying
  );
}
