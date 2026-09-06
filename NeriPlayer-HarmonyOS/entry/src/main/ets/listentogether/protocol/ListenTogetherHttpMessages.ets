/**
 * Port of listentogether/protocol/ListenTogetherHttpMessages.kt: the room HTTP
 * API payloads (create/join/leave requests and their responses).
 */
import {
  JsonRecord,
  jsonRecordFromText,
  optNumber,
  optRecord,
  optRecordArray,
  optString,
  putNumber,
  putRecord,
  putRecordArray,
  putString,
  reqBoolean,
  reqNumber,
  reqString
} from './ListenTogetherJson';
import {
  ListenTogetherRoomSettings,
  ListenTogetherRoomState,
  listenTogetherRoomSettingsFromRecord,
  listenTogetherRoomSettingsToRecord,
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
  ListenTogetherAppliedEvent,
  listenTogetherAppliedEventFromRecord,
  listenTogetherAppliedEventToRecord
} from './ListenTogetherEventModels';

export class ListenTogetherInitialSnapshot {
  queue: ListenTogetherTrack[] = [];
  currentIndex: number = 0;
  track: ListenTogetherTrack | null = null;
  settings: ListenTogetherRoomSettings = new ListenTogetherRoomSettings();
  isPlaying: boolean = false;
  positionMs: number = 0;
  repeatMode: number = 0;
  shuffleEnabled: boolean = false;
}

export class ListenTogetherCreateRoomRequest {
  userUuid: string = '';
  nickname: string = '';
  initialSnapshot: ListenTogetherInitialSnapshot = new ListenTogetherInitialSnapshot();
}

export class ListenTogetherJoinRoomRequest {
  userUuid: string = '';
  nickname: string = '';
  memberSecret: string | null = null;
  joinSecret: string | null = null;
}

export class ListenTogetherRoomResponse {
  ok: boolean = false;
  roomId: string | null = null;
  userUuid: string | null = null;
  userId: string | null = null;
  nickname: string | null = null;
  role: string | null = null;
  memberSecret: string | null = null;
  joinSecret: string | null = null;
  autoPauseOnJoin: boolean = false;
  token: string | null = null;
  state: ListenTogetherRoomState | null = null;
  wsUrl: string | null = null;
  error: string | null = null;
}

export class ListenTogetherStateResponse {
  ok: boolean = false;
  state: ListenTogetherRoomState | null = null;
  expectedPositionMs: number | null = null;
  serverNowMs: number | null = null;
  autoPauseOnJoin: boolean = false;
  error: string | null = null;
}

export class ListenTogetherControlResponse {
  ok: boolean = false;
  applied: ListenTogetherAppliedEvent | null = null;
  error: string | null = null;
}

export class ListenTogetherLeaveRoomResponse {
  ok: boolean = false;
  applied: ListenTogetherAppliedEvent | null = null;
  error: string | null = null;
}

/** Kotlin `@Serializable object ListenTogetherLeaveRoomRequest` serializes as `{}`. */
export const LISTEN_TOGETHER_LEAVE_ROOM_REQUEST_JSON: string = '{}';

export function listenTogetherInitialSnapshotToRecord(
  snapshot: ListenTogetherInitialSnapshot
): JsonRecord {
  const raw: JsonRecord = {};
  putRecordArray(raw, 'queue', listenTogetherTracksToRecords(snapshot.queue));
  raw['currentIndex'] = snapshot.currentIndex;
  putRecord(raw, 'track',
    snapshot.track === null ? null : listenTogetherTrackToRecord(snapshot.track));
  putRecord(raw, 'settings', listenTogetherRoomSettingsToRecord(snapshot.settings));
  raw['isPlaying'] = snapshot.isPlaying;
  raw['positionMs'] = snapshot.positionMs;
  raw['repeatMode'] = snapshot.repeatMode;
  raw['shuffleEnabled'] = snapshot.shuffleEnabled;
  return raw;
}

export function listenTogetherInitialSnapshotFromRecord(
  raw: JsonRecord
): ListenTogetherInitialSnapshot {
  const snapshot = new ListenTogetherInitialSnapshot();
  const queueRecords = optRecordArray(raw, 'queue');
  if (queueRecords !== null) {
    snapshot.queue = listenTogetherTracksFromRecords(queueRecords);
  }
  snapshot.currentIndex = reqNumber(raw, 'currentIndex', 0);
  const trackRecord = optRecord(raw, 'track');
  snapshot.track = trackRecord === null ? null : listenTogetherTrackFromRecord(trackRecord);
  const settingsRecord = optRecord(raw, 'settings');
  snapshot.settings = settingsRecord === null
    ? new ListenTogetherRoomSettings()
    : listenTogetherRoomSettingsFromRecord(settingsRecord);
  snapshot.isPlaying = reqBoolean(raw, 'isPlaying', false);
  snapshot.positionMs = reqNumber(raw, 'positionMs', 0);
  snapshot.repeatMode = reqNumber(raw, 'repeatMode', 0);
  snapshot.shuffleEnabled = reqBoolean(raw, 'shuffleEnabled', false);
  return snapshot;
}

export function listenTogetherCreateRoomRequestToRecord(
  request: ListenTogetherCreateRoomRequest
): JsonRecord {
  const raw: JsonRecord = {};
  raw['userUuid'] = request.userUuid;
  raw['nickname'] = request.nickname;
  putRecord(raw, 'initialSnapshot',
    listenTogetherInitialSnapshotToRecord(request.initialSnapshot));
  return raw;
}

