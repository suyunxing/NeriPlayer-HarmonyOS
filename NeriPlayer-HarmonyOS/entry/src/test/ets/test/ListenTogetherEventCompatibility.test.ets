import { describe, it, expect } from '@ohos/hypium';
import {
  ListenTogetherEvent,
  createListenTogetherEvent
} from '../../../main/ets/listentogether/protocol/ListenTogetherEventModels';
import {
  ListenTogetherPlaybackState,
  ListenTogetherRoomState,
  createListenTogetherRoomState
} from '../../../main/ets/listentogether/protocol/ListenTogetherRoomModels';
import {
  ListenTogetherChannels
} from '../../../main/ets/listentogether/protocol/ListenTogetherChannels';
import {
  ListenTogetherTrack,
  createListenTogetherTrack
} from '../../../main/ets/listentogether/protocol/ListenTogetherTrack';
import {
  buildListenTogetherLegacyQueueMutationFallback,
  buildTrackFinishedLegacyFallbackEvent,
  isListenTogetherMemberControlTargetCurrent,
  isListenTogetherPendingMemberControlSatisfied,
  isListenTogetherQueueMutationCompatibilityError,
  isUnsupportedTrackFinishedEventError,
  resolveListenTogetherLinkReadyState,
  resolveListenTogetherPlaybackCommandShouldPlay,
  shouldSuppressListenerControlWhileAwaitingStream
} from '../../../main/ets/listentogether/compat/ListenTogetherEventCompatibility';
import {
  ListenTogetherQueueMutation
} from '../../../main/ets/listentogether/protocol/ListenTogetherQueueMutation';
import {
  isListenTogetherControlledPlaybackCommandType,
  isListenTogetherControllerHeartbeatRecoveryType,
  isListenTogetherPassivePositionUpdateType,
  isListenTogetherRequestControlEventType,
  isListenTogetherTrackBoundRequestControlEventType
} from '../../../main/ets/listentogether/control/ListenTogetherControlEventTypes';
import {
  resolveListenTogetherPlaybackCommandSnapshot
} from '../../../main/ets/listentogether/control/ListenTogetherPlaybackCommandSnapshot';
import {
  LISTEN_TOGETHER_REPEAT_MODE_ONE,
  clampListenTogetherPositionMs,
  isListenTogetherSeekControlSatisfied,
  listenTogetherExpectedPositionMs,
  wrapListenTogetherSingleTrackRepeatPosition
} from '../../../main/ets/listentogether/playback/ListenTogetherPlaybackPosition';

function track(audioId: string): ListenTogetherTrack {
  return createListenTogetherTrack(
    `netease:${audioId}`,
    ListenTogetherChannels.NETEASE,
    audioId,
    `Song ${audioId}`,
    'Artist'
  );
}

function playingRoom(currentTrack: ListenTogetherTrack | null): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ABC234', 1);
  state.playback.state = 'playing';
  state.track = currentTrack;
  return state;
}

function pausedPlayback(basePositionMs: number): ListenTogetherPlaybackState {
  const playback = new ListenTogetherPlaybackState();
  playback.basePositionMs = basePositionMs;
  return playback;
}

function playingPlayback(
  basePositionMs: number,
  baseTimestampMs: number,
  playbackRate: number = 1.0
): ListenTogetherPlaybackState {
  const playback = new ListenTogetherPlaybackState();
  playback.state = 'playing';
  playback.basePositionMs = basePositionMs;
  playback.baseTimestampMs = baseTimestampMs;
  playback.playbackRate = playbackRate;
  return playback;
}

function trackFinishedEvent(shouldPlay: boolean, nextIndex: number | null): ListenTogetherEvent {
  const event = createListenTogetherEvent('TRACK_FINISHED');
  event.eventId = 'event-finished';
  event.currentIndex = 1;
  event.nextIndex = nextIndex;
  event.finishedTrackStableKey = 'netease:1';
  event.queue = [track('1'), track('2'), track('3')];
  event.shouldPlay = shouldPlay;
  return event;
}

/** A V2 SET_QUEUE carrying a queue mutation against base version 2. */
function mutationEvent(): ListenTogetherEvent {
  const event = createListenTogetherEvent('SET_QUEUE');
  event.eventId = 'evt-9';
  const mutation = new ListenTogetherQueueMutation();
  mutation.baseRoomVersion = 2;
  event.queueMutation = mutation;
  return event;
}

