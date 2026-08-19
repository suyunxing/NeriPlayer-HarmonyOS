/**
 * Port of the SecureTokenStorage subset the sync stack needs on this side:
 * recent-play/playlist-song deletion tombstones plus the sync device id,
 * persisted through the versioned SchemaStore preferences.
 *
 * The normalization (group per stable key → newest wins → newest first →
 * cap 500) mirrors SecureTokenStorage.normalizeRecentPlayDeletions so both
 * endpoints converge to the same tombstone set.
 */
import { SchemaStore } from '../data/schema/SchemaStore';
import { AppPreferences } from '../data/AppPreferences';
import {
  SyncRecentPlayDeletion,
  SyncPlaylistSongDeletion,
  SyncCausalToken
} from './SyncModels';
import { parseJsonText, escapeJsonString, JsonValue } from './SyncDataJsonCodec';

export const MAX_RECENT_PLAY_DELETIONS: number = 500;

type JsonMap = Map<string, JsonValue>;

function asObjectNode(node: JsonValue | undefined): JsonMap | null {
  if (node instanceof Map) {
    return node;
  }
  return null;
}

function asArrayNode(node: JsonValue | undefined): JsonValue[] | null {
  if (node instanceof Array) {
    return node;
  }
  return null;
}

function readStringOf(obj: JsonMap, key: string, defaultValue: string): string {
  const value = obj.get(key);
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return `${value}`;
  }
  return defaultValue;
}

function readNumberOf(obj: JsonMap, key: string, defaultValue: number): number {
  const value = obj.get(key);
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return defaultValue;
}

function readStringOrNullOf(obj: JsonMap, key: string): string | null {
  const value = obj.get(key);
  if (typeof value === 'string') {
    return value;
  }
  return null;
}

function readIdTextOf(obj: JsonMap, key: string): string {
  const value = obj.get(key);
  if (typeof value === 'string') {
    return value;
  }
  return '';
}

export class SyncDeletionState {
  recentPlayDeletions: SyncRecentPlayDeletion[];
  playlistSongDeletions: SyncPlaylistSongDeletion[];
  deviceId: string;

  constructor(
    recentPlayDeletions: SyncRecentPlayDeletion[] = [],
    playlistSongDeletions: SyncPlaylistSongDeletion[] = [],
    deviceId: string = ''
  ) {
    this.recentPlayDeletions = recentPlayDeletions;
    this.playlistSongDeletions = playlistSongDeletions;
    this.deviceId = deviceId;
  }

  toJsonText(): string {
    let out = '{"deviceId":' + escapeJsonString(this.deviceId);
    out += ',"recentPlayDeletions":[';
    for (let i = 0; i < this.recentPlayDeletions.length; i++) {
      const d = this.recentPlayDeletions[i];
      if (i > 0) {
        out += ',';
      }
      out += '{"songId":' + (d.syncSongIdText.length > 0
        ? escapeJsonString(d.syncSongIdText) : `${d.songId}`);
      out += ',"album":' + escapeJsonString(d.album);
      if (d.mediaUri !== null) {
        out += ',"mediaUri":' + escapeJsonString(d.mediaUri);
      }
      out += ',"deletedAt":' + `${d.deletedAt}`;
      out += ',"deviceId":' + escapeJsonString(d.deviceId) + '}';
    }
    out += '],"playlistSongDeletions":[';
    for (let i = 0; i < this.playlistSongDeletions.length; i++) {
      const d = this.playlistSongDeletions[i];
      if (i > 0) {
        out += ',';
      }
      out += '{"playlistId":' + `${d.playlistId}`;
      out += ',"songId":' + (d.syncSongIdText.length > 0
        ? escapeJsonString(d.syncSongIdText) : `${d.songId}`);
      out += ',"album":' + escapeJsonString(d.album);
      if (d.mediaUri !== null) {
        out += ',"mediaUri":' + escapeJsonString(d.mediaUri);
      }
      out += ',"deletedAt":' + `${d.deletedAt}`;
      out += ',"deviceId":' + escapeJsonString(d.deviceId);
      out += ',"removedMembershipTokens":' + tokensToJson(d.removedMembershipTokens);
      out += '}';
    }
    out += ']}';
    return out;
  }

