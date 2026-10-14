import { describe, it, expect } from '@ohos/hypium';
import {
  ListenTogetherControlOutbox,
  listenTogetherControlOutboxKey
} from '../../../main/ets/listentogether/session/ListenTogetherControlOutbox';
import {
  LISTEN_TOGETHER_DEFAULT_CONNECTING_TIMEOUT_MS,
  ListenTogetherForegroundRecoveryAction,
  isCurrentListenTogetherCoalescedControlJob,
  resolveListenTogetherForegroundRecoveryAction,
  shouldReconnectListenTogetherForegroundSocket
} from '../../../main/ets/listentogether/session/ListenTogetherForegroundRecoveryPolicy';
import {
  ListenTogetherSoftSyncRecheckAction,
  resolveListenTogetherSoftSyncRecheckAction
} from '../../../main/ets/listentogether/playback/ListenTogetherSoftSyncRecoveryPolicy';
import {
  ListenTogetherRestoredPlaybackAction,
  resolveListenTogetherRestoredPlaybackAction
} from '../../../main/ets/listentogether/playback/ListenTogetherRestoredPlaybackPolicy';
import {
  ListenTogetherAuthoritativeStreamAvailability
} from '../../../main/ets/listentogether/playback/ListenTogetherAuthoritativeStreamAvailability';
import {
  shouldApplyListenTogetherClosedRoomPause
} from '../../../main/ets/listentogether/session/ListenTogetherRoomClosurePolicy';
import {
  LISTEN_TOGETHER_NOTICE_CONTROLLER_RECONNECTED,
  isNormalListenTogetherRoomClosureReason,
  normalizeListenTogetherRoomClosureReason,
  resolveListenTogetherRoomNotice
} from '../../../main/ets/listentogether/session/ListenTogetherRoomNotice';
import {
  shouldAutoPauseListenTogetherForMemberChange
} from '../../../main/ets/listentogether/session/ListenTogetherJoinPolicy';
import {
  shouldMuteListenTogetherListenerForAudioRouteLoss
} from '../../../main/ets/listentogether/playback/ListenTogetherListenerSafetyPausePolicy';
import {
  ListenTogetherConnectionState
} from '../../../main/ets/listentogether/protocol/ListenTogetherSessionModels';
import {
  ListenTogetherEvent,
  createListenTogetherEvent
} from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import {
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';

function eventOf(type: string, eventId: string): ListenTogetherEvent {
  const event = createListenTogetherEvent(type);
  event.eventId = eventId;
  return event;
}

function closedRoom(status: string, closedReason: string | null): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ROOM1', 3);
  state.roomStatus = status;
  state.closedReason = closedReason;
  return state;
}

