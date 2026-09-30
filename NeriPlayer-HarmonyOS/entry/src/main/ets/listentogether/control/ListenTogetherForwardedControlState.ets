// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/control/ListenTogetherForwardedControlState.kt.
 *
 * When the controller commits a listener's forwarded request, the server has not
 * yet published the resulting room state. The controller therefore builds the
 * state it just caused, applies it locally, and lets the real one overwrite it
 * when it arrives — the version is deliberately left untouched, so the
 * authoritative state always wins the version gate.
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

export function buildListenTogetherForwardedControlSyntheticState(
  currentState: ListenTogetherRoomState,
  message: ListenTogetherSocketEnvelope,
  committedEvent: ListenTogetherEvent,
  nowMs: number
): ListenTogetherRoomState {
  // An empty forwarded queue means "do not touch the queue", not "clear it": a
  // request that only asks for play/pause carries no queue worth adopting.
  const incomingQueue = message.queue;
  const nextQueue: ListenTogetherTrack[] = incomingQueue !== null && incomingQueue.length > 0
    ? mergeListenTogetherCurrentTrack(
        incomingQueue,
        message.currentIndex ?? currentState.currentIndex,
        message.track
      )
    : mergeListenTogetherCurrentTrack(currentState.queue, currentState.currentIndex, currentState.track);

  const rawIndex = message.currentIndex ?? currentState.currentIndex;
  const maxIndex = Math.max(nextQueue.length - 1, 0);
  const nextIndex = Math.min(Math.max(rawIndex, 0), maxIndex);
  const queueTrack: ListenTogetherTrack | null = nextIndex < nextQueue.length ? nextQueue[nextIndex] : null;
  const nextTrack = message.track ?? queueTrack ?? currentState.track;

  // The committed event's own type is authoritative for transport: it is what the
  // controller actually did. Everything else falls back to what the request asked
  // for, and finally to the state we already had.
  let nextPlaybackState: string;
  if (committedEvent.type === 'PLAY') {
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
