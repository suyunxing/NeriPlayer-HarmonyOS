/**
 * M7.3a control-hardening tests, ported from
 * app/src/test/.../ListenTogetherControlHardeningTest.kt. Its seven
 * clamp/expected-position/single-repeat-wrap cases already live in
 * ListenTogetherPlayback.test.ets; the ten forwarded-control cases are ported
 * here, together with new coverage for ListenTogetherControlBlockPolicy's local
 * block reasons, which upstream exercises only through the UI layer.
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE,
  LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE_LINK,
  LISTEN_TOGETHER_BLOCK_REASON_MEMBER_CONTROL_DISABLED,
  resolveListenTogetherControlBlockReason,
  shouldRejectForwardedListenTogetherMemberControl
} from '../../../main/ets/listentogether/session/ListenTogetherControlBlockPolicy';
import {
  LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_EVENT_IDS,
  LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_REQUESTERS,
  LISTEN_TOGETHER_DEDUPER_GLOBAL_REQUESTER,
  ListenTogetherForwardedRequestDeduper
} from '../../../main/ets/listentogether/session/ListenTogetherForwardedRequestDeduper';
import { buildListenTogetherForwardedControlSyntheticState } from '../../../main/ets/listentogether/control/ListenTogetherForwardedControlState';
import {
  ListenTogetherRoomState,
  ListenTogetherRoomStatuses,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import { ListenTogetherSocketEnvelope } from '../../../main/ets/listentogether/protocol/ListenTogetherSocketEnvelope';
import { createListenTogetherEvent } from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import {
  LISTEN_TOGETHER_ROLE_CONTROLLER,
  LISTEN_TOGETHER_ROLE_LISTENER
} from '../../../main/ets/listentogether/protocol/ListenTogetherSessionModels';

/** Upstream's fixture clock, so the synthetic states carry the same timestamp. */
const NOW_MS: number = 1_700_000_000_000;

function fixtureTrack(stableKey: string): ListenTogetherTrack {
  return createListenTogetherTrack(
    stableKey,
    'channel',
    `audio-${stableKey}`,
    `name-${stableKey}`,
    'artist'
  );
}

function forwardedRequest(
  queue: ListenTogetherTrack[] | null,
  currentIndex: number | null
): ListenTogetherSocketEnvelope {
  const message = new ListenTogetherSocketEnvelope();
  message.type = 'member_control_requested';
  message.queue = queue;
  message.currentIndex = currentIndex;
  return message;
}

/** An offline-controller room, whose `shareAudioLinks` picks the reason code. */
function controllerOfflineRoom(shareAudioLinks: boolean): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ABC234', 1);
  state.roomStatus = ListenTogetherRoomStatuses.CONTROLLER_OFFLINE;
  state.settings.shareAudioLinks = shareAudioLinks;
  return state;
}

