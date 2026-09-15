// SPDX-License-Identifier: GPL-3.0
// Ported from the Android upstream project NeriPlayer (github.com/cwuom/NeriPlayer).

/**
 * Port of listentogether/protocol/ListenTogetherSocketEnvelope.kt.
 *
 * Every WebSocket frame (state broadcast, control ack, heartbeat, forwarded
 * member request) arrives in this single envelope; only `type` is guaranteed.
 */
import {
  JsonRecord,
  jsonRecordFromText,
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
  reqBoolean,
  reqString
} from './ListenTogetherJson';
import {
  ListenTogetherRoomState,
  listenTogetherRoomStateFromRecord,
  listenTogetherRoomStateToRecord
} from './ListenTogetherRoomModels';
import {
  ListenTogetherTrack,
  listenTogetherTrackFromRecord,
  listenTogetherTrackToRecord,
  listenTogetherTracksFromRecords,
  listenTogetherTracksToRecords
} from './ListenTogetherTrack';
import {
  ListenTogetherCause,
  listenTogetherCauseFromRecord,
  listenTogetherCauseToRecord
} from './ListenTogetherEventModels';
import {
  ListenTogetherControlResponse,
  listenTogetherControlResponseFromRecord,
  listenTogetherControlResponseToRecord
} from './ListenTogetherHttpMessages';

export class ListenTogetherSocketEnvelope {
  type: string = '';
  sessionId: string | null = null;
  userUuid: string | null = null;
  userId: string | null = null;
  nickname: string | null = null;
  role: string | null = null;
  autoPauseOnJoin: boolean = false;
  state: ListenTogetherRoomState | null = null;
  expectedPositionMs: number | null = null;
  nowMs: number | null = null;
  t: number | null = null;
  ok: boolean | null = null;
  result: ListenTogetherControlResponse | null = null;
  message: string | null = null;
  roomId: string | null = null;
  version: number | null = null;
  causedBy: ListenTogetherCause | null = null;
  track: ListenTogetherTrack | null = null;
  queue: ListenTogetherTrack[] | null = null;
  positionMs: number | null = null;
  currentIndex: number | null = null;
  requestTrackStableKey: string | null = null;
  shouldPlay: boolean | null = null;
  stateName: string | null = null;
  repeatMode: number | null = null;
  shuffleEnabled: boolean | null = null;
  clientTimeMs: number | null = null;
  clientInstanceId: string | null = null;
  clientSequence: number | null = null;
  requestSequence: number | null = null;
}

export function createListenTogetherSocketEnvelope(type: string): ListenTogetherSocketEnvelope {
  const envelope = new ListenTogetherSocketEnvelope();
  envelope.type = type;
  return envelope;
}

export function listenTogetherSocketEnvelopeFromRecord(
  raw: JsonRecord
): ListenTogetherSocketEnvelope {
  const envelope = new ListenTogetherSocketEnvelope();
  envelope.type = reqString(raw, 'type');
  envelope.sessionId = optString(raw, 'sessionId');
  envelope.userUuid = optString(raw, 'userUuid');
  envelope.userId = optString(raw, 'userId');
  envelope.nickname = optString(raw, 'nickname');
  envelope.role = optString(raw, 'role');
  envelope.autoPauseOnJoin = reqBoolean(raw, 'autoPauseOnJoin', false);
  const stateRecord = optRecord(raw, 'state');
  envelope.state = stateRecord === null ? null : listenTogetherRoomStateFromRecord(stateRecord);
  envelope.expectedPositionMs = optNumber(raw, 'expectedPositionMs');
  envelope.nowMs = optNumber(raw, 'nowMs');
  envelope.t = optNumber(raw, 't');
  envelope.ok = optBoolean(raw, 'ok');
  const resultRecord = optRecord(raw, 'result');
  envelope.result = resultRecord === null
    ? null
    : listenTogetherControlResponseFromRecord(resultRecord);
  envelope.message = optString(raw, 'message');
  envelope.roomId = optString(raw, 'roomId');
  envelope.version = optNumber(raw, 'version');
  const causeRecord = optRecord(raw, 'causedBy');
  envelope.causedBy = causeRecord === null ? null : listenTogetherCauseFromRecord(causeRecord);
  const trackRecord = optRecord(raw, 'track');
  envelope.track = trackRecord === null ? null : listenTogetherTrackFromRecord(trackRecord);
  const queueRecords = optRecordArray(raw, 'queue');
  envelope.queue = queueRecords === null ? null : listenTogetherTracksFromRecords(queueRecords);
  envelope.positionMs = optNumber(raw, 'positionMs');
  envelope.currentIndex = optNumber(raw, 'currentIndex');
  envelope.requestTrackStableKey = optString(raw, 'requestTrackStableKey');
  envelope.shouldPlay = optBoolean(raw, 'shouldPlay');
  envelope.stateName = optString(raw, 'stateName');
  envelope.repeatMode = optNumber(raw, 'repeatMode');
  envelope.shuffleEnabled = optBoolean(raw, 'shuffleEnabled');
  envelope.clientTimeMs = optNumber(raw, 'clientTimeMs');
  envelope.clientInstanceId = optString(raw, 'clientInstanceId');
  envelope.clientSequence = optNumber(raw, 'clientSequence');
  envelope.requestSequence = optNumber(raw, 'requestSequence');
  return envelope;
}

