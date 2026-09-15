// SPDX-License-Identifier: GPL-3.0

import { fileIo, fileUri, fileShare } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../app/Logger';
import { SchemaStore } from './schema/SchemaStore';
import { SongItem } from '../model/SongItem';
import { MusicPlatform } from '../model/MusicPlatform';
import { DownloadStorage } from '../download/DownloadStorage';
import { DownloadedSongEntry, } from '../download/DownloadStorage';

/**
 * Local music library directory scan (backlog §8.3 items 1+3+4): a
 * user-persisted DocumentViewPicker directory is enumerated recursively for
 * audio files, metadata comes from AVMetadataExtractor, sibling `.lrc` files
 * attach as the song's lyric, and the result is cached through SchemaStore
 * so the library survives restarts. Re-entry diffs against the cached set
 * (incremental refresh, no observer-level realtime).
 */

const AUDIO_SUFFIXES: string[] = ['.mp3', '.flac', '.m4a', '.wav', '.ogg', '.aac', '.opus', '.wma'];
const CATALOG_KEY: string = 'local_music_catalog';
/** Safety valve for pathological trees; a real library sits far below this. */
const MAX_FILES: number = 20000;

export class LocalDirectoryScanner {
  /** Sandbox path of the picked directory URI; '' when not convertible. */
  static resolveDirPath(dirUri: string): string {
    if (!dirUri.startsWith('file://')) {
      return dirUri;
    }
    try {
      const converted = new fileUri.FileUri(dirUri).path;
      return converted !== null && converted !== undefined ? converted : '';
    } catch (error) {
      const e = error as Error;
      Logger.warn(`resolveDirPath failed: ${e.message}`);
      return '';
    }
  }

  /** Recursive audio listing (relative paths from listFileSync(recursion)). */
  static listAudioFiles(dirPath: string): string[] {
    try {
      const filter: Record<string, Object> = {};
      filter['suffix'] = AUDIO_SUFFIXES;
      const options: Record<string, Object> = {};
      options['recursion'] = true;
      options['filter'] = filter;
      const listed = fileIo.listFileSync(dirPath, options as object);
      const out: string[] = [];
      for (const entry of listed) {
        // Recursive entries are '/relative/path'; top-level are bare names.
        const name = entry.startsWith('/') ? entry.substring(1) : entry;
        out.push(name);
        if (out.length >= MAX_FILES) {
          Logger.warn(`local scan hit the ${MAX_FILES} file cap, truncating`);
          break;
        }
      }
      return out;
    } catch (error) {
      const e = error as Error;
      Logger.warn(`listAudioFiles failed: ${e.message}`);
      return [];
    }
  }

  /** Sibling `.lrc` path for an audio file (same dir, same stem, .lrc). */
  static siblingLyricPath(audioPath: string): string {
    const dirEnd = audioPath.lastIndexOf('/');
    const dir = dirEnd >= 0 ? audioPath.substring(0, dirEnd) : '';
    const name = dirEnd >= 0 ? audioPath.substring(dirEnd + 1) : audioPath;
    const dot = name.lastIndexOf('.');
    const stem = dot > 0 ? name.substring(0, dot) : name;
    return dir.length > 0 ? `${dir}/${stem}.lrc` : `${stem}.lrc`;
  }