export default function listenTogetherControlHardeningTest() {
  describe('ListenTogetherControlHardening', () => {
    it('passes any requester while member control is allowed', 0, () => {
      expect(shouldRejectForwardedListenTogetherMemberControl(
        'listener-1', 'controller', true
      )).assertFalse();
    });

    it('rejects listener requests while member control is disabled', 0, () => {
      expect(shouldRejectForwardedListenTogetherMemberControl(
        'listener-1', 'controller', false
      )).assertTrue();
    });

    it('still allows the controller own request while member control is disabled', 0, () => {
      expect(shouldRejectForwardedListenTogetherMemberControl(
        'controller', 'controller', false
      )).assertFalse();
    });

    it('rejects a blank or unknown requester while member control is disabled', 0, () => {
      // The server may forward a request it could not attribute; honouring it
      // would let member control back in through the door the settings closed.
      expect(shouldRejectForwardedListenTogetherMemberControl(
        null, 'controller', false
      )).assertTrue();
      expect(shouldRejectForwardedListenTogetherMemberControl(
        '   ', 'controller', false
      )).assertTrue();
      // Not even a blank controller id makes a blank requester the controller.
      expect(shouldRejectForwardedListenTogetherMemberControl(
        '   ', null, false
      )).assertTrue();
    });

    it('keeps each requester sequence independent', 0, () => {
      const deduper = new ListenTogetherForwardedRequestDeduper();

      expect(deduper.shouldProcess('A', 1, null)).assertTrue();
      expect(deduper.shouldProcess('A', 1, null)).assertFalse();
      expect(deduper.shouldProcess('A', 2, null)).assertTrue();
      expect(deduper.shouldProcess('A', 1, null)).assertFalse();
      // B's first, lower sequence must not look stale because A ran ahead — the
      // single global counter this replaced silently dropped exactly this case.
      expect(deduper.shouldProcess('B', 1, null)).assertTrue();
      // A blank requester falls into the shared bucket rather than its own.
      expect(deduper.shouldProcess('  ', 4, null)).assertTrue();
      expect(deduper.shouldProcess(null, 4, null)).assertFalse();
      expect(LISTEN_TOGETHER_DEDUPER_GLOBAL_REQUESTER).assertEqual('__global__');
    });

    it('falls back to the event id when the sequence is missing', 0, () => {
      const deduper = new ListenTogetherForwardedRequestDeduper();

      expect(deduper.shouldProcess('A', 0, 'e1')).assertTrue();
      expect(deduper.shouldProcess('A', null, 'e1')).assertFalse();
      expect(deduper.shouldProcess('A', null, 'e2')).assertTrue();
      // Event ids are global, not per requester: the same id is the same request.
      expect(deduper.shouldProcess('B', null, 'e2')).assertFalse();
    });

    it('passes a request through when it has neither sequence nor event id', 0, () => {
      const deduper = new ListenTogetherForwardedRequestDeduper();

      // Dropping these would lose a real command, which is worse than acting twice.
      expect(deduper.shouldProcess('A', 0, null)).assertTrue();
      expect(deduper.shouldProcess('A', null, '  ')).assertTrue();
      expect(deduper.shouldProcess('A', null, '  ')).assertTrue();
    });

    it('resets deduper state on clear', 0, () => {
      const deduper = new ListenTogetherForwardedRequestDeduper();

      expect(deduper.shouldProcess('A', 5, null)).assertTrue();
      expect(deduper.shouldProcess('A', null, 'e1')).assertTrue();
      expect(deduper.shouldProcess('A', 5, null)).assertFalse();
      expect(deduper.shouldProcess('A', null, 'e1')).assertFalse();

      deduper.clear();

      // Both rings are cleared, so a reconnected session starts from scratch
      // rather than silently dropping the room's first commands as duplicates.
      expect(deduper.shouldProcess('A', 5, null)).assertTrue();
      expect(deduper.shouldProcess('A', null, 'e1')).assertTrue();
      expect(LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_REQUESTERS).assertEqual(64);
      expect(LISTEN_TOGETHER_DEDUPER_DEFAULT_MAX_EVENT_IDS).assertEqual(256);
    });

    it('evicts the oldest requester once the cache is full', 0, () => {
      const deduper = new ListenTogetherForwardedRequestDeduper(2, 2);

      expect(deduper.shouldProcess('A', 5, null)).assertTrue();
      expect(deduper.shouldProcess('B', 5, null)).assertTrue();
      expect(deduper.shouldProcess('C', 5, null)).assertTrue();
      // A was the oldest of the three, so it was evicted and its already-seen
      // sequence is accepted again. That is the documented cost of a bounded
      // cache, not a regression: a requester this stale has almost certainly
      // left the room rather than resent an old sequence.
      expect(deduper.shouldProcess('A', 5, null)).assertTrue();
      // Re-admitting A evicted B in its turn, but C is still the most recent
      // survivor, so its sequence is still remembered.
      expect(deduper.shouldProcess('C', 5, null)).assertFalse();
    });

    it('retains the current queue for an empty forwarded queue', 0, () => {
      const track1 = fixtureTrack('k1');
      const track2 = fixtureTrack('k2');
      const currentState = createListenTogetherRoomState('room-1', 3);
      currentState.queue = [track1, track2];
      currentState.currentIndex = 0;
      currentState.track = track1;
      const committedEvent = createListenTogetherEvent('PLAY');
      committedEvent.positionMs = 5_000;

      const next = buildListenTogetherForwardedControlSyntheticState(
        currentState,
        forwardedRequest([], 1),
        committedEvent,
        NOW_MS
      );

      // An empty forwarded queue means "do not touch the queue", not "clear it".
      expect(next.queue.length).assertEqual(2);
      expect(next.queue[0].stableKey).assertEqual('k1');
      expect(next.queue[1].stableKey).assertEqual('k2');
      expect(next.playback.state).assertEqual('playing');
      expect(next.playback.basePositionMs).assertEqual(5_000);
      // Re-based to now, so the position reads as "this, as of this instant".
      expect(next.playback.baseTimestampMs).assertEqual(NOW_MS);
      // The version is deliberately untouched: the authoritative state must win
      // the version gate when it arrives.
      expect(next.version).assertEqual(3);
      expect(next.currentIndex).assertEqual(1);
    });

    it('adopts a non-empty forwarded queue', 0, () => {
      const current = fixtureTrack('k1');
      const incoming1 = fixtureTrack('k2');
      const incoming2 = fixtureTrack('k3');
      const currentState = createListenTogetherRoomState('room-1', 3);
      currentState.queue = [current];
      currentState.currentIndex = 0;
      currentState.track = current;
      currentState.playback.state = 'playing';

      const next = buildListenTogetherForwardedControlSyntheticState(
        currentState,
        forwardedRequest([incoming1, incoming2], 1),
        createListenTogetherEvent('PAUSE'),
        NOW_MS
      );

      expect(next.queue.length).assertEqual(2);
      expect(next.queue[0].stableKey).assertEqual('k2');
      expect(next.queue[1].stableKey).assertEqual('k3');
      // The committed event's own type is authoritative for transport.
      expect(next.playback.state).assertEqual('paused');
      expect(next.playback.basePositionMs).assertEqual(0);
      const nextTrack = next.track;
      expect(nextTrack === null).assertFalse();
      if (nextTrack !== null) {
        expect(nextTrack.stableKey).assertEqual('k3');
      }
    });

    it('falls back to the request state for a non-transport commit', 0, () => {
      const current = fixtureTrack('k1');
      const currentState = createListenTogetherRoomState('room-1', 3);
      currentState.queue = [current];
      currentState.currentIndex = 0;
      currentState.track = current;
      currentState.playback.state = 'playing';
      const committedEvent = createListenTogetherEvent('SEEK');
      committedEvent.positionMs = 12_000;

      const named = forwardedRequest(null, null);
      named.stateName = 'paused';
      expect(buildListenTogetherForwardedControlSyntheticState(
        currentState, named, committedEvent, NOW_MS
      ).playback.state).assertEqual('paused');

      const shouldPlay = forwardedRequest(null, null);
      shouldPlay.shouldPlay = true;
      expect(buildListenTogetherForwardedControlSyntheticState(
        currentState, shouldPlay, committedEvent, NOW_MS
      ).playback.state).assertEqual('playing');

      // Nothing said: keep what the room was already doing.
      const silent = buildListenTogetherForwardedControlSyntheticState(
        currentState, forwardedRequest(null, null), committedEvent, NOW_MS
      );
      expect(silent.playback.state).assertEqual('playing');
      expect(silent.playback.basePositionMs).assertEqual(12_000);
    });

    it('clamps a forwarded index into the resulting queue', 0, () => {
      const currentState = createListenTogetherRoomState('room-1', 3);
      currentState.queue = [fixtureTrack('k1'), fixtureTrack('k2')];
      currentState.currentIndex = 0;

      const past = buildListenTogetherForwardedControlSyntheticState(
        currentState, forwardedRequest(null, 9), createListenTogetherEvent('PLAY'), NOW_MS
      );
      expect(past.currentIndex).assertEqual(1);

      const negative = buildListenTogetherForwardedControlSyntheticState(
        currentState, forwardedRequest(null, -4), createListenTogetherEvent('PLAY'), NOW_MS
      );
      expect(negative.currentIndex).assertEqual(0);

      // A negative committed position is floored rather than propagated.
      const rewound = createListenTogetherEvent('SEEK');
      rewound.positionMs = -1;
      expect(buildListenTogetherForwardedControlSyntheticState(
        currentState, forwardedRequest(null, 0), rewound, NOW_MS
      ).playback.basePositionMs).assertEqual(0);
    });

    it('blocks every non-controller role while the controller is offline', 0, () => {
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, controllerOfflineRoom(true), 'PLAY'
      )).assertEqual(LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE_LINK);
      // Without link sharing there is no stream to fall back on, so the reason
      // the user is shown is the plainer one.
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, controllerOfflineRoom(false), 'PLAY'
      )).assertEqual(LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE);
      // An unknown role is not a controller either: with nobody answering, nobody
      // may drive the room.
      expect(resolveListenTogetherControlBlockReason(
        null, controllerOfflineRoom(true), 'PLAY'
      )).assertEqual(LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE_LINK);
      // The offline branch outranks the command type: even an uncontrolled
      // command is refused.
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, controllerOfflineRoom(true), 'SET_TRACK'
      )).assertEqual(LISTEN_TOGETHER_BLOCK_REASON_CONTROLLER_OFFLINE_LINK);
      // The controller itself is the one who can fix it.
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_CONTROLLER, controllerOfflineRoom(true), 'PLAY'
      )).assertNull();
    });

    it('blocks only controlled commands when member control is disabled', 0, () => {
      const disabled = createListenTogetherRoomState('ABC234', 1);
      disabled.settings.allowMemberControl = false;

      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, disabled, 'PLAY'
      )).assertEqual(LISTEN_TOGETHER_BLOCK_REASON_MEMBER_CONTROL_DISABLED);
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, disabled, 'NEXT'
      )).assertEqual(LISTEN_TOGETHER_BLOCK_REASON_MEMBER_CONTROL_DISABLED);
      // SET_TRACK is not a controlled transport command upstream, so it passes.
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, disabled, 'SET_TRACK'
      )).assertNull();
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_CONTROLLER, disabled, 'PLAY'
      )).assertNull();
    });

    it('never blocks with member control allowed or no room state', 0, () => {
      const allowed = createListenTogetherRoomState('ABC234', 1);
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, allowed, 'PLAY'
      )).assertNull();
      // No room state at all: nothing is being shared, so nothing is blocked.
      expect(resolveListenTogetherControlBlockReason(
        LISTEN_TOGETHER_ROLE_LISTENER, null, 'PLAY'
      )).assertNull();
    });
  });
}
