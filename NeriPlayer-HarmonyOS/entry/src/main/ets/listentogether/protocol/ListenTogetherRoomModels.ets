/**
 * Port of listentogether/protocol/ListenTogetherRoomModels.kt: room settings,
 * members, the authoritative playback state and the versioned room snapshot.
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
  reqBoolean,
  reqNumber,
  reqString
} from './ListenTogetherJson';
import {
  ListenTogetherTrack,
  cloneListenTogetherTrack,
  listenTogetherTrackFromRecord,
  listenTogetherTrackToRecord,
  listenTogetherTracksFromRecords,
  listenTogetherTracksToRecords
} from './ListenTogetherTrack';

export class ListenTogetherRoomStatuses {
  static readonly ACTIVE: string = 'active';
  static readonly CONTROLLER_OFFLINE: string = 'controller_offline';
  static readonly CLOSED: string = 'closed';
}

export class ListenTogetherRoomSettings {
  allowMemberControl: boolean = true;
  autoPauseOnMemberChange: boolean = true;
  shareAudioLinks: boolean = true;
}

export class ListenTogetherMember {
  userUuid: string = '';
  nickname: string = '';
  userId: string | null = null;
  role: string = '';
  joinedAt: number = 0;
}

export class ListenTogetherPlaybackState {
  state: string = 'paused';
  basePositionMs: number = 0;
  baseTimestampMs: number = 0;
  playbackRate: number = 1.0;
  repeatMode: number | null = null;
  shuffleEnabled: boolean | null = null;
}

export class ListenTogetherRoomState {
  roomId: string = '';
  version: number = 0;
  schemaVersion: number = 1;
  controllerUserUuid: string | null = null;
  controllerUserId: string | null = null;
  controllerHeartbeatAt: number | null = null;
  settings: ListenTogetherRoomSettings = new ListenTogetherRoomSettings();
  members: ListenTogetherMember[] = [];
  queue: ListenTogetherTrack[] = [];
  currentIndex: number = 0;
  track: ListenTogetherTrack | null = null;
  playback: ListenTogetherPlaybackState = new ListenTogetherPlaybackState();
  controllerOfflineSince: number | null = null;
  roomStatus: string = ListenTogetherRoomStatuses.ACTIVE;
  closedReason: string | null = null;
  updatedAt: number = 0;
}

/** `ListenTogetherRoomSettings?.normalized()` from session/ListenTogetherRoomSettingsPolicy.kt. */
export function normalizedListenTogetherRoomSettings(
  settings: ListenTogetherRoomSettings | null
): ListenTogetherRoomSettings {
  return settings === null ? new ListenTogetherRoomSettings() : settings;
}

export function createListenTogetherRoomState(
  roomId: string,
  version: number
): ListenTogetherRoomState {
  const state = new ListenTogetherRoomState();
  state.roomId = roomId;
  state.version = version;
  return state;
}

export function cloneListenTogetherRoomSettings(
  settings: ListenTogetherRoomSettings
): ListenTogetherRoomSettings {
  const copy = new ListenTogetherRoomSettings();
  copy.allowMemberControl = settings.allowMemberControl;
  copy.autoPauseOnMemberChange = settings.autoPauseOnMemberChange;
  copy.shareAudioLinks = settings.shareAudioLinks;
  return copy;
}

export function cloneListenTogetherPlaybackState(
  playback: ListenTogetherPlaybackState
): ListenTogetherPlaybackState {
  const copy = new ListenTogetherPlaybackState();
  copy.state = playback.state;
  copy.basePositionMs = playback.basePositionMs;
  copy.baseTimestampMs = playback.baseTimestampMs;
  copy.playbackRate = playback.playbackRate;
  copy.repeatMode = playback.repeatMode;
  copy.shuffleEnabled = playback.shuffleEnabled;
  return copy;
}

