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
  if (state.track !== null) {
    return state.track.stableKey;
  }
  const index = state.currentIndex;
  if (index < 0 || index >= state.queue.length) {
    return null;
  }
  return state.queue[index].stableKey;
}

/** True once the room state reflects what a pending member request asked for. */
export function isListenTogetherPendingMemberControlSatisfied(
  event: ListenTogetherEvent,
  state: ListenTogetherRoomState | null,
  seekSatisfiedDriftMs: number = 1500
): boolean {
  if (state === null) {
    return false;
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
