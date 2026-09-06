/**
 * M7.3a sync-layer tests, ported from
 * app/src/test/.../ListenTogetherPlayerSyncPlannerTest.kt (the twelve planner
 * cases; its seven `shouldReload/WaitForListenTogetherAuthoritativeStream` cases
 * already live in ListenTogetherPlayback.test.ets) plus coverage for the three
 * sync policies the Android suite exercises only indirectly through
 * ListenTogetherSessionManager: soft sync, the zero-position rollback guard and
 * the listener stall detector.
 */
import { describe, it, expect } from '@ohos/hypium';
import { SongItem } from '../../../main/ets/model/SongItem';
import { PlaybackStatus } from '../../../main/ets/player/PlaybackConstants';
import {
  ListenTogetherPlayerSyncContext,
  resolveListenTogetherPlayerSyncPlan,
  LISTEN_TOGETHER_HEARTBEAT_DRIFT_FORCE_SYNC_MS,
  LISTEN_TOGETHER_PAUSED_DRIFT_FORCE_SYNC_MS,
  LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS,
  LISTEN_TOGETHER_TRACK_SWITCH_FORCE_SYNC_MS
} from '../../../main/ets/listentogether/playback/sync/ListenTogetherPlayerSyncPlanner';
import {
  resolveListenTogetherSoftSyncPlaybackRate,
  shouldIgnoreListenTogetherUnexpectedZeroPositionRollback
} from '../../../main/ets/listentogether/playback/ListenTogetherPlaybackSyncPolicies';
import {
  LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE,
  shouldHoldListenTogetherPlaybackForSafetyPause,
  shouldUseListenTogetherListenerSafetyPause
} from '../../../main/ets/listentogether/playback/ListenTogetherListenerSafetyPausePolicy';
import {
  ListenTogetherListenerStallRecovery,
  ListenTogetherStallPlayerSnapshot
} from '../../../main/ets/listentogether/playback/ListenTogetherListenerStallRecovery';
import {
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import { createListenTogetherTrack } from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import { ListenTogetherChannels } from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';

const SOFT_SYNC_MIN_DRIFT_MS: number = 600;
const SOFT_SYNC_FAST_DRIFT_MS: number = 1_500;
const ZERO_ROLLBACK_GUARD_MS: number = 2_000;
const STALL_TIMEOUT_MS: number = 8_000;
const STALL_RECOVERY_COOLDOWN_MS: number = 12_000;
/**
 * The stall detector's cooldown starts from `lastRecoveryAtElapsedMs = 0`, so a
 * test clock that starts near zero would have its *first* recovery swallowed by a
 * cooldown that never actually elapsed on a real device. The elapsed clock these
 * cases stand in for is device uptime, which is always well past the cooldown, so
 * the fixtures start there too.
 */
const UPTIME_BASE_MS: number = 100_000;

/**
 * A context carrying the same values the Kotlin test passes by name. Every case
 * then overrides only the fields it is about, which is what makes the Kotlin
 * named-argument style readable — the field bag has to be assembled the same way
 * or the cases stop being comparable.
 */
function syncContext(): ListenTogetherPlayerSyncContext {
  const context = new ListenTogetherPlayerSyncContext();
  context.trackSwitchForceSyncMs = 500;
  context.heartbeatDriftForceSyncMs = 5_000;
  context.playingDriftForceSyncMs = 2_500;
  context.pausedDriftForceSyncMs = 800;
  return context;
}

function neteaseSong(audioId: string): SongItem {
  const song = new SongItem(Number(audioId), `Song ${audioId}`, 'Artist', '', 0, 269000, '');
  song.channelId = ListenTogetherChannels.NETEASE;
  song.audioId = audioId;
  return song;
}

/** A playing room whose single queued track is `audioId`. */
function playingRoom(audioId: string): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ABC234', 1);
  state.queue = [
    createListenTogetherTrack(
      `netease:${audioId}`,
      ListenTogetherChannels.NETEASE,
      audioId,
      `Song ${audioId}`,
      'Artist'
    )
  ];
  state.currentIndex = 0;
  state.playback.state = 'playing';
  return state;
}

