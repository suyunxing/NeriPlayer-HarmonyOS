// SPDX-License-Identifier: GPL-3.0

import { SongItem } from '../model/SongItem';

/**
 * Per-source fetch contract for the source-sync coordinator. Implementations
 * wrap one platform adapter (NetEase playlist / Bilibili fav folder) and never
 * touch storage, so the diff/apply logic stays independent and testable.
 */
export interface SyncSourceAdapter {
  /**
   * Cheap remote fingerprint (one lightweight request) for the
   * skip-if-unchanged check. Must be stable while the remote list is unchanged.
   */
  peekFingerprint(): Promise<string>;
  /** Full snapshot in remote order (one or more requests). */
  fetchSongs(): Promise<SongItem[]>;
}
