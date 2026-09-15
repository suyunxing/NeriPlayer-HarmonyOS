// SPDX-License-Identifier: GPL-3.0

import { util } from '@kit.ArkTS';
import { picker, fileIo } from '@kit.CoreFileKit';
import { LocalPlaylistRepository } from './LocalPlaylistRepository';
import { HistoryRepository } from './HistoryRepository';
import { SongItem } from '../model/SongItem';
import { Playlist } from '../model/Playlist';
import { MusicPlatform } from '../model/MusicPlatform';
import { SyncData, SyncPlaylist, SyncRecentPlay, SyncSong } from '../sync/SyncModels';
import { syncPlaylistFromPlaylist, syncSongFromSongItem } from '../sync/SyncSongConvert';
import { serializeSyncDataJson, deserializeSyncContent, utf8Decode } from '../sync/SyncDataJsonCodec';
import { Logger } from '../app/Logger';

/**
 * Local playlist backup file (user request, Android BackupManager parity):
 * export writes the same SyncData JSON document the cloud sync produces
 * (version 2.x, playlists + recent plays), so a backup file is
 * interchangeable with a manually downloaded backup.json from either side.
 * Import decodes any of the three sync formats (JSON / GZIP-proto / legacy
 * base64) and merges playlists by name, songs by stable key. Playback stats
 * stay out of the file deliberately: they are covered by cloud sync and the
 * merge semantics differ from playlist membership.
 */

const FILE_PREFIX: string = 'neriplayer_backup';
/** Mirrors Android BackupManager.MAX_BACKUP_IMPORT_BYTES. */
const MAX_IMPORT_BYTES: number = 10 * 1024 * 1024;

export class PlaylistBackupResult {
  playlistsImported: number = 0;
  songsImported: number = 0;
  historyImported: number = 0;
  message: string = '';
}

export class PlaylistBackupManager {
  /** Builds the backup document (SyncData JSON text) from the local stores. */
  static async buildBackupJson(): Promise<string> {
    const playlists = await LocalPlaylistRepository.loadAll();
    const history = await HistoryRepository.getRecent();
    const data = new SyncData('2.2', 'local-backup', 'NeriPlayer HarmonyOS', Date.now());
    for (const playlist of playlists) {
      data.playlists.push(syncPlaylistFromPlaylist(playlist, Date.now()));
    }
    for (const song of history) {
      const syncSong = syncSongFromSongItem(song);
      if (syncSong !== null) {
        data.recentPlays.push(new SyncRecentPlay(syncSong.id, syncSong, song.addedAt, 'local-backup', 0));
      }
    }
    const bytes = serializeSyncDataJson(data);
    return utf8Decode(bytes);
  }

  /** File name with a sortable timestamp, matching the Android prefix. */
  static backupFileName(now: Date = new Date()): string {
    const pad = (v: number): string => `${v}`.padStart(2, '0');
    const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`
      + `_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    return `${FILE_PREFIX}_${stamp}.json`;
  }

  /** Picker-driven export; returns a user-facing result message. */
  static async exportViaPicker(): Promise<string> {
    const text = await PlaylistBackupManager.buildBackupJson();
    const docPicker = new picker.DocumentViewPicker();
    const uris = await docPicker.save({ newFileNames: [PlaylistBackupManager.backupFileName()] });
    if (uris.length === 0) {
      return '';
    }
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, text);
    } finally {
      fileIo.closeSync(file);
    }
    return '备份已导出';
  }

  /** Picker-driven import; returns the merge result. */
  static async importViaPicker(): Promise<PlaylistBackupResult> {
    const docPicker = new picker.DocumentViewPicker();
    const uris = await docPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['json']
    });
    if (uris.length === 0) {
      return new PlaylistBackupResult();
    }
    const text = await PlaylistBackupManager.readPickedFile(uris[0]);
    return PlaylistBackupManager.importFromJson(text);
  }

  /** Decodes a picked backup file; throws with a user-facing message. */
  static async readPickedFile(uri: string): Promise<string> {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(file.fd);
      if (stat.size > MAX_IMPORT_BYTES) {
        throw new Error('文件超过 10MB 上限');
      }
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
    } finally {
      fileIo.closeSync(file);
    }
  }

  /**
   * Merges a decoded SyncData into the local stores: playlists merge by name
   * (existing playlists keep their local id shape), songs append by stable
   * key, history merges through the repository's import path.
   */
  static async importFromJson(json: string): Promise<PlaylistBackupResult> {
    const result = new PlaylistBackupResult();
    let data: SyncData | null = null;
    try {
      const decoded = deserializeSyncContent(PlaylistBackupManager.encodeUtf8(json));
      data = decoded.data;
    } catch (error) {
      Logger.warn(`backup import decode failed: ${(error as Error).message}`);
    }
    if (data === null) {
      result.message = '不是有效的备份文件';
      return result;
    }
    const current = await LocalPlaylistRepository.loadAll();
    for (const syncPlaylist of data.playlists) {
      if (syncPlaylist.isDeleted || syncPlaylist.name.length === 0) {
        continue;
      }
      const playlist = PlaylistBackupManager.mergePlaylist(syncPlaylist, current);
      if (playlist === null) {
        continue;
      }
      result.playlistsImported += 1;
      result.songsImported += playlist.songs.length;
    }
    await LocalPlaylistRepository.replaceAllFromSync(current);
    if (data.recentPlays.length > 0) {
      const historySongs: SongItem[] = [];
      for (const recent of data.recentPlays) {
        historySongs.push(PlaylistBackupManager.songFromSync(recent.song, recent.playedAt));
      }
      const existing = await HistoryRepository.getRecent();
      const merged = HistoryRepository.mergeForImport(existing, historySongs);
      await HistoryRepository.replaceFromSync(merged);
      result.historyImported = historySongs.length;
    }
    result.message = `已导入 ${result.playlistsImported} 个歌单 / ${result.songsImported} 首歌`;
    return result;
  }

  private static mergePlaylist(syncPlaylist: SyncPlaylist, current: Playlist[]): Playlist | null {
    let target: Playlist | undefined;
    for (const playlist of current) {
      if (playlist.name === syncPlaylist.name) {
        target = playlist;
        break;
      }
    }
    if (target === undefined) {
      target = new Playlist(`local_${Date.now()}_${syncPlaylist.id}`, syncPlaylist.name);
      current.push(target);
    }
    for (const syncSong of syncPlaylist.songs) {
      const song = PlaylistBackupManager.songFromSync(syncSong, 0);
      const key = `${song.id}|${song.album}|${song.mediaUri}`;
      if (target.songKeys.indexOf(key) >= 0) {
        continue;
      }
      target.songKeys.push(key);
      target.songs.push(song);
    }
    target.updatedAt = Date.now();
    return target;
  }

  private static songFromSync(syncSong: SyncSong, addedAt: number): SongItem {
    const song = new SongItem(syncSong.id, syncSong.name, syncSong.artist, syncSong.album,
      syncSong.albumId, syncSong.durationMs, syncSong.coverUrl ?? '', syncSong.mediaUri ?? '');
    song.channelId = syncSong.channelId ?? '';
    song.audioId = syncSong.audioId ?? '';
    song.subAudioId = syncSong.subAudioId ?? '';
    song.addedAt = addedAt;
    song.syncIdText = syncSong.syncIdText;
    return song;
  }

  private static encodeUtf8(text: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(text);
  }
}