/** A player that is loaded on `audioId` but producing no audio. */
function stalledPlayer(audioId: string): ListenTogetherStallPlayerSnapshot {
  const player = new ListenTogetherStallPlayerSnapshot();
  player.isPlaying = false;
  player.currentSong = neteaseSong(audioId);
  player.status = PlaybackStatus.LOADING;
  return player;
}

export default function listenTogetherSyncPlannerTest() {
  describe('ListenTogetherSyncPlanner', () => {
    it('exposes the upstream production drift thresholds', 0, () => {
      expect(LISTEN_TOGETHER_TRACK_SWITCH_FORCE_SYNC_MS).assertEqual(500);
      expect(LISTEN_TOGETHER_HEARTBEAT_DRIFT_FORCE_SYNC_MS).assertEqual(5_000);
      expect(LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS).assertEqual(2_500);
      expect(LISTEN_TOGETHER_PAUSED_DRIFT_FORCE_SYNC_MS).assertEqual(800);
      // A context built without thresholds must behave like production, not like
      // a caller who forgot them.
      const bare = new ListenTogetherPlayerSyncContext();
      expect(bare.trackSwitchForceSyncMs).assertEqual(500);
      expect(bare.heartbeatDriftForceSyncMs).assertEqual(5_000);
      expect(bare.playingDriftForceSyncMs).assertEqual(2_500);
      expect(bare.pausedDriftForceSyncMs).assertEqual(800);
    });

    it('does not force a playlist reload for a same-track heartbeat', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = true;
      context.expectedPositionMs = 1_600;
      context.localPositionMs = 1_000;

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldReloadPlaylist).assertFalse();
      expect(plan.shouldSeek).assertFalse();
      expect(plan.shouldIssuePlay).assertFalse();
    });

    it('seeks on heartbeat drift above the threshold without reloading', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = true;
      context.expectedPositionMs = 6_200;
      context.localPositionMs = 0;
      context.causeType = 'HEARTBEAT';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldReloadPlaylist).assertFalse();
      expect(plan.shouldSeek).assertTrue();
      expect(plan.shouldIssuePlay).assertFalse();
    });

    it('only forces a pause after a remote reload for a paused track switch', 0, () => {
      const context = syncContext();
      context.playbackContextChanged = true;
      context.desiredPlaying = false;
      context.localPlaying = true;
      context.causeType = 'SET_TRACK';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldReloadPlaylist).assertTrue();
      expect(plan.shouldForcePauseAfterRemoteLoad).assertTrue();
      expect(plan.shouldSeek).assertFalse();
      expect(plan.shouldIssuePlay).assertFalse();
      expect(plan.shouldIssuePause).assertTrue();
    });

    it('cancels a pending local playback start when the room is paused', 0, () => {
      const context = syncContext();
      context.desiredPlaying = false;
      context.localPlaying = false;
      context.localPlaybackAlreadyStarting = true;
      context.causeType = 'JOIN_AUTO_PAUSE';

      expect(resolveListenTogetherPlayerSyncPlan(context).shouldIssuePause).assertTrue();
    });

    it('keeps current progress on a passive zero rollback', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = true;
      context.expectedPositionMs = 0;
      context.localPositionMs = 9_200;
      context.ignoreUnexpectedZeroPositionRollback = true;
      context.causeType = 'HEARTBEAT';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.effectiveExpectedPositionMs).assertEqual(9_200);
      expect(plan.shouldSeek).assertFalse();
    });

    it('does not hard seek on a passive update during the track-switch grace', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = true;
      context.expectedPositionMs = 10_000;
      context.localPositionMs = 0;
      context.trackSwitchGracePeriodActive = true;
      context.causeType = 'HEARTBEAT';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldSeek).assertFalse();
      expect(plan.effectiveExpectedPositionMs).assertEqual(0);
    });

    it('still seeks for an active track switch during the grace period', 0, () => {
      const context = syncContext();
      context.playbackContextChanged = true;
      context.desiredPlaying = true;
      context.localPlaying = true;
      context.expectedPositionMs = 1_200;
      context.localPositionMs = 0;
      context.trackSwitchGracePeriodActive = true;
      context.causeType = 'SET_TRACK';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldReloadPlaylist).assertTrue();
      expect(plan.shouldSeek).assertTrue();
    });

    it('always seeks before a listener safety resume restarts playback', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = false;
      context.expectedPositionMs = 1_050;
      context.localPositionMs = 1_000;
      context.forcePositionSync = true;
      context.causeType = LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE;

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      // 50 ms of drift is far under every threshold; only forcePositionSync gets
      // this seek issued.
      expect(plan.shouldSeek).assertTrue();
      expect(plan.shouldIssuePlay).assertTrue();
    });

    it('does not re-issue play for a reload that is still waiting for the link', 0, () => {
      const context = syncContext();
      context.playbackContextChanged = true;
      context.desiredPlaying = true;
      context.localPlaying = false;
      context.awaitingAuthoritativeStream = true;
      context.causeType = 'LINK_READY';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldReloadPlaylist).assertTrue();
      expect(plan.shouldIssuePlay).assertFalse();
    });

    it('resumes playback once a LINK_READY reload has its stream', 0, () => {
      const context = syncContext();
      context.playbackContextChanged = true;
      context.desiredPlaying = true;
      context.localPlaying = false;
      context.causeType = 'LINK_READY';

      const plan = resolveListenTogetherPlayerSyncPlan(context);

      expect(plan.shouldReloadPlaylist).assertTrue();
      expect(plan.shouldIssuePlay).assertTrue();
    });

    it('re-issues play when a local start is stuck', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = false;
      context.localPlaybackAlreadyStarting = true;
      context.expectedPositionMs = 6_000;
      context.localPositionMs = 6_000;
      context.causeType = 'WATCHDOG';

      expect(resolveListenTogetherPlayerSyncPlan(context).shouldIssuePlay).assertTrue();
    });

    it('waits for the controller stream before re-issuing a stuck play', 0, () => {
      const context = syncContext();
      context.desiredPlaying = true;
      context.localPlaying = false;
      context.localPlaybackAlreadyStarting = true;
      context.awaitingAuthoritativeStream = true;
      context.expectedPositionMs = 6_000;
      context.localPositionMs = 6_000;
      context.causeType = 'WATCHDOG';

      expect(resolveListenTogetherPlayerSyncPlan(context).shouldIssuePlay).assertFalse();
    });

    it('reports a signed drift so the caller can tell ahead from behind', 0, () => {
      const behind = syncContext();
      behind.desiredPlaying = true;
      behind.localPlaying = true;
      behind.expectedPositionMs = 5_000;
      behind.localPositionMs = 1_000;
      const behindPlan = resolveListenTogetherPlayerSyncPlan(behind);
      expect(behindPlan.signedDriftMs).assertEqual(4_000);
      expect(behindPlan.driftMs).assertEqual(4_000);

      const ahead = syncContext();
      ahead.desiredPlaying = true;
      ahead.localPlaying = true;
      ahead.expectedPositionMs = 1_000;
      ahead.localPositionMs = 5_000;
      const aheadPlan = resolveListenTogetherPlayerSyncPlan(ahead);
      expect(aheadPlan.signedDriftMs).assertEqual(-4_000);
      expect(aheadPlan.driftMs).assertEqual(4_000);
    });

    it('nudges the playback rate only inside the soft-sync band', 0, () => {
      // Below the floor: nothing worth correcting.
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        400, 400, true, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertNull();
      // At or above the force threshold the caller seeks instead.
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        2_500, 2_500, true, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertNull();
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        1_800, 1_800, true, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertEqual(1.05);
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        900, 900, true, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertEqual(1.03);
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        1_800, -1_800, true, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertEqual(0.95);
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        900, -900, true, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertEqual(0.97);
    });

    it('never soft-syncs the controller or a disabled room', 0, () => {
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        900, 900, true, true,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertNull();
      expect(resolveListenTogetherSoftSyncPlaybackRate(
        900, 900, false, false,
        SOFT_SYNC_MIN_DRIFT_MS, SOFT_SYNC_FAST_DRIFT_MS, LISTEN_TOGETHER_PLAYING_DRIFT_FORCE_SYNC_MS
      )).assertNull();
    });

    it('ignores a stale zero position only when nothing about the track changed', 0, () => {
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'HEARTBEAT', true, 0, 60_000, false, false, ZERO_ROLLBACK_GUARD_MS
      )).assertTrue();
      // An active cause is the room genuinely telling us to go to 0.
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'SEEK', true, 0, 60_000, false, false, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
      // A real track switch legitimately arrives at 0.
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'HEARTBEAT', true, 0, 60_000, true, false, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'HEARTBEAT', true, 0, 60_000, false, true, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
      // Near the start of a track a rollback to 0 is indistinguishable from truth.
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'HEARTBEAT', true, 0, 1_999, false, false, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'HEARTBEAT', false, 0, 60_000, false, false, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        'HEARTBEAT', true, 1, 60_000, false, false, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
      expect(shouldIgnoreListenTogetherUnexpectedZeroPositionRollback(
        null, true, 0, 60_000, false, false, ZERO_ROLLBACK_GUARD_MS
      )).assertFalse();
    });

    it('applies the listener safety pause only when member control is disabled', 0, () => {
      expect(shouldUseListenTogetherListenerSafetyPause(true, false, false)).assertTrue();
      expect(shouldUseListenTogetherListenerSafetyPause(true, true, false)).assertFalse();
      expect(shouldUseListenTogetherListenerSafetyPause(true, false, true)).assertFalse();
      expect(shouldUseListenTogetherListenerSafetyPause(false, false, false)).assertFalse();
      // Unknown settings must not pin a listener paused.
      expect(shouldUseListenTogetherListenerSafetyPause(true, false, null)).assertFalse();
    });

    it('holds passive state until the explicit safety resume arrives', 0, () => {
      expect(shouldHoldListenTogetherPlaybackForSafetyPause(true, 'HEARTBEAT')).assertTrue();
      expect(shouldHoldListenTogetherPlaybackForSafetyPause(
        true, LISTEN_TOGETHER_LISTENER_SAFETY_RESUME_CAUSE
      )).assertFalse();
      expect(shouldHoldListenTogetherPlaybackForSafetyPause(false, 'HEARTBEAT')).assertFalse();
    });

    it('fires a stall recovery only after the timeout on one continuous stall', 0, () => {
      const detector = new ListenTogetherListenerStallRecovery(
        STALL_TIMEOUT_MS,
        STALL_RECOVERY_COOLDOWN_MS
      );
      const state = playingRoom('1001');
      const player = stalledPlayer('1001');

      // First tick starts the clock and never fires.
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS)).assertFalse();
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS + 7_999)).assertFalse();
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS + 8_000)).assertTrue();
      // The cooldown holds the verdict back without discarding the wait.
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS + 16_000)).assertFalse();
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS + 20_000)).assertTrue();
    });

    it('resets the stall clock on every not-a-stall condition', 0, () => {
      const detector = new ListenTogetherListenerStallRecovery(
        STALL_TIMEOUT_MS,
        STALL_RECOVERY_COOLDOWN_MS
      );
      const state = playingRoom('1001');
      const player = stalledPlayer('1001');

      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS)).assertFalse();
      // Audio started: the accumulated wait must be discarded, not paused.
      const playing = stalledPlayer('1001');
      playing.isPlaying = true;
      playing.status = PlaybackStatus.PLAYING;
      expect(detector.shouldRecover(state, playing, UPTIME_BASE_MS + 1_000)).assertFalse();
      // Had the wait survived, 8_500 would already be past the timeout.
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS + 8_500)).assertFalse();
      expect(detector.shouldRecover(state, player, UPTIME_BASE_MS + 16_600)).assertTrue();
    });

    it('leaves a paused room, a wrong track and a healthy player alone', 0, () => {
      const detector = new ListenTogetherListenerStallRecovery(
        STALL_TIMEOUT_MS,
        STALL_RECOVERY_COOLDOWN_MS
      );
      const pausedRoom = playingRoom('1001');
      pausedRoom.playback.state = 'paused';
      const player = stalledPlayer('1001');
      expect(detector.shouldRecover(pausedRoom, player, UPTIME_BASE_MS)).assertFalse();
      expect(detector.shouldRecover(pausedRoom, player, UPTIME_BASE_MS + 20_000)).assertFalse();

      const state = playingRoom('1001');
      // A different local track is a sync problem the planner owns, not a stall.
      const wrongTrack = stalledPlayer('2002');
      expect(detector.shouldRecover(state, wrongTrack, UPTIME_BASE_MS)).assertFalse();
      expect(detector.shouldRecover(state, wrongTrack, UPTIME_BASE_MS + 20_000)).assertFalse();

      const nothingLoaded = stalledPlayer('1001');
      nothingLoaded.currentSong = null;
      expect(detector.shouldRecover(state, nothingLoaded, UPTIME_BASE_MS)).assertFalse();

      // PAUSED with no pending start is a player at rest, not a wedged one.
      const atRest = stalledPlayer('1001');
      atRest.status = PlaybackStatus.PAUSED;
      expect(detector.shouldRecover(state, atRest, UPTIME_BASE_MS)).assertFalse();
      expect(detector.shouldRecover(state, atRest, UPTIME_BASE_MS + 20_000)).assertFalse();
      // ...but a pending play or media load makes the same status a stall.
      const pendingStart = stalledPlayer('1001');
      pendingStart.status = PlaybackStatus.PAUSED;
      pendingStart.playWhenReady = true;
      expect(detector.shouldRecover(state, pendingStart, UPTIME_BASE_MS + 30_000)).assertFalse();
      expect(detector.shouldRecover(state, pendingStart, UPTIME_BASE_MS + 38_000)).assertTrue();
    });

    it('clears the cooldown on reset so the next track is not delayed', 0, () => {
      const state = playingRoom('1001');
      const player = stalledPlayer('1001');
      // Two detectors driven by the same clock, differing only in the reset. The
      // pair is what makes the assertion meaningful: on a single detector the
      // cooldown is indistinguishable from the timeout restarting.
      const withReset = new ListenTogetherListenerStallRecovery(
        STALL_TIMEOUT_MS,
        STALL_RECOVERY_COOLDOWN_MS
      );
      const withoutReset = new ListenTogetherListenerStallRecovery(
        STALL_TIMEOUT_MS,
        STALL_RECOVERY_COOLDOWN_MS
      );

      expect(withReset.shouldRecover(state, player, UPTIME_BASE_MS)).assertFalse();
      expect(withoutReset.shouldRecover(state, player, UPTIME_BASE_MS)).assertFalse();
      expect(withReset.shouldRecover(state, player, UPTIME_BASE_MS + 8_000)).assertTrue();
      expect(withoutReset.shouldRecover(state, player, UPTIME_BASE_MS + 8_000)).assertTrue();

      withReset.reset();

      // Both are past the timeout again at +17_000, but only the reset one has
      // dropped the cooldown that would otherwise swallow the verdict.
      expect(withReset.shouldRecover(state, player, UPTIME_BASE_MS + 9_000)).assertFalse();
      expect(withReset.shouldRecover(state, player, UPTIME_BASE_MS + 17_000)).assertTrue();
      expect(withoutReset.shouldRecover(state, player, UPTIME_BASE_MS + 17_000)).assertFalse();
    });
  });
}