export function listenTogetherJoinRoomRequestToRecord(
  request: ListenTogetherJoinRoomRequest
): JsonRecord {
  const raw: JsonRecord = {};
  raw['userUuid'] = request.userUuid;
  raw['nickname'] = request.nickname;
  putString(raw, 'memberSecret', request.memberSecret);
  putString(raw, 'joinSecret', request.joinSecret);
  return raw;
}

export function listenTogetherRoomResponseFromRecord(raw: JsonRecord): ListenTogetherRoomResponse {
  const response = new ListenTogetherRoomResponse();
  response.ok = reqBoolean(raw, 'ok', false);
  response.roomId = optString(raw, 'roomId');
  response.userUuid = optString(raw, 'userUuid');
  response.userId = optString(raw, 'userId');
  response.nickname = optString(raw, 'nickname');
  response.role = optString(raw, 'role');
  response.memberSecret = optString(raw, 'memberSecret');
  response.joinSecret = optString(raw, 'joinSecret');
  response.autoPauseOnJoin = reqBoolean(raw, 'autoPauseOnJoin', false);
  response.token = optString(raw, 'token');
  const stateRecord = optRecord(raw, 'state');
  response.state = stateRecord === null ? null : listenTogetherRoomStateFromRecord(stateRecord);
  response.wsUrl = optString(raw, 'wsUrl');
  response.error = optString(raw, 'error');
  return response;
}

export function listenTogetherRoomResponseToRecord(
  response: ListenTogetherRoomResponse
): JsonRecord {
  const raw: JsonRecord = {};
  raw['ok'] = response.ok;
  putString(raw, 'roomId', response.roomId);
  putString(raw, 'userUuid', response.userUuid);
  putString(raw, 'userId', response.userId);
  putString(raw, 'nickname', response.nickname);
  putString(raw, 'role', response.role);
  putString(raw, 'memberSecret', response.memberSecret);
  putString(raw, 'joinSecret', response.joinSecret);
  raw['autoPauseOnJoin'] = response.autoPauseOnJoin;
  putString(raw, 'token', response.token);
  putRecord(raw, 'state',
    response.state === null ? null : listenTogetherRoomStateToRecord(response.state));
  putString(raw, 'wsUrl', response.wsUrl);
  putString(raw, 'error', response.error);
  return raw;
}

export function listenTogetherStateResponseFromRecord(
  raw: JsonRecord
): ListenTogetherStateResponse {
  const response = new ListenTogetherStateResponse();
  response.ok = reqBoolean(raw, 'ok', false);
  const stateRecord = optRecord(raw, 'state');
  response.state = stateRecord === null ? null : listenTogetherRoomStateFromRecord(stateRecord);
  response.expectedPositionMs = optNumber(raw, 'expectedPositionMs');
  response.serverNowMs = optNumber(raw, 'serverNowMs');
  response.autoPauseOnJoin = reqBoolean(raw, 'autoPauseOnJoin', false);
  response.error = optString(raw, 'error');
  return response;
}

export function listenTogetherControlResponseFromRecord(
  raw: JsonRecord
): ListenTogetherControlResponse {
  const response = new ListenTogetherControlResponse();
  response.ok = reqBoolean(raw, 'ok', false);
  const appliedRecord = optRecord(raw, 'applied');
  response.applied = appliedRecord === null
    ? null
    : listenTogetherAppliedEventFromRecord(appliedRecord);
  response.error = optString(raw, 'error');
  return response;
}

export function listenTogetherControlResponseToRecord(
  response: ListenTogetherControlResponse
): JsonRecord {
  const raw: JsonRecord = {};
  raw['ok'] = response.ok;
  putRecord(raw, 'applied',
    response.applied === null ? null : listenTogetherAppliedEventToRecord(response.applied));
  putString(raw, 'error', response.error);
  return raw;
}

export function listenTogetherLeaveRoomResponseFromRecord(
  raw: JsonRecord
): ListenTogetherLeaveRoomResponse {
  const response = new ListenTogetherLeaveRoomResponse();
  response.ok = reqBoolean(raw, 'ok', false);
  const appliedRecord = optRecord(raw, 'applied');
  response.applied = appliedRecord === null
    ? null
    : listenTogetherAppliedEventFromRecord(appliedRecord);
  response.error = optString(raw, 'error');
  return response;
}

/** Convenience parsers for the HTTP layer (M7.2): malformed bodies yield null. */
export function listenTogetherRoomResponseFromJson(
  text: string
): ListenTogetherRoomResponse | null {
  const raw = jsonRecordFromText(text);
  return raw === null ? null : listenTogetherRoomResponseFromRecord(raw);
}

export function listenTogetherStateResponseFromJson(
  text: string
): ListenTogetherStateResponse | null {
  const raw = jsonRecordFromText(text);
  return raw === null ? null : listenTogetherStateResponseFromRecord(raw);
}

export function listenTogetherControlResponseFromJson(
  text: string
): ListenTogetherControlResponse | null {
  const raw = jsonRecordFromText(text);
  return raw === null ? null : listenTogetherControlResponseFromRecord(raw);
}

export function listenTogetherLeaveRoomResponseFromJson(
  text: string
): ListenTogetherLeaveRoomResponse | null {
  const raw = jsonRecordFromText(text);
  return raw === null ? null : listenTogetherLeaveRoomResponseFromRecord(raw);
}

/** The error surfaced to the user when a response carries `ok: false`. */
export function listenTogetherResponseErrorOrNull(
  ok: boolean,
  error: string | null
): string | null {
  if (ok) {
    return null;
  }
  const trimmed = error === null ? '' : error.trim();
  return trimmed.length > 0 ? trimmed : '一起听服务端返回了未知错误';
}
