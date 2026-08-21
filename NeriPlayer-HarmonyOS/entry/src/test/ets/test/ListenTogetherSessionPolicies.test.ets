/**
 * M7.3a session-policy tests, ported from
 * app/src/test/.../ListenTogetherSessionPoliciesTest.kt. Its two `session role`
 * cases already live in ListenTogetherSession.test.ets and are not duplicated
 * here; everything else it covers is ported, plus the three policy files upstream
 * reaches only through ListenTogetherSessionManager (incoming-state ignore/defer,
 * the accepted-version high-water mark and the track-finished legacy fallback).
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LISTEN_TOGETHER_DEFAULT_RECENT_EVENT_LIMIT,
  ListenTogetherRecentEventTracker
} from '../../../main/ets/listentogether/session/ListenTogetherRecentEventTracker';
import { shouldDropListenTogetherControllerLocalEcho } from '../../../main/ets/listentogether/session/ListenTogetherControllerEchoPolicy';
import {
  LISTEN_TOGETHER_DEFAULT_CONTROLLER_GRACE_PERIOD_MS,
  LISTEN_TOGETHER_NOTICE_CONTROLLER_OFFLINE,
  LISTEN_TOGETHER_NOTICE_ROOM_CLOSED,
  resolveListenTogetherRoomNotice
} from '../../../main/ets/listentogether/session/ListenTogetherRoomNotice';
import {
  LISTEN_TOGETHER_PAUSED_HEARTBEAT_INTERVAL_MS,
  LISTEN_TOGETHER_PLAYING_HEARTBEAT_INTERVAL_MS,
  LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS,
  resolveListenTogetherHeartbeatIntervalMs,
  shouldApplyListenTogetherRoomStateToPlayer,
  shouldDeferListenTogetherIncomingStateForLocalTrackFinish,
  shouldIgnoreListenTogetherIncomingState,
  shouldRepairListenTogetherListenerState
} from '../../../main/ets/listentogether/session/ListenTogetherIncomingStatePolicy';
import {
  ListenTogetherPendingMemberControlRequest,
  ListenTogetherPendingTrackFinishedLegacyFallback
} from '../../../main/ets/listentogether/session/ListenTogetherPendingEvents';
import { latestListenTogetherAcceptedRoomVersion } from '../../../main/ets/listentogether/session/ListenTogetherRoomVersion';
import {
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  createListenTogetherCause,
  createListenTogetherEvent
} from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import { createListenTogetherTrack } from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import { ListenTogetherChannels } from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';

const WEBSOCKET_SILENCE_TIMEOUT_MS: number = 45_000;
const REPAIR_MIN_INTERVAL_MS: number = 30_000;
const CONTROLLER_COOLDOWN_MS: number = 1_200;
/** Upstream's fixture room id, kept so the version cases read the same. */
const ROOM_ID: string = 'ABC234';

function roomState(version: number = 1): ListenTogetherRoomState {
  return createListenTogetherRoomState(ROOM_ID, version);
}