export default function listenTogetherRobustnessTest(): void {
  describe('ListenTogetherControlOutbox', () => {
    it('keysEventsByRoomAndIntent', 0, () => {
      expect(listenTogetherControlOutboxKey('R1', eventOf('SET_QUEUE', 'e1'))).assertEqual('R1:queue');
      expect(listenTogetherControlOutboxKey('R1', eventOf('REQUEST_SET_TRACK', 'e2'))).assertEqual('R1:track');
      expect(listenTogetherControlOutboxKey('R1', eventOf('PLAY', 'e3'))).assertEqual('R1:transport');
      expect(listenTogetherControlOutboxKey('R1', eventOf('SEEK', 'e4'))).assertEqual('R1:seek');
      expect(listenTogetherControlOutboxKey('R1', eventOf('PLAYBACK_MODE', 'e5'))).assertEqual('R1:playback_mode');
      expect(listenTogetherControlOutboxKey('R1', eventOf('TRACK_FINISHED', 'e6'))).assertEqual('R1:track_finished');
      expect(listenTogetherControlOutboxKey('R1', eventOf('HEARTBEAT', 'e7'))).assertNull();
    });

    it('replacesTheQueuedEventForTheSameIntent', 0, () => {
      const outbox = new ListenTogetherControlOutbox();
      outbox.offer(eventOf('SET_QUEUE', 'first'), 'R1');
      outbox.offer(eventOf('SET_QUEUE', 'second'), 'R1');
      const pending = outbox.pendingForRoom('R1');
      expect(pending.length).assertEqual(1);
      expect(pending[0].event.eventId).assertEqual('second');
    });

    it('ignoresOffersWithoutARoom', 0, () => {
      const outbox = new ListenTogetherControlOutbox();
      outbox.offer(eventOf('SET_QUEUE', 'e1'), null);
      outbox.offer(eventOf('SET_QUEUE', 'e2'), '  ');
      expect(outbox.pendingForRoom('R1').length).assertEqual(0);
    });

    it('evictsTheOldestEntryBeyondTheLruCap', 0, () => {
      const outbox = new ListenTogetherControlOutbox(2);
      outbox.offer(eventOf('SET_QUEUE', 'e1'), 'R1');
      outbox.offer(eventOf('PLAY', 'e2'), 'R1');
      outbox.offer(eventOf('SEEK', 'e3'), 'R1');
      expect(outbox.pendingByEventId('e1')).assertNull();
      expect(outbox.pendingByEventId('e2') === null).assertFalse();
      expect(outbox.pendingByEventId('e3') === null).assertFalse();
    });

    it('acknowledgesByEventId', 0, () => {
      const outbox = new ListenTogetherControlOutbox();
      outbox.offer(eventOf('SET_QUEUE', 'e1'), 'R1');
      outbox.acknowledge('e1');
      expect(outbox.pendingForRoom('R1').length).assertEqual(0);
      // Unknown or blank ids change nothing.
      outbox.offer(eventOf('PLAY', 'e2'), 'R1');
      outbox.acknowledge(null);
      outbox.acknowledge('nope');
      expect(outbox.pendingForRoom('R1').length).assertEqual(1);
    });

    it('resolvesASingleFallbackCandidateOnlyWhenUnambiguous', 0, () => {
      const outbox = new ListenTogetherControlOutbox();
      expect(outbox.singlePendingWithLegacyFallback()).assertNull();
      outbox.offer(eventOf('SET_QUEUE', 'e1'), 'R1', eventOf('SET_QUEUE', 'e1-legacy'));
      const single = outbox.singlePendingWithLegacyFallback();
      expect(single === null ? '' : single.event.eventId).assertEqual('e1');
      outbox.offer(eventOf('PLAY', 'e2'), 'R1', eventOf('PLAY', 'e2-legacy'));
      expect(outbox.singlePendingWithLegacyFallback()).assertNull();
    });

    it('replacesAnEventKeepingItsRoom', 0, () => {
      const outbox = new ListenTogetherControlOutbox();
      outbox.offer(eventOf('SET_QUEUE', 'e1'), 'R1');
      const replaced = outbox.replace('e1', eventOf('SET_QUEUE', 'e1-v2'));
      expect(replaced === null ? '' : replaced.event.eventId).assertEqual('e1');
      const pending = outbox.pendingForRoom('R1');
      expect(pending.length).assertEqual(1);
      expect(pending[0].event.eventId).assertEqual('e1-v2');
      expect(pending[0].roomId).assertEqual('R1');
      expect(outbox.replace('missing', eventOf('PLAY', 'x'))).assertNull();
    });
  });

  describe('ListenTogetherForegroundRecoveryPolicy', () => {
    it('doesNothingWithoutARoomSocketOrReconnect', 0, () => {
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.DISCONNECTED, null, 'wss://x', true, 0, 0))
        .assertEqual(ListenTogetherForegroundRecoveryAction.NONE);
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.DISCONNECTED, 'R1', '  ', true, 0, 0))
        .assertEqual(ListenTogetherForegroundRecoveryAction.NONE);
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.DISCONNECTED, 'R1', 'wss://x', false, 0, 0))
        .assertEqual(ListenTogetherForegroundRecoveryAction.NONE);
    });

    it('reconnectsWhenDisconnectedAndRefreshesWhenConnected', 0, () => {
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.DISCONNECTED, 'R1', 'wss://x', true, 0, 0))
        .assertEqual(ListenTogetherForegroundRecoveryAction.CONNECT);
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.CONNECTED, 'R1', 'wss://x', true, 0, 0))
        .assertEqual(ListenTogetherForegroundRecoveryAction.REFRESH_ROOM_STATE);
    });

    it('forcesAReconnectWhenConnectingIsStuck', 0, () => {
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.CONNECTING, 'R1', 'wss://x', true,
        1000, 1000 + LISTEN_TOGETHER_DEFAULT_CONNECTING_TIMEOUT_MS - 1))
        .assertEqual(ListenTogetherForegroundRecoveryAction.NONE);
      expect(resolveListenTogetherForegroundRecoveryAction(
        ListenTogetherConnectionState.CONNECTING, 'R1', 'wss://x', true,
        1000, 1000 + LISTEN_TOGETHER_DEFAULT_CONNECTING_TIMEOUT_MS))
        .assertEqual(ListenTogetherForegroundRecoveryAction.CONNECT);
    });

    it('reconnectsTheProbeOnlyWhenNothingArrived', 0, () => {
      expect(shouldReconnectListenTogetherForegroundSocket(
        true, ListenTogetherConnectionState.CONNECTED, 'R1', 'R1', 1000, 2000)).assertTrue();
      // A message after the probe started proves the pipe is alive.
      expect(shouldReconnectListenTogetherForegroundSocket(
        true, ListenTogetherConnectionState.CONNECTED, 'R1', 'R1', 2500, 2000)).assertFalse();
      expect(shouldReconnectListenTogetherForegroundSocket(
        true, ListenTogetherConnectionState.CONNECTED, 'R1', 'OTHER', 1000, 2000)).assertFalse();
      expect(shouldReconnectListenTogetherForegroundSocket(
        false, ListenTogetherConnectionState.CONNECTED, 'R1', 'R1', 1000, 2000)).assertFalse();
    });

    it('identifiesTheCurrentCoalescedJobByGeneration', 0, () => {
      expect(isCurrentListenTogetherCoalescedControlJob(3, 3)).assertTrue();
      expect(isCurrentListenTogetherCoalescedControlJob(4, 3)).assertFalse();
    });
  });

  describe('ListenTogetherSoftSyncRecoveryPolicy', () => {
    it('ignoresAnUnmodifiedRate', 0, () => {
      expect(resolveListenTogetherSoftSyncRecheckAction(
        1.0, true, false, true, true, true, 3000, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.NONE);
    });

    it('resetsTheRateWhenAnyPreconditionDropped', 0, () => {
      expect(resolveListenTogetherSoftSyncRecheckAction(
        0.98, false, false, true, true, true, 3000, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.RESET_RATE);
      expect(resolveListenTogetherSoftSyncRecheckAction(
        0.98, true, true, false, true, true, 3000, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.RESET_RATE);
      expect(resolveListenTogetherSoftSyncRecheckAction(
        0.98, true, false, true, true, true, 3000, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.RESET_RATE);
    });

    it('keepsResetsOrForcesByDriftMagnitude', 0, () => {
      expect(resolveListenTogetherSoftSyncRecheckAction(
        0.98, true, false, true, true, true, 3000, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.KEEP_RATE);
      expect(resolveListenTogetherSoftSyncRecheckAction(
        0.98, true, false, true, true, true, 500, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.RESET_RATE);
      expect(resolveListenTogetherSoftSyncRecheckAction(
        0.98, true, false, true, true, true, 25000, 800, 20000))
        .assertEqual(ListenTogetherSoftSyncRecheckAction.FORCE_POSITION_SYNC);
    });
  });

  describe('ListenTogetherRestoredPlaybackPolicy', () => {
    it('skipsWithoutARestoreRequest', 0, () => {
      expect(resolveListenTogetherRestoredPlaybackAction(false, true, false))
        .assertEqual(ListenTogetherRestoredPlaybackAction.SKIP);
    });

    it('resumesLocallyOutsideAListenerRoom', 0, () => {
      expect(resolveListenTogetherRestoredPlaybackAction(true, false, false))
        .assertEqual(ListenTogetherRestoredPlaybackAction.RESUME_LOCAL_PLAYBACK);
      expect(resolveListenTogetherRestoredPlaybackAction(true, true, true))
        .assertEqual(ListenTogetherRestoredPlaybackAction.RESUME_LOCAL_PLAYBACK);
    });

    it('waitsForTheRoomWhenAListenerRestores', 0, () => {
      expect(resolveListenTogetherRestoredPlaybackAction(true, true, false))
        .assertEqual(ListenTogetherRestoredPlaybackAction.WAIT_FOR_AUTHORITATIVE_ROOM_STATE);
    });
  });

  describe('ListenTogetherAuthoritativeStreamAvailability', () => {
    it('confirmsOnlyOnTwoDistinctSignals', 0, () => {
      const ledger = new ListenTogetherAuthoritativeStreamAvailability();
      expect(ledger.markUnavailable('R1', 'kA', 'sig-1')).assertFalse();
      expect(ledger.isAwaitingConfirmation('R1', 'kA')).assertTrue();
      expect(ledger.isUnavailable('R1', 'kA')).assertFalse();
      // The same signal relayed twice is still one signal.
      expect(ledger.markUnavailable('R1', 'kA', 'sig-1')).assertFalse();
      expect(ledger.markUnavailable('R1', 'kA', 'sig-2')).assertTrue();
      expect(ledger.isUnavailable('R1', 'kA')).assertTrue();
      expect(ledger.isAwaitingConfirmation('R1', 'kA')).assertFalse();
    });

    it('resetsOnTargetChangeAndClearsOnStreamOrBlankInput', 0, () => {
      const ledger = new ListenTogetherAuthoritativeStreamAvailability();
      ledger.markUnavailable('R1', 'kA', 'sig-1');
      ledger.markUnavailable('R1', 'kA', 'sig-2');
      // A different target resets the count.
      expect(ledger.markUnavailable('R1', 'kB', 'sig-3')).assertFalse();
      expect(ledger.isUnavailable('R1', 'kA')).assertFalse();
      // Reconciling an authoritative stream clears the record outright.
      ledger.markUnavailable('R1', 'kA', 'sig-4');
      ledger.reconcile('R1', 'kA', true);
      expect(ledger.isAwaitingConfirmation('R1', 'kA')).assertFalse();
      // Blank input clears as well.
      ledger.markUnavailable('R1', 'kA', 'sig-5');
      expect(ledger.markUnavailable(null, 'kA', 'sig-6')).assertFalse();
      expect(ledger.isAwaitingConfirmation('R1', 'kA')).assertFalse();
    });
  });

  describe('ListenTogetherRoomClosurePolicy', () => {
    it('mirrorsTheFinalPausedState', 0, () => {
      const paused = createListenTogetherRoomState('R1', 2);
      paused.playback.state = 'paused';
      expect(shouldApplyListenTogetherClosedRoomPause(paused)).assertTrue();
      const playing = createListenTogetherRoomState('R1', 2);
      playing.playback.state = 'playing';
      expect(shouldApplyListenTogetherClosedRoomPause(playing)).assertFalse();
    });
  });

  describe('ListenTogetherRoomNoticeNormalization', () => {
    it('canonicalizesClosureReasons', 0, () => {
      expect(normalizeListenTogetherRoomClosureReason(' CONTROLLER_LEFT ')).assertEqual('controller_left');
      expect(normalizeListenTogetherRoomClosureReason('Controller_Timeout')).assertEqual('controller_timeout');
      expect(normalizeListenTogetherRoomClosureReason('room_closed')).assertEqual('room_closed');
      expect(normalizeListenTogetherRoomClosureReason('custom reason')).assertEqual('custom reason');
      expect(normalizeListenTogetherRoomClosureReason('   ')).assertNull();
      expect(normalizeListenTogetherRoomClosureReason(null)).assertNull();
      expect(isNormalListenTogetherRoomClosureReason('controller_left')).assertTrue();
      expect(isNormalListenTogetherRoomClosureReason('controller_timeout')).assertFalse();
    });

    it('prefersTheServerCloseReasonOverAnyFallback', 0, () => {
      const state = closedRoom(ListenTogetherRoomStatuses.CLOSED, 'controller_timeout');
      expect(resolveListenTogetherRoomNotice(state, 'fallback message'))
        .assertEqual('controller_timeout');
      const withoutReason = closedRoom(ListenTogetherRoomStatuses.CLOSED, null);
      expect(resolveListenTogetherRoomNotice(withoutReason, 'fallback message'))
        .assertEqual('fallback message');
      expect(resolveListenTogetherRoomNotice(withoutReason, null)).assertEqual('room_closed');
    });

    it('gatesTheControllerReconnectedNotice', 0, () => {
      const state = createListenTogetherRoomState('R1', 3);
      expect(resolveListenTogetherRoomNotice(
        state, LISTEN_TOGETHER_NOTICE_CONTROLLER_RECONNECTED, 0, 600000, false)).assertNull();
      expect(resolveListenTogetherRoomNotice(
        state, LISTEN_TOGETHER_NOTICE_CONTROLLER_RECONNECTED, 0, 600000, true))
        .assertEqual(LISTEN_TOGETHER_NOTICE_CONTROLLER_RECONNECTED);
    });
  });

  describe('ListenTogetherMemberChangeAndRouteMute', () => {
    it('autoPausesOnlyForRealMemberChanges', 0, () => {
      expect(shouldAutoPauseListenTogetherForMemberChange(true, 'MEMBER_JOINED')).assertTrue();
      expect(shouldAutoPauseListenTogetherForMemberChange(true, 'MEMBER_LEFT')).assertTrue();
      expect(shouldAutoPauseListenTogetherForMemberChange(true, 'OTHER')).assertFalse();
      expect(shouldAutoPauseListenTogetherForMemberChange(true, null)).assertFalse();
      expect(shouldAutoPauseListenTogetherForMemberChange(false, 'MEMBER_JOINED')).assertFalse();
    });

    it('mutesAnyListenerOnRouteLossRegardlessOfTransportState', 0, () => {
      // #359 widened the route-loss mute to every listener (the playing flag
      // no longer gates it) — the signature dropped the isPlaying parameter.
      expect(shouldMuteListenTogetherListenerForAudioRouteLoss(true, false)).assertTrue();
      expect(shouldMuteListenTogetherListenerForAudioRouteLoss(false, false)).assertFalse();
      expect(shouldMuteListenTogetherListenerForAudioRouteLoss(true, true)).assertFalse();
    });
  });
}