export function cloneListenTogetherMember(member: ListenTogetherMember): ListenTogetherMember {
  const copy = new ListenTogetherMember();
  copy.userUuid = member.userUuid;
  copy.nickname = member.nickname;
  copy.userId = member.userId;
  copy.role = member.role;
  copy.joinedAt = member.joinedAt;
  return copy;
}

/** Kotlin `copy()` equivalent: deep enough that callers can mutate the clone. */
export function cloneListenTogetherRoomState(
  state: ListenTogetherRoomState
): ListenTogetherRoomState {
  const copy = new ListenTogetherRoomState();
  copy.roomId = state.roomId;
  copy.version = state.version;
  copy.schemaVersion = state.schemaVersion;
  copy.controllerUserUuid = state.controllerUserUuid;
  copy.controllerUserId = state.controllerUserId;
  copy.controllerHeartbeatAt = state.controllerHeartbeatAt;
  copy.settings = cloneListenTogetherRoomSettings(state.settings);
  const members: ListenTogetherMember[] = [];
  for (const member of state.members) {
    members.push(cloneListenTogetherMember(member));
  }
  copy.members = members;
  const queue: ListenTogetherTrack[] = [];
  for (const track of state.queue) {
    queue.push(cloneListenTogetherTrack(track));
  }
  copy.queue = queue;
  copy.currentIndex = state.currentIndex;
  copy.track = state.track === null ? null : cloneListenTogetherTrack(state.track);
  copy.playback = cloneListenTogetherPlaybackState(state.playback);
  copy.controllerOfflineSince = state.controllerOfflineSince;
  copy.roomStatus = state.roomStatus;
  copy.closedReason = state.closedReason;
  copy.updatedAt = state.updatedAt;
  return copy;
}

export function listenTogetherRoomSettingsFromRecord(raw: JsonRecord): ListenTogetherRoomSettings {
  const settings = new ListenTogetherRoomSettings();
  settings.allowMemberControl = reqBoolean(raw, 'allowMemberControl', true);
  settings.autoPauseOnMemberChange = reqBoolean(raw, 'autoPauseOnMemberChange', true);
  settings.shareAudioLinks = reqBoolean(raw, 'shareAudioLinks', true);
  return settings;
}

export function listenTogetherRoomSettingsToRecord(
  settings: ListenTogetherRoomSettings
): JsonRecord {
  const raw: JsonRecord = {};
  raw['allowMemberControl'] = settings.allowMemberControl;
  raw['autoPauseOnMemberChange'] = settings.autoPauseOnMemberChange;
  raw['shareAudioLinks'] = settings.shareAudioLinks;
  return raw;
}

export function listenTogetherMemberFromRecord(raw: JsonRecord): ListenTogetherMember {
  const member = new ListenTogetherMember();
  member.userUuid = reqString(raw, 'userUuid');
  member.nickname = reqString(raw, 'nickname');
  member.userId = optString(raw, 'userId');
  member.role = reqString(raw, 'role');
  member.joinedAt = reqNumber(raw, 'joinedAt', 0);
  return member;
}

export function listenTogetherMemberToRecord(member: ListenTogetherMember): JsonRecord {
  const raw: JsonRecord = {};
  raw['userUuid'] = member.userUuid;
  raw['nickname'] = member.nickname;
  putString(raw, 'userId', member.userId);
  raw['role'] = member.role;
  raw['joinedAt'] = member.joinedAt;
  return raw;
}

export function listenTogetherPlaybackStateFromRecord(
  raw: JsonRecord
): ListenTogetherPlaybackState {
  const playback = new ListenTogetherPlaybackState();
  playback.state = reqString(raw, 'state', 'paused');
  playback.basePositionMs = reqNumber(raw, 'basePositionMs', 0);
  playback.baseTimestampMs = reqNumber(raw, 'baseTimestampMs', 0);
  playback.playbackRate = reqNumber(raw, 'playbackRate', 1.0);
  playback.repeatMode = optNumber(raw, 'repeatMode');
  playback.shuffleEnabled = optBoolean(raw, 'shuffleEnabled');
  return playback;
}