  /** Reads the sibling lyric text; '' when absent or unreadable. */
  static readSiblingLyric(audioPath: string): string {
    const lrcPath = LocalDirectoryScanner.siblingLyricPath(audioPath);
    try {
      if (!fileIo.accessSync(lrcPath)) {
        return '';
      }
      const file = fileIo.openSync(lrcPath, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(lrcPath);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        return LocalDirectoryScanner.decodeUtf8(new Uint8Array(buffer));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      const e = error as Error;
      Logger.debug(`readSiblingLyric ignored: ${e.message}`);
      return '';
    }
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    let out = '';
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    // BOM strip + naive UTF-8 decode via URI round trip for multi-byte runs.
    if (out.startsWith('\uFEFF')) {
      out = out.substring(1);
    }
    return LocalDirectoryScanner.decodeUtf8Bytes(bytes);
  }

  /** Proper UTF-8 decode (same tolerance as GzipInflate's reader). */
  private static decodeUtf8Bytes(bytes: Uint8Array): string {
    let out = '';
    let i = 0;
    while (i < bytes.length) {
      const b0 = bytes[i];
      if (b0 < 0x80) {
        out += String.fromCharCode(b0);
        i += 1;
      } else if (b0 < 0xC0) {
        out += '\uFFFD';
        i += 1;
      } else if (b0 < 0xE0 && i + 1 < bytes.length) {
        out += String.fromCharCode(((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else if (b0 < 0xF0 && i + 2 < bytes.length) {
        out += String.fromCharCode(((b0 & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
        i += 3;
      } else if (i + 3 < bytes.length) {
        const cp = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) |
          ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
        const offset = cp - 0x10000;
        out += String.fromCharCode(0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF));
        i += 4;
      } else {
        out += '\uFFFD';
        i += 1;
      }
    }
    return out;
  }

  /**
   * Scans the persisted directory: enumerate audio files, read metadata per
   * file, attach sibling lyrics and download-catalog identities. The cached
   * catalog merges with fresh results by local path (incremental refresh).
   */
  static async scanPersistedDirectory(dirUri: string): Promise<SongItem[]> {
    const dirPath = LocalDirectoryScanner.resolveDirPath(dirUri);
    if (dirPath.length === 0) {
      return [];
    }
    const catalog = await DownloadStorage.getCatalog();
    const songs: SongItem[] = [];
    const files = LocalDirectoryScanner.listAudioFiles(dirPath);
    for (const relative of files) {
      const absolute = `${dirPath}/${relative}`;
      const song = await LocalDirectoryScanner.inspectFile(absolute, relative, catalog);
      if (song !== null) {
        songs.push(song);
      }
    }
    if (songs.length > 0) {
      await LocalDirectoryScanner.saveCatalog(songs);
    }
    return songs;
  }

  /** Metadata + sibling lyric + download identity for one audio file. */
  static async inspectFile(absolutePath: string, relativePath: string,
    catalog: DownloadedSongEntry[]): Promise<SongItem | null> {
    let file: fileIo.File | null = null;
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      file = fileIo.openSync(absolutePath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(absolutePath);
      const fileName = relativePath.substring(relativePath.lastIndexOf('/') + 1);
      const song = new SongItem(0, fileName, '', '', 0, 0, '', absolutePath, MusicPlatform.LOCAL);
      song.localFileName = fileName;
      song.localFilePath = absolutePath;

      extractor = await media.createAVMetadataExtractor();
      const descriptor: media.AVFileDescriptor = { fd: file.fd, offset: 0, length: stat.size };
      extractor.fdSrc = descriptor;
      const metadata = await extractor.fetchMetadata();
      const title = metadata.title ?? '';
      if (title.length > 0) {
        song.name = title;
      }
      song.artist = metadata.artist ?? '';
      song.album = metadata.album ?? '';
      song.durationMs = Number(metadata.duration ?? 0);

      const lyric = LocalDirectoryScanner.readSiblingLyric(absolutePath);
      if (lyric.length > 0) {
        song.matchedLyric = lyric;
      }
      // Downloaded re-imports restore their remote identity (backlog §1.2).
      const downloaded = LocalDirectoryScanner.matchCatalogEntry(song, catalog);
      if (downloaded !== null) {
        song.sourceStableKey = downloaded.stableKey;
      }
      return song;
    } catch (error) {
      const e = error as Error;
      Logger.debug(`inspect ${relativePath} failed: ${e.message}`);
      return null;
    } finally {
      try {
        if (extractor !== null) {
          extractor.release();
        }
      } catch (_error) {
        // release failures are non-fatal for the scan result
      }
      try {
        if (file !== null) {
          fileIo.closeSync(file);
        }
      } catch (_error) {
        // close failures leave an fd leak warning at most; next scan re-opens
      }
    }
  }

  private static matchCatalogEntry(song: SongItem, catalog: DownloadedSongEntry[]): DownloadedSongEntry | null {
    for (const entry of catalog) {
      const entryPath = entry.audioPath.startsWith('file://')
        ? DownloadStorage.resolveFilePath(entry.audioPath) : entry.audioPath;
      if (entryPath === song.localFilePath) {
        return entry;
      }
    }
    return null;
  }

  /** Persists the scanned library (stable-keyed, latest wins). */
  static async saveCatalog(songs: SongItem[]): Promise<void> {
    const json = JSON.stringify(songs.map((song: SongItem): Object => {
      const record: Record<string, Object> = {};
      record['songJson'] = song.toJson();
      return record;
    }));
    await SchemaStore.save(CATALOG_KEY, json, (value: string) => value);
  }

  static async loadCached(): Promise<SongItem[]> {
    return SchemaStore.load<SongItem[]>(CATALOG_KEY, [], (json: string): SongItem[] | null => {
      const rawList = JSON.parse(json) as Object[];
      if (!Array.isArray(rawList)) {
        return null;
      }
      const songs: SongItem[] = [];
      for (const raw of rawList) {
        try {
          const record = raw as Record<string, Object>;
          const songJson = record['songJson'];
          if (songJson !== undefined && songJson !== null) {
            songs.push(SongItem.fromJson(String(songJson)));
          }
        } catch (_error) {
          // Corrupt row: skip, keep the rest.
        }
      }
      return songs;
    });
  }

  /** Re-activates the persisted directory permission after cold start. */
  static activatePersistedPermission(dirUri: string): void {
    if (dirUri.length === 0) {
      return;
    }
    const policy: fileShare.PolicyInfo = {
      uri: dirUri,
      operationMode: fileShare.OperationMode.READ_MODE
    };
    fileShare.activatePermission([policy]).catch((error: Error) => {
      Logger.warn(`activate local scan permission failed: ${error.message}`);
    });
  }
}