function mirroredRoom(): ListenTogetherRoomState {
  const state = createListenTogetherRoomState('ABC234', 3);
  state.queue = [track('1'), track('2')];
  state.currentIndex = 0;
  state.track = track('1');
  return state;
}

export default function listenTogetherEventCompatibilityTest(): void {
  describe('ListenTogetherShouldPlayCompatibility', () => {
    it('prefersAnExplicitShouldPlayFlag', 0, () => {
      expect(resolveListenTogetherPlaybackCommandShouldPlay('PLAY', true, false, false)).assertTrue();
      expect(resolveListenTogetherPlaybackCommandShouldPlay('PLAY', false, true, true)).assertFalse();
    });

    it('infersATransportDrivenCommandFromTheLocalTransport', 0, () => {
      expect(resolveListenTogetherPlaybackCommandShouldPlay('NEXT', null, true, false)).assertTrue();
      expect(resolveListenTogetherPlaybackCommandShouldPlay('SEEK', null, false, true)).assertTrue();
      expect(resolveListenTogetherPlaybackCommandShouldPlay('NEXT', null, false, false))
        .assertFalse();
    });

    it('fallsBackToTheLocalPlayingFlagForOtherCommands', 0, () => {
      // SET_TRACK is not transport driven, so a buffering transport does not count.
      expect(resolveListenTogetherPlaybackCommandShouldPlay('SET_TRACK', null, true, false))
        .assertFalse();
      expect(resolveListenTogetherPlaybackCommandShouldPlay('SET_TRACK', null, false, true))
        .assertTrue();
    });

    it('reportsTheLinkReadyStateFromEitherSide', 0, () => {
      expect(resolveListenTogetherLinkReadyState(' Playing ', false, false)).assertEqual('playing');
      expect(resolveListenTogetherLinkReadyState('paused', true, false)).assertEqual('playing');
      expect(resolveListenTogetherLinkReadyState('paused', false, true)).assertEqual('playing');
      expect(resolveListenTogetherLinkReadyState('paused', false, false)).assertEqual('paused');
      expect(resolveListenTogetherLinkReadyState(null, false, false)).assertEqual('paused');
    });
  });

  describe('ListenTogetherMemberControlCompatibility', () => {
    it('bindsATrackBoundRequestToTheCurrentTrack', 0, () => {
      expect(isListenTogetherMemberControlTargetCurrent(
        'REQUEST_PLAY', ' netease:1 ', 'netease:1')).assertTrue();
      expect(isListenTogetherMemberControlTargetCurrent(
        'REQUEST_SEEK', 'netease:1', 'netease:2')).assertFalse();
      expect(isListenTogetherMemberControlTargetCurrent(
        'REQUEST_PAUSE', null, 'netease:1')).assertFalse();
      expect(isListenTogetherMemberControlTargetCurrent(
        'REQUEST_PAUSE', 'netease:1', '   ')).assertFalse();
    });

    it('leavesUnboundRequestsAlone', 0, () => {
      expect(isListenTogetherMemberControlTargetCurrent('REQUEST_PLAYBACK_MODE', null, null))
        .assertTrue();
      expect(isListenTogetherMemberControlTargetCurrent('HEARTBEAT', null, null)).assertTrue();
    });

    it('suppressesStreamDependentRequestsWhileAwaitingTheStream', 0, () => {
      expect(shouldSuppressListenerControlWhileAwaitingStream('REQUEST_PAUSE', true, false))
        .assertTrue();
      expect(shouldSuppressListenerControlWhileAwaitingStream('REQUEST_SEEK', true, false))
        .assertTrue();
      // A direct stream means the local player can already act on it.
      expect(shouldSuppressListenerControlWhileAwaitingStream('REQUEST_PAUSE', true, true))
        .assertFalse();
      expect(shouldSuppressListenerControlWhileAwaitingStream('REQUEST_PAUSE', false, false))
        .assertFalse();
      expect(shouldSuppressListenerControlWhileAwaitingStream('REQUEST_PLAY', true, false))
        .assertFalse();
    });
  });

  describe('ListenTogetherPendingRequestSettlement', () => {
    it('settlesPlayAndPauseOnTheRoomTransport', 0, () => {
      const playing = playingRoom(null);
      const paused = createListenTogetherRoomState('ABC234', 1);

      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_PLAY'), playing)).assertTrue();
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_PLAY'), paused)).assertFalse();
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_PAUSE'), paused)).assertTrue();
      // Controller-side names settle through the same rules.
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('PAUSE'), paused)).assertTrue();
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_PLAY'), null)).assertFalse();
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('HEARTBEAT'), paused)).assertFalse();
    });

    it('settlesASeekWithinTheDriftWindow', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      state.playback.basePositionMs = 60000;

      const near = createListenTogetherEvent('REQUEST_SEEK');
      near.positionMs = 60700;
      const far = createListenTogetherEvent('REQUEST_SEEK');
      far.positionMs = 63000;

      expect(isListenTogetherPendingMemberControlSatisfied(near, state)).assertTrue();
      expect(isListenTogetherPendingMemberControlSatisfied(far, state)).assertFalse();
      expect(isListenTogetherPendingMemberControlSatisfied(near, state, 100)).assertFalse();
      expect(isListenTogetherPendingMemberControlSatisfied(far, state, 5000)).assertTrue();
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_SEEK'), state)).assertFalse();
    });

    it('settlesAPlaybackModeRequestFieldByField', 0, () => {
      const state = createListenTogetherRoomState('ABC234', 1);
      state.playback.repeatMode = 2;
      state.playback.shuffleEnabled = true;

      const both = createListenTogetherEvent('REQUEST_PLAYBACK_MODE');
      both.repeatMode = 2;
      both.shuffleEnabled = true;
      expect(isListenTogetherPendingMemberControlSatisfied(both, state)).assertTrue();

      const wrongRepeat = createListenTogetherEvent('REQUEST_PLAYBACK_MODE');
      wrongRepeat.repeatMode = 1;
      expect(isListenTogetherPendingMemberControlSatisfied(wrongRepeat, state)).assertFalse();

      const wrongShuffle = createListenTogetherEvent('REQUEST_PLAYBACK_MODE');
      wrongShuffle.shuffleEnabled = false;
      expect(isListenTogetherPendingMemberControlSatisfied(wrongShuffle, state)).assertFalse();

      // Absent fields were never requested, so they cannot hold the request open.
      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_PLAYBACK_MODE'), state)).assertTrue();
    });

    it('settlesASetTrackRequestOnTheStableKey', 0, () => {
      const state = playingRoom(track('2'));

      const byTrack = createListenTogetherEvent('REQUEST_SET_TRACK');
      byTrack.track = track('2');
      expect(isListenTogetherPendingMemberControlSatisfied(byTrack, state)).assertTrue();

      const byQueueIndex = createListenTogetherEvent('REQUEST_SET_TRACK');
      byQueueIndex.queue = [track('1'), track('2')];
      byQueueIndex.currentIndex = 1;
      expect(isListenTogetherPendingMemberControlSatisfied(byQueueIndex, state)).assertTrue();
      byQueueIndex.currentIndex = 0;
      expect(isListenTogetherPendingMemberControlSatisfied(byQueueIndex, state)).assertFalse();
      byQueueIndex.currentIndex = 9;
      expect(isListenTogetherPendingMemberControlSatisfied(byQueueIndex, state)).assertFalse();

      expect(isListenTogetherPendingMemberControlSatisfied(
        createListenTogetherEvent('REQUEST_SET_TRACK'), state)).assertFalse();

      // With no authoritative track the room falls back to queue[currentIndex].
      const byRoomQueue = playingRoom(null);
      byRoomQueue.queue = [track('1'), track('2')];
      byRoomQueue.currentIndex = 1;
      expect(isListenTogetherPendingMemberControlSatisfied(byTrack, byRoomQueue)).assertTrue();
      byRoomQueue.currentIndex = 5;
      expect(isListenTogetherPendingMemberControlSatisfied(byTrack, byRoomQueue)).assertFalse();
    });
  });

  describe('ListenTogetherTrackFinishedFallback', () => {
    it('recognizesBothServerSpellingsOfTheRejection', 0, () => {
      expect(isUnsupportedTrackFinishedEventError('Unsupported event type: TRACK_FINISHED'))
        .assertTrue();
      // The upstream server shipped the typo'd message for a while.
      expect(isUnsupportedTrackFinishedEventError('unsuppported event type: track_finished'))
        .assertTrue();
      expect(isUnsupportedTrackFinishedEventError('unsupported event type: PLAY')).assertFalse();
      expect(isUnsupportedTrackFinishedEventError('room_closed')).assertFalse();
      expect(isUnsupportedTrackFinishedEventError(null)).assertFalse();
    });

    it('rewritesAContinuingFinishIntoSetTrack', 0, () => {
      const fallback = buildTrackFinishedLegacyFallbackEvent(
        trackFinishedEvent(true, 2), true, 1700000000000, () => 'event-fallback');

      expect(fallback !== null).assertTrue();
      const rewritten = fallback as ListenTogetherEvent;
      expect(rewritten.type).assertEqual('SET_TRACK');
      expect(rewritten.eventId).assertEqual('event-fallback');
      expect(rewritten.clientTimeMs).assertEqual(1700000000000);
      expect(rewritten.currentIndex).assertEqual(2);
      expect(rewritten.positionMs).assertEqual(0);
      expect(rewritten.shouldPlay).assertTrue();
      expect(rewritten.state).assertEqual('playing');
      expect((rewritten.track as ListenTogetherTrack).stableKey).assertEqual('netease:3');
      // The legacy server does not understand either of these fields.
      expect(rewritten.nextIndex).assertNull();
      expect(rewritten.finishedTrackStableKey).assertNull();
    });

    it('rewritesAStoppingFinishIntoPause', 0, () => {
      const stopping = buildTrackFinishedLegacyFallbackEvent(
        trackFinishedEvent(false, 2), true, 1700000000000, () => 'event-fallback');
      expect((stopping as ListenTogetherEvent).type).assertEqual('PAUSE');
      expect((stopping as ListenTogetherEvent).shouldPlay).assertFalse();
      expect((stopping as ListenTogetherEvent).state).assertEqual('paused');

      const noNext = trackFinishedEvent(true, null);
      noNext.currentIndex = null;
      expect((buildTrackFinishedLegacyFallbackEvent(
        noNext, true, 1, () => 'event-fallback') as ListenTogetherEvent).type).assertEqual('PAUSE');
    });

    it('fallsBackToTheCurrentIndexAndOnlyForTheController', 0, () => {
      const withoutNext = buildTrackFinishedLegacyFallbackEvent(
        trackFinishedEvent(true, null), true, 1, () => 'event-fallback') as ListenTogetherEvent;
      expect(withoutNext.type).assertEqual('SET_TRACK');
      expect(withoutNext.currentIndex).assertEqual(1);

      expect(buildTrackFinishedLegacyFallbackEvent(
        trackFinishedEvent(true, 2), false, 1, () => 'event-fallback')).assertNull();
      expect(buildTrackFinishedLegacyFallbackEvent(
        createListenTogetherEvent('PAUSE'), true, 1, () => 'event-fallback')).assertNull();
    });
  });

  describe('ListenTogetherControlEventTypes', () => {
    it('classifiesEachWireEventName', 0, () => {
      expect(isListenTogetherControllerHeartbeatRecoveryType('PLAY')).assertTrue();
      expect(isListenTogetherControllerHeartbeatRecoveryType('MEMBER_JOINED')).assertTrue();
      expect(isListenTogetherControllerHeartbeatRecoveryType('HEARTBEAT')).assertFalse();
      // 上游 89a8694c：队列更新族加入心跳恢复与请求/受控类型。
      expect(isListenTogetherControllerHeartbeatRecoveryType('REQUEST_SET_QUEUE')).assertTrue();
      expect(isListenTogetherRequestControlEventType('REQUEST_SET_QUEUE')).assertTrue();
      expect(isListenTogetherRequestControlEventType('SET_QUEUE')).assertFalse();
      expect(isListenTogetherControlledPlaybackCommandType('SET_QUEUE')).assertTrue();

      expect(isListenTogetherPassivePositionUpdateType('HEARTBEAT')).assertTrue();
      expect(isListenTogetherPassivePositionUpdateType('WATCHDOG_STALL')).assertTrue();
      expect(isListenTogetherPassivePositionUpdateType('PLAY')).assertFalse();

      expect(isListenTogetherControlledPlaybackCommandType('NEXT')).assertTrue();
      expect(isListenTogetherControlledPlaybackCommandType('SET_TRACK')).assertFalse();

      expect(isListenTogetherRequestControlEventType('REQUEST_SET_TRACK')).assertTrue();
      expect(isListenTogetherRequestControlEventType('SET_TRACK')).assertFalse();

      expect(isListenTogetherTrackBoundRequestControlEventType('REQUEST_SEEK')).assertTrue();
      expect(isListenTogetherTrackBoundRequestControlEventType('REQUEST_PLAYBACK_MODE'))
        .assertFalse();
    });

    it('treatsAnEmptyCommandQueueAsKeepWhatIsPlaying', 0, () => {
      const current: string[] = ['x', 'y'];

      const explicit = resolveListenTogetherPlaybackCommandSnapshot<string>(
        ['a'], 5000, current, 1000);
      expect(explicit.queue.length).assertEqual(1);
      expect(explicit.queue[0]).assertEqual('a');
      expect(explicit.positionMs).assertEqual(5000);

      const emptied = resolveListenTogetherPlaybackCommandSnapshot<string>([], null, current, 1000);
      expect(emptied.queue === current).assertTrue();
      expect(emptied.positionMs).assertEqual(1000);

      const absent = resolveListenTogetherPlaybackCommandSnapshot<string>(null, -5, current, 1000);
      expect(absent.queue === current).assertTrue();
      expect(absent.positionMs).assertEqual(0);
    });
  });

  describe('ListenTogetherPlaybackPosition', () => {
    it('clampsAPositionIntoTheTrack', 0, () => {
      expect(clampListenTogetherPositionMs(-5, 1000)).assertEqual(0);
      expect(clampListenTogetherPositionMs(500, 1000)).assertEqual(500);
      expect(clampListenTogetherPositionMs(5000, 1000)).assertEqual(1000);
      // An unknown duration cannot clamp the upper bound.
      expect(clampListenTogetherPositionMs(5000, 0)).assertEqual(5000);
      expect(clampListenTogetherPositionMs(-1, 0)).assertEqual(0);
    });

    it('holdsThePositionWhileTheRoomIsPaused', 0, () => {
      expect(listenTogetherExpectedPositionMs(pausedPlayback(12345), 1700000000000))
        .assertEqual(12345);
      expect(listenTogetherExpectedPositionMs(pausedPlayback(-3), 1700000000000)).assertEqual(0);
    });

    it('extrapolatesTheAuthoritativePositionOntoTheLocalClock', 0, () => {
      expect(listenTogetherExpectedPositionMs(playingPlayback(1000, 1000), 3000)).assertEqual(3000);
      // An illegal baseTimestampMs must not produce an astronomical position.
      expect(listenTogetherExpectedPositionMs(playingPlayback(30000, 0), 1700000000000))
        .assertEqual(30000);
      // The server clock offset is applied before the elapsed difference.
      expect(listenTogetherExpectedPositionMs(playingPlayback(10000, 1000, 1.5), 3000, 1000))
        .assertEqual(14500);
    });

    it('wrapsASingleTrackRepeatBackIntoTheTrack', 0, () => {
      expect(LISTEN_TOGETHER_REPEAT_MODE_ONE).assertEqual(1);
      expect(wrapListenTogetherSingleTrackRepeatPosition(63000, 1, 60000)).assertEqual(3000);
      expect(wrapListenTogetherSingleTrackRepeatPosition(63000, 2, 60000)).assertEqual(63000);
      expect(wrapListenTogetherSingleTrackRepeatPosition(63000, 1, 0)).assertEqual(63000);
      expect(wrapListenTogetherSingleTrackRepeatPosition(-5, 1, 60000)).assertEqual(0);

      const repeating = playingPlayback(58000, 1000);
      repeating.repeatMode = 1;
      expect(listenTogetherExpectedPositionMs(repeating, 6000, 0, 60000)).assertEqual(3000);
    });

    it('acceptsASeekOnceTheBasePositionIsCloseEnough', 0, () => {
      const playback = pausedPlayback(60000);

      expect(isListenTogetherSeekControlSatisfied(playback, 60700)).assertTrue();
      expect(isListenTogetherSeekControlSatisfied(playback, 61500)).assertTrue();
      expect(isListenTogetherSeekControlSatisfied(playback, 63000)).assertFalse();
      expect(isListenTogetherSeekControlSatisfied(playback, 63000, 5000)).assertTrue();
      expect(isListenTogetherSeekControlSatisfied(pausedPlayback(0), -100)).assertTrue();
    });
  });

  describe('ListenTogetherQueueMutationCompatibility', () => {
    it('settlesAQueueMutationOnlyOnItsOwnCommit', 0, () => {
      const event = mutationEvent();
      const state = mirroredRoom();
      expect(isListenTogetherPendingMemberControlSatisfied(event, state, 1500, 'evt-9')).assertTrue();
      // Someone else's commit (or a missing one) must not release the retry.
      expect(isListenTogetherPendingMemberControlSatisfied(event, state, 1500, 'evt-8')).assertFalse();
      expect(isListenTogetherPendingMemberControlSatisfied(event, state, 1500, null)).assertFalse();
      // The room must have moved past the base version.
      const stale = mirroredRoom();
      stale.version = 2;
      expect(isListenTogetherPendingMemberControlSatisfied(event, stale, 1500, 'evt-9')).assertFalse();
      // No event id on the request at all: never satisfied.
      const anonymous = mutationEvent();
      anonymous.eventId = null;
      expect(isListenTogetherPendingMemberControlSatisfied(anonymous, state, 1500, 'evt-9')).assertFalse();
    });

    it('settlesALegacySetQueueOnTheExactMirror', 0, () => {
      const event = createListenTogetherEvent('SET_QUEUE');
      event.queue = [track('1'), track('2'), track('3')];
      event.currentIndex = 2;

      const mirrored = mirroredRoom();
      mirrored.version = 3;
      mirrored.queue = [track('1'), track('2'), track('3')];
      mirrored.currentIndex = 2;
      mirrored.track = track('3');
      expect(isListenTogetherPendingMemberControlSatisfied(event, mirrored)).assertTrue();

      const wrongIndex = mirroredRoom();
      wrongIndex.queue = [track('1'), track('2'), track('3')];
      wrongIndex.currentIndex = 1;
      wrongIndex.track = track('2');
      expect(isListenTogetherPendingMemberControlSatisfied(event, wrongIndex)).assertFalse();

      const wrongLength = mirroredRoom();
      wrongLength.queue = [track('1'), track('2')];
      wrongLength.currentIndex = 2;
      expect(isListenTogetherPendingMemberControlSatisfied(event, wrongLength)).assertFalse();

      const emptied = createListenTogetherEvent('SET_QUEUE');
      emptied.queue = [];
      emptied.currentIndex = -1;
      const emptyRoom = mirroredRoom();
      emptyRoom.queue = [];
      emptyRoom.currentIndex = -1;
      emptyRoom.track = null;
      expect(isListenTogetherPendingMemberControlSatisfied(emptied, emptyRoom)).assertTrue();
    });

    it('rewritesAMutationIntoTheLegacySnapshotFallback', 0, () => {
      const event = createListenTogetherEvent('SET_QUEUE');
      event.eventId = 'e1';
      event.queueMutation = new ListenTogetherQueueMutation();
      event.legacyQueueSnapshot = [track('1'), track('2')];

      const fallback = buildListenTogetherLegacyQueueMutationFallback(event, 'e1-legacy');
      expect(fallback === null).assertFalse();
      expect(fallback?.eventId).assertEqual('e1-legacy');
      expect(fallback?.queue?.length).assertEqual(2);
      expect(fallback?.queueMutation).assertNull();
      expect(fallback?.legacyQueueSnapshot).assertNull();
      // The original event is untouched (the rewrite works on a clone).
      expect(event.queueMutation === null).assertFalse();
      expect(event.legacyQueueSnapshot?.length).assertEqual(2);

      // Missing snapshot, mutation or a blank id all refuse the rewrite.
      const snapshotless = createListenTogetherEvent('SET_QUEUE');
      snapshotless.queueMutation = new ListenTogetherQueueMutation();
      expect(buildListenTogetherLegacyQueueMutationFallback(snapshotless, 'x')).assertNull();
      expect(buildListenTogetherLegacyQueueMutationFallback(event, '')).assertNull();
    });

    it('classifiesTheV2QueueMutationRejections', 0, () => {
      expect(isListenTogetherQueueMutationCompatibilityError('Queue Mutation is Invalid')).assertTrue();
      expect(isListenTogetherQueueMutationCompatibilityError('queue mutation base version is ahead'))
        .assertTrue();
      expect(isListenTogetherQueueMutationCompatibilityError('QUEUE MUTATION EVENT TYPE UNSUPPORTED'))
        .assertTrue();
      expect(isListenTogetherQueueMutationCompatibilityError('queue update queue required')).assertTrue();
      expect(isListenTogetherQueueMutationCompatibilityError('room not found')).assertFalse();
      expect(isListenTogetherQueueMutationCompatibilityError(null)).assertFalse();
      expect(isListenTogetherQueueMutationCompatibilityError('   ')).assertFalse();
    });
  });
}