export function listenTogetherPlaybackStateToRecord(
  playback: ListenTogetherPlaybackState
): JsonRecord {
  const raw: JsonRecord = {};
  raw['state'] = playback.state;
  raw['basePositionMs'] = playback.basePositionMs;
  raw['baseTimestampMs'] = playback.baseTimestampMs;
  raw['playbackRate'] = playback.playbackRate;
  putNumber(raw, 'repeatMode', playback.repeatMode);
  putBoolean(raw, 'shuffleEnabled', playback.shuffleEnabled);
  return raw;
}

export function listenTogetherRoomStateFromRecord(raw: JsonRecord): ListenTogetherRoomState {
  const state = new ListenTogetherRoomState();
  state.roomId = reqString(raw, 'roomId');
  state.version = reqNumber(raw, 'version', 0);
  state.schemaVersion = reqNumber(raw, 'schemaVersion', 1);
  state.controllerUserUuid = optString(raw, 'controllerUserUuid');
  state.controllerUserId = optString(raw, 'controllerUserId');
  state.controllerHeartbeatAt = optNumber(raw, 'controllerHeartbeatAt');
  const settings = optRecord(raw, 'settings');
  state.settings = settings === null
    ? new ListenTogetherRoomSettings()
    : listenTogetherRoomSettingsFromRecord(settings);
  const memberRecords = optRecordArray(raw, 'members');
  if (memberRecords !== null) {
    const members: ListenTogetherMember[] = [];
    for (const record of memberRecords) {
      members.push(listenTogetherMemberFromRecord(record));
    }
    state.members = members;
  }
  const queueRecords = optRecordArray(raw, 'queue');
  if (queueRecords !== null) {
    state.queue = listenTogetherTracksFromRecords(queueRecords);
  }
  state.currentIndex = reqNumber(raw, 'currentIndex', 0);
  const trackRecord = optRecord(raw, 'track');
  state.track = trackRecord === null ? null : listenTogetherTrackFromRecord(trackRecord);
  const playbackRecord = optRecord(raw, 'playback');
  state.playback = playbackRecord === null
    ? new ListenTogetherPlaybackState()
    : listenTogetherPlaybackStateFromRecord(playbackRecord);
  state.controllerOfflineSince = optNumber(raw, 'controllerOfflineSince');
  state.roomStatus = reqString(raw, 'roomStatus', ListenTogetherRoomStatuses.ACTIVE);
  state.closedReason = optString(raw, 'closedReason');
  state.updatedAt = reqNumber(raw, 'updatedAt', 0);
  return state;
}

export function listenTogetherRoomStateToRecord(state: ListenTogetherRoomState): JsonRecord {
  const raw: JsonRecord = {};
  raw['roomId'] = state.roomId;
  raw['version'] = state.version;
  raw['schemaVersion'] = state.schemaVersion;
  putString(raw, 'controllerUserUuid', state.controllerUserUuid);
  putString(raw, 'controllerUserId', state.controllerUserId);
  putNumber(raw, 'controllerHeartbeatAt', state.controllerHeartbeatAt);
  putRecord(raw, 'settings', listenTogetherRoomSettingsToRecord(state.settings));
  const memberRecords: JsonRecord[] = [];
  for (const member of state.members) {
    memberRecords.push(listenTogetherMemberToRecord(member));
  }
  putRecordArray(raw, 'members', memberRecords);
  putRecordArray(raw, 'queue', listenTogetherTracksToRecords(state.queue));
  raw['currentIndex'] = state.currentIndex;
  putRecord(raw, 'track', state.track === null ? null : listenTogetherTrackToRecord(state.track));
  putRecord(raw, 'playback', listenTogetherPlaybackStateToRecord(state.playback));
  putNumber(raw, 'controllerOfflineSince', state.controllerOfflineSince);
  raw['roomStatus'] = state.roomStatus;
  putString(raw, 'closedReason', state.closedReason);
  raw['updatedAt'] = state.updatedAt;
  return raw;
}
