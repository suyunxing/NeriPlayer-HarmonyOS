// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/compat/ListenTogetherEventCompatibility.kt: the
 * defensive rules that keep this client working against an older room server or
 * an older peer (missing `shouldPlay`, unsupported TRACK_FINISHED, stale
 * member requests).
 */
import {
  ListenTogetherEvent,
  cloneListenTogetherEvent
} from '../protocol/ListenTogetherEventModels';
import { ListenTogetherRoomState } from '../protocol/ListenTogetherRoomModels';
import { isListenTogetherSeekControlSatisfied } from '../playback/ListenTogetherPlaybackPosition';
import { listenTogetherCurrentStableKey } from '../playback/ListenTogetherPlaybackTrack';

const TRANSPORT_DRIVEN_COMMAND_TYPES: Set<string> = new Set<string>([
  'PLAY_PLAYLIST',
  'PLAY_FROM_QUEUE',
  'NEXT',
  'PREVIOUS',
  'SEEK',
  'HEARTBEAT',
  'LINK_READY'
]);

const TRACK_BOUND_MEMBER_CONTROL_TYPES: Set<string> = new Set<string>([
  'REQUEST_PLAY',
  'REQUEST_PAUSE',
  'REQUEST_SEEK'
]);

const STREAM_DEPENDENT_MEMBER_CONTROL_TYPES: Set<string> = new Set<string>([
  'REQUEST_PAUSE',
  'REQUEST_SEEK'
]);

const REQUEST_TYPE_PREFIX: string = 'REQUEST_';

/**
 * Upstream #359: rewrite a rejected V2 queue-mutation event into the legacy
 * full-snapshot form, using the snapshot stashed on the event at build time.
 */
export function buildListenTogetherLegacyQueueMutationFallback(
  event: ListenTogetherEvent,
  fallbackEventId: string
): ListenTogetherEvent | null {
  const snapshot = event.legacyQueueSnapshot;
  if (snapshot === null || event.queueMutation === null || fallbackEventId.length === 0) {
    return null;
  }
  const fallback = cloneListenTogetherEvent(event);
  fallback.eventId = fallbackEventId;
  fallback.queue = snapshot.slice();
  fallback.queueMutation = null;
  fallback.legacyQueueSnapshot = null;
  return fallback;
}

/** The error strings an older room server answers a V2 queue mutation with. */
export function isListenTogetherQueueMutationCompatibilityError(
  errorMessageText: string | null
): boolean {
  const normalized = errorMessageText === null ? '' : errorMessageText.trim().toLowerCase();
  return normalized.includes('queue mutation is invalid') ||
    normalized.includes('queue mutation base version is ahead') ||
    normalized.includes('queue mutation event type unsupported') ||
    normalized.includes('queue update queue required');
}

