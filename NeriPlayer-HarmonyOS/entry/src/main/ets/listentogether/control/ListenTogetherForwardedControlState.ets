// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/control/ListenTogetherForwardedControlState.kt,
 * rewritten at upstream #359 (squashed 3cfd7037): when the controller commits
 * a listener's forwarded request, the server has not yet published the
 * resulting room state. The controller therefore builds the state it just
 * caused, applies it locally, and lets the real one overwrite it when it
 * arrives — the version is deliberately left untouched, so the authoritative
 * state always wins the version gate.
 *
 * A V2 mutation is applied to the current queue through the mutation applier;
 * a legacy snapshot replaces the queue outright; and when neither is present
 * the current queue stays, because an absent queue means "do not touch".
 */
import {
  ListenTogetherRoomState,
  cloneListenTogetherPlaybackState,
  cloneListenTogetherRoomState
} from '../protocol/ListenTogetherRoomModels';
import { ListenTogetherEvent } from '../protocol/ListenTogetherEventModels';
import { ListenTogetherSocketEnvelope } from '../protocol/ListenTogetherSocketEnvelope';
import { ListenTogetherTrack } from '../protocol/ListenTogetherTrack';
import { mergeListenTogetherCurrentTrack } from '../playback/ListenTogetherShareableQueueSnapshot';
import {
  listenTogetherCurrentTrack,
  resolveListenTogetherQueueIndex
} from '../playback/ListenTogetherPlaybackTrack';
import {
  applyListenTogetherQueueMutation,
  ListenTogetherQueueMutationResult
} from './ListenTogetherQueueMutationApplier';

export function buildListenTogetherForwardedControlSyntheticState(
  currentState: ListenTogetherRoomState,
  message: ListenTogetherSocketEnvelope,
  committedEvent: ListenTogetherEvent,
  nowMs: number
): ListenTogetherRoomState {
  const currentQueue = mergeListenTogetherCurrentTrack(
    currentState.queue,
    currentState.currentIndex,
    currentState.track
  );

  // A V2 mutation describes the diff against the current queue; applying it
  // locally mirrors what the server will do with the same base version.
  let mutationResult: ListenTogetherQueueMutationResult | null = null;
  if (message.queueMutation !== null) {
    mutationResult = applyListenTogetherQueueMutation(
      currentQueue,
      currentState.currentIndex,
      message.queueMutation,
      message.track === null ? null : message.track.stableKey
    );
  }
  // An empty legacy queue means "do not touch" for everything except an
  // explicit SET_QUEUE, where clearing the queue is the whole request.
  let legacyQueueSnapshot: ListenTogetherTrack[] | null = null;
  if (message.queue !== null &&
    (message.queue.length > 0 || committedEvent.type === 'SET_QUEUE')) {
    legacyQueueSnapshot = message.queue;
  }
  const queueWithoutCurrentTrack: ListenTogetherTrack[] = mutationResult !== null
    ? mutationResult.queue
    : (legacyQueueSnapshot ?? currentQueue);

  // Where the current index lands: a track selection honours the mutation's
  // target, everything else keeps the requested/previous index — then the
  // preferred stableKey gets the final say when the index no longer names it.
  const isTrackSelection = committedEvent.type === 'SET_TRACK';
  let requestedIndex: number;
  if (isTrackSelection) {
    requestedIndex = mutationResult !== null && mutationResult.targetCurrentIndex !== null
      ? mutationResult.targetCurrentIndex
      : (mutationResult !== null ? mutationResult.currentIndex : -1);
    if (requestedIndex < 0) {
      requestedIndex = message.currentIndex ?? currentState.currentIndex;
    }
  } else {
    requestedIndex = mutationResult !== null
      ? mutationResult.currentIndex
      : (message.currentIndex ?? currentState.currentIndex);
  }
  let preferredStableKey: string | null;
  if (isTrackSelection) {
    preferredStableKey = message.requestTrackStableKey ??
      committedEvent.requestTrackStableKey ??
      (message.track === null ? null : message.track.stableKey) ??
      (committedEvent.track === null ? null : committedEvent.track.stableKey);
  } else {
    preferredStableKey = message.requestTrackStableKey ?? committedEvent.requestTrackStableKey;
  }
  const nextIndex = resolveListenTogetherQueueIndex(queueWithoutCurrentTrack, requestedIndex, preferredStableKey);
  const nextQueue = mergeListenTogetherCurrentTrack(queueWithoutCurrentTrack, nextIndex, message.track);

  let nextTrack: ListenTogetherTrack | null;
  if (nextQueue.length === 0) {
    nextTrack = null;
  } else {
    const queued = nextIndex >= 0 && nextIndex < nextQueue.length ? nextQueue[nextIndex] : null;
    nextTrack = queued ?? message.track ?? listenTogetherCurrentTrack(currentState);
  }

  // The committed event's own type is authoritative for transport: it is what
  // the controller actually did. Everything else falls back to what the request
  // asked for, and finally to the state we already had.
  let nextPlaybackState: string;
  if (nextQueue.length === 0) {
    nextPlaybackState = 'paused';
  } else if (committedEvent.type === 'PLAY') {
    nextPlaybackState = 'playing';
  } else if (committedEvent.type === 'PAUSE') {
    nextPlaybackState = 'paused';
  } else if (message.stateName !== null) {
    nextPlaybackState = message.stateName;
  } else {
    nextPlaybackState = message.shouldPlay === true ? 'playing' : currentState.playback.state;
  }

  const next = cloneListenTogetherRoomState(currentState);
  next.queue = nextQueue;
  next.currentIndex = nextIndex;
  next.track = nextTrack;
  const playback = cloneListenTogetherPlaybackState(currentState.playback);
  playback.state = nextPlaybackState;
  playback.basePositionMs = Math.max(committedEvent.positionMs ?? message.expectedPositionMs ?? 0, 0);
  // Re-basing the timestamp to now is what makes the synthetic state usable: the
  // position must be read as "this, as of this instant".
  playback.baseTimestampMs = nowMs;
  playback.repeatMode = committedEvent.repeatMode ?? currentState.playback.repeatMode;
  playback.shuffleEnabled = committedEvent.shuffleEnabled ?? currentState.playback.shuffleEnabled;
  next.playback = playback;
  return next;
}