/** A room playing `netease:<audioId>` out of a one-track queue. */
function playingRoomOn(audioId: string): ListenTogetherRoomState {
  const state = roomState(1);
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

/** Nothing is in either recent-event ring. */
const noRecentEvent: (eventId: string) => boolean = (eventId: string) => false;

export default function listenTogetherSessionPoliciesTest() {
  describe('ListenTogetherSessionPolicies', () => {
    it('trims the oldest event ids out of the recent-event ring', 0, () => {
      const tracker = new ListenTogetherRecentEventTracker(2);

      tracker.markOutbound('first');
      tracker.markOutbound('second');
      tracker.markOutbound('third');

      expect(tracker.hasOutbound('first')).assertFalse();
      expect(tracker.hasOutbound('second')).assertTrue();
      expect(tracker.hasOutbound('third')).assertTrue();
      // The two directions are separate rings, not one shared budget.
      expect(tracker.hasInbound('third')).assertFalse();
    });

    it('ignores blank ids and clears both ring directions', 0, () => {
      const tracker = new ListenTogetherRecentEventTracker(2);

      tracker.markOutbound('');
      tracker.markInbound('inbound');
      tracker.markOutbound('outbound');
      tracker.clear();

      expect(tracker.hasOutbound('')).assertFalse();
      expect(tracker.hasOutbound('outbound')).assertFalse();
      expect(tracker.hasInbound('inbound')).assertFalse();
    });

    it('trims an event id before storing it', 0, () => {
      const tracker = new ListenTogetherRecentEventTracker();
      tracker.markOutbound('  padded  ');
      // Divergence over upstream, on purpose: the ring trims on mark, and the
      // ignore policy trims on lookup, so a padded id still matches its echo.
      expect(tracker.hasOutbound('padded')).assertTrue();
      expect(LISTEN_TOGETHER_DEFAULT_RECENT_EVENT_LIMIT).assertEqual(128);
    });

    it('drops a controller echo caused by the controller itself', 0, () => {
      const state = roomState(4);
      state.controllerUserUuid = 'controller-id';

      expect(shouldDropListenTogetherControllerLocalEcho(
        state,
        createListenTogetherCause('controller-id', 'PLAY', 'event-1'),
        3,
        'controller-id',
        1_000,
        1_800,
        CONTROLLER_COOLDOWN_MS
      )).assertTrue();
    });

    it('keeps a track-finished echo and a stale distant echo', 0, () => {
      const state = roomState(4);
      state.controllerUserUuid = 'controller-id';

      // The server picks the next track, so this echo carries new information.
      expect(shouldDropListenTogetherControllerLocalEcho(
        state,
        createListenTogetherCause('controller-id', 'TRACK_FINISHED'),
        3,
        'controller-id',
        1_000,
        1_800,
        CONTROLLER_COOLDOWN_MS
      )).assertFalse();
      // Past the cooldown this is no longer an echo of a local action.
      expect(shouldDropListenTogetherControllerLocalEcho(
        state,
        createListenTogetherCause('controller-id', 'PLAY'),
        3,
        'controller-id',
        1_000,
        3_000,
        CONTROLLER_COOLDOWN_MS
      )).assertFalse();
      // Another member's command must always be applied.
      expect(shouldDropListenTogetherControllerLocalEcho(
        state,
        createListenTogetherCause('member-id', 'PLAY'),
        3,
        'controller-id',
        1_000,
        1_800,
        CONTROLLER_COOLDOWN_MS
      )).assertFalse();
      // A listener never treats anything as its own controller echo.
      expect(shouldDropListenTogetherControllerLocalEcho(
        state,
        createListenTogetherCause('member-id', 'PLAY'),
        3,
        'member-id',
        1_000,
        1_800,
        CONTROLLER_COOLDOWN_MS
      )).assertFalse();
      // More than one version ahead is real news, not an echo.
      const jumped = roomState(6);
      jumped.controllerUserUuid = 'controller-id';
      expect(shouldDropListenTogetherControllerLocalEcho(
        jumped,
        createListenTogetherCause('controller-id', 'PLAY'),
        3,
        'controller-id',
        1_000,
        1_800,
        CONTROLLER_COOLDOWN_MS
      )).assertFalse();
    });

    it('resolves the controller-offline countdown', 0, () => {
      const state = roomState(1);
      state.roomStatus = ListenTogetherRoomStatuses.CONTROLLER_OFFLINE;
      state.controllerOfflineSince = 10_000;

      expect(resolveListenTogetherRoomNotice(state, null, 12_000, 9 * 60 * 1_000))
        .assertEqual('controller_offline:9');
      // No offline timestamp: the bare code, with the fallback still winning.
      const unknownSince = roomState(1);
      unknownSince.roomStatus = ListenTogetherRoomStatuses.CONTROLLER_OFFLINE;
      expect(resolveListenTogetherRoomNotice(unknownSince, null, 12_000))
        .assertEqual(LISTEN_TOGETHER_NOTICE_CONTROLLER_OFFLINE);
      expect(resolveListenTogetherRoomNotice(unknownSince, 'fallback', 12_000))
        .assertEqual('fallback');
      expect(LISTEN_TOGETHER_DEFAULT_CONTROLLER_GRACE_PERIOD_MS).assertEqual(10 * 60 * 1_000);
    });

    it('keeps the fallback and the closed-reason precedence', 0, () => {
      const active = roomState(1);
      active.roomStatus = ListenTogetherRoomStatuses.ACTIVE;
      expect(resolveListenTogetherRoomNotice(active, 'fallback')).assertEqual('fallback');

      const closed = roomState(1);
      closed.roomStatus = ListenTogetherRoomStatuses.CLOSED;
      closed.closedReason = 'room expired';
      expect(resolveListenTogetherRoomNotice(closed)).assertEqual('room expired');
      // A caller-supplied message outranks the server's reason.
      expect(resolveListenTogetherRoomNotice(closed, 'fallback')).assertEqual('fallback');

      const closedWithoutReason = roomState(1);
      closedWithoutReason.roomStatus = ListenTogetherRoomStatuses.CLOSED;
      expect(resolveListenTogetherRoomNotice(closedWithoutReason))
        .assertEqual(LISTEN_TOGETHER_NOTICE_ROOM_CLOSED);

      expect(resolveListenTogetherRoomNotice(active)).assertNull();
      expect(resolveListenTogetherRoomNotice(null, 'fallback')).assertEqual('fallback');
      expect(resolveListenTogetherRoomNotice(null)).assertNull();
    });

    it('keeps the member-departure broadcast', 0, () => {
      const active = roomState(1);
      active.roomStatus = ListenTogetherRoomStatuses.ACTIVE;
      expect(resolveListenTogetherRoomNotice(active, 'member_left:Listener'))
        .assertEqual('member_left:Listener');
    });

    it('requires a current matching room and a non-stale version to apply', 0, () => {
      const current = roomState(5);

      expect(shouldApplyListenTogetherRoomStateToPlayer(roomState(5), current)).assertTrue();
      expect(shouldApplyListenTogetherRoomStateToPlayer(roomState(6), current)).assertTrue();
      expect(shouldApplyListenTogetherRoomStateToPlayer(roomState(4), current)).assertFalse();

      const otherRoom = createListenTogetherRoomState('OTHER1', 6);
      expect(shouldApplyListenTogetherRoomStateToPlayer(otherRoom, current)).assertFalse();
      expect(shouldApplyListenTogetherRoomStateToPlayer(current, null)).assertFalse();
    });

    it('repairs listener state on websocket silence or a version gap', 0, () => {
      // `pendingVersionGap = -1` is upstream's "no gap" sentinel; anything >= 0
      // is a real gap, including zero.
      expect(shouldRepairListenTogetherListenerState(
        100_000, 90_000, 0, -1, WEBSOCKET_SILENCE_TIMEOUT_MS, REPAIR_MIN_INTERVAL_MS
      )).assertFalse();
      expect(shouldRepairListenTogetherListenerState(
        100_000, 50_000, 0, -1, WEBSOCKET_SILENCE_TIMEOUT_MS, REPAIR_MIN_INTERVAL_MS
      )).assertTrue();
      expect(shouldRepairListenTogetherListenerState(
        100_000, 99_000, 0, 8, WEBSOCKET_SILENCE_TIMEOUT_MS, REPAIR_MIN_INTERVAL_MS
      )).assertTrue();
      // The minimum-interval gate comes first, so a persistent gap cannot storm.
      expect(shouldRepairListenTogetherListenerState(
        100_000, 50_000, 90_000, 8, WEBSOCKET_SILENCE_TIMEOUT_MS, REPAIR_MIN_INTERVAL_MS
      )).assertFalse();
      // Never having heard from the socket is itself a reason to repair.
      expect(shouldRepairListenTogetherListenerState(
        100_000, 0, 0, -1, WEBSOCKET_SILENCE_TIMEOUT_MS, REPAIR_MIN_INTERVAL_MS
      )).assertTrue();
    });

    it('keeps both heartbeat cadences below the worker controller timeout', 0, () => {
      expect(resolveListenTogetherHeartbeatIntervalMs(true))
        .assertEqual(LISTEN_TOGETHER_PLAYING_HEARTBEAT_INTERVAL_MS);
      expect(resolveListenTogetherHeartbeatIntervalMs(false))
        .assertEqual(LISTEN_TOGETHER_PAUSED_HEARTBEAT_INTERVAL_MS);
      expect(resolveListenTogetherHeartbeatIntervalMs(true, 1_000, 2_000)).assertEqual(1_000);
      expect(resolveListenTogetherHeartbeatIntervalMs(false, 1_000, 2_000)).assertEqual(2_000);

      expect(LISTEN_TOGETHER_PLAYING_HEARTBEAT_INTERVAL_MS < LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS)
        .assertTrue();
      expect(LISTEN_TOGETHER_PAUSED_HEARTBEAT_INTERVAL_MS < LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS)
        .assertTrue();
      // Upstream's third assertion also bounds
      // ListenTogetherSessionManager.LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS
      // against the same timeout. That constant belongs to the session runtime,
      // which is M7.3b; the assertion is deferred to this suite's session-manager
      // tests rather than being asserted against a constant that does not exist yet.
    });

    it('ignores an incoming state that is this client own event coming back', 0, () => {
      const mine: (eventId: string) => boolean = (eventId: string) => eventId === 'mine';

      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('other-user', 'PLAY', 'mine'), 'me', mine, noRecentEvent
      )).assertTrue();
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('other-user', 'PLAY', 'mine'), 'me', noRecentEvent, mine
      )).assertTrue();
      // Padding must not defeat the ring lookup.
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('other-user', 'PLAY', '  mine  '), 'me', mine, noRecentEvent
      )).assertTrue();
      // Same author, different id: still our own action seen through the server.
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('me', 'PLAY', 'unseen'), 'me', noRecentEvent, noRecentEvent
      )).assertTrue();
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('other-user', 'PLAY', 'unseen'), 'me', noRecentEvent, noRecentEvent
      )).assertFalse();
    });

    it('never ignores TRACK_FINISHED, a forwarded request or a blank id', 0, () => {
      const everything: (eventId: string) => boolean = (eventId: string) => true;

      // The server decides what plays next, so this state is not ours to skip.
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('me', 'TRACK_FINISHED', 'mine'), 'me', everything, everything
      )).assertFalse();
      // A forwarded REQUEST_* is the listener's ask arriving at the controller —
      // exactly the case that must be acted on.
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('me', 'REQUEST_SEEK', 'mine'), 'me', everything, everything
      )).assertFalse();
      // Without an id there is nothing to match, and the author check is skipped.
      expect(shouldIgnoreListenTogetherIncomingState(
        createListenTogetherCause('me', 'PLAY', '   '), 'me', everything, everything
      )).assertFalse();
      expect(shouldIgnoreListenTogetherIncomingState(
        null, 'me', everything, everything
      )).assertFalse();
    });

    it('defers a passive update while a local track finish is in flight', 0, () => {
      const state = playingRoomOn('1001');

      expect(shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
        state, createListenTogetherCause('other', 'HEARTBEAT'), 'netease:1001'
      )).assertTrue();
      // Nothing pending locally.
      expect(shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
        state, createListenTogetherCause('other', 'HEARTBEAT'), null
      )).assertFalse();
      // The room has already moved on, so the update is about the new track.
      expect(shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
        state, createListenTogetherCause('other', 'HEARTBEAT'), 'netease:2002'
      )).assertFalse();
      // An active cause is an explicit instruction and is never deferred.
      expect(shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
        state, createListenTogetherCause('other', 'SEEK'), 'netease:1001'
      )).assertFalse();
      expect(shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
        state, null, 'netease:1001'
      )).assertFalse();
      // A paused room is not racing the finish.
      const paused = playingRoomOn('1001');
      paused.playback.state = 'paused';
      expect(shouldDeferListenTogetherIncomingStateForLocalTrackFinish(
        paused, createListenTogetherCause('other', 'HEARTBEAT'), 'netease:1001'
      )).assertFalse();
    });

    it('keeps the accepted room version as a high-water mark', 0, () => {
      expect(latestListenTogetherAcceptedRoomVersion(7, roomState(5))).assertEqual(7);
      expect(latestListenTogetherAcceptedRoomVersion(7, roomState(9))).assertEqual(9);
      // A synthetic local state may sit below a version already accepted.
      expect(latestListenTogetherAcceptedRoomVersion(7, null)).assertEqual(7);
      // Before anything has been applied, an unknown state is -1, not 0.
      expect(latestListenTogetherAcceptedRoomVersion(-1, null)).assertEqual(-1);
      expect(latestListenTogetherAcceptedRoomVersion(-1, roomState(0))).assertEqual(0);
    });

    it('preserves the event identity and payload across a retry', 0, () => {
      const event = createListenTogetherEvent('REQUEST_SEEK');
      event.eventId = 'stable-event-id';
      event.clientTimeMs = 123;
      event.clientInstanceId = 'client';
      event.clientSequence = 7;
      event.positionMs = 8_000;
      const pending = new ListenTogetherPendingMemberControlRequest(event, 1_000, 1_000, 1);

      const retried = pending.retriedAt(4_000);

      expect(retried.event === event).assertTrue();
      expect(retried.event.eventId).assertEqual('stable-event-id');
      expect(retried.event.positionMs).assertEqual(8_000);
      expect(retried.lastSentAtElapsedMs).assertEqual(4_000);
      expect(retried.attempts).assertEqual(2);
      // The deadline is measured from the original request, not the latest send.
      expect(retried.createdAtElapsedMs).assertEqual(1_000);
      // Immutable: the original is untouched, so a failed resend can be re-read.
      expect(pending.attempts).assertEqual(1);
      expect(pending.lastSentAtElapsedMs).assertEqual(1_000);
    });

    it('marks the track-finished legacy fallback exactly once', 0, () => {
      const event = createListenTogetherEvent('TRACK_FINISHED');
      event.eventId = 'finished-1';
      const pending = new ListenTogetherPendingTrackFinishedLegacyFallback(event, 2_000);

      expect(pending.attempted).assertFalse();
      const attempted = pending.markAttempted();
      expect(attempted.attempted).assertTrue();
      expect(attempted.event === event).assertTrue();
      expect(attempted.createdAtElapsedMs).assertEqual(2_000);
      // The original stays unattempted, so the rewrite decision is the caller's.
      expect(pending.attempted).assertFalse();
    });
  });
}
