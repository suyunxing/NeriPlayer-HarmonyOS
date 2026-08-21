/**
 * Tests for the five M7.3b-1 strategy files lifted out of
 * ListenTogetherSessionManager.kt's private state (commit "M7.3b 起步"):
 * the server clock-offset filter, the listener membership recovery gates, the
 * pending member-control retry decision and the TRACK_FINISHED legacy fallback
 * gate, plus the runtime-constant invariants upstream asserts in
 * ListenTogetherSessionPoliciesTest (`socket keep-alive < worker timeout`) that
 * had to wait for the constants to exist.
 *
 * Upstream has no direct tests for any of these — they were extracted from the
 * session manager precisely because a private smoothing filter is unverifiable.
 * The expectations below are therefore derived from the Kotlin semantics the
 * files document, with every truncation case pinned explicitly.
 */
import { describe, it, expect } from '@ohos/hypium';
import { ListenTogetherServerClockOffset } from '../../../main/ets/listentogether/session/ListenTogetherServerClockOffset';
import {
  canTriggerListenTogetherMembershipRecovery,
  isFatalListenTogetherMembershipError,
  shouldRecoverMissingListenTogetherMembership
} from '../../../main/ets/listentogether/session/ListenTogetherMembershipRecoveryPolicy';
import {
  LISTEN_TOGETHER_PENDING_CONTROL_EXPIRED,
  LISTEN_TOGETHER_PENDING_CONTROL_IDLE,
  LISTEN_TOGETHER_PENDING_CONTROL_MAX_ATTEMPTS,
  LISTEN_TOGETHER_PENDING_CONTROL_RETRY,
  LISTEN_TOGETHER_PENDING_CONTROL_SATISFIED,
  LISTEN_TOGETHER_PENDING_CONTROL_TOO_SOON,
  buildListenTogetherPendingMemberControlRequest,
  resolveListenTogetherPendingMemberControlRetry
} from '../../../main/ets/listentogether/session/ListenTogetherPendingMemberControlRetry';
import {
  LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_ALREADY_ATTEMPTED,
  LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_EXPIRED,
  LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_IDLE,
  LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_NOT_REJECTED,
  LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_SEND,
  resolveListenTogetherTrackFinishedFallback
} from '../../../main/ets/listentogether/session/ListenTogetherTrackFinishedFallbackPolicy';
import {
  LISTEN_TOGETHER_LISTENER_WEB_SOCKET_SILENCE_TIMEOUT_MS,
  LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_RETRY_INTERVAL_MS,
  LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_TTL_MS,
  LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS,
  LISTEN_TOGETHER_SYNC_WATCHDOG_INTERVAL_MS
} from '../../../main/ets/listentogether/session/ListenTogetherSessionRuntimeConstants';
import {
  ListenTogetherPendingMemberControlRequest,
  ListenTogetherPendingTrackFinishedLegacyFallback
} from '../../../main/ets/listentogether/session/ListenTogetherPendingEvents';
import {
  ListenTogetherMember,
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import { createListenTogetherEvent } from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import { LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS } from '../../../main/ets/listentogether/session/ListenTogetherIncomingStatePolicy';
import { ListenTogetherSessionOperationGate } from '../../../main/ets/listentogether/session/ListenTogetherSessionOperationGate';

const TTL_MS: number = 18_000;
const RETRY_INTERVAL_MS: number = 3_000;
const FALLBACK_TTL_MS: number = 15_000;

function pendingFallback(): ListenTogetherPendingTrackFinishedLegacyFallback {
  return new ListenTogetherPendingTrackFinishedLegacyFallback(
    createListenTogetherEvent('TRACK_FINISHED'), 0, false);
}

function member(uuid: string, legacyUserId: string | null): ListenTogetherMember {
  const member = new ListenTogetherMember();
  member.userUuid = uuid;
  member.nickname = uuid;
  member.userId = legacyUserId;
  member.role = 'listener';
  return member;
}

export default function listenTogetherSessionRuntimeTest() {
  describe('ListenTogetherServerClockOffset', () => {
    it('accepts the first pong sample verbatim', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(1000, 50_000);

      const outcome = clock.acceptPong(52_000, null, 1300, 50_300);

      expect(outcome).assertEqual('accepted');
      // rtt=300, reference = 50000 + 150, offset = 52000 - 50150.
      expect(clock.estimatedOffsetMs()).assertEqual(1850);
    });

    it('smooths later samples 70/30 with truncation', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(1000, 50_000);
      clock.acceptPong(52_000, null, 1300, 50_300);

      clock.markPingSent(2000, 51_000);
      clock.acceptPong(52_500, null, 2400, 51_400);

      // new sample = 52500 - (51000 + 200) = 1300; (1850*7 + 1300*3)/10 = 1685.
      expect(clock.estimatedOffsetMs()).assertEqual(1685);
    });

    it('truncates negative offsets toward zero, not toward -infinity', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(1000, 50_000);
      clock.acceptPong(49_999, null, 1000, 50_300);
      expect(clock.estimatedOffsetMs()).assertEqual(-1);

      clock.markPingSent(2000, 60_000);
      clock.acceptPong(59_998, null, 2000, 60_300);
      // (-1*7 + -2*3)/10 = -1.3; Long division and Math.trunc both give -1,
      // while a floor would wrongly give -2.
      expect(clock.estimatedOffsetMs()).assertEqual(-1);
    });

    it('an echoed send timestamp survives overwritten bookkeeping', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(1000, 50_000);
      // A later ping overwrote the send bookkeeping before the pong arrived;
      // the server's echoed `t` field is authoritative instead.
      clock.markPingSent(9000, 58_000);

      const outcome = clock.acceptPong(52_100, 1000, 9100, 58_100);

      expect(outcome).assertEqual('accepted');
      // sentAtWall = 58100 - (9100 - 1000) = 50000; rtt = 8100;
      // reference = 50000 + 4050 = 54050; offset = 52100 - 54050.
      expect(clock.estimatedOffsetMs()).assertEqual(-1950);
    });

    it('rejects samples without a usable server timestamp', 0, () => {
      const clock = new ListenTogetherServerClockOffset();

      expect(clock.acceptPong(null, null, 1000, 50_000)).assertEqual('missing_server_time');
      expect(clock.acceptPong(0, null, 1000, 50_000)).assertEqual('missing_server_time');
      expect(clock.estimatedOffsetMs()).assertEqual(0);
    });

    it('rejects a round trip measured on a clock that ran backwards', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(5000, 50_000);

      const outcome = clock.acceptPong(50_100, null, 4000, 50_100);

      expect(outcome).assertEqual('negative_round_trip');
      expect(clock.estimatedOffsetMs()).assertEqual(0);
    });

    it('discards round trips beyond the clock-sync RTT ceiling', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(1000, 50_000);

      expect(clock.acceptPong(99_999, null, 35_000, 80_000)).assertEqual('round_trip_too_slow');
      expect(clock.estimatedOffsetMs()).assertEqual(0);

      // Exactly at the ceiling is still good: rtt=30000, ref=50000+15000.
      expect(clock.acceptPong(81_500, null, 31_000, 80_300)).assertEqual('accepted');
      expect(clock.estimatedOffsetMs()).assertEqual(16_500);
    });

    it('treats a non-positive echoed t as absent', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      clock.markPingSent(1000, 50_000);

      clock.acceptPong(52_000, 0, 1300, 50_300);

      expect(clock.estimatedOffsetMs()).assertEqual(1850);
    });

    it('dates an unsolicited server message at "now" with no round trip', 0, () => {
      const clock = new ListenTogetherServerClockOffset();

      const outcome = clock.acceptServerMessage(60_000, 55_000);

      expect(outcome).assertEqual('accepted');
      expect(clock.estimatedOffsetMs()).assertEqual(5000);
    });

    it('uses an HTTP state response as a round-trip clock sample', 0, () => {
      const clock = new ListenTogetherServerClockOffset();

      const outcome = clock.acceptHttpRoundTrip(52_000, 1000, 50_000, 1400, 50_400);

      expect(outcome).assertEqual('accepted');
      // rtt=400, reference=50000+200, offset=1800.
      expect(clock.estimatedOffsetMs()).assertEqual(1800);
    });

    it('keeps the legacy-ping tri-state across resets', 0, () => {
      const clock = new ListenTogetherServerClockOffset();
      expect(clock.shouldSendLegacyPing()).assertFalse();
      expect(clock.clockSyncPingSupport()).assertNull();

      clock.markClockSyncPingSupported();
      expect(clock.shouldSendLegacyPing()).assertFalse();

      clock.reset();
      expect(clock.clockSyncPingSupport()).assertNull();

      clock.markClockSyncPingUnsupported();
      expect(clock.shouldSendLegacyPing()).assertTrue();

      // A reconnect gets to re-probe: reset returns to null, not false.
      clock.reset();
      expect(clock.shouldSendLegacyPing()).assertFalse();
      expect(clock.clockSyncPingSupport()).assertNull();
    });
  });

  describe('ListenTogetherMembershipRecovery', () => {
    it('does not recover without a local identity', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      expect(shouldRecoverMissingListenTogetherMembership(state, null, false)).assertFalse();
      expect(shouldRecoverMissingListenTogetherMembership(state, '   ', false)).assertFalse();
    });

    it('never recovers a controller by rejoining', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      expect(shouldRecoverMissingListenTogetherMembership(state, 'me', true)).assertFalse();
    });

    it('does not rejoin a closed room', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      state.roomStatus = ListenTogetherRoomStatuses.CLOSED;
      expect(shouldRecoverMissingListenTogetherMembership(state, 'me', false)).assertFalse();
    });

    it('stays put when the member list still identifies us', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      state.members = [member('other', null), member('me', null)];
      expect(shouldRecoverMissingListenTogetherMembership(state, 'me', false)).assertFalse();

      // A pre-uuid member recorded only a legacy userId; that still counts.
      const legacy = createListenTogetherRoomState('ABC234', 1);
      legacy.members = [member('', 'legacy-me')];
      expect(shouldRecoverMissingListenTogetherMembership(legacy, 'legacy-me', false)).assertFalse();
    });

    it('asks for a rejoin when the snapshot no longer lists us', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      state.members = [member('someone-else', null)];
      expect(shouldRecoverMissingListenTogetherMembership(state, 'me', false)).assertTrue();
    });

    it('recognizes fatal membership errors by substring, case-insensitively', 0, () => {
      expect(isFatalListenTogetherMembershipError('Member not in room')).assertTrue();
      expect(isFatalListenTogetherMembershipError('room ABC234: member missing for user')).assertTrue();
      expect(isFatalListenTogetherMembershipError('some other failure')).assertFalse();
      expect(isFatalListenTogetherMembershipError(null)).assertFalse();
      expect(isFatalListenTogetherMembershipError('   ')).assertFalse();
    });

    it('requires a complete session before triggering recovery', 0, () => {
      expect(canTriggerListenTogetherMembershipRecovery(
        'https://lt.example', 'ABC234', 'me', 'Nick', false)).assertTrue();

      expect(canTriggerListenTogetherMembershipRecovery(
        'https://lt.example', 'ABC234', 'me', 'Nick', true)).assertFalse();

      expect(canTriggerListenTogetherMembershipRecovery(
        '', 'ABC234', 'me', 'Nick', false)).assertFalse();
      expect(canTriggerListenTogetherMembershipRecovery(
        'https://lt.example', null, 'me', 'Nick', false)).assertFalse();
      expect(canTriggerListenTogetherMembershipRecovery(
        'https://lt.example', 'ABC234', '', 'Nick', false)).assertFalse();
      expect(canTriggerListenTogetherMembershipRecovery(
        'https://lt.example', 'ABC234', 'me', null, false)).assertFalse();
    });
  });

  describe('ListenTogetherPendingMemberControlRetry', () => {
    it('only tracks request events sent by a listener', 0, () => {
      const play = createListenTogetherEvent('REQUEST_PLAY');

      expect(buildListenTogetherPendingMemberControlRequest(play, true, 1000)).assertNull();
      expect(buildListenTogetherPendingMemberControlRequest(
        createListenTogetherEvent('PLAY'), false, 1000)).assertNull();

      const built = buildListenTogetherPendingMemberControlRequest(play, false, 1000);
      expect(built !== null).assertTrue();
      // The first send already happened, so attempts starts at 1.
      expect(built!.attempts).assertEqual(1);
      expect(built!.createdAtElapsedMs).assertEqual(1000);
      expect(built!.lastSentAtElapsedMs).assertEqual(1000);
    });

    it('reports idle when nothing is pending', 0, () => {
      const decision = resolveListenTogetherPendingMemberControlRetry(null, null, 1000);
      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_IDLE);
      expect(decision.next).assertNull();
      expect(decision.shouldResend()).assertFalse();
    });

    it('retires a request the room already honoured', 0, () => {
      const pending = buildListenTogetherPendingMemberControlRequest(
        createListenTogetherEvent('REQUEST_PLAY'), false, 0);
      const room = createListenTogetherRoomState('ABC234', 1);
      room.playback.state = 'playing';

      const decision = resolveListenTogetherPendingMemberControlRetry(pending, room, 20_000);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_SATISFIED);
      expect(decision.next).assertNull();
    });

    it('gives a request exactly at its TTL one last chance', 0, () => {
      const pending = buildListenTogetherPendingMemberControlRequest(
        createListenTogetherEvent('REQUEST_PLAY'), false, 0);

      // Strictly-greater comparison: at exactly the TTL it is still resendable.
      const atTtl = resolveListenTogetherPendingMemberControlRetry(
        pending, null, TTL_MS, TTL_MS, RETRY_INTERVAL_MS);
      expect(atTtl.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_RETRY);

      const pastTtl = resolveListenTogetherPendingMemberControlRetry(
        pending, null, TTL_MS + 1, TTL_MS, RETRY_INTERVAL_MS);
      expect(pastTtl.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_EXPIRED);
      expect(pastTtl.next).assertNull();
    });

    it('stops resending after the attempt budget is spent', 0, () => {
      const spent = new ListenTogetherPendingMemberControlRequest(
        createListenTogetherEvent('REQUEST_PAUSE'), 0, 0, 4);

      const decision = resolveListenTogetherPendingMemberControlRetry(
        spent, null, RETRY_INTERVAL_MS, TTL_MS, RETRY_INTERVAL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_MAX_ATTEMPTS);
      expect(decision.next).assertNull();
    });

    it('keeps the request untouched while inside the retry interval', 0, () => {
      const pending = buildListenTogetherPendingMemberControlRequest(
        createListenTogetherEvent('REQUEST_PAUSE'), false, 10_000);

      const decision = resolveListenTogetherPendingMemberControlRetry(
        pending, null, 11_000, TTL_MS, RETRY_INTERVAL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_TOO_SOON);
      expect(decision.next === pending).assertTrue();
      expect(decision.shouldResend()).assertFalse();
    });

    it('resends the same event with the original creation time', 0, () => {
      const pending = buildListenTogetherPendingMemberControlRequest(
        createListenTogetherEvent('REQUEST_SEEK'), false, 500);
      if (pending === null) {
        return;
      }
      pending.event.positionMs = 42_000;

      const decision = resolveListenTogetherPendingMemberControlRetry(
        pending, null, 4000, TTL_MS, RETRY_INTERVAL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_PENDING_CONTROL_RETRY);
      expect(decision.shouldResend()).assertTrue();
      const next = decision.next!;
      expect(next.event === pending.event).assertTrue();
      expect(next.createdAtElapsedMs).assertEqual(500);
      expect(next.lastSentAtElapsedMs).assertEqual(4000);
      expect(next.attempts).assertEqual(2);
    });
  });

  describe('ListenTogetherTrackFinishedFallback', () => {
    const unsupportedError = 'Unsupported event type: TRACK_FINISHED';

    it('leaves the slot alone for unrelated errors', 0, () => {
      const pending = pendingFallback();

      const decision = resolveListenTogetherTrackFinishedFallback(
        'network unavailable', pending, 1000, FALLBACK_TTL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_NOT_REJECTED);
      expect(decision.next === pending).assertTrue();
      expect(decision.shouldSend()).assertFalse();
    });

    it('has nothing to rewrite when no finish was recorded', 0, () => {
      const decision = resolveListenTogetherTrackFinishedFallback(
        unsupportedError, null, 1000, FALLBACK_TTL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_IDLE);
      expect(decision.next).assertNull();
    });

    it('refuses to rewrite twice but keeps the record', 0, () => {
      const attempted = pendingFallback().markAttempted();

      const decision = resolveListenTogetherTrackFinishedFallback(
        unsupportedError, attempted, 1000, FALLBACK_TTL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_ALREADY_ATTEMPTED);
      expect(decision.next === attempted).assertTrue();
    });

    it('clears an over-TTL fallback instead of sending it', 0, () => {
      const pending = pendingFallback();

      const decision = resolveListenTogetherTrackFinishedFallback(
        unsupportedError, pending, FALLBACK_TTL_MS + 1, FALLBACK_TTL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_EXPIRED);
      expect(decision.next).assertNull();
    });

    it('sends once within the TTL and marks the record attempted', 0, () => {
      const pending = pendingFallback();

      const decision = resolveListenTogetherTrackFinishedFallback(
        unsupportedError, pending, FALLBACK_TTL_MS, FALLBACK_TTL_MS);

      expect(decision.outcome).assertEqual(LISTEN_TOGETHER_TRACK_FINISHED_FALLBACK_SEND);
      expect(decision.shouldSend()).assertTrue();
      expect(decision.next !== null).assertTrue();
      expect(decision.next!.attempted).assertTrue();
      expect(decision.next!.event === pending.event).assertTrue();
      expect(decision.next!.createdAtElapsedMs).assertEqual(0);
    });
  });

  describe('ListenTogetherSessionRuntimeConstants', () => {
    // Upstream ListenTogetherSessionPoliciesTest asserts this against the
    // session manager's companion object; the constants only became importable
    // with the M7.3b split, so the assertion lands here.
    it('keep-alive pings stay under the worker controller timeout', 0, () => {
      expect(LISTEN_TOGETHER_SOCKET_KEEP_ALIVE_INTERVAL_MS <
        LISTEN_TOGETHER_WORKER_CONTROLLER_TIMEOUT_MS).assertTrue();
    });

    it('watchdog and retry cadences stay under their ceilings', 0, () => {
      // The watchdog must notice silence well before the repair window closes.
      expect(LISTEN_TOGETHER_SYNC_WATCHDOG_INTERVAL_MS <
        LISTEN_TOGETHER_LISTENER_WEB_SOCKET_SILENCE_TIMEOUT_MS).assertTrue();
      // A request must be able to reach its max attempts within its TTL.
      expect(LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_RETRY_INTERVAL_MS <
        LISTEN_TOGETHER_PENDING_MEMBER_CONTROL_REQUEST_TTL_MS).assertTrue();
    });
  });

  describe('ListenTogetherSessionOperationGate', () => {
    it('invalidates older asynchronous session work', 0, () => {
      const gate = new ListenTogetherSessionOperationGate();
      const first = gate.begin();
      expect(gate.isCurrent(first)).assertTrue();
      expect(gate.current()).assertEqual(first);

      const second = gate.begin();
      expect(gate.isCurrent(first)).assertFalse();
      expect(gate.isCurrent(second)).assertTrue();
    });
  });
}