function trimmedOrNull(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** An absent `shouldPlay` is inferred from the local transport. */
export function resolveListenTogetherPlaybackCommandShouldPlay(
  commandType: string,
  commandShouldPlay: boolean | null,
  localTransportActive: boolean,
  localPlaying: boolean
): boolean {
  if (commandShouldPlay !== null) {
    return commandShouldPlay;
  }
  if (TRANSPORT_DRIVEN_COMMAND_TYPES.has(commandType)) {
    return localTransportActive || localPlaying;
  }
  return localPlaying;
}

export function resolveListenTogetherLinkReadyState(
  roomPlaybackState: string | null,
  localTransportActive: boolean,
  localPlaying: boolean
): string {
  const normalizedRoomState = roomPlaybackState === null
    ? null
    : roomPlaybackState.trim().toLowerCase();
  if (normalizedRoomState === 'playing' || localTransportActive || localPlaying) {
    return 'playing';
  }
  return 'paused';
}

/** A track-bound member request only counts while the room plays that track. */
export function isListenTogetherMemberControlTargetCurrent(
  eventType: string,
  requestedStableKey: string | null,
  currentStableKey: string | null
): boolean {
  if (!TRACK_BOUND_MEMBER_CONTROL_TYPES.has(eventType)) {
    return true;
  }
  const requested = trimmedOrNull(requestedStableKey);
  if (requested === null) {
    return false;
  }
  const current = trimmedOrNull(currentStableKey);
  if (current === null) {
    return false;
  }
  return requested === current;
}

export function shouldSuppressListenerControlWhileAwaitingStream(
  eventType: string,
  awaitingAuthoritativeStream: boolean,
  localTrackHasDirectStream: boolean
): boolean {
  if (!STREAM_DEPENDENT_MEMBER_CONTROL_TYPES.has(eventType)) {
    return false;
  }
  if (!awaitingAuthoritativeStream) {
    return false;
  }
  return !localTrackHasDirectStream;
}

function currentStableKeyForCompatibility(state: ListenTogetherRoomState): string | null {
  return listenTogetherCurrentStableKey(state);
}

/** True once the room state reflects what a pending member request asked for. */
export function isListenTogetherPendingMemberControlSatisfied(
  event: ListenTogetherEvent,
  state: ListenTogetherRoomState | null,
  seekSatisfiedDriftMs: number = 1500,
  committedEventId: string | null = null
): boolean {
  if (state === null) {
    return false;
  }
  // A V2 queue mutation only counts as satisfied once the room moved past the
  // base version *because of this very event* — a newer version from someone
  // else's mutation must not release our pending retry.
  const queueMutation = event.queueMutation;
  if (queueMutation !== null) {
    const rawEventId = event.eventId;
    const requestEventId = rawEventId !== null && rawEventId.trim().length > 0 ? rawEventId : null;
    if (requestEventId === null) {
      return false;
    }
    if (requestEventId !== committedEventId) {
      return false;
    }
    if (state.version <= queueMutation.baseRoomVersion) {
      return false;
    }
  }
  const requestedType = event.type.startsWith(REQUEST_TYPE_PREFIX)
    ? event.type.substring(REQUEST_TYPE_PREFIX.length)
    : event.type;
  if (requestedType === 'PLAY') {
    return state.playback.state === 'playing';
  }
  if (requestedType === 'PAUSE') {
    return state.playback.state === 'paused';
  }
  if (requestedType === 'SEEK') {
    if (event.positionMs === null) {
      return false;
    }
    return isListenTogetherSeekControlSatisfied(
      state.playback,
      event.positionMs,
      seekSatisfiedDriftMs
    );
  }
  if (requestedType === 'PLAYBACK_MODE') {
    const repeatModeSatisfied = event.repeatMode === null ||
      state.playback.repeatMode === event.repeatMode;
    const shuffleSatisfied = event.shuffleEnabled === null ||
      state.playback.shuffleEnabled === event.shuffleEnabled;
    return repeatModeSatisfied && shuffleSatisfied;
  }
  if (requestedType === 'SET_TRACK') {
    let requestedStableKey: string | null = null;
    if (event.track !== null) {
      requestedStableKey = event.track.stableKey;
    } else if (event.queue !== null) {
      const index = event.currentIndex === null ? -1 : event.currentIndex;
      if (index >= 0 && index < event.queue.length) {
        requestedStableKey = event.queue[index].stableKey;
      }
    }
    if (requestedStableKey === null) {
      return false;
    }
    return currentStableKeyForCompatibility(state) === requestedStableKey;
  }
  if (requestedType === 'SET_QUEUE') {
    // A mutation-shaped request carries no legacy queue; the committed
    // stableKey (or any stableKey at all) counts as reflected.
    if (queueMutation !== null && event.queue === null) {
      const requestedStableKey = event.track === null ? null : event.track.stableKey;
      const committedStableKey = currentStableKeyForCompatibility(state);
      return requestedStableKey === null || requestedStableKey === committedStableKey;
    }
    const requestedQueue = event.queue;
    const requestedIndex = event.currentIndex;
    if (requestedQueue === null || requestedIndex === null) {
      return false;
    }
    if (requestedQueue.length === 0) {
      return requestedIndex === -1 &&
        state.queue.length === 0 &&
        state.currentIndex === -1 &&
        state.track === null;
    }
    if (requestedIndex < 0 || requestedIndex >= requestedQueue.length ||
      state.currentIndex !== requestedIndex) {
      return false;
    }
    if (state.queue.length !== requestedQueue.length) {
      return false;
    }
    for (let index = 0; index < requestedQueue.length; index++) {
      if (state.queue[index].stableKey !== requestedQueue[index].stableKey) {
        return false;
      }
    }
    const requestedStableKey = requestedQueue[requestedIndex].stableKey;
    return currentStableKeyForCompatibility(state) === requestedStableKey;
  }
  return false;
}

/** Recognizes the old servers that reject the TRACK_FINISHED event type. */
export function isUnsupportedTrackFinishedEventError(errorMessage: string | null): boolean {
  const normalized = errorMessage === null ? '' : errorMessage.trim().toLowerCase();
  if (!normalized.includes('track_finished')) {
    return false;
  }
  // The upstream server shipped the typo'd message for a while.
  return normalized.includes('unsupported event type') ||
    normalized.includes('unsuppported event type');
}

/** Rewrites TRACK_FINISHED into SET_TRACK/PAUSE for those servers. */
export function buildTrackFinishedLegacyFallbackEvent(
  event: ListenTogetherEvent,
  isController: boolean,
  nowMs: number,
  eventIdFactory: () => string
): ListenTogetherEvent | null {
  if (!isController || event.type !== 'TRACK_FINISHED') {
    return null;
  }
  const nextIndex = event.nextIndex === null ? event.currentIndex : event.nextIndex;
  const fallback = cloneListenTogetherEvent(event);
  fallback.eventId = eventIdFactory();
  fallback.clientTimeMs = nowMs;
  fallback.nextIndex = null;
  fallback.finishedTrackStableKey = null;
  if (event.shouldPlay === true && nextIndex !== null) {
    fallback.type = 'SET_TRACK';
    fallback.positionMs = 0;
    fallback.currentIndex = nextIndex;
    if (event.track === null && event.queue !== null &&
      nextIndex >= 0 && nextIndex < event.queue.length) {
      fallback.track = event.queue[nextIndex];
    }
    fallback.shouldPlay = true;
    fallback.state = 'playing';
    return fallback;
  }
  fallback.type = 'PAUSE';
  fallback.shouldPlay = false;
  fallback.state = 'paused';
  return fallback;
}