  static fromJsonText(json: string): SyncDeletionState | null {
    const root = parseJsonText(json);
    const obj = asObjectNode(root);
    if (obj === null) {
      return null;
    }
    const recent: SyncRecentPlayDeletion[] = [];
    for (const item of asArrayNode(obj.get('recentPlayDeletions')) ?? []) {
      const entry = asObjectNode(item);
      if (entry === null) {
        continue;
      }
      recent.push(new SyncRecentPlayDeletion(
        readNumberOf(entry, 'songId', 0),
        readStringOf(entry, 'album', ''),
        readStringOrNullOf(entry, 'mediaUri'),
        readNumberOf(entry, 'deletedAt', 0),
        readStringOf(entry, 'deviceId', ''),
        readIdTextOf(entry, 'songId')
      ));
    }
    const playlistDeletions: SyncPlaylistSongDeletion[] = [];
    for (const item of asArrayNode(obj.get('playlistSongDeletions')) ?? []) {
      const entry = asObjectNode(item);
      if (entry === null) {
        continue;
      }
      playlistDeletions.push(new SyncPlaylistSongDeletion(
        readNumberOf(entry, 'playlistId', 0),
        readNumberOf(entry, 'songId', 0),
        readStringOf(entry, 'album', ''),
        readStringOrNullOf(entry, 'mediaUri'),
        readNumberOf(entry, 'deletedAt', 0),
        readStringOf(entry, 'deviceId', ''),
        readTokensOf(entry.get('removedMembershipTokens')),
        readIdTextOf(entry, 'songId')
      ));
    }
    return new SyncDeletionState(recent, playlistDeletions, readStringOf(obj, 'deviceId', ''));
  }
}

function tokensToJson(tokens: SyncCausalToken[]): string {
  let out = '[';
  for (let i = 0; i < tokens.length; i++) {
    if (i > 0) {
      out += ',';
    }
    out += '{"deviceId":' + escapeJsonString(tokens[i].deviceId);
    out += ',"counter":' + `${tokens[i].counter}` + '}';
  }
  return out + ']';
}

function readTokensOf(node: JsonValue | undefined): SyncCausalToken[] {
  const list = asArrayNode(node);
  if (list === null) {
    return [];
  }
  const tokens: SyncCausalToken[] = [];
  for (const item of list) {
    const entry = asObjectNode(item);
    if (entry === null) {
      continue;
    }
    tokens.push(new SyncCausalToken(
      readStringOf(entry, 'deviceId', ''),
      readNumberOf(entry, 'counter', 0)
    ));
  }
  return tokens;
}

/**
 * Group per stable key, keep the newest mirror per group (deletedAt, then
 * deviceId), order newest first, cap at MAX_RECENT_PLAY_DELETIONS.
 */
export function normalizeRecentPlayDeletions(
  deletions: SyncRecentPlayDeletion[]
): SyncRecentPlayDeletion[] {
  const groups = new Map<string, SyncRecentPlayDeletion>();
  for (const deletion of deletions) {
    const key = deletion.stableKey();
    const existing = groups.get(key);
    if (existing === undefined ||
      deletion.deletedAt > existing.deletedAt ||
      (deletion.deletedAt === existing.deletedAt && deletion.deviceId > existing.deviceId)) {
      groups.set(key, deletion);
    }
  }
  const merged: SyncRecentPlayDeletion[] = [];
  groups.forEach((deletion: SyncRecentPlayDeletion) => {
    merged.push(deletion);
  });
  merged.sort((a: SyncRecentPlayDeletion, b: SyncRecentPlayDeletion): number => {
    if (a.deletedAt !== b.deletedAt) {
      return a.deletedAt > b.deletedAt ? -1 : 1;
    }
    return a.deviceId > b.deviceId ? -1 : (a.deviceId < b.deviceId ? 1 : 0);
  });
  return merged.slice(0, MAX_RECENT_PLAY_DELETIONS);
}

/**
 * Preference-backed store. Device ids are not credentials (they are random
 * UUIDs surfaced inside sync payloads), so preferences storage is acceptable
 * here — unlike tokens which must stay in the asset store (see data/auth).
 */
export class SyncDeletionStore {
  private static readonly STATE_KEY: string = 'sync_deletion_state';
  private static readonly DEVICE_ID_KEY: string = 'sync_device_id';

  static parseState(json: string): SyncDeletionState | null {
    return SyncDeletionState.fromJsonText(json);
  }

  static async load(): Promise<SyncDeletionState> {
    const state = await SchemaStore.load<SyncDeletionState>(
      SyncDeletionStore.STATE_KEY,
      new SyncDeletionState(),
      SyncDeletionStore.parseState
    );
    state.recentPlayDeletions = normalizeRecentPlayDeletions(state.recentPlayDeletions);
    return state;
  }

  static async save(state: SyncDeletionState): Promise<void> {
    const normalized = new SyncDeletionState(
      normalizeRecentPlayDeletions(state.recentPlayDeletions),
      state.playlistSongDeletions,
      state.deviceId
    );
    await SchemaStore.save(
      SyncDeletionStore.STATE_KEY,
      normalized.toJsonText(),
      (value: string): string => value
    );
  }

  /** Stable UUID per install; the generator is injected for deterministic tests. */
  static async getOrCreateDeviceId(generate: () => string): Promise<string> {
    const existing = await AppPreferences.getString(SyncDeletionStore.DEVICE_ID_KEY, '');
    if (existing.length > 0) {
      return existing;
    }
    const created = generate();
    await AppPreferences.putString(SyncDeletionStore.DEVICE_ID_KEY, created);
    return created;
  }
}
