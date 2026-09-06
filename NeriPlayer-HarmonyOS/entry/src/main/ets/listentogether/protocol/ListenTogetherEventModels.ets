/**
 * Port of listentogether/protocol/ListenTogetherEventModels.kt: the cause
 * attached to a broadcast, the applied-event acknowledgement and the outbound
 * control event.
 *
 * `queue` stays nullable (absent) instead of defaulting to an empty list: the
 * server treats an absent queue as "do not touch the queue" while an empty
 * queue is a real (rejected) request payload.
 */
import {
  JsonRecord,
  optBoolean,
  optNumber,
  optRecord,
  optRecordArray,
  optString,
  putBoolean,
  putNumber,
  putRecord,
  putRecordArray,
  putString,
  reqString
} from './ListenTogetherJson';
import {
  ListenTogetherRoomSettings,
  ListenTogetherRoomState,
  cloneListenTogetherRoomSettings,
  listenTogetherRoomSettingsFromRecord,
  listenTogetherRoomSettingsToRecord,
  listenTogetherRoomStateFromRecord,
  listenTogetherRoomStateToRecord
} from './ListenTogetherRoomModels';
import {
  ListenTogetherTrack,
  cloneListenTogetherTrack,
  listenTogetherTrackFromRecord,
  listenTogetherTrackToRecord,
  listenTogetherTracksFromRecords,
  listenTogetherTracksToRecords
} from './ListenTogetherTrack';

export class ListenTogetherCause {
  userUuid: string | null = null;
  userId: string | null = null;
  nickname: string | null = null;
  eventId: string | null = null;
  type: string | null = null;
}

export class ListenTogetherAppliedEvent {
  type: string = '';
  roomId: string | null = null;
  version: number | null = null;
  state: ListenTogetherRoomState | null = null;
  expectedPositionMs: number | null = null;
  nowMs: number | null = null;
  causedBy: ListenTogetherCause | null = null;
}

export class ListenTogetherEvent {
  type: string = '';
  eventId: string | null = null;
  clientTimeMs: number | null = null;
  clientInstanceId: string | null = null;
  clientSequence: number | null = null;
  positionMs: number | null = null;
  currentIndex: number | null = null;
  nextIndex: number | null = null;
  track: ListenTogetherTrack | null = null;
  queue: ListenTogetherTrack[] | null = null;
  roomSettings: ListenTogetherRoomSettings | null = null;
  shouldPlay: boolean | null = null;
  state: string | null = null;
  repeatMode: number | null = null;
  shuffleEnabled: boolean | null = null;
  requestTrackStableKey: string | null = null;
  forceRefresh: boolean | null = null;
  finishedTrackStableKey: string | null = null;
}

export function createListenTogetherCause(
  userUuid: string | null,
  type: string | null,
  eventId: string | null = null
): ListenTogetherCause {
  const cause = new ListenTogetherCause();
  cause.userUuid = userUuid;
  cause.type = type;
  cause.eventId = eventId;
  return cause;
}

export function createListenTogetherEvent(type: string): ListenTogetherEvent {
  const event = new ListenTogetherEvent();
  event.type = type;
  return event;
}

/** Kotlin `copy()` equivalent: callers mutate the clone. */
export function cloneListenTogetherEvent(event: ListenTogetherEvent): ListenTogetherEvent {
  const copy = new ListenTogetherEvent();
  copy.type = event.type;
  copy.eventId = event.eventId;
  copy.clientTimeMs = event.clientTimeMs;
  copy.clientInstanceId = event.clientInstanceId;
  copy.clientSequence = event.clientSequence;
  copy.positionMs = event.positionMs;
  copy.currentIndex = event.currentIndex;
  copy.nextIndex = event.nextIndex;
  copy.track = event.track === null ? null : cloneListenTogetherTrack(event.track);
  if (event.queue === null) {
    copy.queue = null;
  } else {
    const queue: ListenTogetherTrack[] = [];
    for (const track of event.queue) {
      queue.push(cloneListenTogetherTrack(track));
    }
    copy.queue = queue;
  }
  copy.roomSettings = event.roomSettings === null
    ? null
    : cloneListenTogetherRoomSettings(event.roomSettings);
  copy.shouldPlay = event.shouldPlay;
  copy.state = event.state;
  copy.repeatMode = event.repeatMode;
  copy.shuffleEnabled = event.shuffleEnabled;
  copy.requestTrackStableKey = event.requestTrackStableKey;
  copy.forceRefresh = event.forceRefresh;
  copy.finishedTrackStableKey = event.finishedTrackStableKey;
  return copy;
}

export function listenTogetherCauseFromRecord(raw: JsonRecord): ListenTogetherCause {
  const cause = new ListenTogetherCause();
  cause.userUuid = optString(raw, 'userUuid');
  cause.userId = optString(raw, 'userId');
  cause.nickname = optString(raw, 'nickname');
  cause.eventId = optString(raw, 'eventId');
  cause.type = optString(raw, 'type');
  return cause;
}