export function listenTogetherSocketEnvelopeToRecord(
  envelope: ListenTogetherSocketEnvelope
): JsonRecord {
  const raw: JsonRecord = {};
  raw['type'] = envelope.type;
  putString(raw, 'sessionId', envelope.sessionId);
  putString(raw, 'userUuid', envelope.userUuid);
  putString(raw, 'userId', envelope.userId);
  putString(raw, 'nickname', envelope.nickname);
  putString(raw, 'role', envelope.role);
  raw['autoPauseOnJoin'] = envelope.autoPauseOnJoin;
  putRecord(raw, 'state',
    envelope.state === null ? null : listenTogetherRoomStateToRecord(envelope.state));
  putNumber(raw, 'expectedPositionMs', envelope.expectedPositionMs);
  putNumber(raw, 'nowMs', envelope.nowMs);
  putNumber(raw, 't', envelope.t);
  putBoolean(raw, 'ok', envelope.ok);
  putRecord(raw, 'result',
    envelope.result === null ? null : listenTogetherControlResponseToRecord(envelope.result));
  putString(raw, 'message', envelope.message);
  putString(raw, 'roomId', envelope.roomId);
  putNumber(raw, 'version', envelope.version);
  putRecord(raw, 'causedBy',
    envelope.causedBy === null ? null : listenTogetherCauseToRecord(envelope.causedBy));
  putRecord(raw, 'track',
    envelope.track === null ? null : listenTogetherTrackToRecord(envelope.track));
  putRecordArray(raw, 'queue',
    envelope.queue === null ? null : listenTogetherTracksToRecords(envelope.queue));
  putNumber(raw, 'positionMs', envelope.positionMs);
  putNumber(raw, 'currentIndex', envelope.currentIndex);
  putString(raw, 'requestTrackStableKey', envelope.requestTrackStableKey);
  putBoolean(raw, 'shouldPlay', envelope.shouldPlay);
  putString(raw, 'stateName', envelope.stateName);
  putNumber(raw, 'repeatMode', envelope.repeatMode);
  putBoolean(raw, 'shuffleEnabled', envelope.shuffleEnabled);
  putNumber(raw, 'clientTimeMs', envelope.clientTimeMs);
  putString(raw, 'clientInstanceId', envelope.clientInstanceId);
  putNumber(raw, 'clientSequence', envelope.clientSequence);
  putNumber(raw, 'requestSequence', envelope.requestSequence);
  return raw;
}

/** Frame parser for the WebSocket client (M7.2): malformed frames yield null. */
export function listenTogetherSocketEnvelopeFromJson(
  text: string
): ListenTogetherSocketEnvelope | null {
  const raw = jsonRecordFromText(text);
  if (raw === null) {
    return null;
  }
  const envelope = listenTogetherSocketEnvelopeFromRecord(raw);
  return envelope.type.length === 0 ? null : envelope;
}
