// SPDX-License-Identifier: GPL-3.0

import { MusicPlatform } from '../model/MusicPlatform';

/**
 * Source playlist sync (把第三方平台的歌单/收藏夹单向同步成本地镜像歌单).
 *
 * A mirror playlist is a regular local playlist whose membership is driven by
 * a remote source (NetEase playlist / Bilibili fav folder). The binding and
 * the per-source sync state live on Playlist.syncSource so the playlist keeps
 * flowing through the existing storage, UI and cross-device sync paths; the
 * deterministic id (mirrorPlaylistId) makes re-adding the same source a no-op
 * and lets every device derive the same sync id (playlistIdToSync hashes it).
 */
export const SOURCE_SYNC_MODE_MIRROR: string = 'mirror';
export const SOURCE_SYNC_MODE_APPEND: string = 'append';

/**
 * Sync binding + device-local bookkeeping for one mirrored source. Serialized
 * inline inside Playlist.toJson/fromJson; legacy snapshots without the field
 * parse back as null (plain local playlist, no migration).
 */
export class PlaylistSyncSource {
  platform: MusicPlatform;
  /** Remote playlist id (NetEase numeric id text / Bilibili fav mediaId). */
  remoteId: string;
  remoteName: string;
  /** SOURCE_SYNC_MODE_MIRROR (remote wins) or SOURCE_SYNC_MODE_APPEND (add-only). */
  mode: string;
  enabled: boolean;
  /** Last check that fetched the remote list successfully (wall clock). */
  lastCheckedAt: number;
  /** Last check that actually changed local membership/order. */
  lastSyncAt: number;
  /** Remote fingerprint at the last successful check (skip-if-unchanged). */
  lastFingerprint: string;
  /**
   * Stable keys the user manually deleted from the mirror playlist. Auto sync
   * never re-adds them (both modes) until the sync state is reset.
   */
  skipKeys: string[];
  /** Remote membership, including skipped keys; tracked per folder, not per platform. */
  ownedSongKeys: string[];
  ownershipKnown: boolean;
  /** Binding generation guards responses from a removed/replaced binding. */
  bindingId: string;
  bindingRevision: number;

  constructor(platform: MusicPlatform = MusicPlatform.NETEASE, remoteId: string = '',
    remoteName: string = '', mode: string = SOURCE_SYNC_MODE_MIRROR) {
    this.platform = platform;
    this.remoteId = remoteId;
    this.remoteName = remoteName;
    this.mode = mode === SOURCE_SYNC_MODE_APPEND ? SOURCE_SYNC_MODE_APPEND : SOURCE_SYNC_MODE_MIRROR;
    this.enabled = true;
    this.lastSyncAt = 0;
    this.lastCheckedAt = 0;
    this.lastFingerprint = '';
    this.skipKeys = [];
    this.ownedSongKeys = [];
    this.ownershipKnown = false;
    this.bindingId = '';
    this.bindingRevision = 0;
  }

  toJson(): string {
    return JSON.stringify(this);
  }

  static fromJson(value: Object | null): PlaylistSyncSource | null {
    if (value === null || value === undefined) {
      return null;
    }
    const raw = value as Record<string, Object>;
    const source = new PlaylistSyncSource();
    source.platform = Number(raw['platform'] ?? MusicPlatform.NETEASE) as MusicPlatform;
    source.remoteId = String(raw['remoteId'] ?? '');
    source.remoteName = String(raw['remoteName'] ?? '');
    const mode = String(raw['mode'] ?? SOURCE_SYNC_MODE_MIRROR);
    source.mode = mode === SOURCE_SYNC_MODE_APPEND ? SOURCE_SYNC_MODE_APPEND : SOURCE_SYNC_MODE_MIRROR;
    source.enabled = Boolean(raw['enabled'] ?? true);
    source.lastSyncAt = Number(raw['lastSyncAt'] ?? 0);
    source.lastCheckedAt = Number(raw['lastCheckedAt'] ?? 0);
    source.lastFingerprint = String(raw['lastFingerprint'] ?? '');
    const skips = raw['skipKeys'];
    if (skips instanceof Array) {
      source.skipKeys = skips.map((key: Object): string => String(key));
    } else {
      source.skipKeys = [];
    }
    const owned = raw['ownedSongKeys'];
    if (owned instanceof Array) {
      source.ownedSongKeys = owned.map((key: Object): string => String(key));
    }
    source.ownershipKnown = Boolean(raw['ownershipKnown'] ?? false);
    source.bindingId = String(raw['bindingId'] ?? '');
    source.bindingRevision = Number(raw['bindingRevision'] ?? 0);
    if (source.remoteId.length === 0) {
      // Corrupt/legacy binding without a remote id is not a usable source.
      return null;
    }
    return source;
  }
}

/** Stable binding identity: different folders on the same platform stay isolated. */
export function sourceKeyOf(source: PlaylistSyncSource): string {
  return `${syncSourceChannel(source.platform)}:${source.remoteId}`;
}

export function sourceBindingTokenOf(source: PlaylistSyncSource): string {
  return `${source.bindingId}|${source.bindingRevision}|${source.mode}|${source.enabled}`;
}

/** Channel token used inside mirror playlist ids (matches channelId style). */
export function syncSourceChannel(platform: MusicPlatform): string {
  if (platform === MusicPlatform.BILIBILI) {
    return 'bilibili';
  }
  if (platform === MusicPlatform.YOUTUBE_MUSIC) {
    return 'youtube_music';
  }
  return 'netease';
}

/**
 * Deterministic local playlist id for a synced source. Stable across devices
 * and re-adds, so the same remote playlist always maps to one local playlist
 * (and via playlistIdToSync's non-numeric fallback to one cross-device sync id).
 */
export function mirrorPlaylistId(platform: MusicPlatform, remoteId: string): string {
  return `mirror_${syncSourceChannel(platform)}_${remoteId}`;
}