export function listenTogetherCauseToRecord(cause: ListenTogetherCause): JsonRecord {
  const raw: JsonRecord = {};
  putString(raw, 'userUuid', cause.userUuid);
  putString(raw, 'userId', cause.userId);
  putString(raw, 'nickname', cause.nickname);
  putString(raw, 'eventId', cause.eventId);
  putString(raw, 'type', cause.type);
  return raw;
}

export function listenTogetherAppliedEventFromRecord(raw: JsonRecord): ListenTogetherAppliedEvent {
  const applied = new ListenTogetherAppliedEvent();
  applied.type = reqString(raw, 'type');
  applied.roomId = optString(raw, 'roomId');
  applied.version = optNumber(raw, 'version');
  const stateRecord = optRecord(raw, 'state');
  applied.state = stateRecord === null ? null : listenTogetherRoomStateFromRecord(stateRecord);
  applied.expectedPositionMs = optNumber(raw, 'expectedPositionMs');
  applied.nowMs = optNumber(raw, 'nowMs');
  const causeRecord = optRecord(raw, 'causedBy');
  applied.causedBy = causeRecord === null ? null : listenTogetherCauseFromRecord(causeRecord);
  return applied;
}

export function listenTogetherAppliedEventToRecord(
  applied: ListenTogetherAppliedEvent
): JsonRecord {
  const raw: JsonRecord = {};
  raw['type'] = applied.type;
  putString(raw, 'roomId', applied.roomId);
  putNumber(raw, 'version', applied.version);
  putRecord(raw, 'state',
    applied.state === null ? null : listenTogetherRoomStateToRecord(applied.state));
  putNumber(raw, 'expectedPositionMs', applied.expectedPositionMs);
  putNumber(raw, 'nowMs', applied.nowMs);
  putRecord(raw, 'causedBy',
    applied.causedBy === null ? null : listenTogetherCauseToRecord(applied.causedBy));
  return raw;
}

export function listenTogetherEventFromRecord(raw: JsonRecord): ListenTogetherEvent {
  const event = new ListenTogetherEvent();
  event.type = reqString(raw, 'type');
  event.eventId = optString(raw, 'eventId');
  event.clientTimeMs = optNumber(raw, 'clientTimeMs');
  event.clientInstanceId = optString(raw, 'clientInstanceId');
  event.clientSequence = optNumber(raw, 'clientSequence');
  event.positionMs = optNumber(raw, 'positionMs');
  event.currentIndex = optNumber(raw, 'currentIndex');
  event.nextIndex = optNumber(raw, 'nextIndex');
  const trackRecord = optRecord(raw, 'track');
  event.track = trackRecord === null ? null : listenTogetherTrackFromRecord(trackRecord);
  const queueRecords = optRecordArray(raw, 'queue');
  event.queue = queueRecords === null ? null : listenTogetherTracksFromRecords(queueRecords);
  const settingsRecord = optRecord(raw, 'roomSettings');
  event.roomSettings = settingsRecord === null
    ? null
    : listenTogetherRoomSettingsFromRecord(settingsRecord);
  event.shouldPlay = optBoolean(raw, 'shouldPlay');
  event.state = optString(raw, 'state');
  event.repeatMode = optNumber(raw, 'repeatMode');
  event.shuffleEnabled = optBoolean(raw, 'shuffleEnabled');
  event.requestTrackStableKey = optString(raw, 'requestTrackStableKey');
  event.forceRefresh = optBoolean(raw, 'forceRefresh');
  event.finishedTrackStableKey = optString(raw, 'finishedTrackStableKey');
  return event;
}

export function listenTogetherEventToRecord(event: ListenTogetherEvent): JsonRecord {
  const raw: JsonRecord = {};
  raw['type'] = event.type;
  putString(raw, 'eventId', event.eventId);
  putNumber(raw, 'clientTimeMs', event.clientTimeMs);
  putString(raw, 'clientInstanceId', event.clientInstanceId);
  putNumber(raw, 'clientSequence', event.clientSequence);
  putNumber(raw, 'positionMs', event.positionMs);
  putNumber(raw, 'currentIndex', event.currentIndex);
  putNumber(raw, 'nextIndex', event.nextIndex);
  putRecord(raw, 'track', event.track === null ? null : listenTogetherTrackToRecord(event.track));
  putRecordArray(raw, 'queue',
    event.queue === null ? null : listenTogetherTracksToRecords(event.queue));
  putRecord(raw, 'roomSettings',
    event.roomSettings === null ? null : listenTogetherRoomSettingsToRecord(event.roomSettings));
  putBoolean(raw, 'shouldPlay', event.shouldPlay);
  putString(raw, 'state', event.state);
  putNumber(raw, 'repeatMode', event.repeatMode);
  putBoolean(raw, 'shuffleEnabled', event.shuffleEnabled);
  putString(raw, 'requestTrackStableKey', event.requestTrackStableKey);
  putBoolean(raw, 'forceRefresh', event.forceRefresh);
  putString(raw, 'finishedTrackStableKey', event.finishedTrackStableKey);
  return raw;
}
